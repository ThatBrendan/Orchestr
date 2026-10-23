/** Auth continuation/privacy regression with mocked HTTP; live resource flow is separate. */
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
const origin = process.env.AUTH_TEST_ORIGIN || 'http://localhost:5173';
assert(['localhost', '127.0.0.1'].includes(new URL(origin).hostname));
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
const token = 'a'.repeat(64), path = '/s/' + token;
async function session(immediateSignup = false) {
 const context = await browser.newContext(), page = await context.newPage(); page.setDefaultTimeout(15000);
 const calls = []; let signedIn = false, callback;
 const user = { id: '34000000-0000-4000-8000-000000000004', email: 'share-browser@example.test', aud: 'authenticated', role: 'authenticated', created_at: new Date().toISOString(), email_confirmed_at: new Date().toISOString(), app_metadata: { provider: 'email' }, user_metadata: {}, identities: [] };
 const authToken = () => ({ access_token: `e30.${Buffer.from(JSON.stringify({ sub: user.id, exp: Math.floor(Date.now()/1000)+3600, role: 'authenticated', aud: 'authenticated' })).toString('base64url')}.signature`, refresh_token: 'mock-refresh', expires_in: 3600, token_type: 'bearer', user });
 await context.route('**/*', async route => {
  const request = route.request(), url = new URL(request.url());
  if (url.origin === origin && !/^\/(auth|rest)\/v1\//.test(url.pathname)) return route.continue();
  calls.push(url.pathname);
  const reply = (data, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(data) });
  const end = url.pathname.split('/').pop();
  if (url.pathname.startsWith('/auth/v1/')) {
   if (end === 'signup') { callback = url.searchParams.get('redirect_to'); if (immediateSignup) { signedIn = true; return reply(authToken()); } return reply({ ...user, email_confirmed_at: null }); }
   if (end === 'token') { signedIn = true; return reply(authToken()); }
   if (end === 'user') return reply(user);
   return reply({});
  }
  if (end === 'resolve_shared_resource') return reply({ state: request.postDataJSON().p_token !== token || signedIn ? 'unavailable' : 'sign_in' });
  if (end === 'users') return reply({ id: user.id, display_name: 'Synthetic', email: user.email, timezone: 'UTC', default_currency: 'GBP' });
  return reply([]);
 });
 return { context, page, calls, get callback() { return callback; } };
}
async function unavailable(page) { await page.getByText("This shared item isn't available to your account.", { exact: true }).waitFor(); }
async function fields(page, signup = false) {
 await page.getByLabel('Email', { exact: true }).fill('share-browser@example.test');
 await page.getByLabel(/^Password/).fill('password123');
 if (signup) await page.getByLabel('Confirm password', { exact: true }).fill('password123');
 await page.getByRole('button', { name: signup ? 'Create account' : 'Log in', exact: true }).click();
}
try {
 const login = await session();
 await login.page.goto(origin + path); await login.page.getByText('Sign in to open this shared item.', { exact: true }).waitFor();
 for (const width of [375,430,768,1280]) { await login.page.setViewportSize({ width, height: 900 }); assert(await login.page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)); }
 assert(!login.calls.some(p => /\/(projects|commitments|project_members)$/.test(p)));
 await login.page.getByRole('link', { name: 'Log in', exact: true }).click(); await fields(login.page);
 await login.page.waitForURL(origin + path); await unavailable(login.page); await login.page.reload(); await unavailable(login.page);
 assert(!login.calls.some(p => /\/(projects|commitments|project_members)$/.test(p)));
 for (const width of [375,430,768,1280]) { await login.page.setViewportSize({ width, height: 900 }); assert(await login.page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)); }
 await login.page.goto(origin + '/s/malformed'); await unavailable(login.page); await login.context.close();
 console.log('PASS share browser: logged-out minimal page, password continuation, nonmember privacy, refresh, malformed token, responsive widths');
 for (const immediate of [false,true]) {
  const f = await session(immediate); await f.page.goto(origin + path); await f.page.getByRole('link', { name: 'Create account', exact: true }).click(); await fields(f.page,true);
  if (!immediate) {
   await f.page.getByRole('heading', { name: 'Check your email' }).waitFor();
   assert.equal(new URL(f.callback).searchParams.get('redirect'),path);
   const callback = new URL(f.callback); callback.searchParams.set('code','mock-share-confirmation');
   await f.page.goto(origin + callback.pathname + callback.search);
  }
  await f.page.waitForURL(origin + path); await unavailable(f.page); await f.context.close();
 }
 console.log('PASS share browser: immediate signup and confirmation-required signup/PKCE return to share route without granting access; HTTP mocked, no emails');
} finally { await browser.close(); }
