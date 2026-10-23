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
const reportPath = process.env.REIMBURSEMENT_RESULT_FILE || '/tmp/orchestrio-reimbursements-live-result.json';
let users = [], clients = [], browser, page, project, crossProject, category;
let stage = 'preflight';
const report = { target, startedAt: new Date().toISOString(), projects: [], checks: [], cleanup: false };
function save() { fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), { mode: 0o600 }); }
function pass(name, evidence) {
  report.checks.push({ name, status: 'PASS', ...(evidence ? { evidence } : {}) });
  console.log('PASS reimbursements: ' + name); save();
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
 for(const table of ['v_project_financials','v_activity_member_settlements','v_member_balances','cost_shares','v_activity_payment_schedule_financials','payments']) result[table]=sorted(await rows(table,'project_id',project));
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
  stage='isolated project and membership setup';
  const today=DateTime.utc().toISODate();
  project=uuid(await rpc('create_project',{p_name:'Reimbursement smoke '+new Date().toISOString(),p_timezone:'UTC',p_currency:'GBP',p_starts_on:today,p_profile:'team_project'}));
  crossProject=uuid(await rpc('create_project',{p_name:'Reimbursement isolation '+new Date().toISOString(),p_timezone:'UTC',p_currency:'GBP',p_starts_on:today,p_profile:'team_project'},clients[2]));
  report.projects.push(project,crossProject);save();
  await join(1,'member');
  category=unwrap(await clients[0].from('project_areas').insert({project_id:project,title:'Reimbursement smoke'}).select().single(),'Category').id;
  const title='Villa reimbursement smoke';
  const activity=uuid(await createActivity(title,90000));report.activity=activity;save();
  for(const table of ['v_reimbursements','reimbursement_requests','commitments']) check((await rows(table,'project_id',project,clients[2])).length===0,'Outsider read denied');
  await outsiderPage.goto(`${origin}/app/projects/${project}/areas?commitment=${activity}`);
  await outsiderPage.waitForLoadState('networkidle');
  check(await outsiderPage.locator('#activity-reimbursements').count()===0,'Outsider browser isolation');
  pass('Cross-project Organizer outsider cannot read project reimbursement context');
  await join(2,'member');
  const members=await rows('project_members','project_id',project);
  const ids=users.map(u=>uuid(members.find(m=>m.user_id===u.id).id));
  async function split(id){await rpc('set_activity_cost_split',{p_commitment:id,p_split:{mode:'even',cost:90000,members:ids}});}
  async function paid(id,who,amount,client=clients[0]){
    return unwrap(await client.from('payments').insert({project_id:project,commitment_id:id,paid_by_member_id:ids[who],type:'full',direction:'outgoing',status:'paid',amount_minor:amount,paid_on:today}).select().single(),'Actual payment').id;
  }
  await split(activity);
  stage='real payment browser form';
  await open(activity,title);
  const payments=page.locator('#activity-payments');
  await payments.getByRole('button',{name:'Add payment',exact:true}).click();
  await payments.getByLabel('Amount',{exact:true}).fill('900');
  await payments.locator('form').getByRole('button',{name:'Add payment',exact:true}).click();
  await payments.getByLabel('Amount',{exact:true}).waitFor({state:'hidden'});
  const source=uuid((await rows('payments','commitment_id',activity)).find(p=>p.status==='paid').id);
  const suggestions=await rpc('get_reimbursement_suggestions',{p_payment:source});
  check(suggestions.length===2&&suggestions.every(s=>s.amount_minor===30000&&s.creditor_member_id===ids[0]&&s.debtor_member_id!==ids[0]),'Single payer current balance suggestions');
  const before=await snapshot();
  stage='browser create reimbursements';
  const panel=page.locator('#activity-reimbursements');
  await panel.getByRole('button',{name:'Create reimbursements',exact:true}).click();
  await poll(async()=>await panel.locator('input[type=checkbox]').count()===2);
  check((await panel.textContent()).includes('£600.00'),'Suggested total 600 visible');
  await fits('Suggestion form and amounts');
  await panel.getByRole('button',{name:'Create selected reimbursements',exact:true}).click();
  await poll(async()=>(await rows('v_reimbursements','commitment_id',activity)).length===2);
  await poll(async()=>await panel.locator('[data-reimbursement-id]').count()===2);
  assert.deepEqual(await snapshot(),before);
  const requests=await rows('v_reimbursements','commitment_id',activity);
  const a=requests.find(r=>r.debtor_member_id===ids[1]),b=requests.find(r=>r.debtor_member_id===ids[2]);
  check(a&&b&&requests.every(r=>r.is_creditor&&!r.needs_review),'Creditor context');
  check((await panel.getByText(/owes you/).count())===2,'Organizer sees both owed to them');
  await fits('Creditor list and source provenance');
  await page.reload();await panel.locator(`[data-reimbursement-id="${a.id}"]`).waitFor();
  pass('£900 payment creates two £300 requests through browser; reload persists; cost/spend/shares/schedules/all balances unchanged',{costMinor:90000,spendMinor:90000,workflowMinor:60000});
  stage='debtor isolation notification health';
  for(const [index,p,r] of [[1,memberPage,a],[2,outsiderPage,b]]){
    const own=await rows('v_reimbursements','commitment_id',activity,clients[index]);
    check(own.length===1&&own[0].id===r.id&&own[0].is_debtor,'Debtor sees own only');
    const inbox=await rows('v_my_reimbursement_notifications','project_id',project,clients[index]);
    check(inbox.length===1&&inbox[0].reimbursement_id===r.id,'Exactly one debtor notification');
    await p.goto(`${origin}/app/projects/${project}/overview`);
    await p.getByRole('button',{name:'Notifications',exact:true}).click();
    await p.locator('section[aria-labelledby=reimbursement-notifications-title]').getByRole('button').filter({hasText:'Reimbursement requested'}).click();
    await p.locator('#activity-reimbursements').waitFor();
    check(p.url().includes('section=reimbursements')&&p.url().includes(activity),'Notification canonical destination');
    await p.locator('#activity-reimbursements').getByText(/^You owe /).waitFor();
    check(await p.locator('#activity-reimbursements [data-reimbursement-id]').count()===1,'Debtor browser privacy');
    await fits('Debtor perspective and notification destination',p);
    check((await rows('v_my_reimbursement_notifications','project_id',project,clients[index]))[0].read_at,'Notification read');
    const findings=(await rpc('get_project_health',{p_project:project},clients[index])).filter(f=>f.subject_type==='reimbursement');
    check(findings.length===1&&findings[0].subject_id===r.id&&!findings[0].affects_health&&!/overdue|due soon/i.test(findings[0].message),'Debtor attention without urgency');
    await p.goto(`${origin}/app/projects/${project}/overview`);
    await p.locator('a[href*="section=reimbursements"]:visible').filter({hasText:/You owe /}).first().waitFor();
    await fits('Debtor Needs Attention',p);
  }
  check((await rows('v_my_reimbursement_notifications','project_id',project)).length===0,'No creditor notification');
  check(!(await rpc('get_project_health',{p_project:project})).some(f=>f.subject_type==='reimbursement'),'No creditor personal alert');
  await deny(clients[1],'cancel_reimbursement',{p_request:a.id});
  await deny(clients[1],'create_reimbursement',{p_payment:source,p_debtor:ids[2],p_amount:30000});
  pass('Both debtors see only their request; debtor-only notification opens Activity and marks read; personal attention has no due urgency');
  stage='existing member balance drill-down';
  await page.goto(`${origin}/app/projects/${project}/budget`);
  await poll(async()=>await page.locator('section[aria-label=Balances] details').count()>=3);
  for(const detail of await page.locator('section[aria-label=Balances] details').all()){
    if(await detail.locator('section[aria-label="Reimbursement requests"]').count()) await detail.locator('summary').click();
  }
  await page.locator('section[aria-label="Reimbursement requests"]').getByRole('link').first().waitFor();
  await fits('Member balance reimbursement drill-down');
  await page.locator('section[aria-label="Reimbursement requests"]').getByRole('link').first().click();
  await panel.waitFor();check(page.url().includes('section=reimbursements'),'Balance destination');
  pass('Existing member balance drill-down shows source requests and links to Activity without adding aggregate totals');
  stage='cancellation browser';
  await panel.locator(`[data-reimbursement-id="${a.id}"]`).getByRole('button',{name:'Cancel reimbursement',exact:true}).click();
  await fits('Cancellation confirmation');
  await panel.getByRole('button',{name:'Confirm cancellation',exact:true}).click();
  await panel.locator(`[data-reimbursement-id="${a.id}"]`).getByText('Cancelled',{exact:true}).waitFor();
  assert.deepEqual(await snapshot(),before);
  check((await rows('v_my_reimbursement_notifications','project_id',project,clients[1])).length===0,'Cancelled inbox disappears');
  check(!(await rpc('get_project_health',{p_project:project},clients[1])).some(f=>f.subject_id===a.id),'Cancelled health disappears');
  pass('Browser cancellation retains payment, shares and every balance; removes debtor inbox and attention');
  stage='viewer party';
  unwrap(await clients[0].from('project_members').update({role:'viewer'}).eq('id',ids[2]),'Viewer role');
  await open(activity,title,outsiderPage);
  await outsiderPage.locator('#activity-reimbursements').getByText(/^You owe /).waitFor();
  check(await outsiderPage.locator('#activity-reimbursements').getByRole('button').count()===0,'Viewer no mutation UI');
  await deny(clients[2],'cancel_reimbursement',{p_request:b.id});
  await deny(clients[2],'create_reimbursement',{p_payment:source,p_debtor:ids[1],p_amount:30000});
  unwrap(await clients[0].from('project_members').update({role:'member'}).eq('id',ids[2]),'Member restore');
  pass('Viewer party can read own request, with no mutation UI or backend authority');
  stage='refund reconciliation';
  unwrap(await clients[0].from('payments').insert({project_id:project,commitment_id:activity,paid_by_member_id:ids[0],type:'refund',direction:'incoming',status:'paid',amount_minor:10000,paid_on:today}),'Refund');
  check((await rows('v_reimbursements','id',b.id))[0].needs_review,'Refund flags snapshot');
  await deny(clients[0],'get_reimbursement_suggestions',{p_payment:source});
  check(!(await rpc('get_project_health',{p_project:project},clients[2])).some(f=>f.subject_id===b.id),'Review not stale debt attention');
  await open(activity,title,outsiderPage);
  await outsiderPage.locator('#activity-reimbursements').getByText('Review needed',{exact:true}).waitFor();
  check(await outsiderPage.locator('#activity-reimbursements').getByText(/^You owe /).count()===0,'No stale owed assertion');
  check((await rows('v_my_reimbursement_notifications','project_id',project,clients[2]))[0].needs_review,'Review notification model');
  await rpc('cancel_reimbursement',{p_request:b.id});
  check((await rpc('get_reimbursement_suggestions',{p_payment:source})).reduce((s,r)=>s+r.amount_minor,0)===50000,'Current creditor capacity after refund');
  pass('Refund preserves original request, requires review/cancellation, removes stale debt claim and reduces new capacity');
  stage='multiple payer authoritative suggestions';
  const multiTitle='Multiple payer reimbursement smoke',multi=uuid(await createActivity(multiTitle,90000));await split(multi);
  const multiSource=await paid(multi,0,60000);const otherSource=await paid(multi,1,30000,clients[1]);
  check((await rpc('get_reimbursement_suggestions',{p_payment:otherSource},clients[1])).length===0,'Own share only no suggestions');
  const multiSuggestions=await rpc('get_reimbursement_suggestions',{p_payment:multiSource});
  const balances=await rows('v_activity_member_settlements','commitment_id',multi);
  check(multiSuggestions.length===1&&multiSuggestions[0].debtor_member_id===ids[2]&&multiSuggestions[0].amount_minor===Math.min(balances.find(s=>s.member_id===ids[2]).remaining_minor,-balances.find(s=>s.member_id===ids[0]).remaining_minor),'Same existing settlement bounds');
  await open(multi,multiTitle);await panel.getByRole('button',{name:'Create reimbursements',exact:true}).click();
  await panel.getByLabel('Paid payment',{exact:true}).selectOption(multiSource);
  await poll(async()=>await panel.locator('input[type=checkbox]').count()===1);
  const multiBefore=await snapshot();
  await panel.getByRole('button',{name:'Create selected reimbursements',exact:true}).click();
  await poll(async()=>(await rows('v_reimbursements','commitment_id',multi)).length===1);
  assert.deepEqual(await snapshot(),multiBefore);
  pass('£600 Organizer + £300 Member payer case matches existing settlement view; no self/own-share request or double counting');
  stage='payer Member browser and retry';
  const memberTitle='Member payer reimbursement smoke',memberActivity=uuid(await createActivity(memberTitle,90000));await split(memberActivity);
  await paid(memberActivity,0,30000);const memberSource=await paid(memberActivity,1,60000,clients[1]);
  await open(memberActivity,memberTitle,memberPage);
  const memberPanel=memberPage.locator('#activity-reimbursements');
  await memberPanel.getByRole('button',{name:'Create reimbursements',exact:true}).click();
  await poll(async()=>await memberPanel.locator('input[type=checkbox]').count()===1);
  await memberPanel.getByRole('button',{name:'Create selected reimbursements',exact:true}).click();
  await memberPanel.getByText(/owes you/).waitFor();
  const retry=await Promise.all([0,1].map(()=>rpc('create_reimbursement',{p_payment:memberSource,p_debtor:ids[2],p_amount:30000},clients[1])));
  check(retry[0]===retry[1]&&(await rows('v_reimbursements','commitment_id',memberActivity)).length===1,'Concurrent exact retry one request');
  await memberPanel.getByRole('button',{name:'Cancel reimbursement',exact:true}).click();
  await memberPanel.getByRole('button',{name:'Confirm cancellation',exact:true}).click();
  await memberPanel.getByText('Cancelled',{exact:true}).waitFor();
  pass('Authoritative payer Member creates and cancels in browser; concurrent exact retries return one request');
  stage='event evidence';
  const facts=query(`select e.event_type,e.resource_type,e.resource_id,e.payload,(select count(*)::int from app.domain_event_processing p where p.event_id=e.id) processing,(select count(*)::int from app.automation_action_runs a where a.event_id=e.id) actions,(select count(*)::int from public.notifications n where n.domain_event_id=e.id) notifications from app.domain_events e where e.project_id='${uuid(project)}' and e.event_type like 'reimbursement.%' order by e.created_at,e.id;`);
  check(facts.length===7,'Four creation and three cancellation facts');
  for(const fact of facts){check(fact.resource_type==='reimbursement'&&fact.processing===1,'Canonical event receipt');assert.deepEqual(Object.keys(fact.payload).sort(),['activity_id','payment_id']);check(fact.actions===(fact.event_type==='reimbursement.created'?1:0)&&fact.notifications===fact.actions,'Only creation notifies once');}
  report.eventEvidence=facts;report.historyBeforeCleanup=historyCounts();save();
  pass('Minimal creation/cancellation facts; one processing receipt and debtor action/notification per creation');
  pass('Full real develop reimbursement browser smoke complete');
} catch (error) {
  // Do not emit Playwright call logs, assertion values, fixture contents or tokens.
  let message = String(error.message || error);
  for (const u of users) for (const v of Object.values(u)) if (typeof v === 'string' && v) message = message.split(v).join('[private]');
  message = message.replace(/eyJ[A-Za-z0-9_.-]+/g, '[token]').replace(/[a-f0-9]{64}/g, '[token]');
  report.failure = { stage, message: message.slice(0, 1600) };
  console.error('FAIL reimbursements at ' + stage + ': ' + report.failure.message); process.exitCode = 1;
} finally {
  stage = 'cleanup';
  const cleanupErrors = [];
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
