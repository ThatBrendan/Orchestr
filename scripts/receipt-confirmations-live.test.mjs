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
const reportPath = process.env.RECEIPT_CONFIRMATION_RESULT_FILE || '/tmp/orchestrio-receipt-confirmations-live-result.json';
let users = [], clients = [], browser, page, project, crossProject, category;
const createdLinks = [];
let stage = 'preflight';
const report = { target, startedAt: new Date().toISOString(), projects: [], checks: [], cleanup: false };
function save() { fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), { mode: 0o600 }); }
function pass(name, evidence) {
  report.checks.push({ name, status: 'PASS', ...(evidence ? { evidence } : {}) });
  console.log('PASS receipt confirmations: ' + name); save();
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
 return query(`select jsonb_build_object('events',(select count(*) from app.domain_events where project_id='${uuid(project)}'),'payments',(select count(*) from public.payments where project_id='${project}'),'requests',(select count(*) from public.reimbursement_requests where project_id='${project}'),'confirmations',(select count(*) from public.reimbursement_receipt_confirmations where project_id='${project}'),'acknowledgements',(select count(*) from public.reimbursement_payment_acknowledgements where project_id='${project}'),'audit',(select count(*) from public.audit_log where project_id='${project}')) evidence;`)[0].evidence;
}
function sorted(rows) { return rows.sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b))); }
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
  const memberPage = await pageFor(1); await pageFor(2);
  pass('Three independent real browser logins; develop-only network');
  stage='isolated setup';
  const today=DateTime.utc().toISODate();
  project=uuid(await rpc('create_project',{p_name:'Receipt confirmation smoke '+new Date().toISOString(),p_timezone:'UTC',p_currency:'GBP',p_starts_on:today,p_profile:'team_project'}));
  crossProject=uuid(await rpc('create_project',{p_name:'Receipt isolation '+new Date().toISOString(),p_timezone:'UTC',p_currency:'GBP',p_starts_on:today,p_profile:'team_project'},clients[2]));
  report.projects.push(project,crossProject);save();await join(1,'member');
  category=unwrap(await clients[0].from('project_areas').insert({project_id:project,title:'Receipt smoke'}).select().single(),'Category').id;
  let members=await rows('project_members','project_id',project);
  const owner=members.find(m=>m.user_id===users[0].id).id,debtor=members.find(m=>m.user_id===users[1].id).id;
  const status=async(request,client=clients[0])=>(await rows('v_reimbursement_payment_status','reimbursement_request_id',request,client))[0];
  const confirm=(ack,client=clients[0])=>rpc('confirm_reimbursement_receipt',{p_acknowledgement:ack},client);
  const acknowledge=(request,client=clients[1])=>rpc('acknowledge_reimbursement_payment',{p_request:request},client);
  const undo=(ack,client=clients[1])=>rpc('withdraw_reimbursement_payment_acknowledgement',{p_acknowledgement:ack},client);
  const health=c=>rpc('get_project_health',{p_project:project},c);
  const receiptNotices=c=>rows('v_my_receipt_confirmation_notifications','project_id',project,c);
  const card=(p,id)=>p.locator(`[data-reimbursement-id="${id}"]`);
  async function setup(label,creditor=owner,owing=debtor,amount=45000){
    const activity=uuid(await createActivity(label,90000));
    await rpc('set_activity_cost_split',{p_commitment:activity,p_split:{mode:'custom',cost:90000,members:[creditor,owing],amounts:{[creditor]:90000-amount,[owing]:amount}}});
    const payment=unwrap(await clients[0].from('payments').insert({project_id:project,commitment_id:activity,paid_by_member_id:creditor,type:'full',direction:'outgoing',status:'paid',amount_minor:90000,paid_on:today}).select().single(),'Source').id;
    const request=uuid(await rpc('create_reimbursement',{p_payment:payment,p_debtor:owing,p_amount:amount}));
    return {activity,payment,request,title:label};
  }
  async function financialProof(c){
    const result={};
    for(const table of ['v_commitment_financials','cost_shares','v_activity_payment_schedule_financials','v_activity_member_settlements','payments'])result[table]=sorted(await rows(table,'commitment_id',c.activity));
    result.project=await rows('v_project_financials','project_id',project);
    result.activity=(await rows('commitments','id',c.activity))[0];return result;
  }
  const c=await setup('Villa receipt confirmation',owner,debtor,30000);report.activity=c.activity;
  unwrap(await clients[0].from('activity_payment_schedules').insert({project_id:project,commitment_id:c.activity,title:'Supplier balance',amount_minor:90000,due_on:today}),'Schedule');
  const initial=await financialProof(c);
  const old=await acknowledge(c.request);await undo(old);
  await open(c.activity,c.title,memberPage);
  await card(memberPage,c.request).getByRole('button',{name:"I've paid",exact:true}).click();
  await memberPage.getByRole('dialog',{name:'Mark payment as sent?',exact:true}).getByRole('button',{name:"Yes, I've paid",exact:true}).click();
  await card(memberPage,c.request).getByText('Payment sent',{exact:true}).waitFor();
  const active=(await status(c.request,clients[1])).active_acknowledgement_id;
  pass('Debtor explicitly marks payment sent in browser before creditor confirmation');
  await deny(clients[0],'confirm_reimbursement_receipt',{p_acknowledgement:old});
  await deny(clients[1],'confirm_reimbursement_receipt',{p_acknowledgement:active});
  await deny(clients[2],'confirm_reimbursement_receipt',{p_acknowledgement:active});
  check((await rows('reimbursement_receipt_confirmations','project_id',project,clients[2])).length===0,'Outsider history hidden');
  assert.deepEqual(await financialProof(c),initial);
  pass('Old acknowledgement, debtor self-confirm and outsider denied; claim/undo leave finances unchanged');
  stage='creditor Health and notification deep link';
  const pending=(await health(clients[0])).filter(f=>f.code==='reimbursement_confirmation'&&f.subject_id===c.request);
  check(pending.length===1&&!pending[0].affects_health,'Actionable creditor attention without score penalty');
  check(!(await health(clients[1])).some(f=>f.subject_id===c.request),'Debtor has no confirmation attention');
  await page.goto(`${origin}/app/projects/${project}/overview`);
  const healthLink=page.locator(`a[href*="commitment=${c.activity}"][href*="section=reimbursements"]`).filter({hasText:"Confirm whether you have received it."}).first();
  await healthLink.waitFor();await fits('Creditor confirmation Health',page);await healthLink.click();
  await card(page,c.request).getByRole('button',{name:'Confirm received',exact:true}).waitFor();
  await fits('Creditor confirmation CTA',page);
  await page.goto(`${origin}/app/projects/${project}/overview`);
  await page.getByRole('button',{name:'Notifications',exact:true}).click();
  await page.getByRole('button').filter({hasText:'Payment marked as sent'}).click();
  await poll(()=>page.url().includes('section=reimbursements'));
  pass('Creditor-only Health and existing acknowledgement notification route to reimbursement');
  stage='explicit creditor dialog and concurrent confirmation';
  const trigger=card(page,c.request).getByRole('button',{name:'Confirm received',exact:true});
  await trigger.focus();await page.keyboard.press('Enter');
  const dialog=page.getByRole('dialog',{name:'Confirm receipt?',exact:true});
  await dialog.locator('[id^=headlessui-dialog-panel]').waitFor();
  check(!!await dialog.getAttribute('aria-describedby'),'Description associated');
  await fits('Receipt confirmation modal',page);
  for(let i=0;i<7;i++){await page.keyboard.press('Tab');check(await dialog.evaluate(el=>el.contains(document.activeElement)),'Focus trap');}
  await page.keyboard.press('Escape');await dialog.locator('[id^=headlessui-dialog-panel]').waitFor({state:'hidden'});await poll(()=>trigger.evaluate(el=>el===document.activeElement));
  check((await rows('reimbursement_receipt_confirmations','reimbursement_request_id',c.request)).length===0,'Dialog dismissal does not settle');
  await trigger.click();
  const results=await Promise.all([dialog.getByRole('button',{name:'Confirm received',exact:true}).click(),confirm(active),confirm(active),confirm(active)]);
  await card(page,c.request).getByText('Settled',{exact:true}).waitFor();
  check(new Set(results.slice(1)).size===1,'Concurrent confirmations one identity');
  const confirmation=(await rows('reimbursement_receipt_confirmations','reimbursement_request_id',c.request))[0];
  const after=await financialProof(c),pair=after.payments.filter(p=>p.settlement_group_id);
  check(pair.length===2&&new Set(pair.map(p=>p.settlement_group_id)).size===1,'One pair/group');
  check(pair.every(p=>p.settlement_group_id===confirmation.settlement_group_id&&p.amount_minor===30000),'Exact linked amount');
  check(pair.some(p=>p.direction==='outgoing'&&p.paid_by_member_id===debtor)&&pair.some(p=>p.direction==='incoming'&&p.paid_by_member_id===owner),'Correct transfer attribution');
  for(const key of ['project','activity','v_commitment_financials','cost_shares','v_activity_payment_schedule_financials'])assert.deepEqual(after[key],initial[key]);
  assert.deepEqual(after.payments.filter(p=>!p.settlement_group_id),initial.payments);
  check(after.v_activity_member_settlements.every(m=>m.remaining_minor===0),'Member balances cleared through pair');
  const facts=query(`select (select count(*)::int from app.domain_events where resource_id='${uuid(confirmation.id)}') events,(select count(*)::int from public.notifications where receipt_confirmation_id='${confirmation.id}') notifications;`)[0];assert.deepEqual(facts,{events:1,notifications:1});
  report.financialEvidence={amountMinor:30000,costBefore:initial.v_commitment_financials[0].effective_cost_minor,costAfter:after.v_commitment_financials[0].effective_cost_minor,spendBefore:initial.project[0].net_actual_spend_minor,spendAfter:after.project[0].net_actual_spend_minor,remainingBefore:initial.v_activity_member_settlements.map(m=>m.remaining_minor).sort((a,b)=>a-b),remainingAfter:after.v_activity_member_settlements.map(m=>m.remaining_minor),addedSettlementRows:2,addedSettlementGroups:1};
  pass('Explicit confirm plus concurrent retries creates one linked settlement, event and notification',report.financialEvidence);
  stage='settled debtor and creditor views';
  check(!(await health(clients[0])).some(f=>f.subject_id===c.request),'Creditor attention cleared');
  check((await receiptNotices(clients[1])).length===1&&(await receiptNotices(clients[0])).length===0&&(await receiptNotices(clients[2])).length===0,'Only debtor receives confirmation notice');
  await memberPage.goto(`${origin}/app`);await memberPage.getByRole('button',{name:'Notifications',exact:true}).click();
  await memberPage.getByRole('button').filter({hasText:'Reimbursement settled'}).click();
  await card(memberPage,c.request).getByText('Settled',{exact:true}).waitFor();await card(memberPage,c.request).getByText(/confirmed receipt\./).waitFor();
  check(await card(memberPage,c.request).getByRole('button',{name:/I've paid|Undo|Confirm received|Cancel reimbursement/}).count()===0,'No settled actions');
  check((await rpc('get_reimbursement_payment_options',{p_request:c.request},clients[1])).length===0,'Settled payment options empty');
  await deny(clients[1],'withdraw_reimbursement_payment_acknowledgement',{p_acknowledgement:active});await deny(clients[0],'cancel_reimbursement',{p_request:c.request});
  await card(memberPage,c.request).getByText('Payment-sent history',{exact:true}).click();await card(memberPage,c.request).getByText(/Receipt confirmed /).waitFor();
  await fits('Settled debtor state and history',memberPage);await fits('Settled creditor state',page);
  pass('Settled state, debtor notification, cleared attention, undo/cancel lockouts and history');
  stage='Observer Organizer and Member or Viewer creditor';
  await join(2,'viewer');members=await rows('project_members','project_id',project);const observer=members.find(m=>m.user_id===users[2].id).id;
  const other=await setup('Member creditor receipt',debtor,observer);
  const otherAck=await acknowledge(other.request,clients[2]);
  await deny(clients[0],'confirm_reimbursement_receipt',{p_acknowledgement:otherAck});
  await open(other.activity,other.title,page);check(await card(page,other.request).getByRole('button',{name:'Confirm received',exact:true}).count()===0,'Organizer observer no confirmation CTA');
  unwrap(await clients[0].from('project_members').update({role:'viewer'}).eq('id',debtor),'Viewer creditor');
  await open(other.activity,other.title,memberPage);await card(memberPage,other.request).getByRole('button',{name:'Confirm received',exact:true}).click();
  await memberPage.getByRole('dialog',{name:'Confirm receipt?',exact:true}).getByRole('button',{name:'Confirm received',exact:true}).click();await card(memberPage,other.request).getByText('Settled',{exact:true}).waitFor();
  await deny(clients[1],'record_item_settlement',{p_item:other.activity,p_from:observer,p_to:debtor,p_amount:1,p_date:today});
  unwrap(await clients[0].from('project_members').update({role:'member'}).eq('id',debtor),'Restore member role');
  pass('Viewer actual creditor confirms; Organizer cannot impersonate; general settlement authority unchanged');
  stage='stale and archive boundaries';
  const stale=await setup('Stale receipt review');const staleAck=await acknowledge(stale.request);
  unwrap(await clients[0].from('projects').update({status:'archived'}).eq('id',project),'Archive');await deny(clients[0],'confirm_reimbursement_receipt',{p_acknowledgement:staleAck});
  unwrap(await clients[0].from('projects').update({status:'active'}).eq('id',project),'Unarchive');
  unwrap(await clients[0].from('payments').insert({project_id:project,commitment_id:stale.activity,paid_by_member_id:owner,type:'refund',direction:'incoming',status:'paid',amount_minor:1000,paid_on:today}),'Refund');
  const staleBefore=await financialProof(stale);await deny(clients[0],'confirm_reimbursement_receipt',{p_acknowledgement:staleAck});
  await open(stale.activity,stale.title,page);await card(page,stale.request).getByText('Review needed',{exact:true}).waitFor();check(await card(page,stale.request).getByRole('button',{name:'Confirm received',exact:true}).count()===0,'Review no confirmation');
  assert.deepEqual(await financialProof(stale),staleBefore);await fits('Review-needed creditor state',page);
  pass('Archived and stale confirmation denied; no transfer beyond legitimate refund');
  stage='concurrent undo cancellation and independent settlement';
  for(const race of ['undo','cancel','settlement']){
    const fixture=await setup('Confirmation race '+race),a=await acknowledge(fixture.request);
    const competing=()=>race==='undo'?clients[1].rpc('withdraw_reimbursement_payment_acknowledgement',{p_acknowledgement:a}):race==='cancel'?clients[0].rpc('cancel_reimbursement',{p_request:fixture.request}):clients[0].rpc('record_item_settlement',{p_item:fixture.activity,p_from:debtor,p_to:owner,p_amount:45000,p_date:today});
    const outcomes=await Promise.all([clients[0].rpc('confirm_reimbursement_receipt',{p_acknowledgement:a}),competing()]);
    check(outcomes.filter(o=>!o.error).length===1,'Exactly one legal race winner '+race);
    const st=await status(fixture.request),payments=(await rows('payments','commitment_id',fixture.activity)).filter(p=>p.settlement_group_id);
    if(!outcomes[0].error){check(st.confirmation_id&&payments.length===2,'Confirm won with one pair');check((await rows('v_reimbursements','id',fixture.request))[0].status==='settled','No cancelled settled combination');check(!(await rows('reimbursement_payment_acknowledgements','id',a))[0].withdrawn_at,'Confirmed claim remains active');}
    else {check(!st.confirmation_id,'Competing operation won without confirmation');check(payments.length===(race==='settlement'?2:0),'No orphan or duplicate pair');}
    pass('Concurrent confirmation versus '+race+' serializes safely',{winner:outcomes[0].error?race:'confirmation'});
  }
  stage='post-confirm changes and existing reversal';
  unwrap(await clients[0].from('payments').insert({project_id:project,commitment_id:c.activity,paid_by_member_id:owner,type:'refund',direction:'incoming',status:'paid',amount_minor:1000,paid_on:today}),'Post-confirm refund');
  check((await status(c.request)).confirmation_state==='settled','Later refund retains historical confirmed state');
  await rpc('cancel_item_settlement',{p_group:confirmation.settlement_group_id});
  check((await status(c.request)).confirmation_state==='reversed','Existing correction derives reversed state');
  check((await rows('reimbursement_receipt_confirmations','id',confirmation.id)).length===1,'Reversal retains confirmation');
  check(await confirm(active)===confirmation.id,'Retry after reversal never recreates pair');
  await open(c.activity,c.title,memberPage);await card(memberPage,c.request).getByText('Settlement reversed',{exact:true}).waitFor();check(await card(memberPage,c.request).getByRole('button',{name:/I've paid|Undo|Confirm received/}).count()===0,'Reversed history does not reopen old request');
  pass('Later supplier refund and existing settlement correction retain immutable confirmation and do not replay settlement');
  report.historyBeforeCleanup=historyCounts();save();pass('Full actual develop Phase10 smoke complete');
} catch (error) {
  // Do not emit Playwright call logs, assertion values, fixture contents or tokens.
  let message = String(error.message || error);
  for (const u of users) for (const v of Object.values(u)) if (typeof v === 'string' && v) message = message.split(v).join('[private]');
  message = message.replace(/eyJ[A-Za-z0-9_.-]+/g, '[token]').replace(/[a-f0-9]{64}/g, '[token]');
  report.failure = { stage, message: message.slice(0, 1600) };
  console.error('FAIL receipt confirmations at ' + stage + ': ' + report.failure.message); process.exitCode = 1;
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
      for (const c of clients) for (const table of ['projects', 'commitments', 'activity_payment_schedules', 'project_members', 'v_my_reimbursement_notifications', 'v_my_payment_acknowledgement_notifications', 'reimbursement_payment_acknowledgements', 'reimbursement_receipt_confirmations', 'v_my_receipt_confirmation_notifications', 'v_reimbursements']) {
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
      for (const key of ['events', 'payments', 'requests', 'acknowledgements', 'confirmations', 'audit']) check(after[key] >= report.historyBeforeCleanup[key], 'Historical retention ' + key);
      report.historyAfterCleanup = after;
    } catch { cleanupErrors.push('history verification'); process.exitCode = 1; }
  }
  report.cleanup = cleanupErrors.length === 0;
  if (cleanupErrors.length) { report.cleanupErrors = cleanupErrors; console.error('Cleanup verification failed; see credential-free result.'); }
  report.finishedAt = new Date().toISOString(); save();
  await browser?.close();
  for (const c of clients) await c.auth.signOut({ scope: 'local' }).catch(() => {});
}
