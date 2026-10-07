import test from 'node:test';
import assert from 'node:assert/strict';
import { GoogleCalendarProvider, ProviderError, GOOGLE_SCOPE } from '../supabase/functions/calendar-integration/provider.mjs';
import { mapEvent } from '../supabase/functions/calendar-integration/mapping.mjs';
import { syncOne, disconnect } from '../supabase/functions/calendar-integration/sync.mjs';
import { createHandler, sha256 } from '../supabase/functions/calendar-integration/handler.mjs';
const entry = { entry_id: 'activity:11111111-1111-4111-8111-111111111111', project_id: 'project', source_type: 'activity', source_id: 'activity', activity_id: 'activity', title: 'Venue visit', status: 'confirmed', start_at: '2026-10-07T23:30:00Z', end_at: '2026-10-08T01:00:00Z', timezone: 'Pacific/Kiritimati', all_day: false };
const appUrl = 'https://develop.example.test';
function adapter(responses) {
  const calls = [];
  const provider = new GoogleCalendarProvider({ clientId: 'client', clientSecret: 'private-client-secret', redirectUri: 'https://edge.example.test/callback', fetchImpl: async (url, options) => {
    calls.push({ url, ...options });
    const next = responses.shift();
    if (next instanceof Error) throw next;
    assert(next, 'Unexpected provider request');
    return new Response(next.status === 204 ? null : JSON.stringify(next.body ?? {}), { status: next.status });
  } });
  return { provider, calls };
}
test('minimal scope, offline consent, state and PKCE', () => {
  const { provider } = adapter([]); const url = new URL(provider.authorizationUrl('state', 'challenge'));
  assert.equal(url.searchParams.get('scope'), GOOGLE_SCOPE); assert(!GOOGLE_SCOPE.includes('calendar.events'));
  assert.equal(url.searchParams.get('code_challenge_method'), 'S256'); assert.equal(url.searchParams.get('access_type'), 'offline');
  assert.equal(url.searchParams.get('state'), 'state'); assert(!url.href.includes('private-client-secret'));
});
test('all-day inclusive end becomes exclusive without timezone drift', () => {
  const event = mapEvent({ ...entry, all_day: true, start_date: '2026-10-08', end_date: '2026-10-10' }, appUrl);
  assert.deepEqual(event.start, { date: '2026-10-08' }); assert.deepEqual(event.end, { date: '2026-10-11' });
});
test('payment excludes amount, notes, links and arbitrary payload', () => {
  const event = mapEvent({ ...entry, source_type: 'payment_schedule', all_day: true, start_date: '2026-10-08', amount_minor: 9999, description: 'PRIVATE', payment_link: 'SECRET', notes: 'PRIVATE' }, appUrl);
  assert.equal(event.summary, 'Payment due — Venue visit');
  assert(!JSON.stringify(event).includes('9999')); assert(!JSON.stringify(event).includes('PRIVATE')); assert(!JSON.stringify(event).includes('SECRET'));
  assert.equal(new URL(event.source.url).searchParams.get('section'), 'payments'); assert.equal(event.visibility, 'private');
});
test('timed source preserves timestamp and IANA timezone', () => {
  const event = mapEvent(entry, appUrl); assert.deepEqual(event.start, { dateTime: entry.start_at, timeZone: 'Pacific/Kiritimati' }); assert.equal(event.end.dateTime, entry.end_at);
});
test('timed Activity without an end stays internal-only without invented duration', () => {
  const event = mapEvent({ ...entry, end_at: null }, appUrl); assert.equal(event, null); assert.equal(entry.end_at, '2026-10-08T01:00:00Z');
});
test('decision gets presentation-only 30 minute marker and canonical deep link', () => {
  const event = mapEvent({ ...entry, source_type: 'decision', end_at: null }, appUrl);
  assert.equal(Date.parse(event.end.dateTime) - Date.parse(event.start.dateTime), 1800000); assert.equal(event.source.url, appUrl + '/app/projects/project/decisions/activity');
});
test('concrete occurrence identity and link; no external RRULE', () => {
  const event = mapEvent({ ...entry, entry_id: 'occurrence:series:2026-10-08', occurrence_date: '2026-10-08' }, appUrl);
  assert.equal(event.extendedProperties.private.orchestrio_source, 'occurrence:series:2026-10-08'); assert(!event.recurrence); assert(event.source.url.includes('occurrence=2026-10-08'));
});
test('existing event updated in place', async () => {
  const { provider, calls } = adapter([{ status: 200 }]); await provider.upsertEvent('secret', 'calendar', 'stableid', mapEvent(entry, appUrl));
  assert.equal(calls.length, 1); assert.equal(calls[0].method, 'PUT'); assert(calls[0].url.endsWith('/stableid'));
});
test('missing event recreated with reserved ID', async () => {
  const { provider, calls } = adapter([{ status: 404 }, { status: 200 }]); await provider.upsertEvent('secret', 'calendar', 'stableid', {});
  assert.equal(JSON.parse(calls[1].body).id, 'stableid');
});
test('ambiguous create retry recovers 409 without duplicate', async () => {
  const { provider, calls } = adapter([{ status: 404 }, { status: 409 }, { status: 200, body: { status: 'confirmed' } }, { status: 200 }]);
  await provider.upsertEvent('secret', 'calendar', 'stableid', {}); assert.equal(calls.filter(c => c.method === 'POST').length, 1); assert(calls[3].url.endsWith('/stableid'));
});
test('cancelled tombstone requests new durable ID', async () => {
  const { provider } = adapter([{ status: 404 }, { status: 409 }, { status: 200, body: { status: 'cancelled' } }]);
  await assert.rejects(provider.upsertEvent('secret', 'calendar', 'id', {}), { code: 'event_deleted' });
});
test('provider deletion is idempotent', async () => {
  const { provider } = adapter([{ status: 404 }, { status: 410 }]); await provider.deleteEvent('secret', 'calendar', 'id'); await provider.deleteEvent('secret', 'calendar', 'id');
});
test('missing calendar is distinct from missing event', async () => {
  const { provider } = adapter([{ status: 404 }]); await assert.rejects(provider.checkCalendar('secret', 'calendar'), { code: 'calendar_missing' });
});
for (const [name, status, body, code] of [['500', 500, { error: 'PRIVATE' }, 'transient'], ['429', 429, {}, 'quota'], ['Google quota 403', 403, { error: { errors: [{ reason: 'rateLimitExceeded' }] } }, 'quota'], ['revoked', 400, { error: 'invalid_grant', error_description: 'PRIVATE' }, 'auth'], ['permission', 403, {}, 'permanent']]) {
  test('safe error classification: ' + name, async () => {
    const { provider } = adapter([{ status, body }]);
    await assert.rejects(provider.refreshAuth('private-refresh'), error => error.code === code && !error.message.includes('PRIVATE') && !error.message.includes('private-refresh'));
  });
}
test('token refresh and code exchange remain server-side form posts', async () => {
  const { provider, calls } = adapter([{ status: 200, body: { access_token: 'new', expires_in: 3600 } }, { status: 200, body: { access_token: 'code-access', refresh_token: 'refresh', expires_in: 3600 } }]);
  assert.equal((await provider.refreshAuth('private-refresh')).access_token, 'new');
  assert.equal((await provider.exchange('code', 'verifier')).refresh_token, 'refresh');
  assert.equal(calls[0].body.get('grant_type'), 'refresh_token'); assert.equal(calls[1].body.get('code_verifier'), 'verifier'); assert(!calls[0].url.includes('private-refresh'));
});
function harness({ entries = [entry], expired = false, failure, calendar = 'calendar', old = [] } = {}) {
  let claimed = false; const operations = [], providerCalls = [], links = new Map(old.map(link => [link.source_key, link]));
  const backend = async (action, data = {}) => {
    operations.push({ action, data });
    if (action === 'claim') { if (claimed) return null; claimed = true; return { id: 'job', lease: 'lease', cursor_key: '' }; }
    if (action === 'bundle') return { calendar_id: calendar, access_token: 'old-access', refresh_token: 'refresh', expires_at: new Date(Date.now() + (expired ? -1000 : 3600000)).toISOString() };
    if (action === 'projection') return entries;
    if (action === 'links') return [...links.values()];
    if (action === 'reserve') { if (!links.has(data.source_key)) links.set(data.source_key, { source_key: data.source_key, provider_event_id: 'durableid' }); return links.get(data.source_key); }
    if (action === 'rotate') links.get(data.source_key).provider_event_id = 'replacementid';
    return {};
  };
  const provider = Object.fromEntries(['checkCalendar', 'createCalendar', 'upsertEvent', 'deleteEvent', 'refreshAuth'].map(method => [method, async (...args) => {
    providerCalls.push({ method, args });
    if (failure && failure.method === method) throw new ProviderError(failure.code);
    return method === 'refreshAuth' ? { access_token: 'new-access', expires_at: new Date(Date.now() + 3600000).toISOString() } : { id: 'created-calendar' };
  }]));
  return { backend, provider, operations, providerCalls, links, appUrl };
}
test('orchestrator refreshes, persists secret then updates event', async () => {
  const h = harness({ expired: true }); await syncOne(h);
  assert(h.operations.some(o => o.action === 'token')); assert(h.operations.some(o => o.action === 'finish'));
  assert.equal(h.providerCalls.find(c => c.method === 'upsertEvent').args[0], 'new-access');
});
test('orchestrator removes obsolete sources and retains eligible history', async () => {
  const h = harness({ entries: [{ ...entry, status: 'completed' }], old: [{ source_key: 'obsolete', provider_event_id: 'old' }] }); await syncOne(h);
  assert(h.providerCalls.some(c => c.method === 'deleteEvent' && c.args[2] === 'old')); assert(h.providerCalls.some(c => c.method === 'upsertEvent'));
});
for (const code of ['auth', 'quota', 'transient', 'calendar_missing']) test('worker isolates failure: ' + code, async () => {
  const h = harness({ failure: { method: 'checkCalendar', code } }); await syncOne(h);
  assert.equal(h.operations.find(o => o.action === 'fail').data.code, code); assert(!h.operations.some(o => o.action === 'finish'));
  assert(h.operations.every(o => !['update_activity', 'update_decision', 'update_payment'].includes(o.action)));
});
test('ambiguous container creation is never blindly retried', async () => {
  const h = harness({ calendar: null, failure: { method: 'createCalendar', code: 'transient' } }); await syncOne(h);
  assert(h.operations.some(o => o.action === 'provision_begin')); assert.equal(h.operations.find(o => o.action === 'fail').data.code, 'provisioning_uncertain');
});
test('bounded worker checkpoints before yielding', async () => {
  const h = harness({ entries: [entry, { ...entry, entry_id: 'activity:z' }] }); await syncOne({ ...h, maxOperations: 1 });
  assert(h.operations.some(o => o.action === 'checkpoint')); assert(h.operations.some(o => o.action === 'yield')); assert(!h.operations.some(o => o.action === 'finish'));
});
test('disconnect disables locally before failed provider cleanup', async () => {
  const order = [];
  const result = await disconnect({ userId: 'owner', backend: async a => { order.push(a); return { id: 'id', calendar_id: 'calendar', access_token: 'access', refresh_token: 'refresh' }; }, provider: { deleteCalendar: async () => { order.push('delete'); throw new ProviderError('transient'); }, revoke: async () => { order.push('revoke'); } } });
  assert.deepEqual(order, ['disconnect', 'delete', 'revoke', 'cleanup_warning']); assert.equal(result.cleanup_required, true); assert(!JSON.stringify(result).includes('refresh'));
});
function handlerHarness() {
  const states = new Map(), calls = [];
  const backend = async (action, data) => {
    calls.push({ action, data });
    if (action === 'state_create') states.set(data.hash, { user_id: data.user_id, verifier: data.verifier });
    if (action === 'state_consume') { const result = states.get(data.hash); states.delete(data.hash); return result; }
    if (action === 'authorize_worker') return false;
    return {};
  };
  const provider = new GoogleCalendarProvider({ clientId: 'client', clientSecret: 'secret', redirectUri: 'https://edge.test/callback' });
  provider.exchange = async () => ({ access_token: 'PRIVATE-ACCESS', refresh_token: 'PRIVATE-REFRESH', expires_at: new Date().toISOString() });
  provider.identity = async () => ({ subject: 'subject', email: 'safe@example.test' });
  const handler = createHandler({ backend, provider, authenticate: async jwt => jwt === 'valid' ? { id: 'owner' } : null, appUrl, configured: true, allowedOrigins: [appUrl], background: () => {} });
  return { handler, calls, states, provider };
}
async function start(h) {
  return h.handler(new Request('https://edge.test/start', { method: 'POST', headers: { origin: appUrl, 'content-type': 'application/x-www-form-urlencoded' }, body: 'access_token=valid' }));
}
test('OAuth start authenticates owner, emits HttpOnly binding, safe redirect, no token URL', async () => {
  const h = handlerHarness(), response = await start(h), url = new URL(response.headers.get('location'));
  assert.equal(response.status, 303); assert.equal(h.calls[0].data.user_id, 'owner'); assert(response.headers.get('set-cookie').includes('HttpOnly; Secure; SameSite=Lax'));
  assert.equal(response.headers.get('referrer-policy'), 'no-referrer'); assert.equal(url.searchParams.get('state').length, 64); assert(!url.href.includes('valid')); assert(!url.href.includes('secret'));
});
test('valid OAuth callback stores server tokens and redirects without them', async () => {
  const h = handlerHarness(), response = await start(h), state = new URL(response.headers.get('location')).searchParams.get('state');
  const callback = await h.handler(new Request(`https://edge.test/callback?state=${state}&code=code&redirect=https://evil.test`, { headers: { cookie: response.headers.get('set-cookie') } }));
  assert.equal(callback.headers.get('location'), appUrl + '/app/settings?calendar_result=connected');
  assert.equal(h.calls.find(c => c.action === 'connect').data.refresh_token, 'PRIVATE-REFRESH'); assert(!(await callback.text()).includes('PRIVATE'));
  const replay = await h.handler(new Request(`https://edge.test/callback?state=${state}&code=code`, { headers: { cookie: response.headers.get('set-cookie') } }));
  assert(replay.headers.get('location').endsWith('=error'));
});
test('OAuth invalid browser binding never consumes state', async () => {
  const h = handlerHarness(); await start(h);
  const response = await h.handler(new Request('https://edge.test/callback?state=' + 'a'.repeat(64) + '&code=code'));
  assert(response.headers.get('location').endsWith('=error')); assert(!h.calls.some(c => c.action === 'state_consume'));
});
test('OAuth expired state cannot exchange or connect', async () => {
  const h = handlerHarness(), state = 'a'.repeat(64);
  const response = await h.handler(new Request(`https://edge.test/callback?state=${state}&code=code`, { headers: { cookie: '__Host-orchestrio-calendar=' + await sha256(state) } }));
  assert(response.headers.get('location').endsWith('=error')); assert(!h.calls.some(c => c.action === 'connect'));
});
test('code exchange failure gives only safe fixed redirect', async () => {
  const h = handlerHarness(), first = await start(h), state = new URL(first.headers.get('location')).searchParams.get('state');
  h.provider.exchange = async () => { throw new Error('PRIVATE'); };
  const response = await h.handler(new Request(`https://edge.test/callback?state=${state}&code=code`, { headers: { cookie: first.headers.get('set-cookie') } }));
  assert(response.headers.get('location').endsWith('=error')); assert(!(await response.text()).includes('PRIVATE'));
});
test('cross-origin start and unauthorized worker denied', async () => {
  const h = handlerHarness();
  assert.equal((await h.handler(new Request('https://edge.test/start', { method: 'POST', headers: { origin: 'https://evil.test' } }))).status, 403);
  assert.equal((await h.handler(new Request('https://edge.test/worker', { method: 'POST', headers: { authorization: 'Bearer user-jwt' } }))).status, 401);
});

test('removing timed end excludes source and removes its previous external mapping', async () => {
 const h = harness({ entries: [{ ...entry, end_at: null }], old: [{ source_key: entry.entry_id, provider_event_id: 'previous' }] });
 await syncOne(h); assert(!h.providerCalls.some(c => c.method === 'upsertEvent')); assert(h.providerCalls.some(c => c.method === 'deleteEvent'));
});
test('disconnect refreshes expired access only in memory, then revokes rotated grant', async () => {
 const calls = []; let tries = 0;
 const result = await disconnect({ userId: 'owner', backend: async a => { calls.push(a); return { id: 'id', calendar_id: 'calendar', access_token: 'expired', refresh_token: 'old-refresh' }; }, provider: {
  deleteCalendar: async token => { calls.push('delete:' + token); if (!tries++) throw new ProviderError('auth', 401); },
  refreshAuth: async () => ({ access_token: 'new-access', refresh_token: 'rotated-refresh' }),
  revoke: async token => calls.push('revoke:' + token),
 } });
 assert.equal(result.cleanup_required, false); assert.deepEqual(calls, ['disconnect', 'delete:expired', 'delete:new-access', 'revoke:rotated-refresh']);
});
test('failed callback persistence revokes newly issued grant without exposing it', async () => {
 const state = 'b'.repeat(64), hash = await sha256(state); let revoked;
 const handler = createHandler({ appUrl, configured: true, allowedOrigins: [appUrl], background: () => {}, authenticate: async () => null,
  backend: async action => { if (action === 'state_consume') return { user_id: 'owner', verifier: 'verifier' }; throw new Error('Disconnected during exchange'); },
  provider: { exchange: async () => ({ access_token: 'access', refresh_token: 'new-grant' }), identity: async () => ({ subject: 'subject' }), revoke: async token => { revoked = token; } },
 });
 const response = await handler(new Request(`https://edge.test/callback?state=${state}&code=code`, { headers: { cookie: '__Host-orchestrio-calendar=' + hash } }));
 assert.equal(revoked, 'new-grant'); assert(response.headers.get('location').endsWith('=error')); assert(!(await response.text()).includes('new-grant'));
});
test('secret-free worker wake-up consumes only DB authorization and ignores caller targets', async () => {
 const calls = []; let work;
 const handler = createHandler({ appUrl, configured: true, allowedOrigins: [appUrl], authenticate: async () => null,
  backend: async (action, data) => { calls.push({ action, data }); return action === 'authorize_worker' ? true : null; },
  provider: {}, background: promise => { work = promise; },
 });
 const response = await handler(new Request('https://edge.test/worker', { method: 'POST', body: JSON.stringify({ user_id: 'attacker-selected', token: 'untrusted' }) }));
 assert.equal(response.status, 202); await work;
 assert.deepEqual(calls.map(c => c.action), ['authorize_worker', 'claim']); assert(calls.every(c => c.data === undefined));
 assert.deepEqual(await response.json(), { accepted: true });
});
