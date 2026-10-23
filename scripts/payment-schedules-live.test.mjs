/** Real develop HTTP/browser/cron verification. No auth creation, email or mocks.
 * PAYMENT_FIXTURE_FILE: private JSON {users:[{id,email,password}, ...]} outside repo.
 * Three existing accounts: Organizer, Member, outsider then Viewer. Cleanup in finally.
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
const reportPath = process.env.PAYMENT_RESULT_FILE || '/tmp/orchestrio-payments-live-result.json';
let users = [], clients = [], browser, page, project, crossProject, category;
let stage = 'preflight';
const report = { target, startedAt: new Date().toISOString(), projects: [], checks: [], cleanup: false };
function save() { fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), { mode: 0o600 }); }
function pass(name, evidence) {
  report.checks.push({ name, status: 'PASS', ...(evidence ? { evidence } : {}) });
  console.log('PASS payments: ' + name); save();
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
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'orchestrio-payment-smoke-'));
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
const panel = () => page.locator('#activity-payments');
const scheduleRow = title => panel().locator('.divide-y').first().locator(':scope > div').filter({ has: page.getByText(title, { exact: true }) });
async function addSchedule(label, amount, date) {
  await panel().getByRole('button', { name: 'Add schedule', exact: true }).click();
  await panel().getByLabel('Payment label', { exact: true }).fill(label);
  await panel().getByLabel('Payment amount', { exact: true }).fill(String(amount));
  await panel().getByLabel('Payment due date', { exact: true }).fill(date);
  await fits('Schedule form');
  await panel().locator('form').getByRole('button', { name: 'Add schedule', exact: true }).click();
  await panel().getByText(label, { exact: true }).waitFor();
}
async function paymentForm(id, amount) {
  await panel().getByRole('button', { name: 'Add payment', exact: true }).click();
  if (id) await panel().getByLabel('Payment schedule', { exact: true }).selectOption(id);
  else check(await panel().getByLabel('Payment schedule', { exact: true }).count() === 0, 'Direct payment must not require schedule');
  await panel().getByLabel('Amount', { exact: true }).fill(String(amount));
}
async function pay(id, amount) {
  await paymentForm(id, amount); await fits(id ? 'Payment allocation selector' : 'Direct payment form');
  await panel().locator('form').getByRole('button', { name: 'Add payment', exact: true }).click();
  await panel().getByLabel('Amount', { exact: true }).waitFor({ state: 'hidden' });
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
async function summary(cost, paid, remaining) {
  for (const [label, value] of [['Cost', cost], ['Paid', paid], ['Remaining', remaining]]) {
    const item = page.getByRole('dialog').getByText(label, { exact: true }).first().locator('..');
    await poll(async () => (await item.textContent()).includes(value));
  }
}
async function budget(spent) {
  await page.goto(`${origin}/app/projects/${project}/budget`);
  const tile = page.getByText('Spent so far', { exact: true }).first().locator('..');
  await poll(async () => (await tile.textContent()).includes(spent));
}
function historyCounts() {
  return query(`select jsonb_build_object('events',(select count(*) from app.domain_events where project_id='${uuid(project)}'),'processing',(select count(*) from app.domain_event_processing ep join app.domain_events e on e.id=ep.event_id where e.project_id='${project}'),'actions',(select count(*) from app.automation_action_runs a join app.domain_events e on e.id=a.event_id where e.project_id='${project}'),'payments',(select count(*) from public.payments where project_id='${project}'),'audit',(select count(*) from public.audit_log where project_id='${project}')) evidence;`)[0].evidence;
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
  const memberPage = await pageFor(1), outsiderPage = await pageFor(2);
  pass('Three independent real browser logins; develop-only network');
  // Choose a project calendar date different from UTC; browser itself stays UTC.
  const utcNow = DateTime.utc();
  const zone = utcNow.setZone('Pacific/Kiritimati').toISODate() !== utcNow.toISODate() ? 'Pacific/Kiritimati' : 'Pacific/Honolulu';
  const today = utcNow.setZone(zone);
  check(today.toISODate() !== utcNow.toISODate(), 'Timezone test must cross UTC date boundary');
  report.timezone = { zone, projectToday: today.toISODate(), utcToday: utcNow.toISODate(), browserZone: 'UTC' };
  stage = 'isolated setup';
  project = uuid(await rpc('create_project', { p_name: 'Payment schedule smoke ' + new Date().toISOString(), p_timezone: zone, p_currency: 'GBP', p_starts_on: today.toISODate(), p_profile: 'team_project' }));
  report.projects.push(project); save();
  await join(1, 'member');
  crossProject = uuid(await rpc('create_project', { p_name: 'Payment isolation smoke ' + new Date().toISOString(), p_timezone: 'UTC', p_currency: 'GBP', p_starts_on: utcNow.toISODate(), p_profile: 'team_project' }, clients[2]));
  report.projects.push(crossProject); save();
  category = unwrap(await clients[0].from('project_areas').insert({ project_id: project, title: 'Venue' }).select().single(), 'Category creation').id;
  const title = 'Schedule smoke Venue';
  const activity = uuid(await createActivity(title, 400000)); report.activity = activity; save();
  await open(activity, title); await summary('£4,000', '£0', '£4,000');
  pass('Normal £4000 Activity cost visible before schedules');
  const balancesBefore = await rows('v_member_balances', 'project_id', project);
  const sharesBefore = await rows('cost_shares', 'project_id', project);
  stage = 'schedule creation';
  const names = ['Deposit', 'Second payment', 'Final balance with a deliberately long descriptive venue label for responsive testing'];
  for (let i = 0; i < 3; i++) await addSchedule(names[i], [1000, 1500, 1500][i], today.plus({ days: 30 + i }).toISODate());
  const schedules = await rows('v_activity_payment_schedule_financials', 'commitment_id', activity);
  check(schedules.length === 3 && schedules.reduce((sum, s) => sum + s.scheduled_amount_minor, 0) === 400000, 'Schedule total');
  const ids = names.map(n => uuid(schedules.find(s => s.title === n).payment_schedule_id));
  assert.deepEqual(await rows('v_member_balances', 'project_id', project), balancesBefore);
  assert.deepEqual(await rows('cost_shares', 'project_id', project), sharesBefore);
  let financial = (await rows('v_project_financials', 'project_id', project))[0];
  check(financial.total_cost_minor === 400000 && financial.net_actual_spend_minor === 0, 'No double counting');
  await summary('£4,000', '£0', '£4,000'); await budget('£0');
  pass('£4000 schedules leave £4000 cost, zero spend, cost shares and member balances unchanged');
  stage = 'schedule persistence';
  await open(activity, title); await page.getByRole('button', { name: 'Close dialog', exact: true }).click();
  await page.goto(`${origin}/app/projects/${project}/overview`); await open(activity, title);
  for (const name of names) await panel().getByText(name, { exact: true }).waitFor();
  await page.reload(); await panel().getByText(names[2], { exact: true }).waitFor();
  assert.deepEqual(await rows('v_activity_payment_schedule_financials', 'commitment_id', activity), schedules);
  pass('Three schedules persist through close, navigation, reopen and refresh');
  stage = 'outsider isolation';
  for (const table of ['commitments', 'activity_payment_schedules', 'v_activity_payment_schedule_financials', 'v_my_payment_notifications']) check((await rows(table, 'project_id', project, clients[2])).length === 0, 'Outsider isolation');
  const cross = await clients[2].from('activity_payment_schedules').insert({ project_id: crossProject, commitment_id: activity, title: 'Rejected cross-project schedule', amount_minor: 100, due_on: today.toISODate() });
  check(!!cross.error, 'Cross-project schedule must fail');
  await outsiderPage.goto(`${origin}/app/projects/${project}/areas?commitment=${activity}`);
  await outsiderPage.waitForLoadState('networkidle');
  check(await outsiderPage.locator('#activity-payments').count() === 0, 'Outsider browser must not show payments');
  pass('Cross-project outsider cannot read schedules, financials or reminders, or bind a schedule');
  await join(2, 'viewer');
  const members = await rows('project_members', 'project_id', project);
  const memberIds = users.map(u => uuid(members.find(m => m.user_id === u.id).id));
  await open(activity, title, outsiderPage);
  check(await outsiderPage.locator('#activity-payments').getByRole('button', { name: 'Add schedule', exact: true }).count() === 0, 'Viewer cannot manage schedule');
  check((await rows('v_activity_payment_schedule_financials', 'commitment_id', activity, clients[2])).length === 3, 'Viewer reads schedule');
  const denied = await clients[2].from('activity_payment_schedules').insert({ project_id: project, commitment_id: activity, title: 'Rejected Viewer write', amount_minor: 100, due_on: today.toISODate() });
  check(!!denied.error, 'Viewer backend cannot create schedule');
  pass('Viewer reads persisted schedules but cannot manage them through UI or backend');
  stage = 'partial payments';
  await pay(ids[0], 1000); await pay(ids[1], 500);
  await summary('£4,000', '£1,500', '£2,500');
  const deposit = (await rows('v_activity_payment_schedule_financials', 'payment_schedule_id', ids[0]))[0];
  const partial = (await rows('v_activity_payment_schedule_financials', 'payment_schedule_id', ids[1]))[0];
  check(deposit.net_paid_minor === 100000 && deposit.outstanding_minor === 0, 'Deposit paid');
  check(partial.net_paid_minor === 50000 && partial.outstanding_minor === 100000, 'Partial derivation');
  await scheduleRow(names[0]).getByText('Paid', { exact: true }).waitFor();
  await scheduleRow(names[1]).getByText('Part paid', { exact: true }).waitFor();
  check((await scheduleRow(names[1]).textContent()).includes('£1,000.00 outstanding'), 'Outstanding visible');
  await fits('Partial payment, summary and long label');
  financial = (await rows('v_project_financials', 'project_id', project))[0];
  check(financial.total_cost_minor === 400000 && financial.net_actual_spend_minor === 150000, 'Ledger-only spend');
  await budget('£1,500'); await open(activity, title);
  pass('Deposit paid; second £500 paid/£1000 outstanding; UI £1500 paid/£2500 remaining; Budget spend £1500');
  stage = 'over-allocation';
  const paymentCount = (await rows('payments', 'commitment_id', activity)).length;
  await paymentForm(ids[1], 1100);
  await panel().locator('form').getByRole('button', { name: 'Add payment', exact: true }).click();
  await panel().getByText('Payment exceeds the schedule amount.', { exact: true }).waitFor();
  check(!/orchestr:|P0001|postgres/i.test(await panel().locator('form').textContent()), 'No raw database error');
  check((await rows('payments', 'commitment_id', activity)).length === paymentCount, 'Invalid payment must not persist');
  await panel().getByRole('button', { name: 'Cancel', exact: true }).click();
  pass('£1100 over-allocation rejected with safe UI copy and no invalid payment');
  stage = 'schedule mutation protections';
  check(await scheduleRow(names[0]).getByRole('button', { name: 'Remove schedule', exact: true }).count() === 0, 'Paid schedule remove hidden');
  check(!!(await clients[0].rpc('soft_delete_payment_schedule', { p_schedule: ids[0] })).error, 'Paid schedule deletion denied');
  await scheduleRow(names[0]).getByRole('button', { name: 'Edit schedule', exact: true }).click();
  await panel().getByLabel('Payment amount', { exact: true }).fill('999');
  await panel().getByRole('button', { name: 'Save schedule', exact: true }).click();
  await panel().getByText('The amount cannot be less than the net paid amount.', { exact: true }).waitFor();
  await panel().getByRole('button', { name: 'Cancel', exact: true }).click();
  const paidRow = (await rows('payments', 'payment_schedule_id', ids[0]))[0];
  check(!!(await clients[0].from('payments').update({ payment_schedule_id: ids[1] }).eq('id', paidRow.id)).error, 'Paid allocation immutable');
  check((await rows('payments', 'id', paidRow.id))[0].payment_schedule_id === ids[0], 'Original allocation retained');
  pass('Paid schedule deletion and reduction blocked; immutable payment cannot move');
  stage = 'completion';
  const blocked = await clients[0].from('commitments').update({ status: 'completed' }).eq('id', activity);
  check(blocked.error?.message.includes('financial_unsettled'), 'Server must block outstanding completion');
  await pay(ids[1], 1000); await pay(ids[2], 1500); await summary('£4,000', '£4,000', '£0');
  unwrap(await clients[0].from('commitments').update({ status: 'completed' }).eq('id', activity), 'Fully paid completion');
  check((await rows('commitments', 'id', activity))[0].status === 'completed', 'Completion persisted');
  pass('Server rejects partial completion and accepts fully paid Activity');
  stage = 'refund';
  await open(activity, title); await panel().locator('summary').click();
  await panel().getByRole('button', { name: 'Record refund', exact: true }).click();
  await panel().getByLabel('Payment schedule', { exact: true }).selectOption(ids[0]);
  await panel().getByLabel('Amount', { exact: true }).fill('200');
  await panel().locator('form').getByRole('button', { name: 'Record refund', exact: true }).click();
  await panel().getByLabel('Amount', { exact: true }).waitFor({ state: 'hidden' });
  const refund = (await rows('v_activity_payment_schedule_financials', 'payment_schedule_id', ids[0]))[0];
  check(refund.gross_paid_minor === 100000 && refund.refunded_minor === 20000 && refund.net_paid_minor === 80000 && refund.outstanding_minor === 20000, 'Refund derivation');
  check((await rows('payments', 'id', paidRow.id))[0].amount_minor === 100000, 'Original paid history retained');
  await poll(async () => /£200.00 refunded/.test(await scheduleRow(names[0]).textContent()));
  await budget('£3,800');
  check((await rows('v_project_financials', 'project_id', project))[0].net_actual_spend_minor === 380000, 'Refund spend');
  pass('Existing refund UI: £1000 gross, £200 refund, £800 net, £200 outstanding; project spend £3800');
  stage = 'direct payment';
  const direct = uuid(await createActivity('Direct payment compatibility', 10000));
  await open(direct, 'Direct payment compatibility'); await pay(null, 100);
  const directRows = await rows('payments', 'commitment_id', direct);
  check(directRows.length === 1 && directRows[0].payment_schedule_id === null && directRows[0].amount_minor === 10000, 'Direct ledger row');
  await summary('£100', '£100', '£0');
  financial = (await rows('v_project_financials', 'project_id', project))[0];
  check(financial.total_cost_minor === 410000 && financial.net_actual_spend_minor === 390000, 'Direct ledger compatibility');
  pass('Unscheduled Activity retains existing direct-payment UI and ledger semantics');
  stage = 'reminder fixtures';
  const reminders = [];
  for (const [label, owner, days, recipient] of [
    ['Venue reminder balance', null, 0, 0],
    ['Assigned Member balance', memberIds[1], 2, 1],
    ['Organizer assigned balance', memberIds[0], 3, 0],
    ['Viewer assigned balance', memberIds[2], 4, 2],
    ['Overdue venue balance', null, -1, null],
    ['Seventh day balance', memberIds[1], 7, 1],
    ['Upcoming reserve balance', null, 9, null],
  ]) {
    const id = uuid(await createActivity(label + ' Activity', 60000, owner));
    const due = today.plus({ days }).toISODate();
    await open(id, label + ' Activity'); await addSchedule(label, 600, due);
    const schedule = uuid((await rows('v_activity_payment_schedule_financials', 'commitment_id', id))[0].payment_schedule_id);
    reminders.push({ label, activity: id, schedule, due, recipient });
  }
  report.reminders = reminders.map(({ recipient, ...r }) => ({ ...r, recipientRole: recipient === null ? 'none' : ['Organizer', 'Member', 'Viewer'][recipient] })); save();
  // A legacy scheduled ledger row linked to the first schedule must not duplicate its deadline.
  unwrap(await clients[0].from('payments').insert({ project_id: project, commitment_id: reminders[0].activity, payment_schedule_id: reminders[0].schedule, type: 'balance', direction: 'outgoing', status: 'scheduled', due_on: reminders[0].due, amount_minor: 60000 }), 'Linked legacy deadline');
  stage = 'timeline and timezone';
  const timeline = await rpc('get_project_timeline_events', { p_project: project, p_start: today.minus({ days: 3 }).toISO(), p_end: today.plus({ days: 40 }).toISO() });
  for (const r of reminders) {
    const events = timeline.filter(e => e.subject_type === 'payment_schedule' && e.subject_id === r.activity);
    check(events.length === 1 && events[0].all_day, 'Single all-day schedule deadline');
    check(DateTime.fromISO(events[0].occurs_at).setZone(zone).toISODate() === r.due, 'Project-local timeline date');
  }
  check(timeline.find(e => e.subject_id === reminders[0].activity).status === 'due_today', 'Project-local due today');
  check(!timeline.some(e => e.event_type === 'payment_due'), 'No duplicate legacy deadline');
  await page.goto(`${origin}/app/projects/${project}/timeline`);
  const dueLink = page.getByRole('link').filter({ hasText: 'Venue reminder balance' }); await dueLink.waitFor();
  check(await dueLink.count() === 1, 'One browser schedule row');
  const dueGroup = dueLink.locator('../../../..');
  check((await dueGroup.textContent()).includes(today.toFormat('cccc d LLL')), 'Browser date matches project zone');
  check(/due today/i.test(await dueLink.locator('..').textContent()), 'Browser due today status');
  await page.getByRole('link').filter({ hasText: 'Upcoming reserve balance' }).locator('..').getByText('Upcoming', { exact: true }).waitFor();
  check((await dueLink.textContent()).includes('600'), 'Timeline amount visible');
  check(!(await page.textContent('body')).includes('00:00'), 'No midnight display');
  await fits('Timeline deadlines');
  pass('One project-local Timeline deadline per schedule; amount/status clear; linked legacy row suppressed', report.timezone);
  stage = 'health pagination';
  const health = await rpc('get_project_health', { p_project: project });
  check(health.filter(h => h.subject_type === 'payment_schedule').length === 6, 'Six active schedule findings');
  check(health.find(h => h.subject_id === reminders[4].schedule).severity === 'blocker', 'Overdue urgency');
  check(!health.some(h => ids.includes(h.subject_id)), 'Completed/paid schedules absent');
  await page.goto(`${origin}/app/projects/${project}/overview`);
  const attention = page.getByText('Needs attention', { exact: true }).locator('..');
  await page.getByLabel('Next needs attention page', { exact: true }).waitFor();
  const attentionBox = attention;
  const attentionLinks = attentionBox.locator('a[href*="section=payments"]');
  check(await attentionLinks.count() === 5, 'Five findings per page');
  check((await attentionLinks.first().textContent()).includes('Overdue venue balance is overdue'), 'Urgency ordering');
  await fits('Health and Needs Attention');
  await page.getByLabel('Next needs attention page', { exact: true }).click();
  check(await attentionLinks.count() === 1, 'Second page remaining finding');
  await page.getByLabel('Previous needs attention page', { exact: true }).click();
  await page.goto(`${origin}/app/projects/${project}/health`);
  await page.getByText(/Venue reminder balance is due on/).waitFor();
  await page.getByText(/Overdue venue balance is overdue/).waitFor(); await fits('Health findings');
  pass('Health due/overdue copy and £600 outstanding; five-item pagination and blocker-first order');
  stage = 'actual cron';
  console.log('Waiting for actual develop cron delivery…');
  await poll(async () => {
    for (const r of reminders.filter(r => r.recipient !== null)) {
      if (!(await rows('v_my_payment_notifications', 'project_id', project, clients[r.recipient])).some(n => n.commitment_id === r.activity)) return false;
    }
    return true;
  }, 150000);
  const evidenceSql = `select e.resource_id,e.project_id,e.resource_type,e.payload,e.deduplication_key,(select count(*)::int from app.domain_event_processing p where p.event_id=e.id) processing,(select count(*)::int from app.automation_action_runs a where a.event_id=e.id) actions,(select count(*)::int from public.notifications n where n.domain_event_id=e.id) notifications from app.domain_events e where e.project_id='${project}' and e.event_type='payment.due_soon' order by e.resource_id;`;
  const facts = query(evidenceSql);
  check(facts.length === 5, 'Exactly five eligible schedule facts; overdue emits none');
  for (const r of reminders.filter(r => r.recipient !== null)) {
    const fact = facts.find(e => e.resource_id === r.schedule);
    check(fact?.project_id === project && fact.resource_type === 'payment_schedule' && fact.deduplication_key === 'due:' + r.due + ':7', 'Canonical event binding/key');
    assert.deepEqual(fact.payload, { activity_id: r.activity });
    check(fact.processing === 1 && fact.actions === 1 && fact.notifications === 1, 'One receipt, action and notification');
    for (let i = 0; i < 3; i++) {
      const notifications = (await rows('v_my_payment_notifications', 'project_id', project, clients[i])).filter(n => n.commitment_id === r.activity);
      check(notifications.length === (i === r.recipient ? 1 : 0), 'Recipient isolation');
    }
  }
  report.cronEvidence = facts; save();
  query('select app.evaluate_scheduled_domain_events();');
  assert.deepEqual(query(evidenceSql), facts);
  pass('Actual cron: five eligible schedules each have one minimal fact, processing receipt, action and notification; retry unchanged');
  pass('Member assignee, Organizer fallback, Organizer-as-assignee and valid Viewer assignee receive exactly once; unrelated Members/Viewers excluded');
  stage = 'notification browser destinations';
  for (const [p, r] of [[page, reminders[0]], [memberPage, reminders[1]], [outsiderPage, reminders[3]]]) {
    await p.goto(`${origin}/app/projects/${project}/overview`);
    await p.getByRole('button', { name: 'Notifications', exact: true }).click();
    await p.getByRole('button').filter({ hasText: r.label + ' — Payment reminder' }).click();
    await p.getByRole('heading', { name: r.label + ' Activity', exact: true }).waitFor();
    check(p.url().includes('section=payments') && p.url().includes(r.activity), 'Canonical Payments destination');
    await p.locator('#activity-payments').waitFor(); await fits('Notification Payments destination', p);
    await poll(async () => (await rows('v_my_payment_notifications', 'project_id', project, clients[r.recipient])).find(n => n.commitment_id === r.activity)?.read_at);
  }
  pass('Organizer, Member and Viewer notifications open canonical Activity Payments and mark read');
  stage = 'paid finding removal';
  await open(reminders[0].activity, reminders[0].label + ' Activity');
  // Pay the existing legacy row through the normal domain update, avoiding a second actual payment.
  const legacy = (await rows('payments', 'commitment_id', reminders[0].activity)).find(p => p.status === 'scheduled');
  unwrap(await clients[0].from('payments').update({ status: 'paid', paid_on: today.toISODate(), paid_by_member_id: memberIds[0] }).eq('id', legacy.id), 'Mark scheduled payment paid');
  await page.reload(); await scheduleRow(reminders[0].label).getByText('Paid', { exact: true }).waitFor();
  check(!(await rpc('get_project_health', { p_project: project })).some(h => h.subject_id === reminders[0].schedule), 'Paid Health finding removed');
  await page.goto(`${origin}/app/projects/${project}/overview`);
  await page.getByText(/Venue reminder balance is due on/).waitFor({ state: 'hidden' });
  await page.goto(`${origin}/app/projects/${project}/timeline`);
  await page.getByRole('link').filter({ hasText: 'Venue reminder balance' }).locator('..').getByText('Paid', { exact: true }).waitFor();
  pass('Paid schedule removes dynamic Health/Needs Attention finding and Timeline becomes Paid');
  report.historyBeforeCleanup = historyCounts(); save();
  pass('Full real-backend browser scenario complete');
} catch (error) {
  // Do not emit Playwright call logs, assertion values, fixture contents or tokens.
  let message = String(error.message || error);
  for (const u of users) for (const v of Object.values(u)) if (typeof v === 'string' && v) message = message.split(v).join('[private]');
  message = message.replace(/eyJ[A-Za-z0-9_.-]+/g, '[token]').replace(/[a-f0-9]{64}/g, '[token]');
  report.failure = { stage, message: message.slice(0, 1600) };
  console.error('FAIL payments at ' + stage + ': ' + report.failure.message); process.exitCode = 1;
} finally {
  stage = 'cleanup';
  const cleanupErrors = [];
  for (const [id, owner] of [[project, clients[0]], [crossProject, clients[2]]]) {
    if (!id) continue;
    try {
      await rpc('soft_delete_project', { p_project: id }, owner);
      for (const c of clients) for (const table of ['projects', 'commitments', 'activity_payment_schedules', 'project_members', 'v_my_payment_notifications']) {
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
      for (const key of ['events', 'processing', 'actions', 'payments', 'audit']) check(after[key] >= report.historyBeforeCleanup[key], 'Historical retention ' + key);
      report.historyAfterCleanup = after;
    } catch { cleanupErrors.push('history verification'); process.exitCode = 1; }
  }
  report.cleanup = cleanupErrors.length === 0;
  if (cleanupErrors.length) { report.cleanupErrors = cleanupErrors; console.error('Cleanup verification failed; see credential-free result.'); }
  report.finishedAt = new Date().toISOString(); save();
  await browser?.close();
  for (const c of clients) await c.auth.signOut({ scope: 'local' }).catch(() => {});
}
