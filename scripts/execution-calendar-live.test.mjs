/** Real develop Calendar HTTP/browser verification. No auth creation, email or successful-response mocks.
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
const reportPath = process.env.CALENDAR_RESULT_FILE || '/tmp/orchestrio-calendar-live-result.json';
let users = [], clients = [], browser, page, project, category;
let stage = 'preflight';
const report = { target, startedAt: new Date().toISOString(), projects: [], checks: [], cleanup: false };
function save() { fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), { mode: 0o600 }); }
function pass(name, evidence) {
  report.checks.push({ name, status: 'PASS', ...(evidence ? { evidence } : {}) });
  console.log('PASS calendar: ' + name); save();
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
    const r = spawnSync('supabase', ['db', 'query', '--linked', '--project-ref', target, '--file', file], { encoding: 'utf8', timeout: 120000 });
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
  const zone='Pacific/Kiritimati', local=DateTime.now().setZone(zone).plus({days:2}), day=local.toISODate();
  const rangeStart=local.startOf('month').startOf('week').toISODate(), rangeEnd=local.endOf('month').endOf('week').plus({days:1}).toISODate();
  project=uuid(await rpc('create_project',{p_name:'Phase 12 Calendar smoke '+new Date().toISOString(),p_timezone:zone,p_currency:'GBP',p_starts_on:day,p_profile:'team_project'}));
  report.projects.push(project);save();
  const read=(client=clients[0])=>rpc('get_project_calendar',{p_project:project,p_range_start:rangeStart,p_range_end:rangeEnd},client);
  check((await read(clients[2])).length===0,'Outsider Calendar isolation');
  await join(1,'member');await join(2,'viewer');
  category=unwrap(await clients[0].from('project_areas').insert({project_id:project,title:'Calendar category with a long descriptive name for responsive verification'}).select().single(),'Category').id;
  const members=await rows('project_members','project_id',project), owner=members.find(m=>m.user_id===users[0].id).id;
  const activity=uuid(await createActivity('Venue visit with a long descriptive title for responsive verification',10000,owner));
  const stamp=local.startOf('day').plus({hours:13,minutes:30}).toUTC().toISO();
  unwrap(await clients[0].from('commitments').update({starts_at:stamp,is_all_day:false,activity_type:'event'}).eq('id',activity),'Timed Activity');
  const allDay=uuid(await createActivity('All-day checklist',0,owner));
  unwrap(await clients[0].from('commitments').update({starts_at:local.startOf('day').toUTC().toISO(),is_all_day:true}).eq('id',allDay),'All day');
  const decision=uuid(await rpc('create_decision',{p_project:project,p_title:'Choose venue',p_description:null,p_deadline:stamp,p_options:[{title:'A'},{title:'B'}]}));
  const schedule=unwrap(await clients[0].from('activity_payment_schedules').insert({project_id:project,commitment_id:activity,title:'Deposit',amount_minor:10000,due_on:day}).select().single(),'Schedule').id;
  unwrap(await clients[0].from('payments').insert({project_id:project,commitment_id:activity,payment_schedule_id:schedule,type:'deposit',status:'scheduled',amount_minor:10000,due_on:day}),'Legacy schedule');
  const series=uuid(await createActivity('Weekly check',0,owner));
  unwrap(await clients[0].from('commitments').update({starts_at:stamp,recurrence_frequency:'weekly',recurrence_interval:1,recurrence_start_date:day,recurrence_end_date:local.plus({days:14}).toISODate(),recurrence_active:true}).eq('id',series),'Recurring Activity');
  const entries=await read();
  check(entries.filter(e=>e.source_type==='payment_schedule').length===1,'No linked duplicate');
  check(entries.some(e=>e.source_id===activity&&e.start_at===stamp.replace('.000Z','+00:00')) || entries.some(e=>e.source_id===activity&&Date.parse(e.start_at)===Date.parse(stamp)),'Timestamp authority');
  check(entries.find(e=>e.source_id===allDay).start_date===day,'All day authority');
  check(!entries.some(e=>e.source_id===series&&e.source_type==='activity'),'No recurring parent');
  for(const c of clients) assert.deepEqual((await read(c)).map(e=>e.entry_id).sort(),entries.map(e=>e.entry_id).sort());
  pass('Organizer Member Viewer source visibility; outsider isolation; normalized dates and duplicate suppression');
  const calendarUrl=`${origin}/app/projects/${project}/calendar`;
  async function show(p=page,mode='Agenda') {
    await p.goto(calendarUrl);await p.getByRole('button',{name:mode,exact:true}).click();
    // Sources are two days ahead, which can cross into the next month.
    if(local.month!==DateTime.now().setZone(zone).month) await p.getByRole('button',{name:'Next month',exact:true}).click();
    await p.getByRole('link',{name:/Payment due: Deposit/}).first().waitFor();
  }
  for(const p of [page,memberPage,viewerPage]) {await show(p);await p.getByRole('link',{name:/Decision deadline: Choose venue/}).waitFor();}
  pass('Three independent browser Calendar reads');
  await fits('Agenda long content',page);
  check(await page.getByText('13:30 · Venue visit',{exact:false}).count()>0,'Project-local time in UTC browser');
  check(await page.getByText('00:00',{exact:true}).count()===0,'No midnight artifacts');
  await page.getByRole('button',{name:'Activities',exact:true}).click();
  check(await page.getByRole('link',{name:/Payment due: Deposit/}).count()===0,'Activities filter');
  await page.getByRole('button',{name:'Decisions',exact:true}).click();
  check(await page.getByRole('link',{name:/Activity ·/}).count()===0,'Decisions filter');
  await page.getByRole('button',{name:'Payments',exact:true}).click();
  check(await page.getByRole('link',{name:/Decision deadline:/}).count()===0,'Payments filter');
  await page.getByRole('button',{name:'All',exact:true}).click();
  pass('Project timezone and all source filters');
  await page.getByRole('button',{name:'Month',exact:true}).click();
  for(const width of [375,430,768,1280]) {
    await page.setViewportSize({width,height:950});
    check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Month overflow '+width);
    await page.screenshot({path:`/tmp/phase12-calendar-${width}.png`,fullPage:true});
  }
  await page.getByRole('button',{name:new RegExp(local.toFormat('cccc, d LLLL yyyy'))}).click();
  check(await page.getByRole('link',{name:/Payment due: Deposit/}).count()>0,'Day overflow complete list');
  await page.getByRole('button',{name:'Next month',exact:true}).focus();await page.keyboard.press('Enter');
  await page.getByRole('button',{name:'Today',exact:true}).click();
  pass('Month grid, day overflow, keyboard navigation and responsive 375 430 768 1280');
  stage='canonical deep links';
  await show();await page.getByRole('link',{name:/Payment due: Deposit/}).click();
  await page.locator('#activity-payments').waitFor();check(new URL(page.url()).searchParams.get('section')==='payments','Payment canonical section');
  await show();await page.getByRole('link',{name:/Decision deadline: Choose venue/}).click();
  await page.waitForURL(`**/decisions/${decision}`);
  await show();await page.getByRole('link',{name:/Activity · task: Weekly check/}).first().click();
  await page.waitForURL(u=>u.searchParams.get('occurrence')===day);
  check(new URL(page.url()).searchParams.get('commitment')===series,'Occurrence deep link');
  await show();await page.getByRole('link',{name:/Activity · task: All-day checklist/}).click();
  await page.getByRole('heading',{name:'All-day checklist',exact:true}).waitFor();
  pass('Activity Decision Payment and exact occurrence deep links');
  stage='source reschedule UI';
  await page.getByRole('button',{name:'Edit',exact:true}).click();
  await page.getByLabel('Due date',{exact:true}).fill(local.plus({days:1}).toISODate());
  await page.getByRole('button',{name:'Save activity',exact:true}).click();
  await poll(async()=> (await read()).find(e=>e.source_id===allDay)?.start_date===local.plus({days:1}).toISODate());
  await show();check((await read()).filter(e=>e.source_id===allDay).length===1,'Reschedule unique source');
  pass('Existing Activity edit UI reschedules source without Calendar mutation');
  stage='lifecycle';
  const options=await rows('decision_options','decision_id',decision);
  await rpc('resolve_decision',{p_decision:decision,p_option:options[0].id});
  for(const amount of [4000,6000]) {
    unwrap(await clients[0].from('payments').insert({project_id:project,commitment_id:activity,payment_schedule_id:schedule,paid_by_member_id:owner,type:'deposit',direction:'outgoing',status:'paid',amount_minor:amount,paid_on:DateTime.now().setZone(zone).toISODate()}),'Paid allocation');
    check((await read()).find(e=>e.source_id===schedule).status===(amount===4000?'part_paid':'paid'),'Payment progression');
  }
  unwrap(await clients[0].from('commitments').update({status:'completed'}).eq('id',allDay),'Complete');
  await show();
  await page.getByRole('link',{name:/Decision deadline: Choose venue, Resolved/}).waitFor();
  await page.getByRole('link',{name:/Payment due: Deposit, Paid/}).waitFor();
  await page.getByRole('link',{name:/Activity · task: All-day checklist, Complete/}).waitFor();
  const financialBefore=await rows('v_project_financials','project_id',project), historyBefore=historyCounts();
  await read();await read(clients[1]);await read(clients[2]);
  assert.deepEqual(await rows('v_project_financials','project_id',project),financialBefore);const historyAfter=historyCounts();
  // The real minute scheduler can append due-soon events between HTTP requests.
  for(const key of Object.keys(historyBefore).filter(k=>k!=='events')) check(historyAfter[key]===historyBefore[key], 'Read preserves '+key);
  check(historyAfter.events>=historyBefore.events,'Append-only reminder history');
  pass('Resolved completed and paid history; part-paid progression; no read financial or history mutation');
  stage='empty and error states';
  await page.setViewportSize({width:375,height:950});await page.goto(calendarUrl);
  await page.getByRole('button',{name:'Agenda',exact:true}).waitFor();
  check(await page.getByRole('button',{name:'Agenda',exact:true}).getAttribute('aria-pressed')==='true','Mobile defaults to Agenda');
  await page.getByRole('button',{name:'Next month',exact:true}).click();
  await page.getByText('Nothing scheduled in this range.',{exact:false}).waitFor();
  await fits('Empty Calendar');
  await page.setViewportSize({width:1280,height:950});await page.goto(calendarUrl);
  check(await page.getByRole('button',{name:'Month',exact:true}).getAttribute('aria-pressed')==='true','Desktop defaults to Month');
  await page.route('**/rest/v1/rpc/get_project_calendar',r=>r.abort());
  await page.reload();await page.getByText("Calendar couldn't be loaded.",{exact:true}).waitFor();
  await page.unroute('**/rest/v1/rpc/get_project_calendar');
  await page.getByRole('button',{name:'Retry',exact:true}).click();
  await page.getByRole('table',{name:'Month calendar'}).waitFor();
  pass('Responsive default views, bounded empty window, safe error and real-response retry');
  report.retainedBefore=historyCounts();
} catch(error) {
  let message=error instanceof Error?error.message:String(error);
  for(const u of users) for(const value of [u.email,u.password,u.id]) if(value) message=message.split(value).join('[private]');
  report.failure={stage,message:message.slice(0,1400)};console.error('FAIL calendar at '+stage+': '+report.failure.message);process.exitCode=1;
} finally {
  try {
    if(project) {
      await rpc('soft_delete_project',{p_project:project});
      report.cleanupEvidence=query(`select (select count(*)::int from public.projects where id='${uuid(project)}' and deleted_at is null) live_projects,(select count(*)::int from public.commitments where project_id='${project}' and deleted_at is null) live_activities,(select count(*)::int from public.project_members where project_id='${project}' and deleted_at is null and status='active') active_memberships;`)[0];
      assert.deepEqual(report.cleanupEvidence,{live_projects:0,live_activities:0,active_memberships:0});
      report.retainedAfter=historyCounts();
      if(report.retainedBefore) for(const key of Object.keys(report.retainedBefore)) check(report.retainedAfter[key]>=report.retainedBefore[key],'History retained '+key);
    }
    report.cleanup=true;pass('Domain API cleanup; zero live fixtures; history retained; preferences and payment links untouched');
  } catch(error) {report.cleanup=false;report.cleanupFailure=error instanceof Error?error.message:'Cleanup failed';console.error('FAIL calendar cleanup');process.exitCode=1;}
  await browser?.close();for(const c of clients) await c.auth.signOut();report.finishedAt=new Date().toISOString();save();
}
