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
const reportPath = process.env.NOTIFICATIONS_RESULT_FILE || '/tmp/orchestrio-notifications-live-result.json';
let users = [], clients = [], browser, page, project, category, createdLink;
let stage = 'preflight';
const report = { target, startedAt: new Date().toISOString(), projects: [], checks: [], cleanup: false };
function save() { fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), { mode: 0o600 }); }
function pass(name, evidence) {
  report.checks.push({ name, status: 'PASS', ...(evidence ? { evidence } : {}) });
  console.log('PASS notifications: ' + name); save();
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
async function waitForCronAfter(started) {
  const until = Date.now() + 90000;
  while (Date.now() < until) {
    const latest = query("select max(start_time)::text started from cron.job_run_details where jobid=1 and status='succeeded';")[0].started;
    if (latest && Date.parse(latest) > Date.parse(started)) return;
    await new Promise(r => setTimeout(r, 5000));
  }
  throw new Error('Timed out waiting for the installed notification scheduler');
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
  const memberPage = await pageFor(1); const viewerPage = await pageFor(2);
  pass('Three independent real browser logins; develop-only network');
  stage='isolated setup';
  const today=DateTime.utc().toISODate();
  project=uuid(await rpc('create_project',{p_name:'Phase 11 notification smoke '+new Date().toISOString(),p_timezone:'Pacific/Kiritimati',p_currency:'GBP',p_starts_on:today,p_profile:'team_project'}));
  report.projects.push(project);save();await join(1,'member');
  check((await rows('v_my_notification_inbox','project_id',project,clients[2])).length===0,'Outsider inbox isolation');
  pass('Outsider isolation before membership');
  await join(2,'viewer');
  category=unwrap(await clients[0].from('project_areas').insert({project_id:project,title:'Notification smoke'}).select().single(),'Category').id;
  const members=await rows('project_members','project_id',project);
  const owner=members.find(m=>m.user_id===users[0].id).id,member=members.find(m=>m.user_id===users[1].id).id;
  const kinds=['activities','decisions','payments','reimbursements','project_access'];
  for(const c of clients) for(const k of kinds) await rpc('set_my_notification_preference',{p_category:k,p_enabled:true},c);
  stage='settings browser persistence';
  await memberPage.goto(origin+'/app/settings');
  await memberPage.getByRole('heading',{name:'Notifications',exact:true}).waitFor();
  await memberPage.getByRole('checkbox',{name:'Payments',exact:true}).focus();await memberPage.keyboard.press('Space');
  await poll(async()=> (await rows('user_notification_preferences','category','payments',clients[1])).length===1);
  await memberPage.reload();
  check(!(await memberPage.getByRole('checkbox',{name:'Payments',exact:true}).isChecked()),'Preference persists across reload');
  await fits('Settings',memberPage);
  pass('Labelled keyboard-operable optional controls persist across refresh');
  stage='recipient specific suppression';
  await rpc('set_my_notification_preference',{p_category:'activities',p_enabled:false},clients[1]);
  const activity=uuid(await createActivity('Recipient-specific activity',90000,member));
  const suppressed=(await rows('v_my_notification_inbox','project_id',project,clients[1])).filter(n=>n.resource_id===activity);
  const delivered=(await rows('v_my_notification_inbox','project_id',project,clients[2])).filter(n=>n.resource_id===activity);
  check(suppressed.length===0&&delivered.length===1,'Same fact filters only opted-out recipient');
  const eventEvidence=query(`select count(*)::int events,(select count(*)::int from app.domain_event_processing d join app.domain_events e on e.id=d.event_id where e.resource_id='${activity}') processed,(select count(*)::int from app.automation_action_runs a join app.domain_events e on e.id=a.event_id where e.resource_id='${activity}') actions,(select count(*)::int from app.notification_delivery_receipts d join app.domain_events e on e.id=d.event_id where e.resource_id='${activity}' and d.outcome='preference_suppressed') suppressed,(select count(*)::int from app.notification_delivery_receipts d join app.domain_events e on e.id=d.event_id where e.resource_id='${activity}' and d.outcome='delivered') delivered from app.domain_events where resource_id='${activity}';`)[0];
  assert.deepEqual(eventEvidence,{events:1,processed:1,actions:1,suppressed:1,delivered:1});
  pass('Same event preserves facts/action/processing and records both recipient outcomes',eventEvidence);
  const financialBefore=await rows('v_project_financials','project_id',project);
  stage='payment schedule preferences';
  const localToday=DateTime.now().setZone('Pacific/Kiritimati').toISODate();
  const schedule=unwrap(await clients[0].from('activity_payment_schedules').insert({project_id:project,commitment_id:activity,title:'Optional deposit',amount_minor:90000,due_on:localToday}).select().single(),'Schedule').id;
  query('select app.evaluate_scheduled_domain_events();');
  check((await rows('v_my_payment_notifications','project_id',project,clients[1])).length===0,'Optional payment suppressed');
  check(query(`select count(*)::int n from app.domain_events where event_type='payment.due_soon' and resource_id='${uuid(schedule)}';`)[0].n===1,'Payment fact still exists');
  await memberPage.reload();await memberPage.getByRole('checkbox',{name:'Payments',exact:true}).check();
  await poll(async()=> (await rows('user_notification_preferences','category','payments',clients[1])).length===0);
  query('select app.evaluate_scheduled_domain_events();');
  check((await rows('v_my_payment_notifications','project_id',project,clients[1])).length===0,'No replay on enable');
  unwrap(await clients[0].from('activity_payment_schedules').update({due_on:DateTime.fromISO(localToday).plus({days:1}).toISODate()}).eq('id',schedule),'Schedule version');
  query('select app.evaluate_scheduled_domain_events();');
  check((await rows('v_my_payment_notifications','project_id',project,clients[1])).length===1,'Future version delivers');
  pass('Real scheduler preserves suppressed payment fact; re-enable delivers only future version');
  stage='Activity reminder';
  await rpc('set_my_notification_preference',{p_category:'activities',p_enabled:true},clients[1]);
  const cronBeforeActivity=query("select max(start_time)::text started from cron.job_run_details where jobid=1 and status='succeeded';")[0].started;
  unwrap(await clients[0].from('commitments').update({starts_at:DateTime.utc().plus({days:2}).toISO()}).eq('id',activity),'Activity date');
  await waitForCronAfter(cronBeforeActivity);
  let due=(await rows('v_my_notification_inbox','project_id',project,clients[1])).filter(n=>n.kind==='activity_due_soon');
  check(due.length===1,'One reminder despite repeated scan');
  await memberPage.goto(origin+'/app');await memberPage.getByRole('button',{name:'Notifications',exact:true}).click();
  await fits('Upcoming Activity inbox',memberPage);
  await memberPage.locator(`[data-notification-id="${due[0].id}"]`).click();
  await memberPage.getByRole('heading',{name:'Recipient-specific activity',exact:true}).waitFor();
  const cronBeforeVersion=query("select max(start_time)::text started from cron.job_run_details where jobid=1 and status='succeeded';")[0].started;
  unwrap(await clients[0].from('commitments').update({starts_at:DateTime.utc().plus({days:1}).toISO()}).eq('id',activity),'New date');
  await waitForCronAfter(cronBeforeVersion);
  due=(await rows('v_my_notification_inbox','project_id',project,clients[1])).filter(n=>n.kind==='activity_due_soon');
  check(due.length===2,'New timestamp version reminder');
  assert.deepEqual(await rows('v_project_financials','project_id',project),financialBefore);
  pass('Activity owner reminder, real deep link, new version, dedupe and financial invariance');
  stage='critical confirmations';
  await rpc('set_my_notification_preference',{p_category:'reimbursements',p_enabled:false},clients[1]);
  await rpc('set_my_notification_preference',{p_category:'reimbursements',p_enabled:false},clients[0]);
  await rpc('set_activity_cost_split',{p_commitment:activity,p_split:{mode:'custom',cost:90000,members:[owner,member],amounts:{[owner]:60000,[member]:30000}}});
  const payment=unwrap(await clients[0].from('payments').insert({project_id:project,commitment_id:activity,paid_by_member_id:owner,type:'full',direction:'outgoing',status:'paid',amount_minor:90000,paid_on:today}).select().single(),'Source payment').id;
  const request=uuid(await rpc('create_reimbursement',{p_payment:payment,p_debtor:member,p_amount:30000}));
  check((await rows('v_my_reimbursement_notifications','project_id',project,clients[1])).length===0,'Optional request suppressed');
  createdLink=uuid(await rpc('save_my_payment_link',{p_provider:'custom',p_url:'https://payments.example.com/orchestrio-phase11',p_label:'Smoke payment page'}));
  check((await rpc('get_reimbursement_payment_options',{p_request:request},clients[1])).some(link=>link.id===createdLink),'Debtor payment link remains available with notifications off');
  pass('Existing payment-link provider abstraction remains available; no provider request');
  let ack=uuid(await rpc('acknowledge_reimbursement_payment',{p_request:request},clients[1]));
  check((await rows('v_my_payment_acknowledgement_notifications','project_id',project)).length===1,'Critical claim delivered');
  await rpc('withdraw_reimbursement_payment_acknowledgement',{p_acknowledgement:ack},clients[1]);
  check((await rows('v_my_payment_acknowledgement_notifications','project_id',project)).some(n=>n.kind==='reimbursement_payment_acknowledgement_withdrawn'),'Critical withdrawal delivered');
  ack=uuid(await rpc('acknowledge_reimbursement_payment',{p_request:request},clients[1]));
  await open(activity,'Recipient-specific activity');
  await page.locator(`[data-reimbursement-id="${request}"]`).getByRole('button',{name:'Confirm received',exact:true}).click();
  await page.getByRole('dialog',{name:'Confirm receipt?',exact:true}).getByRole('button',{name:'Confirm received',exact:true}).click();
  await page.locator(`[data-reimbursement-id="${request}"]`).getByText('Settled',{exact:true}).waitFor();
  check((await rows('v_my_receipt_confirmation_notifications','project_id',project,clients[1])).length===1,'Critical receipt delivered despite opt-out');
  const balance=(await rows('v_activity_member_settlements','commitment_id',activity)).find(r=>r.member_id===member);
  check(balance.remaining_minor===0,'Actual settlement cleared debtor');
  await memberPage.goto(origin+'/app');await memberPage.getByRole('button',{name:'Notifications',exact:true}).click();
  await memberPage.getByRole('button').filter({hasText:'Reimbursement settled'}).click();
  await memberPage.locator(`[data-reimbursement-id="${request}"]`).getByText('Settled',{exact:true}).waitFor();
  pass('Optional request suppressed; critical claim/withdrawal/receipt survive opt-out; real creditor UI settles');
  stage='pagination and read state';
  for(let i=0;i<24;i++) await createActivity('Inbox pagination '+String(i).padStart(2,'0'),0);
  await viewerPage.goto(origin+'/app');await viewerPage.getByRole('button',{name:'Notifications',exact:true}).click();
  await poll(async()=>await viewerPage.locator('[data-notification-id]').count()===20);
  const firstIds=await viewerPage.locator('[data-notification-id]').evaluateAll(es=>es.map(e=>e.dataset.notificationId));
  await fits('Inbox unread and pagination',viewerPage);
  await viewerPage.getByRole('button',{name:'Load older notifications',exact:true}).click();
  await poll(async()=>await viewerPage.locator('[data-notification-id]').count()>20);
  const allIds=await viewerPage.locator('[data-notification-id]').evaluateAll(es=>es.map(e=>e.dataset.notificationId));
  check(new Set(allIds).size===allIds.length&&firstIds.every((id,i)=>id===allIds[i]),'Pagination stable no duplicates');
  const expected=(await rows('v_my_notification_inbox','project_id',project,clients[2])).map(n=>n.id);
  while(await viewerPage.getByRole('button',{name:'Load older notifications',exact:true}).count()) { await viewerPage.getByRole('button',{name:'Load older notifications',exact:true}).click();await new Promise(r=>setTimeout(r,500)); }
  const shown=await viewerPage.locator('[data-notification-id]').evaluateAll(es=>es.map(e=>e.dataset.notificationId));
  check(expected.every(id=>shown.includes(id)),'No missing synthetic notification');
  const otherUnread=(await rows('v_my_notification_inbox','project_id',project,clients[1])).filter(n=>!n.read_at).length;
  const markAll=viewerPage.getByRole('button',{name:'Mark all as read',exact:true});await markAll.focus();await viewerPage.keyboard.press('Enter');
  await poll(async()=>!(await rows('v_my_notification_inbox','project_id',project,clients[2])).some(n=>!n.read_at));
  check((await rows('v_my_notification_inbox','project_id',project,clients[1])).filter(n=>!n.read_at).length===otherUnread,'Other user remains unread');
  await fits('Inbox read history',viewerPage);
  pass('Cursor history no missing/duplicate rows, readable times, keyboard mark-all current user only',{syntheticItems:expected.length});
  report.retainedBefore=historyCounts();
} catch(error) {
  let message=error instanceof Error?error.message:String(error);
  for(const u of users) for(const value of [u.email,u.password,u.id]) if(value) message=message.split(value).join('[private]');
  report.failure={stage,message:message.slice(0,1400)};console.error('FAIL notifications at '+stage+': '+report.failure.message);process.exitCode=1;
} finally {
  stage='cleanup';
  try {
    if(createdLink) await rpc('delete_my_payment_link',{p_id:createdLink});
    if(project) for(const c of clients) for(const category of ['activities','decisions','payments','reimbursements','project_access']) await rpc('set_my_notification_preference',{p_category:category,p_enabled:true},c);
    if(project) {
      await rpc('soft_delete_project',{p_project:project});
      for(const c of clients) for(const table of ['projects','commitments','project_members','v_my_notification_inbox','v_reimbursements']) { const remaining=await rows(table,table==='projects'?'id':'project_id',project,c);check((table==='project_members'?remaining.filter(m=>m.status==='active'&&!m.deleted_at):remaining).length===0,'Cleanup '+table); }
      for(const c of clients) check(unwrap(await c.from('user_notification_preferences').select('category'),'Preference reset').length===0,'No preference overrides');
      report.retainedAfter=historyCounts();
      if(report.retainedBefore) for(const key of Object.keys(report.retainedBefore)) check(report.retainedAfter[key]>=report.retainedBefore[key],'History retained '+key);
      check(!(await rpc('list_my_payment_links',{})).some(link=>link.id===createdLink),'Synthetic link removed');
      const emptyPage=await pageFor(1);await emptyPage.goto(origin+'/app');await emptyPage.getByRole('button',{name:'Notifications',exact:true}).click();
      await emptyPage.getByText('No updates yet.',{exact:true}).waitFor();await fits('Inbox empty state',emptyPage);
      report.cleanupEvidence=query(`select (select count(*)::int from public.projects where id='${uuid(project)}' and deleted_at is null) live_projects,(select count(*)::int from public.commitments where project_id='${project}' and deleted_at is null) live_activities,(select count(*)::int from public.project_members where project_id='${project}' and deleted_at is null and status='active') active_memberships;`)[0];
      assert.deepEqual(report.cleanupEvidence,{live_projects:0,live_activities:0,active_memberships:0});
    }
    report.cleanup=true;pass('Domain API cleanup and preference reset; history retained');
  } catch(error) {report.cleanup=false;let message=error instanceof Error?error.message:'Cleanup failed';for(const u of users) for(const value of [u.email,u.password,u.id]) if(value) message=message.split(value).join('[private]');report.cleanupFailure=message.slice(0,800);console.error('FAIL notification cleanup: '+report.cleanupFailure);process.exitCode=1;}
  await browser?.close();for(const c of clients) await c.auth.signOut();report.finishedAt=new Date().toISOString();save();
}
