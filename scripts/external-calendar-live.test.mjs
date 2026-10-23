/** Develop-only real DB + real browser, production handler with injected Google simulator.
 * Private fixture and service key stay in memory; never printed or written.
 * No production provider URL is contacted. Cleanup always disables fixtures.
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { chromium } from 'playwright';
import { DateTime } from 'luxon';
import { createHandler } from '../supabase/functions/calendar-integration/handler.mjs';
import { syncOne, disconnect } from '../supabase/functions/calendar-integration/sync.mjs';
import { ProviderError } from '../supabase/functions/calendar-integration/provider.mjs';
const target = 'msfkczsoutbeyhjvegnw', origin = 'http://127.0.0.1:5173', edge = `https://${target}.supabase.co/functions/v1/calendar-integration`;
const report = { checks: [], cleanup: false, target }, reportFile = '/tmp/orchestrio-external-calendar-result.json';
let users = [], clients = [], admin, browser, project, backend, stage = 'preflight';
const connectionIds = [], calendars = new Map(), providerCalls = [];
let failure = null, fixtureConnectionsAuthorized = false;
function save() { fs.writeFileSync(reportFile, JSON.stringify(report, null, 2), { mode: 0o600 }); }
function pass(name, evidence) { report.checks.push({ name, ...(evidence ? { evidence } : {}) }); save(); console.log('PASS external calendar: ' + name); }
function unwrap(r, label = 'Database operation') { if (r.error) throw new Error(label + ' failed (' + r.error.code + ')'); return r.data; }
const rpc = async (name, args, client = clients[0]) => unwrap(await client.rpc(name, args), name);
function sql(statement) {
  assert.equal(fs.readFileSync('supabase/.temp/project-ref', 'utf8').trim(), target);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'orchestrio-external-'));
  try {
    const file = path.join(dir, 'query.sql'); fs.writeFileSync(file, statement, { mode: 0o600 });
    const r = spawnSync('supabase', ['db', 'query', '--linked', '--project-ref', target, '--file', file], { encoding: 'utf8', timeout: 60000 });
    assert.equal(r.status, 0, 'Develop SQL failed'); return JSON.parse(r.stdout).rows;
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
}
const provider = {
  authorizationUrl(state) { return `https://accounts.google.com/o/oauth2/v2/auth?state=${state}`; },
  async exchange() { return { access_token: 'synthetic-access-only', refresh_token: 'synthetic-refresh-only', expires_at: new Date(Date.now() + 3600000).toISOString() }; },
  async identity() { return { subject: 'synthetic-provider-subject', email: 'calendar-fixture@example.test' }; },
  async refreshAuth() { if (failure === 'auth') throw new ProviderError('auth'); return { access_token: 'synthetic-refreshed', expires_at: new Date(Date.now() + 3600000).toISOString() }; },
  async createCalendar() { const id = crypto.randomUUID(); calendars.set(id, new Map()); providerCalls.push({ method: 'createCalendar', id }); return { id }; },
  async checkCalendar(_token, id) { if (failure) throw new ProviderError(failure); if (!calendars.has(id)) throw new ProviderError('calendar_missing'); },
  async upsertEvent(_token, calendar, id, event) { if (failure) throw new ProviderError(failure); calendars.get(calendar).set(id, structuredClone(event)); providerCalls.push({ method: 'upsert', calendar, id, event }); },
  async deleteEvent(_token, calendar, id) { calendars.get(calendar)?.delete(id); providerCalls.push({ method: 'delete', calendar, id }); },
  async deleteCalendar(_token, id) { providerCalls.push({ method: 'deleteCalendar', id }); if (failure) throw new ProviderError(failure); calendars.delete(id); },
  async revoke() { providerCalls.push({ method: 'revoke' }); if (failure) throw new ProviderError(failure); },
};
async function run() { for (let i = 0; i < 30; i++) if (!await syncOne({ backend, provider, appUrl: origin })) return; throw new Error('Worker failed to drain'); }
async function settings(page) { await page.goto(origin + '/app/settings'); await page.getByTestId('calendar-sync-settings').getByText('Google Calendar ·', { exact: false }).waitFor(); return page.getByTestId('calendar-sync-settings'); }
async function fits(page, name) {
  for (const width of [375, 430, 768, 1280]) {
    await page.setViewportSize({ width, height: 950 });
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), name + ' overflow ' + width);
    const section = page.getByTestId('calendar-sync-settings');
    assert(await section.evaluate(el => el.scrollWidth <= el.clientWidth), name + ' section overflow');
  }
  pass(name + ' responsive', { widths: [375, 430, 768, 1280], overflow: false });
}
try {
  assert.equal(fs.readFileSync('supabase/.temp/project-ref', 'utf8').trim(), target);
  const env = Object.fromEntries(fs.readFileSync('.env.local', 'utf8').split('\n').filter(l => l.includes('=') && !l.startsWith('#')).map(l => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).replace(/^['"]|['"]$/g, '')]; }));
  assert.equal(env.VITE_SUPABASE_URL, `https://${target}.supabase.co`);
  const fixture = fs.realpathSync(process.env.PAYMENT_FIXTURE_FILE ?? '/Users/Ghost/.orchestrio/develop-synthetic-users.json');
  assert(!fixture.startsWith(fs.realpathSync('.') + path.sep)); users = JSON.parse(fs.readFileSync(fixture, 'utf8')).users.slice(0, 3); assert.equal(users.length, 3);
  const keyResult = spawnSync('supabase', ['projects', 'api-keys', '--project-ref', target, '--output', 'json'], { encoding: 'utf8', timeout: 60000 });
  assert.equal(keyResult.status, 0, 'Develop service authentication unavailable');
  const keyData = JSON.parse(keyResult.stdout), keys = Array.isArray(keyData) ? keyData : keyData.api_keys ?? keyData.keys;
  const serviceKey = keys.find(k => k.name === 'service_role')?.api_key;
  assert(serviceKey, 'Develop service role key unavailable');
  admin = createClient(env.VITE_SUPABASE_URL, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  backend = async (action, data = {}) => unwrap(await admin.rpc('calendar_backend', { p_action: action, p_data: data }), 'Calendar backend ' + action);
  clients = users.map(() => createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_PUBLISHABLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } }));
  for (let i = 0; i < 3; i++) { const r = unwrap(await clients[i].auth.signInWithPassword({ email: users[i].email, password: users[i].password }), 'Synthetic login'); users[i].id = r.user.id; }
  // Never replace an existing real connection or claim unrelated live jobs.
  for (const client of clients) assert.equal(unwrap(await client.from('user_calendar_connections').select('*')).filter(c => c.status !== 'disconnected').length, 0, 'Fixture already has active connection');
  assert.equal(sql("select count(*)::int n from public.user_calendar_connections where status<>'disconnected';")[0].n, 0, 'Unrelated active connections: do not run global worker');
  fixtureConnectionsAuthorized = true;
  const handler = createHandler({ backend, provider, appUrl: origin, configured: true, allowedOrigins: [origin], authenticate: async jwt => { const r = await admin.auth.getUser(jwt); return r.error ? null : r.data.user; }, background: () => {} });
  browser = await chromium.launch({ headless: true, channel: 'chrome' });
  const pages = [];
  for (let i = 0; i < 3; i++) {
    const context = await browser.newContext({ timezoneId: 'UTC', serviceWorkers: 'block' });
    await context.route('**/*', async route => {
      const request = route.request(), url = new URL(request.url());
      if (url.href.startsWith(edge + '/')) {
        const response = await handler(new Request(request.url(), { method: request.method(), headers: await request.allHeaders(), ...(request.method() !== 'GET' && request.method() !== 'HEAD' ? { body: request.postData() ?? '' } : {}) }));
        if (url.pathname.endsWith('/start') && response.status === 303) {
          // Playwright cannot intercept every request in a redirect chain. Replace
          // only Google's consent hop, keeping the actual start cookie and callback.
          const state = new URL(response.headers.get('location')).searchParams.get('state');
          const headers = Object.fromEntries(response.headers); delete headers.location;
          headers['content-type'] = 'text/html';
          return route.fulfill({ status: 200, headers, body: '<a href="' + edge + '/callback?state=' + state + '&code=synthetic-code">Continue simulated Google consent</a>' });
        }
        return route.fulfill({ status: response.status, headers: Object.fromEntries(response.headers), body: await response.text() });
      }
      if (url.hostname === 'accounts.google.com') return route.fulfill({ status: 303, headers: { location: `${edge}/callback?state=${url.searchParams.get('state')}&code=synthetic-code` }, body: '' });
      if (url.origin === origin || url.origin === env.VITE_SUPABASE_URL) return route.continue();
      return route.abort();
    });
    const page = await context.newPage(); page.setDefaultTimeout(20000); pages.push(page);
    await page.goto(origin + '/login'); await page.getByLabel('Email', { exact: true }).fill(users[i].email); await page.getByLabel(/^Password/).fill(users[i].password);
    await page.getByRole('button', { name: 'Log in', exact: true }).click(); await page.waitForURL(origin + '/app');
  }
  const [page, memberPage, viewerPage] = pages;
  stage = 'disconnected Settings'; let section = await settings(page);
  await section.getByRole('button', { name: 'Connect Google Calendar', exact: true }).waitFor(); assert.equal(await section.getByRole('button', { name: 'Sync now', exact: true }).count(), 0);
  await fits(page, 'Disconnected Settings');
  pass('Three real browser logins; provider simulation only, real develop DB and authenticated HTTP');
  stage = 'isolated source setup';
  const local = DateTime.now().setZone('Pacific/Kiritimati').plus({ days: 2 }), day = local.toISODate(), stamp = local.set({ hour: 13, minute: 30, second: 0, millisecond: 0 }).toUTC().toISO();
  project = await rpc('create_project', { p_name: 'Phase 13 isolated sync fixture', p_timezone: 'Pacific/Kiritimati', p_currency: 'GBP', p_starts_on: day, p_profile: 'team_project' }); report.project = project; save();
  for (const [i, role] of [[1, 'member'], [2, 'viewer']]) {
    if (i === 2) assert.equal((await rpc('get_project_calendar', { p_project: project, p_range_start: day, p_range_end: local.plus({ days: 30 }).toISODate() }, clients[i])).length, 0);
    await rpc('create_invitation', { p_project_id: project, p_email: users[i].email, p_role: role });
    const invite = (await rpc('list_my_invitations', {}, clients[i])).find(x => x.project_id === project); await rpc('accept_invitation', { p_token: invite.token }, clients[i]);
  }
  const category = unwrap(await clients[0].from('project_areas').insert({ project_id: project, title: 'Calendar sync fixture' }).select().single()).id;
  const create = async (title, fields = {}) => (await rpc('create_activity_in_category', { p_project: project, p_category: category, p_fields: { title, kind: 'other', activity_type: 'task', estimated_cost_minor: 1000, starts_at: stamp, ...fields }, p_split: null })).id;
  const activity = await create('Sync venue visit', { ends_at: DateTime.fromISO(stamp).plus({ hours: 2 }).toUTC().toISO() });
  const noEnd = await create('Timed without end stays internal');
  const allDay = await create('All-day sync task', { starts_at: local.startOf('day').toUTC().toISO(), is_all_day: true });
  const series = await create('Weekly sync fixture', { is_all_day: true, recurrence_frequency: 'weekly', recurrence_interval: 1, recurrence_start_date: day, recurrence_end_date: local.plus({ days: 14 }).toISODate(), recurrence_active: true });
  const decision = await rpc('create_decision', { p_project: project, p_title: 'Sync decision', p_description: null, p_deadline: stamp, p_options: [{ title: 'A' }, { title: 'B' }] });
  const schedule = unwrap(await clients[0].from('activity_payment_schedules').insert({ project_id: project, commitment_id: activity, title: 'Sync deposit', amount_minor: 1000, due_on: day }).select().single()).id;
  const financialBefore = unwrap(await clients[0].from('v_project_financials').select('*').eq('project_id', project));
  stage = 'OAuth browser flow';
  for (let i = 0; i < 3; i++) {
    const panel = await settings(pages[i]); await panel.getByRole('button', { name: 'Connect Google Calendar', exact: true }).click({ noWaitAfter: true });
    await pages[i].getByRole('link', { name: 'Continue simulated Google consent' }).click();
    await pages[i].waitForURL(origin + '/app/settings**');
    await pages[i].getByTestId('calendar-sync-settings').getByRole('button', { name: 'Sync now', exact: true }).waitFor();
    const rows = unwrap(await clients[i].from('user_calendar_connections').select('*')); assert.equal(rows.length, 1); assert.equal(rows[0].user_id, users[i].id); connectionIds.push(rows[0].id);
    await rpc('request_calendar_sync', { p_activities: true, p_decisions: true, p_payments: false }, clients[i]);
    assert(!Object.keys(rows[0]).some(k => /token|secret/.test(k)));
  }
  for (let i = 0; i < 3; i++) { const denied = await clients[i].rpc('calendar_backend', { p_action: 'claim' }); assert(denied.error); }
  pass('Browser-bound OAuth flow; three independent connections; owner-only sanitized rows and backend denial');
  stage = 'initial worker'; await run();
  assert.equal(calendars.size, 3);
  let ownCalendar = sql(`select calendar_id from app.calendar_credentials where connection_id='${connectionIds[0]}';`)[0].calendar_id;
  const events = () => [...calendars.get(ownCalendar).entries()];
  const findSource = key => events().find(([, event]) => event.extendedProperties.private.orchestrio_source === key);
  assert(findSource('activity:' + activity)); assert(!findSource('activity:' + noEnd)); assert(findSource('decision:' + decision)); assert(!findSource('payment_schedule:' + schedule));
  assert.equal(events().filter(([, e]) => e.extendedProperties.private.orchestrio_source.startsWith('occurrence:' + series)).length, 3);
  assert(!findSource('activity:' + series)); assert.equal(findSource('activity:' + allDay)[1].start.date, day);
  assert.equal(findSource('activity:' + activity)[1].start.timeZone, 'Pacific/Kiritimati'); assert.equal(Date.parse(findSource('activity:' + activity)[1].start.dateTime), Date.parse(stamp));
  pass('Initial export: Activity, concrete recurrence, Decision, timezone and all-day; Payments default off');
  section = await settings(page); await section.getByText(/Last synced/).waitFor(); await fits(page, 'Connected Settings, preferences and last sync');
  await section.getByRole('button', { name: 'Sync now', exact: true }).click();
  await section.getByText('Sync requested.', { exact: true }).waitFor(); await run();
  pass('Sync now requests server-side reconciliation from Settings');
  await section.getByRole('checkbox', { name: 'Sync payments', exact: true }).check(); await section.getByText('Preferences saved. Sync requested.', { exact: true }).waitFor(); await run();
  assert.equal(findSource('payment_schedule:' + schedule)[1].start.date, day); assert(!JSON.stringify(findSource('payment_schedule:' + schedule)[1]).includes('1000'));
  await section.getByRole('checkbox', { name: 'Sync payments', exact: true }).uncheck(); await section.getByText('Preferences saved. Sync requested.', { exact: true }).waitFor(); await run(); assert(!findSource('payment_schedule:' + schedule));
  pass('Payment opt-in exports minimal date-only event; disabling deletes external projection');
  stage = 'keyboard preferences';
  const activityToggle = section.getByRole('checkbox', { name: 'Sync activities', exact: true });
  await activityToggle.focus();
  await Promise.all([page.waitForResponse(r => r.url().endsWith('/rpc/request_calendar_sync') && r.request().method() === 'POST'), page.keyboard.press('Space')]);
  await section.getByText('Preferences saved. Sync requested.', { exact: true }).waitFor();
  assert.equal(await activityToggle.isChecked(), false);
  await Promise.all([page.waitForResponse(r => r.url().endsWith('/rpc/request_calendar_sync') && r.request().method() === 'POST'), activityToggle.check()]);
  await section.getByText('Preferences saved. Sync requested.', { exact: true }).waitFor();
  assert.equal(await activityToggle.isChecked(), true); await run();
  pass('Labelled controls are keyboard operable; status and alerts are textual');
  assert.deepEqual(unwrap(await clients[0].from('v_project_financials').select('*').eq('project_id', project)), financialBefore);
  stage = 'provider failure plus UI Activity mutation';
  const oldId = findSource('activity:' + activity)[0]; failure = 'transient'; await rpc('request_calendar_sync', {}); await run();
  await page.goto(`${origin}/app/projects/${project}/areas?commitment=${activity}`); await page.getByRole('button', { name: 'Edit', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Edit activity' }); await dialog.getByRole('heading', { name: 'Edit activity' }).waitFor();
  const newDay = local.plus({ days: 3 }).toISODate(); await dialog.locator('input[type=date]').first().fill(newDay); await dialog.getByLabel('End date', { exact: true }).fill(newDay);
  await dialog.getByRole('button', { name: 'Save activity', exact: true }).click(); await dialog.getByRole('heading', { name: 'Edit activity' }).waitFor({ state: 'hidden' });
  const changed = unwrap(await clients[0].from('commitments').select('starts_at').eq('id', activity).single()); assert.equal(DateTime.fromISO(changed.starts_at).setZone('Pacific/Kiritimati').toISODate(), newDay);
  const failed = sql(`select attempt,status,error_code from app.external_calendar_jobs where connection_id='${connectionIds[0]}' and status='pending';`)[0]; assert(failed.attempt >= 1); assert.equal(failed.error_code, 'transient');
  failure = null; sql(`update app.external_calendar_jobs set available_at=now() where connection_id='${connectionIds[0]}' and status='pending';`); await run();
  assert.equal(findSource('activity:' + activity)[0], oldId); assert.equal(findSource('activity:' + activity)[1].start.date, newDay);
  pass('Google 500 simulation leaves UI Activity reschedule successful; retry updates same provider ID');
  stage = 'external drift and deletion';
  calendars.get(ownCalendar).get(oldId).summary = 'External edit'; await rpc('request_calendar_sync', {}); await run(); assert.equal(findSource('activity:' + activity)[1].summary, 'Sync venue visit');
  calendars.get(ownCalendar).delete(oldId); await rpc('request_calendar_sync', {}); await run(); assert.equal(findSource('activity:' + activity)[0], oldId);
  const deletedId = findSource('activity:' + allDay)[0]; unwrap(await clients[0].from('commitments').update({ status: 'cancelled' }).eq('id', allDay));
  await rpc('request_calendar_sync', {}); await run(); await rpc('request_calendar_sync', {}); await run();
  assert.equal(providerCalls.filter(c => c.method === 'delete' && c.calendar === ownCalendar && c.id === deletedId).length, 1);
  pass('External edit overwritten, external deletion recreated, cancelled source deleted once');
  stage = 'membership removal';
  sql(`update public.project_members set status='removed' where project_id='${project}' and user_id='${users[2].id}';`);
  await rpc('request_calendar_sync', {}, clients[2]); await run();
  const viewerCalendar = sql(`select calendar_id from app.calendar_credentials where connection_id='${connectionIds[2]}';`)[0].calendar_id;
  assert.equal([...calendars.get(viewerCalendar).values()].filter(event => new URL(event.source.url).pathname.includes('/projects/' + project + '/')).length, 0); pass('Removed Viewer membership removes previously exported project entries');
  stage = 'revoked refresh';
  sql(`update app.calendar_credentials set expires_at=now()-interval '1 hour' where connection_id='${connectionIds[0]}';`);
  failure = 'auth'; await rpc('request_calendar_sync', {}); await run(); section = await settings(page); await section.getByRole('button', { name: 'Reconnect Google Calendar', exact: true }).waitFor(); await fits(page, 'Reconnect-required alert');
  assert.equal(unwrap(await clients[0].from('user_calendar_connections').select('*').single()).status, 'reauthorization_required');
  failure = null; await section.getByRole('button', { name: 'Reconnect Google Calendar', exact: true }).click(); await page.getByRole('link', { name: 'Continue simulated Google consent' }).click(); await page.waitForURL(origin + '/app/settings**'); await page.getByRole('button', { name: 'Sync now', exact: true }).waitFor(); await run();
  assert.equal(calendars.size, 3); assert.equal(findSource('activity:' + activity)[0], oldId);
  pass('Invalid grant stops sync and shows reconnect; reconnect reuses calendar and event mappings');
  stage = 'disconnect';
  section = await settings(page); await section.getByRole('button', { name: 'Disconnect', exact: true }).click(); await fits(page, 'Disconnect confirmation');
  const financialBeforeDisconnect = unwrap(await clients[0].from('v_project_financials').select('*').eq('project_id', project));
  const beforeDisconnect = await rpc('get_project_calendar', { p_project: project, p_range_start: day, p_range_end: local.plus({ days: 30 }).toISODate() });
  failure = 'transient'; await section.getByRole('button', { name: 'Disconnect and remove calendar', exact: true }).click();
  await section.getByText('Not connected', { exact: true }).waitFor(); failure = null;
  assert.equal(sql(`select count(*)::int n from app.calendar_credentials where connection_id='${connectionIds[0]}';`)[0].n, 0);
  assert.deepEqual(await rpc('get_project_calendar', { p_project: project, p_range_start: day, p_range_end: local.plus({ days: 30 }).toISODate() }), beforeDisconnect);
  assert.deepEqual(unwrap(await clients[0].from('v_project_financials').select('*').eq('project_id', project)), financialBeforeDisconnect);
  assert(providerCalls.some(c => c.method === 'deleteCalendar' && c.id === ownCalendar));
  assert((await clients[0].rpc('request_calendar_sync')).error); pass('Disconnect survives provider failure, erases credentials, attempts cleanup; Calendar and finances unchanged');
  // Independent sessions still have their own Settings connection.
  await settings(memberPage); await memberPage.getByRole('button', { name: 'Sync now', exact: true }).waitFor(); await settings(viewerPage);
  pass('Other users remain connected independently');
} catch (error) {
  let message = error instanceof Error ? error.message : String(error);
  for (const user of users) for (const value of [user.email, user.password, user.id]) if (value) message = message.split(value).join('[private]');
  report.failure = { stage, message: message.slice(0, 1500) }; console.error('FAIL external calendar at ' + stage + ': ' + report.failure.message); process.exitCode = 1;
} finally {
  try {
    failure = null;
    if (backend && fixtureConnectionsAuthorized) for (const user of users) if (user.id) await disconnect({ backend, provider, userId: user.id });
    if (project) await rpc('soft_delete_project', { p_project: project });
    if (connectionIds.length) {
      const ids = connectionIds.map(id => `'${id}'`).join(',');
      report.cleanupEvidence = sql(`select (select count(*)::int from app.calendar_credentials where connection_id in(${ids})) credentials,(select count(*)::int from app.external_calendar_jobs where connection_id in(${ids}) and status in('pending','running')) live_jobs,(select count(*)::int from app.external_calendar_event_links where connection_id in(${ids})) mappings,(select count(*)::int from public.projects where id='${project}' and deleted_at is null) live_projects;`)[0];
      assert.deepEqual(report.cleanupEvidence, { credentials: 0, live_jobs: 0, mappings: 0, live_projects: 0 });
    }
    calendars.clear(); report.cleanup = true; pass('Cleanup: zero live fixture projects, credentials, mappings or runnable jobs; audit retained');
  } catch { report.cleanup = false; console.error('FAIL external calendar cleanup'); process.exitCode = 1; }
  await browser?.close(); for (const client of clients) await client.auth.signOut(); save();
}
