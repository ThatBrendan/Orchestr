/** Real develop reimbursement HTTP/browser verification. No auth creation, email or mocks.
 * PAYMENT_FIXTURE_FILE: private JSON {users:[{id,email,password}, ...]} outside repo.
 * Three existing accounts: Organizer, Member, outsider then Member/Viewer. Cleanup in finally.
 * Output contains checkpoint evidence and isolated resource IDs, never fixture values.
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { createClient } from '@supabase/supabase-js';
import { DateTime } from 'luxon';

const target = 'msfkczsoutbeyhjvegnw';
const origin = process.env.AUTH_TEST_ORIGIN || 'http://127.0.0.1:5173';
const reportPath = process.env.PAYMENT_LINK_RESULT_FILE || '/tmp/orchestrio-payment-links-live-result.json';
let users = [], clients = [], browser, page, project, crossProject, category;
const createdLinks = [];
let stage = 'preflight';
const report = { target, startedAt: new Date().toISOString(), projects: [], checks: [], cleanup: false };
function save() { fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), { mode: 0o600 }); }
function pass(name, evidence) {
  report.checks.push({ name, status: 'PASS', ...(evidence ? { evidence } : {}) });
  console.log('PASS payment links: ' + name); save();
}
function check(value, message) { assert(value, message); }
function unwrap(result, label) { if (result.error) throw new Error(label + ' failed (' + result.error.code + ')'); return result.data; }
async function rpc(name, args, client = clients[0]) { return unwrap(await client.rpc(name, args), name); }
async function rows(table, field, value, client = clients[0]) { return unwrap(await client.from(table).select('*').eq(field, value), table); }
async function poll(fn, timeout = 20000) {
  const until = Date.now() + timeout;
  while (Date.now() < until) { const result = await fn(); if (result) return result; await new Promise(r => setTimeout(r, 500)); }
  throw new Error('Timed out at ' + stage);
}
function query(sql) {
  check(fs.readFileSync('supabase/.temp/project-ref', 'utf8').trim() === target, 'Develop link changed');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'orchestrio-reimbursement-smoke-'));
  try {
    const file = path.join(dir, 'check.sql'); fs.writeFileSync(file, sql, { mode: 0o600 });
    const r = spawnSync('supabase', ['db', 'query', '--linked', '--project-ref', target, '--file', file], { encoding: 'utf8', timeout: 60000 });
    check(r.status === 0, 'Trusted develop query failed');
    return JSON.parse(r.stdout).rows;
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
}
function uuid(value) { check(/^[a-f0-9-]{36}$/.test(value), 'Invalid resource ID'); return value; }
async function pageFor(index) {
  const context = await browser.newContext({ timezoneId: 'UTC', serviceWorkers: 'block' });
  // Guard before transmission; all allowed requests use the actual server response.
  await context.route('**/*', route => {
    const u = new URL(route.request().url());
    if (u.origin === origin || u.origin === `https://${target}.supabase.co`) return route.continue();
    return route.abort();
  });
  const p = await context.newPage(); p.setDefaultTimeout(20000);
  await p.goto(origin + '/login');
  await p.getByLabel('Email', { exact: true }).fill(users[index].email);
  await p.getByLabel(/^Password/).fill(users[index].password);
  await p.getByRole('button', { name: 'Log in', exact: true }).click();
  await p.waitForURL(origin + '/app');
  return p;
}
async function fits(label, p = page) {
  for (const width of [375, 430, 768, 1280]) {
    await p.setViewportSize({ width, height: 950 });
    check(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth), label + ' document overflow ' + width);
    for (const modal of await p.locator('[id^=headlessui-dialog-panel]').all()) check(await modal.evaluate(el => el.scrollWidth <= el.clientWidth), label + ' dialog overflow ' + width);
    if (await p.locator('#activity-payments').count()) check(await p.locator('#activity-payments').evaluate(el => el.scrollWidth <= el.clientWidth), label + ' payments overflow ' + width);
  }
  pass(label + ' responsive', { widths: [375, 430, 768, 1280], horizontalOverflow: false });
}
async function open(id, title, p = page) {
  await p.goto(`${origin}/app/projects/${project}/areas?commitment=${id}`);
  await p.getByRole('heading', { name: title, exact: true }).waitFor();
  await p.locator('#activity-payments').waitFor();
}
async function createActivity(title, cost, owner) {
  return (await rpc('create_activity_in_category', { p_project: project, p_category: category, p_fields: { title, kind: 'other', activity_type: 'task', estimated_cost_minor: cost, ...(owner ? { owner_member_id: owner } : {}) }, p_split: null })).id;
}
async function join(index, role) {
  // Existing in-app invitations; no auth invite endpoint or external delivery.
  await rpc('create_invitation', { p_project_id: project, p_email: users[index].email, p_role: role });
  const invitation = (await rpc('list_my_invitations', {}, clients[index])).find(i => i.project_id === project);
  check(!!invitation, 'Synthetic in-app invitation missing');
  await rpc('accept_invitation', { p_token: invitation.token }, clients[index]);
}
function historyCounts() {
 return query(`select jsonb_build_object('events',(select count(*) from app.domain_events where project_id='${uuid(project)}'),'payments',(select count(*) from public.payments where project_id='${project}'),'requests',(select count(*) from public.reimbursement_requests where project_id='${project}'),'audit',(select count(*) from public.audit_log where project_id='${project}')) evidence;`)[0].evidence;
}
function sorted(rows) { return rows.sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b))); }
async function snapshot() {
 const result={};
 for(const table of ['v_project_financials','v_activity_member_settlements','v_member_balances','cost_shares','v_activity_payment_schedule_financials','payments','reimbursement_requests']) result[table]=sorted(await rows(table,'project_id',project));
 return result;
}
async function deny(client,name,args){check(!!(await client.rpc(name,args)).error,'Denied '+name);}

try {
  check(['localhost', '127.0.0.1'].includes(new URL(origin).hostname), 'Local browser origin required');
  check(fs.readFileSync('supabase/.temp/project-ref', 'utf8').trim() === target, 'Develop link required');
  const env = Object.fromEntries(fs.readFileSync('.env.local', 'utf8').split('\n').filter(l => l.includes('=') && !l.startsWith('#')).map(l => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).replace(/^['"]|['"]$/g, '')]; }));
  check(env.VITE_SUPABASE_URL === `https://${target}.supabase.co`, 'Develop frontend required');
  check(!!process.env.PAYMENT_FIXTURE_FILE, 'Private fixture required');
  const fixturePath = fs.realpathSync(process.env.PAYMENT_FIXTURE_FILE);
  check(!fixturePath.startsWith(fs.realpathSync('.') + path.sep), 'Fixture must be outside repository');
  users = JSON.parse(fs.readFileSync(fixturePath, 'utf8')).users.slice(0, 3);
  // The user supplies these existing identities specifically for synthetic testing.
  // Do not assume the legacy fixture's email domain or IDs for replacement accounts.
  check(users.length === 3 && users.every(u => typeof u.email === 'string' && u.email.includes('@') && typeof u.password === 'string' && u.password), 'Three existing synthetic accounts required');
  clients = users.map(() => createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_PUBLISHABLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } }));
  for (let i = 0; i < users.length; i++) {
    const auth = await clients[i].auth.signInWithPassword({ email: users[i].email, password: users[i].password });
    check(!auth.error, 'Synthetic account ' + (i + 1) + ' authentication failed (' + (auth.error?.code || 'unknown') + ', HTTP ' + (auth.error?.status || 'unknown') + ')');
    check(!!auth.data.session && !!auth.data.user?.id, 'Synthetic authentication must return an identity');
    // Fixture IDs may predate replacement test accounts. Authentication is authoritative;
    // use the returned identity only in memory, never rewrite or report private values.
    users[i] = { ...users[i], id: auth.data.user.id };
  }
  check(new Set(users.map(u => u.id)).size === 3, 'Three distinct authenticated identities required');
  browser = await chromium.launch({ headless: true, channel: 'chrome' });
  page = await pageFor(0);
  const memberPage = await pageFor(1), outsiderPage = await pageFor(2);
  pass('Three independent real browser logins; develop-only network');
  stage='clean synthetic payment preferences';
  for(const index of [0,1]) check((await rpc('list_my_payment_links',{},clients[index])).length===0,'Synthetic owner must start without payment configuration');
  stage='isolated setup';
  const today=DateTime.utc().toISODate();
  project=uuid(await rpc('create_project',{p_name:'Payment links smoke '+new Date().toISOString(),p_timezone:'UTC',p_currency:'GBP',p_starts_on:today,p_profile:'team_project'}));
  crossProject=uuid(await rpc('create_project',{p_name:'Payment links isolation '+new Date().toISOString(),p_timezone:'UTC',p_currency:'GBP',p_starts_on:today,p_profile:'team_project'},clients[2]));
  report.projects.push(project,crossProject);save();
  await join(1,'member');
  category=unwrap(await clients[0].from('project_areas').insert({project_id:project,title:'Payment links smoke'}).select().single(),'Category').id;
  const title='Villa payment destination',activity=uuid(await createActivity(title,90000));report.activity=activity;save();
  let members=await rows('project_members','project_id',project);
  const owner=uuid(members.find(m=>m.user_id===users[0].id).id),debtor=uuid(members.find(m=>m.user_id===users[1].id).id);
  await rpc('set_activity_cost_split',{p_commitment:activity,p_split:{mode:'even',cost:90000,members:[owner,debtor]}});
  const payment=unwrap(await clients[0].from('payments').insert({project_id:project,commitment_id:activity,paid_by_member_id:owner,type:'full',direction:'outgoing',status:'paid',amount_minor:90000,paid_on:today}).select().single(),'Actual payment').id;
  const request=uuid(await rpc('create_reimbursement',{p_payment:payment,p_debtor:debtor,p_amount:45000}));
  const before=await snapshot();
  stage='settings browser';
  await page.goto(`${origin}/app/settings`);
  const settings=page.locator('#payment-links-settings');
  await settings.getByText('No payment links added.',{exact:true}).waitFor();
  async function add(provider,url,label){
    await settings.getByRole('button',{name:'Add payment link',exact:true}).click();
    await settings.getByLabel('Provider',{exact:true}).selectOption(provider);
    if(label)await settings.getByLabel('Label',{exact:true}).fill(label);
    await settings.getByLabel('Payment link',{exact:true}).fill(url);
    await settings.getByRole('button',{name:'Save payment link',exact:true}).click();
    await settings.locator('form').waitFor({state:'hidden'});
    const links=await rpc('list_my_payment_links',{});const link=links.find(l=>l.payment_url===url);
    check(link,'Saved link exists');createdLinks.push([uuid(link.id),0]);return link.id;
  }
  const monzo=await add('monzo','https://monzo.me/orchestrio-phase8-synthetic');
  const revolut=await add('revolut','https://revolut.me/orchestrio-phase8-synthetic');
  const card=id=>settings.locator(`[data-payment-link-id="${id}"]`);
  await card(revolut).getByRole('button',{name:'Set as default',exact:true}).click();
  await card(revolut).getByRole('button',{name:'Clear default',exact:true}).waitFor();
  await page.reload();await card(revolut).getByRole('button',{name:'Clear default',exact:true}).waitFor();
  check((await rpc('list_my_payment_links',{}))[0].id===revolut,'Persisted default ordering');
  await card(revolut).getByRole('button',{name:'Edit',exact:true}).click();
  await settings.getByLabel('Payment link',{exact:true}).fill('https://monzo.me.evil.com/orchestrio-phase8-synthetic');
  await settings.getByRole('button',{name:'Save payment link',exact:true}).click();
  await settings.getByRole('alert').filter({hasText:'Use your personal Revolut payment link.'}).waitFor();
  check(await settings.getByLabel('Payment link',{exact:true}).getAttribute('aria-invalid')==='true','Validation field invalid');
  check((await settings.getByLabel('Payment link',{exact:true}).getAttribute('aria-describedby')).includes('payment-link-error'),'Validation linked to field');
  await settings.getByLabel('Payment link',{exact:true}).fill('https://revolut.me/orchestrio-phase8-edited');
  await fits('Settings add/edit provider form');
  await settings.getByRole('button',{name:'Save payment link',exact:true}).click();await settings.locator('form').waitFor({state:'hidden'});
  const custom=await add('custom','https://payments.example.com/orchestrio-phase8/'+ 'long-path-'.repeat(25),'Other personal link');
  await fits('Settings long URL list and default indicator');
  await card(custom).getByRole('button',{name:'Remove',exact:true}).click();
  await settings.getByRole('button',{name:'Confirm removal',exact:true}).click();await card(custom).waitFor({state:'hidden'});
  await page.reload();await card(monzo).waitFor();check(await card(custom).count()===0,'Removed preference stays removed');
  await Promise.all([rpc('set_default_payment_link',{p_id:monzo}),rpc('set_default_payment_link',{p_id:revolut})]);
  check((await rpc('list_my_payment_links',{})).filter(l=>l.is_default).length===1,'Concurrent one-default invariant');
  await rpc('set_default_payment_link',{p_id:revolut});
  assert.deepEqual(await snapshot(),before);
  pass('Settings add edit remove refresh default and concurrent default; labelled validation; financial snapshots identical');
  stage='server validation and owner isolation';
  for(const url of ['javascript:alert(1)','data:text/html,hi','http://monzo.me/test','https://monzo.me.evil.com/test','https://127.0.0.1/test']) await deny(clients[0],'save_my_payment_link',{p_provider:'monzo',p_url:url});
  await deny(clients[1],'save_my_payment_link',{p_provider:'monzo',p_url:'https://monzo.me/orchestrio-phase8-other',p_id:monzo});
  await deny(clients[1],'delete_my_payment_link',{p_id:monzo});
  check((await rpc('get_reimbursement_payment_options',{p_request:request},clients[2])).length===0,'Outsider context denied');
  check((await rpc('get_reimbursement_payment_options',{p_request:request})).length===0,'Creditor no debtor action');
  check((await rows('user_payment_links','user_id',users[0].id,clients[1])).length===0,'Direct cross-user rows hidden');
  pass('Actual HTTP rejects unsafe URLs and cross-user writes; outsider and creditor cannot resolve debtor options');
  stage='debtor notification payment destination';
  await memberPage.goto(`${origin}/app/projects/${project}/overview`);
  await memberPage.getByRole('button',{name:'Notifications',exact:true}).click();
  await memberPage.locator('section[aria-labelledby=reimbursement-notifications-title]').getByRole('button').filter({hasText:'Reimbursement requested'}).click();
  const reimbursement=memberPage.locator(`[data-reimbursement-id="${request}"]`);
  await reimbursement.getByRole('heading',{name:/^Pay /}).waitFor();
  const options=reimbursement.locator('section[aria-label="Payment options"]');
  check((await rpc('get_reimbursement_payment_options',{p_request:request},clients[1]))[0].id===revolut,'Debtor default first');
  check(await options.locator('[data-payment-option-id]').first().getAttribute('data-payment-option-id')===revolut,'Default first in UI');
  await fits('Debtor Pay section external actions',memberPage);
  const stateBeforeOpen=await snapshot();
  const notificationsBefore=await rows('v_my_reimbursement_notifications','project_id',project,clients[1]);
  const healthBefore=await rpc('get_project_health',{p_project:project},clients[1]);
  const action=options.getByRole('link').first();
  check(await action.getAttribute('target')==='_blank'&&(await action.getAttribute('rel')).includes('noopener')&&(await action.getAttribute('rel')).includes('noreferrer'),'Safe external attributes');
  let navigationSeen=false;
  // Abort before transmission; no provider request, login, form submission or money movement.
  await memberPage.context().route('https://revolut.me/**',route=>{navigationSeen=true;return route.abort();});
  await action.focus();check(await action.evaluate(el=>el===document.activeElement),'Keyboard reachable external link');
  const popupPromise=memberPage.context().waitForEvent('page');await memberPage.keyboard.press('Enter');const popup=await popupPromise;
  await poll(()=>navigationSeen);check(await popup.evaluate(()=>window.opener===null),'External opener isolated');await popup.close();
  assert.deepEqual(await snapshot(),stateBeforeOpen);assert.deepEqual(await rows('v_my_reimbursement_notifications','project_id',project,clients[1]),notificationsBefore);assert.deepEqual(await rpc('get_project_health',{p_project:project},clients[1]),healthBefore);
  await reimbursement.getByText('Outstanding',{exact:true}).waitFor();
  pass('Debtor follows notification to default provider; keyboard opens isolated tab, network aborted; no financial Health or notification mutation');
  stage='viewer and unrelated organizer';
  unwrap(await clients[0].from('project_members').update({role:'viewer'}).eq('id',debtor),'Viewer debtor');
  await open(activity,title,memberPage);await reimbursement.getByRole('link',{name:/Open Revolut/}).waitFor();
  check((await rpc('get_reimbursement_payment_options',{p_request:request},clients[1])).length===2,'Viewer debtor scoped options');
  unwrap(await clients[0].from('project_members').update({role:'member'}).eq('id',debtor),'Restore Member');
  await join(2,'member');members=await rows('project_members','project_id',project);const third=uuid(members.find(m=>m.user_id===users[2].id).id);
  const memberLink=uuid(await rpc('save_my_payment_link',{p_provider:'monzo',p_url:'https://monzo.me/orchestrio-phase8-member'},clients[1]));createdLinks.push([memberLink,1]);
  const otherActivity=uuid(await createActivity('Member creditor private destination',60000));
  await rpc('set_activity_cost_split',{p_commitment:otherActivity,p_split:{mode:'even',cost:60000,members:[debtor,third]}});
  const otherPayment=unwrap(await clients[1].from('payments').insert({project_id:project,commitment_id:otherActivity,paid_by_member_id:debtor,type:'full',direction:'outgoing',status:'paid',amount_minor:60000,paid_on:today}).select().single(),'Member payment').id;
  const otherRequest=uuid(await rpc('create_reimbursement',{p_payment:otherPayment,p_debtor:third,p_amount:30000},clients[1]));
  check((await rows('v_reimbursements','id',otherRequest)).length===1,'Organizer sees request');
  check((await rpc('get_reimbursement_payment_options',{p_request:otherRequest})).length===0,'Organizer cannot see other creditor URL');
  await deny(clients[0],'save_my_payment_link',{p_provider:'monzo',p_url:'https://monzo.me/orchestrio-phase8-other',p_id:memberLink});
  await open(otherActivity,'Member creditor private destination');check(await page.locator('section[aria-label="Payment options"]').count()===0,'Organizer UI no payment destination');
  await open(otherActivity,'Member creditor private destination',outsiderPage);await outsiderPage.getByRole('link',{name:/Open Monzo payment link/}).waitFor();
  pass('Viewer debtor can resolve link; Organizer can inspect another debt but cannot see or edit creditor payment preferences');
  stage='live link edits removal no-link fallback';
  const unchanged=await snapshot();
  await rpc('save_my_payment_link',{p_provider:'custom',p_url:'https://payments.example.com/orchestrio-phase8/current',p_label:'Current payment page',p_id:monzo});
  check((await rpc('get_reimbursement_payment_options',{p_request:request},clients[1])).some(l=>l.provider==='custom'&&l.display_label==='Current payment page'),'Current metadata live, not snapshot');
  await rpc('delete_my_payment_link',{p_id:monzo});await rpc('delete_my_payment_link',{p_id:revolut});
  await open(activity,title,memberPage);
  await reimbursement.getByText(/has no payment link available/).waitFor();await fits('No-link fallback',memberPage);
  assert.deepEqual(await snapshot(),unchanged);await reimbursement.getByText('Outstanding',{exact:true}).waitFor();
  pass('Current edited routing replaces old options; deleting all links gives no-link fallback without changing request or finances');
  stage='stale cancellation archived and removed suppression';
  const replacement=uuid(await rpc('save_my_payment_link',{p_provider:'monzo',p_url:'https://monzo.me/orchestrio-phase8-restored'}));createdLinks.push([replacement,0]);
  unwrap(await clients[0].from('payments').insert({project_id:project,commitment_id:activity,paid_by_member_id:owner,type:'refund',direction:'incoming',status:'paid',amount_minor:10000,paid_on:today}),'Refund');
  const afterRefund=await snapshot();
  await open(activity,title,memberPage);await reimbursement.getByText('This reimbursement needs review before payment.',{exact:true}).waitFor();
  check(await reimbursement.getByRole('link',{name:/payment link/}).count()===0,'Stale Pay action hidden');check((await rpc('get_reimbursement_payment_options',{p_request:request},clients[1])).length===0,'Stale API suppressed');
  await fits('Review-needed suppression',memberPage);check((await rpc('list_my_payment_links',{})).length===1,'Creditor global config retained');assert.deepEqual(await snapshot(),afterRefund);
  await rpc('cancel_reimbursement',{p_request:request});const afterCancel=await snapshot();
  await open(activity,title,memberPage);await reimbursement.getByText('Cancelled',{exact:true}).waitFor();check(await reimbursement.getByRole('link').count()===0,'Cancelled no action');check((await rpc('get_reimbursement_payment_options',{p_request:request},clients[1])).length===0,'Cancelled API suppressed');assert.deepEqual(await snapshot(),afterCancel);
  unwrap(await clients[0].from('projects').update({status:'archived'}).eq('id',project),'Archive');
  check((await rpc('get_reimbursement_payment_options',{p_request:otherRequest},clients[2])).length===0,'Archived API suppressed');
  unwrap(await clients[0].from('projects').update({status:'active'}).eq('id',project),'Unarchive');
  unwrap(await clients[0].from('project_members').update({status:'removed'}).eq('id',debtor),'Remove creditor');
  check((await rpc('get_reimbursement_payment_options',{p_request:otherRequest},clients[2])).length===0,'Removed creditor options suppressed');
  unwrap(await clients[0].from('project_members').update({status:'active'}).eq('id',debtor),'Restore creditor');
  pass('Refund review cancelled archived and removed-creditor contexts suppress options; personal settings and financial state remain independent');
  report.historyBeforeCleanup=historyCounts();save();
  pass('Full actual develop Phase8 smoke complete');
} catch (error) {
  // Do not emit Playwright call logs, assertion values, fixture contents or tokens.
  let message = String(error.message || error);
  for (const u of users) for (const v of Object.values(u)) if (typeof v === 'string' && v) message = message.split(v).join('[private]');
  message = message.replace(/eyJ[A-Za-z0-9_.-]+/g, '[token]').replace(/[a-f0-9]{64}/g, '[token]');
  report.failure = { stage, message: message.slice(0, 1600) };
  console.error('FAIL payment links at ' + stage + ': ' + report.failure.message); process.exitCode = 1;
} finally {
  stage = 'cleanup';
  const cleanupErrors = [];
  for (const [id,index] of createdLinks) {
    try { await rpc('delete_my_payment_link',{p_id:id},clients[index]); }
    catch { cleanupErrors.push('personal payment link cleanup'); process.exitCode=1; }
  }
  for (const index of [0,1]) if(clients[index]) {
    try { check((await rpc('list_my_payment_links',{},clients[index])).length===0,'No synthetic payment links left'); }
    catch { cleanupErrors.push('personal link visibility'); process.exitCode=1; }
  }
  for (const [id, owner] of [[project, clients[0]], [crossProject, clients[2]]]) {
    if (!id) continue;
    try {
      await rpc('soft_delete_project', { p_project: id }, owner);
      for (const c of clients) for (const table of ['projects', 'commitments', 'activity_payment_schedules', 'project_members', 'v_my_reimbursement_notifications', 'v_reimbursements']) {
        const remaining = await rows(table, table === 'projects' ? 'id' : 'project_id', id, c);
        check((table === 'project_members' ? remaining.filter(m => m.status === 'active' && !m.deleted_at) : remaining).length === 0, 'Cleanup visibility ' + table);
      }
      report.checks.push({ name: 'Soft-delete and authenticated visibility cleanup', status: 'PASS', project: id });
      console.log('Synthetic project soft-deleted: ' + id);
    } catch { cleanupErrors.push(id); process.exitCode = 1; }
  }
  if (project && report.historyBeforeCleanup) {
    try {
      const after = historyCounts();
      for (const key of ['events', 'payments', 'requests', 'audit']) check(after[key] >= report.historyBeforeCleanup[key], 'Historical retention ' + key);
      report.historyAfterCleanup = after;
    } catch { cleanupErrors.push('history verification'); process.exitCode = 1; }
  }
  report.cleanup = cleanupErrors.length === 0;
  if (cleanupErrors.length) { report.cleanupErrors = cleanupErrors; console.error('Cleanup verification failed; see credential-free result.'); }
  report.finishedAt = new Date().toISOString(); save();
  await browser?.close();
  for (const c of clients) await c.auth.signOut({ scope: 'local' }).catch(() => {});
}
