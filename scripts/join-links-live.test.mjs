/** Real develop browser smoke; no HTTP interception, no email and no auth-user creation.
 * JOIN_FIXTURE_FILE: private JSON {users:[{id,email,password}, {id,email,password}]}.
 * Uses existing synthetic accounts, creates one isolated project, then soft-deletes it.
 * Historical requests/events/receipts remain; never prints tokens or credentials.
 */
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { createClient } from '@supabase/supabase-js';
const target = 'msfkczsoutbeyhjvegnw';
const origin = process.env.AUTH_TEST_ORIGIN || 'http://localhost:5173';
assert(['localhost', '127.0.0.1'].includes(new URL(origin).hostname));
assert.equal(fs.readFileSync('supabase/.temp/project-ref', 'utf8').trim(), target);
const env = Object.fromEntries(fs.readFileSync('.env.local', 'utf8').split('\n').filter(l => l.includes('=') && !l.startsWith('#')).map(l => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).replace(/^['"]|['"]$/g, '')]; }));
assert.equal(env.VITE_SUPABASE_URL, `https://${target}.supabase.co`);
assert(process.env.JOIN_FIXTURE_FILE, 'JOIN_FIXTURE_FILE required');
const fixture = JSON.parse(fs.readFileSync(process.env.JOIN_FIXTURE_FILE, 'utf8'));
const users = fixture.users.slice(0, 2);
assert.equal(users.length, 2);
assert(users.every(u => typeof u.email==='string' && u.email.includes('@') && u.password), 'Synthetic accounts required');
const clients = users.map(() => createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_PUBLISHABLE_KEY, { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: (input,init) => fetch(input,{...init,signal:AbortSignal.timeout(20000)}) } }));
for(let i=0;i<users.length;i++){const auth=await clients[i].auth.signInWithPassword({email:users[i].email,password:users[i].password});assert(!auth.error,'Synthetic authentication failed');users[i].id=auth.data.user.id;}
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
let project;
const name = 'Join link refinement smoke ' + new Date().toISOString();
const report = { target, project: null, checks: [], cleanup: false };
const reportPath = process.env.JOIN_RESULT_FILE || '/tmp/orchestrio-join-live-result.json';
function pass(check) { report.checks.push(check); console.log('PASS live: ' + check); }
async function login(page, user) {
 await page.getByLabel('Email', { exact: true }).fill(user.email);
 await page.getByLabel(/^Password/).fill(user.password);
 await page.getByRole('button', { name: 'Log in', exact: true }).click();
}
async function settings(page) {
 await page.goto(`${origin}/app/projects/${project}/people`);
 await page.getByRole('heading', { name: 'Invite link', exact: true }).waitFor();
}
async function copy(page) {
 await page.bringToFront();
 await page.getByRole('button', { name: 'Copy invite link', exact: true }).click();
 await page.getByText('Invite link copied', { exact: true }).waitFor();
 const value = await page.evaluate(() => navigator.clipboard.readText());
 assert.match(new URL(value).pathname, /^\/join\/[a-f0-9]{64}$/);
 return value;
}
async function resolve(token) {
 const c = createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_PUBLISHABLE_KEY, { auth: { persistSession: false } });
 const r = await c.rpc('resolve_project_join_link', { p_token: token }); assert.ifError(r.error); return r.data;
}
try {
 const ownerContext = await browser.newContext({ permissions: ['clipboard-read', 'clipboard-write'] });
 const requesterContext = await browser.newContext();
 const owner = await ownerContext.newPage(), requester = await requesterContext.newPage();
 owner.setDefaultTimeout(20000); requester.setDefaultTimeout(20000);
 // Fail closed if the running frontend points elsewhere, before interacting with it.
 for (const page of [owner, requester]) page.on('request', request => {
  const url = new URL(request.url());
  if (url.hostname.endsWith('.supabase.co')) assert.equal(url.hostname, target + '.supabase.co');
 });
 await owner.goto(origin + '/login'); await login(owner, users[0]); await owner.waitForURL(origin + '/app');
 await owner.goto(origin + '/app/projects');
 await owner.getByRole('button', { name: 'New project', exact: true }).first().click();
 await owner.getByRole('button', { name: /Blank Project/ }).click();
 await owner.getByRole('button', { name: 'Continue', exact: true }).click();
 await owner.getByLabel('Project name').fill(name);
 await owner.getByLabel('Start date').fill(new Date().toISOString().slice(0, 10));
 await owner.getByRole('button', { name: 'Create project', exact: true }).click();
 await owner.waitForURL('**/overview');
 project = owner.url().match(/projects\/([a-f0-9-]+)\//)[1]; report.project = project;
 fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), { mode: 0o600 });
 await settings(owner);
 await copy(owner);
 await owner.getByLabel('Join link', { exact: true }).waitFor();
 const linkA = await copy(owner), tokenA = new URL(linkA).pathname.split('/').pop();

 await settings(owner); assert(await copy(owner) === linkA, 'Recovered Link A must be unchanged');
 // Brand-new browser context and real password login prove recovery beyond component/session memory.
 const freshContext = await browser.newContext({ permissions: ['clipboard-read', 'clipboard-write'] });
 const freshOwner = await freshContext.newPage(); freshOwner.setDefaultTimeout(20000);
 await freshOwner.goto(origin + '/login'); await login(freshOwner, users[0]); await freshOwner.waitForURL(origin + '/app');
 await settings(freshOwner); assert(await copy(freshOwner) === linkA, 'Fresh session must recover unchanged Link A'); await freshContext.close();
 pass('copy later: same Link A after People reopen and fresh authenticated browser session');
 await requester.goto(origin + '/join/' + tokenA);
 await requester.getByText(/Sign in or create an account to request access/).waitFor();
 assert(!(await requester.textContent('body')).includes(name)); pass('unauthenticated join: generic page without project data');
 await requester.getByRole('link', { name: 'Log in', exact: true }).click(); await login(requester, users[1]);
 await requester.waitForURL(origin + '/join/' + tokenA); pass('auth continuation: real password login returns to Link A');
 await requester.getByRole('button', { name: 'Request access', exact: true }).click();
 await requester.getByText('Your access request is pending approval.', { exact: true }).waitFor(); pass('request: real backend pending request');
 const pending = await clients[1].from('projects').select('id').eq('id', project); assert.ifError(pending.error); assert.equal(pending.data.length, 0);
 const pendingMembers = await clients[1].from('project_members').select('id').eq('project_id', project); assert.ifError(pendingMembers.error); assert.equal(pendingMembers.data.length, 0);
 await requester.goto(`${origin}/app/projects/${project}/overview`);
 await requester.getByRole('heading', { name, exact: true }).waitFor({ state: 'hidden' });
 assert(!(await requester.textContent('body')).includes(name)); pass('zero project visibility while pending: normal real backend reads and direct navigation');
 await settings(owner); await owner.getByRole('button', { name: /^Approve / }).click();
 await owner.getByText('Access approved.', { exact: true }).waitFor(); pass('organizer approval: People queue updates');
 await requester.goto(origin + '/join/' + tokenA); await requester.getByRole('link', { name: 'Open project', exact: true }).click();
 await requester.getByRole('heading', { name, exact: true }).waitFor();
 const member = await clients[1].from('project_members').select('role,status').eq('project_id', project).eq('user_id', users[1].id).single(); assert.ifError(member.error);
 assert.equal(member.data.role, 'member'); assert.equal(member.data.status, 'active');
 assert.equal(await requester.getByRole('button', { name: 'Open project settings' }).count(), 0); pass('membership access: active Member, no Organizer controls');
 await owner.getByRole('button', { name: 'Disable link', exact: true }).click();
 await owner.getByText('Join link disabled.', { exact: true }).waitFor();
 const linkB = await copy(owner), tokenB = new URL(linkB).pathname.split('/').pop(); assert(linkA !== linkB, 'Regeneration must change the URL');
 assert.equal((await resolve(tokenA)).state, 'unavailable'); assert.equal((await resolve(tokenB)).state, 'sign_in');
 await requester.goto(origin + '/join/' + tokenA); await requester.getByText('This join link is no longer available.', { exact: true }).waitFor();
  await settings(owner); assert(await copy(owner) === linkB, 'Recovered Link B must be unchanged');
 pass('regeneration: A invalid, B valid and copyable after reopening People');
 await owner.getByRole('button', { name: 'Disable link', exact: true }).click(); await owner.getByText('Join link disabled.', { exact: true }).waitFor();
 assert.equal(await owner.getByRole('button', { name: 'Disable link', exact: true }).count(), 0);
 assert.equal((await resolve(tokenB)).state, 'unavailable');
 await requester.goto(origin + '/join/' + tokenB); await requester.getByText('This join link is no longer available.', { exact: true }).waitFor();
 const memberships = await clients[0].from('project_members').select('user_id,role,status').eq('project_id', project).is('deleted_at', null); assert.ifError(memberships.error);
 assert.equal(memberships.data.filter(m => m.status === 'active').length, 2);
 await requester.goto(`${origin}/app/projects/${project}/overview`); await requester.getByRole('heading', { name, exact: true }).waitFor();
 pass('disable: B unavailable, disabled token, both memberships and Member project access preserved');
} catch (error) {
 // Even a failed navigation/assertion must not print bearer credentials.
 throw new Error(String(error.message).replace(/[a-f0-9]{64}/g, '[redacted-token]'));
} finally {
 if (project) {
  const disable = await clients[0].rpc('disable_project_join_link', { p_project: project }); assert.ifError(disable.error);
  const cleanup = await clients[0].rpc('soft_delete_project', { p_project: project }); assert.ifError(cleanup.error);
  const hidden = await clients[0].from('projects').select('id').eq('id', project).is('deleted_at', null); assert.ifError(hidden.error); assert.equal(hidden.data.length, 0);
  report.cleanup = true; console.log('Synthetic smoke project soft-deleted: ' + project);
 }
 fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), { mode: 0o600 });
 await browser.close();
 for (const c of clients) await c.auth.signOut({ scope: 'local' });
}
