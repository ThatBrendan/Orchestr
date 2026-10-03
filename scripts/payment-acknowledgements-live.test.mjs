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
const reportPath = process.env.PAYMENT_ACKNOWLEDGEMENT_RESULT_FILE || '/tmp/orchestrio-payment-acknowledgements-live-result.json';
let users = [], clients = [], browser, page, project, crossProject, category;
const createdLinks = [];
let stage = 'preflight';
const report = { target, startedAt: new Date().toISOString(), projects: [], checks: [], cleanup: false };
function save() { fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), { mode: 0o600 }); }
function pass(name, evidence) {
  report.checks.push({ name, status: 'PASS', ...(evidence ? { evidence } : {}) });
  console.log('PASS acknowledgements: ' + name); save();
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
 return query(`select jsonb_build_object('events',(select count(*) from app.domain_events where project_id='${uuid(project)}'),'payments',(select count(*) from public.payments where project_id='${project}'),'requests',(select count(*) from public.reimbursement_requests where project_id='${project}'),'acknowledgements',(select count(*) from public.reimbursement_payment_acknowledgements where project_id='${project}'),'audit',(select count(*) from public.audit_log where project_id='${project}')) evidence;`)[0].evidence;
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
  stage='isolated setup';
  const today=DateTime.utc().toISODate();
  project=uuid(await rpc('create_project',{p_name:'Acknowledgement smoke '+new Date().toISOString(),p_timezone:'UTC',p_currency:'GBP',p_starts_on:today,p_profile:'team_project'}));
  crossProject=uuid(await rpc('create_project',{p_name:'Acknowledgement isolation '+new Date().toISOString(),p_timezone:'UTC',p_currency:'GBP',p_starts_on:today,p_profile:'team_project'},clients[2]));
  report.projects.push(project,crossProject);save();
  await join(1,'member');
  category=unwrap(await clients[0].from('project_areas').insert({project_id:project,title:'Acknowledgement smoke'}).select().single(),'Category').id;
  const title='Villa payment acknowledgement',activity=uuid(await createActivity(title,90000));report.activity=activity;save();
  let members=await rows('project_members','project_id',project);
  const owner=uuid(members.find(m=>m.user_id===users[0].id).id),debtor=uuid(members.find(m=>m.user_id===users[1].id).id);
  await rpc('set_activity_cost_split',{p_commitment:activity,p_split:{mode:'even',cost:90000,members:[owner,debtor]}});
  const payment=unwrap(await clients[0].from('payments').insert({project_id:project,commitment_id:activity,paid_by_member_id:owner,type:'full',direction:'outgoing',status:'paid',amount_minor:90000,paid_on:today}).select().single(),'Actual payment').id;
  unwrap(await clients[0].from('activity_payment_schedules').insert({project_id:project,commitment_id:activity,title:'Original schedule',amount_minor:90000,due_on:today}),'Schedule');
  const request=uuid(await rpc('create_reimbursement',{p_payment:payment,p_debtor:debtor,p_amount:45000}));
  const before=await snapshot();
  const status=async (id=request,c=clients[1])=>(await rows('v_reimbursement_payment_status','reimbursement_request_id',id,c))[0];
  const options=()=>rpc('get_reimbursement_payment_options',{p_request:request},clients[1]);
  const ack=()=>rpc('acknowledge_reimbursement_payment',{p_request:request},clients[1]);
  const undo=id=>rpc('withdraw_reimbursement_payment_acknowledgement',{p_acknowledgement:id},clients[1]);
  const health=c=>rpc('get_project_health',{p_project:project},c);
  const notices=c=>rows('v_my_payment_acknowledgement_notifications','project_id',project,c);
  const card=p=>p.locator(`[data-reimbursement-id="${request}"]`);
  const claims=()=>rows('reimbursement_payment_acknowledgements','reimbursement_request_id',request,clients[1]);
  function facts(id){return query(`select (select count(*) from app.domain_events where resource_id='${uuid(id)}')::int events,(select count(*) from public.notifications where payment_acknowledgement_id='${id}')::int notifications;`)[0];}
  async function unchanged(label){assert.deepEqual(await snapshot(),before);pass(label+' financial snapshots unchanged');}
  stage='authority isolation';
  await deny(clients[0],'acknowledge_reimbursement_payment',{p_request:request});
  await deny(clients[2],'acknowledge_reimbursement_payment',{p_request:request});
  check((await rows('v_reimbursement_payment_status','reimbursement_request_id',request,clients[2])).length===0,'Cross-project status hidden');
  check((await rows('reimbursement_payment_acknowledgements','reimbursement_request_id',request,clients[2])).length===0,'Cross-project history hidden');
  check((await health(clients[1])).some(f=>f.code==='reimbursement_outstanding'&&f.subject_id===request),'Initial debtor Health');
  pass('Creditor Organizer and cross-project Organizer cannot acknowledge; isolation enforced');
  stage='explicit no-link browser claim';
  check((await rpc('list_my_payment_links',{})).length===0,'Fresh synthetic creditor preferences');
  await open(activity,title,memberPage);
  await card(memberPage).getByRole('button',{name:"I've paid",exact:true}).waitFor();
  await fits('Outstanding debtor card without payment link',memberPage);
  const trigger=card(memberPage).getByRole('button',{name:"I've paid",exact:true});
  await trigger.focus();await memberPage.keyboard.press('Enter');
  let dialog=memberPage.getByRole('dialog',{name:'Mark payment as sent?',exact:true});
  await dialog.locator('[id^=headlessui-dialog-panel]').waitFor();
  check(!!await dialog.getAttribute('aria-describedby'),'Dialog description associated');
  await fits('Explicit claim confirmation modal',memberPage);
  for(let i=0;i<8;i++){await memberPage.keyboard.press('Tab');check(await dialog.evaluate(el=>el.contains(document.activeElement)),'Modal focus trap');}
  await memberPage.keyboard.press('Escape');await dialog.locator('[id^=headlessui-dialog-panel]').waitFor({state:'hidden'});
  await poll(()=>trigger.evaluate(el=>el===document.activeElement),5000);
  check((await claims()).length===0,'Opening/dismissing dialog is not a claim');
  await trigger.click();await dialog.getByRole('button',{name:"Yes, I've paid",exact:true}).click();
  await card(memberPage).getByText('Payment sent',{exact:true}).waitFor();
  const first=(await status()).active_acknowledgement_id;check(!!first,'Persisted acknowledgement');
  check(await card(memberPage).getByRole('link').count()===0,'No Pay link after acknowledgement');
  check((await options()).length===0,'No server options');
  check(!(await health(clients[1])).some(f=>f.code==='reimbursement_outstanding'&&f.subject_id===request),'Debtor Health suppressed');
  check(!(await health(clients[0])).some(f=>f.subject_id===request),'No creditor Health action');
  await memberPage.reload();await card(memberPage).getByText('Payment sent',{exact:true}).waitFor();
  await fits('Payment sent and awaiting confirmation',memberPage);
  await unchanged('Explicit no-link claim and refresh');
  stage='creditor notification and perspective';
  const ns=await notices(clients[0]);check(ns.length===1,'One creditor notice');
  check((await notices(clients[1])).length===0 && (await notices(clients[2])).length===0,'No other notice');
  await page.reload();await page.getByRole('button',{name:'Notifications',exact:true}).click();
  await page.getByRole('button').filter({hasText:'Payment marked as sent'}).click();
  await poll(()=>page.url().includes('section=reimbursements'));
  await card(page).getByText(/says they've paid/).waitFor();
  check(await card(page).getByRole('button',{name:"I've paid",exact:true}).count()===0,'Creditor no acknowledge');
  check(await card(page).getByRole('button',{name:/Confirm received|Reject payment/}).count()===0,'No Phase10 controls');
  check(await page.locator('#activity-reimbursements').evaluate(el=>el===document.activeElement),'Deep link focuses reimbursements');
  await fits('Creditor claim copy and notification destination',page);
  pass('Creditor-only deduplicated notification; Activity deep link; no confirmation action');
  stage='browser undo and payment options';
  const link=uuid(await rpc('save_my_payment_link',{p_provider:'monzo',p_url:'https://monzo.me/orchestrio-phase9-synthetic'}));createdLinks.push([link,0]);
  check((await options()).length===0,'Configured link still suppressed during claim');
  await card(memberPage).getByRole('button',{name:'Undo payment sent',exact:true}).click();
  dialog=memberPage.getByRole('dialog',{name:'Undo payment sent?',exact:true});
  await fits('Undo confirmation modal',memberPage);
  await dialog.getByRole('button',{name:'Yes, undo',exact:true}).click();
  await card(memberPage).getByText('Outstanding',{exact:true}).waitFor();
  await card(memberPage).getByRole('link',{name:/Open Monzo payment link/}).waitFor();
  check((await options()).length===1,'Link restored server-side');
  const external=memberPage.waitForEvent('popup');
  await card(memberPage).getByRole('link',{name:/Open Monzo payment link/}).click();
  const popup=await external;await popup.close();
  check(!(await status()).active_acknowledgement_id,'Opening payment link is not an acknowledgement');
  // The context guard aborts the provider request before any transmission.
  pass('Payment-link click does not acknowledge or contact the provider');
  check((await health(clients[1])).some(f=>f.code==='reimbursement_outstanding'&&f.subject_id===request),'Debtor Health restored');
  check((await notices(clients[0])).length===1 && (await notices(clients[0]))[0].kind.endsWith('withdrawn'),'Creditor withdrawal notice replaces sent');
  await card(memberPage).getByText('Payment-sent history',{exact:true}).click();await card(memberPage).getByText(/Withdrawn /).waitFor();
  await unchanged('Undo and restored payment options');
  stage='concurrent retries and acknowledgement withdrawal race';
  const retries=await Promise.all([ack(),ack(),ack(),ack()]);check(new Set(retries).size===1,'Concurrent retries one identity');
  const second=retries[0];assert.deepEqual(facts(second),{events:1,notifications:1});
  await Promise.all([undo(second),undo(second),undo(second)]);assert.deepEqual(facts(second),{events:2,notifications:2});
  const third=await ack();await undo(second);check((await status()).active_acknowledgement_id===third,'Old undo cannot touch new claim');
  const raced=await Promise.all([ack(),undo(third)]);
  const afterRace=await status();const activeClaims=(await claims()).filter(a=>!a.withdrawn_at);
  check(activeClaims.length<=1,'Concurrent claim/undo unique active invariant');
  if(raced[0]===third)check(!afterRace.active_acknowledgement_id,'Retry ordered before undo ends withdrawn');
  else check(afterRace.active_acknowledgement_id===raced[0],'Undo before new claim leaves new active identity');
  assert.deepEqual(facts(third),{events:2,notifications:2});
  const current=await ack();await deny(clients[0],'withdraw_reimbursement_payment_acknowledgement',{p_acknowledgement:current});
  await unchanged('Concurrent acknowledge/undo and old-ID retry');
  pass('Concurrent retries one claim/event/notice; undo one transition; race follows serialized order', {race: raced[0]===third ? 'ack retry → undo' : 'undo → new claim'});
  stage='status unavailable fallback';
  await memberPage.route('**/rest/v1/v_reimbursement_payment_status*',r=>r.abort());
  await memberPage.reload();await card(memberPage).getByText('Payment status unavailable.',{exact:false}).waitFor({timeout:30000});
  check(await card(memberPage).getByText('£450.00',{exact:true}).count()>0,'Request amount still visible');
  check(await card(memberPage).getByRole('link').count()===0,'Failure does not encourage payment');
  await memberPage.unroute('**/rest/v1/v_reimbursement_payment_status*');await memberPage.reload();await card(memberPage).getByText('Payment sent',{exact:true}).waitFor();
  pass('Status-only network failure stays local, fails closed, recovers against real backend');
  stage='Viewer debtor and observing Organizer';
  await join(2,'viewer');members=await rows('project_members','project_id',project);const viewer=members.find(m=>m.user_id===users[2].id).id;
  const viewerTitle='Viewer reimbursement',viewerActivity=uuid(await createActivity(viewerTitle,60000));
  await rpc('set_activity_cost_split',{p_commitment:viewerActivity,p_split:{mode:'even',cost:60000,members:[debtor,viewer]}});
  const viewerPayment=unwrap(await clients[0].from('payments').insert({project_id:project,commitment_id:viewerActivity,paid_by_member_id:debtor,type:'full',direction:'outgoing',status:'paid',amount_minor:60000,paid_on:today}).select().single(),'Viewer source').id;
  const viewerRequest=uuid(await rpc('create_reimbursement',{p_payment:viewerPayment,p_debtor:viewer,p_amount:30000}));
  const viewerBefore=await snapshot();
  await deny(clients[0],'acknowledge_reimbursement_payment',{p_request:viewerRequest});
  await open(viewerActivity,viewerTitle,outsiderPage);
  const vc=outsiderPage.locator(`[data-reimbursement-id="${viewerRequest}"]`);
  await vc.getByRole('button',{name:"I've paid",exact:true}).click();await outsiderPage.getByRole('dialog',{name:'Mark payment as sent?',exact:true}).getByRole('button',{name:"Yes, I've paid",exact:true}).click();await vc.getByText('Payment sent',{exact:true}).waitFor();
  const viewerAck=(await status(viewerRequest,clients[2])).active_acknowledgement_id;
  check((await notices(clients[1])).filter(n=>n.reimbursement_id===viewerRequest).length===1,'Viewer claim notifies its actual creditor');
  check((await notices(clients[0])).filter(n=>n.reimbursement_id===viewerRequest).length===0,'No Organizer fallback');
  await open(viewerActivity,viewerTitle,page);const oc=page.locator(`[data-reimbursement-id="${viewerRequest}"]`);await oc.getByText('Payment sent',{exact:true}).waitFor();
  check(await oc.getByRole('button',{name:/I've paid|Undo payment sent|Confirm received/}).count()===0,'Observer Organizer read only for debtor actions');
  assert.deepEqual(await snapshot(),viewerBefore);
  unwrap(await clients[0].from('project_members').update({status:'removed'}).eq('id',debtor),'Remove creditor');
  await deny(clients[2],'withdraw_reimbursement_payment_acknowledgement',{p_acknowledgement:viewerAck});check((await status(viewerRequest,clients[2])).history.length===1,'History remains with removed creditor');
  check((await notices(clients[1])).length===0,'Removed creditor loses notification access');
  unwrap(await clients[0].from('project_members').update({status:'active'}).eq('id',debtor),'Restore creditor');
  unwrap(await clients[0].from('project_members').update({status:'removed'}).eq('id',viewer),'Remove debtor');
  await deny(clients[2],'withdraw_reimbursement_payment_acknowledgement',{p_acknowledgement:viewerAck});check((await rows('v_reimbursement_payment_status','reimbursement_request_id',viewerRequest,clients[2])).length===0,'Removed debtor history hidden');
  unwrap(await clients[0].from('project_members').update({status:'active'}).eq('id',viewer),'Restore debtor');
  pass('Viewer debtor browser claim; observing Organizer cannot impersonate; removed parties isolated; ledger unchanged');
  stage='archive and stale history';
  unwrap(await clients[0].from('projects').update({status:'archived'}).eq('id',project),'Archive');
  await deny(clients[1],'acknowledge_reimbursement_payment',{p_request:request});await deny(clients[1],'withdraw_reimbursement_payment_acknowledgement',{p_acknowledgement:current});
  await open(activity,title,memberPage);await card(memberPage).getByText('Payment sent',{exact:true}).waitFor();check(await card(memberPage).getByRole('button',{name:'Undo payment sent',exact:true}).count()===0,'Archive read-only history');
  unwrap(await clients[0].from('projects').update({status:'active'}).eq('id',project),'Unarchive');
  unwrap(await clients[0].from('payments').insert({project_id:project,commitment_id:activity,paid_by_member_id:owner,type:'refund',direction:'incoming',status:'paid',amount_minor:1000,paid_on:today}),'Refund');
  const afterRefund=await snapshot();
  await open(activity,title,memberPage);await card(memberPage).getByText('Review needed',{exact:true}).waitFor();await card(memberPage).getByText(/Payment was previously marked as sent/).waitFor();
  check(await card(memberPage).getByRole('link').count()===0,'Stale no payment link');check(await card(memberPage).getByRole('button',{name:/I've paid|Undo payment sent|Confirm received/}).count()===0,'Stale no normal actions');
  await deny(clients[1],'acknowledge_reimbursement_payment',{p_request:request});await deny(clients[1],'withdraw_reimbursement_payment_acknowledgement',{p_acknowledgement:current});check((await options()).length===0,'Stale server options empty');
  await fits('Review needed with retained payment-sent history',memberPage);assert.deepEqual(await snapshot(),afterRefund);
  pass('Archived read-only; refund makes Review needed, retains history and suppresses actions');
  stage='cancellation after claim';
  await open(activity,title,page);await card(page).getByRole('button',{name:'Cancel reimbursement',exact:true}).click();await page.getByText(/marked this payment as sent. Cancelling will not record a settlement./).waitFor();
  await page.getByRole('button',{name:'Confirm cancellation',exact:true}).click();await card(page).getByText('Cancelled',{exact:true}).waitFor();
  check((await status()).history.some(h=>h.id===current),'Cancellation retains active historical claim');
  const afterCancel=await snapshot();delete afterCancel.reimbursement_requests;const compare={...afterRefund};delete compare.reimbursement_requests;assert.deepEqual(afterCancel,compare);
  check((await notices(clients[0])).filter(n=>n.reimbursement_id===request).length===0,'Cancelled notice hidden');
  await fits('Cancelled historical claim',page);
  pass('Cancellation warning, retained claim, no settlement, no actionable notification');
  report.historyBeforeCleanup=historyCounts();save();
  pass('Full actual develop Phase9 smoke complete');
} catch (error) {
  // Do not emit Playwright call logs, assertion values, fixture contents or tokens.
  let message = String(error.message || error);
  for (const u of users) for (const v of Object.values(u)) if (typeof v === 'string' && v) message = message.split(v).join('[private]');
  message = message.replace(/eyJ[A-Za-z0-9_.-]+/g, '[token]').replace(/[a-f0-9]{64}/g, '[token]');
  report.failure = { stage, message: message.slice(0, 1600) };
  console.error('FAIL acknowledgements at ' + stage + ': ' + report.failure.message); process.exitCode = 1;
} finally {
  stage = 'cleanup';
  const cleanupErrors = [];
  for (const [id,index] of createdLinks) {
    try { await rpc('delete_my_payment_link',{p_id:id},clients[index]); }
    catch { cleanupErrors.push('personal payment link cleanup'); process.exitCode=1; }
  }
  for (const index of [0,1]) if(clients[index]) {
    try { check((await rpc('list_my_payment_links',{},clients[index])).length===0,'No synthetic acknowledgements left'); }
    catch { cleanupErrors.push('personal link visibility'); process.exitCode=1; }
  }
  for (const [id, owner] of [[project, clients[0]], [crossProject, clients[2]]]) {
    if (!id) continue;
    try {
      await rpc('soft_delete_project', { p_project: id }, owner);
      for (const c of clients) for (const table of ['projects', 'commitments', 'activity_payment_schedules', 'project_members', 'v_my_reimbursement_notifications', 'v_my_payment_acknowledgement_notifications', 'reimbursement_payment_acknowledgements', 'v_reimbursements']) {
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
      for (const key of ['events', 'payments', 'requests', 'acknowledgements', 'audit']) check(after[key] >= report.historyBeforeCleanup[key], 'Historical retention ' + key);
      report.historyAfterCleanup = after;
    } catch { cleanupErrors.push('history verification'); process.exitCode = 1; }
  }
  report.cleanup = cleanupErrors.length === 0;
  if (cleanupErrors.length) { report.cleanupErrors = cleanupErrors; console.error('Cleanup verification failed; see credential-free result.'); }
  report.finishedAt = new Date().toISOString(); save();
  await browser?.close();
  for (const c of clients) await c.auth.signOut({ scope: 'local' }).catch(() => {});
}
