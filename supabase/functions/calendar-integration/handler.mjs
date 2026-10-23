import { disconnect, syncOne } from './sync.mjs';

export async function sha256(value) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))), n => n.toString(16).padStart(2, '0')).join('');
}
function random() { return Array.from(crypto.getRandomValues(new Uint8Array(32)), n => n.toString(16).padStart(2, '0')).join(''); }
async function challenge(verifier) {
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))))).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}
const cookieName = '__Host-orchestrio-calendar';
const cookie = value => `${cookieName}=${value}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${value ? 600 : 0}`;

/** Framework-independent request boundary; dependencies are injected only in tests. */
export function createHandler({ backend, provider, authenticate, appUrl, configured, allowedOrigins, background }) {
  const fixedApp = new URL(appUrl).origin;
  return async function handle(req) {
    const origin = req.headers.get('origin');
    const cors = { Vary: 'Origin', ...(allowedOrigins.includes(origin) ? { 'Access-Control-Allow-Origin': origin } : {}), 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
    const headers = { ...cors, 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' };
    const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...headers, 'Content-Type': 'application/json' } });
    const redirect = (result, extra = {}) => new Response(null, { status: 303, headers: { ...headers, ...extra, Location: `${fixedApp}/app/settings?calendar_result=${result}` } });
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    const url = new URL(req.url);
    const action = url.pathname.split('/').pop();
    try {
      if (action === 'callback' && req.method === 'GET') {
        if (!configured) return redirect('unavailable', { 'Set-Cookie': cookie('') });
        const state = url.searchParams.get('state') ?? '';
        const hash = await sha256(state);
        const browserHash = (req.headers.get('cookie') ?? '').split(';').map(s => s.trim()).find(s => s.startsWith(cookieName + '='))?.slice(cookieName.length + 1);
        if (!/^[a-f0-9]{64}$/.test(state) || browserHash !== hash) return redirect('error', { 'Set-Cookie': cookie('') });
        const stored = await backend('state_consume', { hash });
        if (!stored || url.searchParams.has('error') || !url.searchParams.get('code')) return redirect('error', { 'Set-Cookie': cookie('') });
        const tokens = await provider.exchange(url.searchParams.get('code'), stored.verifier);
        try {
          const identity = await provider.identity(tokens.access_token);
          await backend('connect', { hash, user_id: stored.user_id, ...tokens, ...identity });
        } catch {
          // Disconnect may have invalidated the state during code exchange. Do not
          // leave a newly issued grant behind when credential persistence fails.
          try { await provider.revoke(tokens.refresh_token ?? tokens.access_token); } catch { /* Best effort only. */ }
          throw new Error('Calendar connection failed');
        }
        return redirect('connected', { 'Set-Cookie': cookie('') });
      }
      if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
      if (action === 'worker') {
        // Secret-free wake-up: only a private cron-issued, single-use DB window
        // can authorize this fixed job. Request headers/body cannot select work.
        if (!await backend('authorize_worker')) return json({ error: 'Unauthorized' }, 401);
        if (!configured) return json({ accepted: false, reason: 'unavailable' });
        // Return before pg_net's request timeout, with runtime-managed background work.
        background((async () => {
          const until = Date.now() + 100000;
          for (let i = 0; i < 20 && Date.now() < until - 35000; i++) {
            try { if (!await syncOne({ backend, provider, appUrl: fixedApp, budgetMilliseconds: Math.min(45000, until - Date.now() - 35000) })) break; } catch { break; }
          }
        })());
        return json({ accepted: true }, 202);
      }
      if (!origin || !allowedOrigins.includes(origin)) return json({ error: 'Origin denied' }, 403);
      if (Number(req.headers.get('content-length') ?? 0) > 12000) return json({ error: 'Request too large' }, 413);
      let jwt = req.headers.get('authorization')?.replace(/^Bearer /, '') ?? '';
      if (action === 'start') {
        if (!configured) return redirect('unavailable');
        if (!req.headers.get('content-type')?.startsWith('application/x-www-form-urlencoded')) return json({ error: 'Invalid request' }, 400);
        const body = await req.text();
        if (body.length > 12000) return json({ error: 'Request too large' }, 413);
        jwt = new URLSearchParams(body).get('access_token') ?? '';
      }
      const user = jwt ? await authenticate(jwt) : null;
      if (!user) return json({ error: 'Unauthorized' }, 401);
      if (action === 'config') return json({ configured });
      if (action === 'start') {
        const state = random(), verifier = random(), hash = await sha256(state);
        await backend('state_create', { user_id: user.id, hash, verifier });
        return new Response(null, { status: 303, headers: { ...headers, Location: provider.authorizationUrl(state, await challenge(verifier)), 'Set-Cookie': cookie(hash) } });
      }
      if (action === 'disconnect') return json(await disconnect({ backend, provider, userId: user.id }));
      return json({ error: 'Not found' }, 404);
    } catch {
      // Neither raw PostgREST nor provider errors are safe for browser/log output.
      if (action === 'callback' || action === 'start') return redirect('error', { 'Set-Cookie': cookie('') });
      return json({ error: 'Calendar integration unavailable. Your Orchestrio data is unaffected.' }, 503);
    }
  };
}
