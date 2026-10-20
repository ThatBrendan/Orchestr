/** Real DEVELOP responses; private existing identities, isolated project, cleanup in finally. */
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { createClient } from '@supabase/supabase-js';
import { DateTime } from 'luxon';
const target='msfkczsoutbeyhjvegnw', origin='http://127.0.0.1:5173';
assert.equal(fs.readFileSync('supabase/.temp/project-ref','utf8').trim(),target);
const env=Object.fromEntries(fs.readFileSync('.env.local','utf8').split('\n').filter(l=>l.includes('=')&&!l.startsWith('#')).map(l=>{const i=l.indexOf('=');return[l.slice(0,i),l.slice(i+1).replace(/^['"]|['"]$/g,'')];}));
assert.equal(env.VITE_SUPABASE_URL,`https://${target}.supabase.co`);
assert(process.env.PAYMENT_FIXTURE_FILE,'Private fixture required');
const users=JSON.parse(fs.readFileSync(process.env.PAYMENT_FIXTURE_FILE,'utf8')).users.slice(0,3);
const clients=users.map(()=>createClient(env.VITE_SUPABASE_URL,env.VITE_SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(input,init)=>fetch(input,{...init,signal:AbortSignal.timeout(15000)})}}));
const captures=[],projects=[],links=[];let browser,page,project,stage='login';
const report={checks:[],cleanup:false,consoleErrors:[],networkErrors:[],browserConsoleErrors:[]};
// Optional diagnostics never control fixture cleanup. Attach rejection handlers
// immediately, and bound both response capture and diagnostic child lifetimes.
const pendingReads=new Map(), observations=[];let observing=false, observationCount=0;
const diagnosticChildren=new Set();
let observer;
report.criticalReads=[];report.databaseObservations=[];
report.diagnostics={enabled:process.env.JOURNEY_OBSERVE_READS==='1',errors:[]};
function diagnosticFailure(kind,code){report.diagnostics.errors.push({kind,code});}
function capture(promise){
 let timer;
 const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('capture_timeout')),15000);});
 captures.push(Promise.race([promise,timeout]).catch(error=>{
  diagnosticFailure('capture',error?.message==='capture_timeout'?'timeout':'failed');
 }).finally(()=>clearTimeout(timer)));
}
const criticalPath=u=>/\/v_my_notification_inbox$|\/get_my_notification_unread_state$|\/v_reimbursement_payment_status$/.test(new URL(u).pathname);
const observationFile='/tmp/orchestrio-lightweight-active.sql';
function observe(slow){
 observing=true;observationCount++;
 const at=new Date().toISOString();
 observations.push(new Promise(resolve=>{
  let child,timer,finished=false;
  const finish=(code,output='')=>{
   if(finished)return;finished=true;
   clearTimeout(timer);diagnosticChildren.delete(cancel);observing=false;
   let rows;try{rows=JSON.parse(output).rows;}catch{/* Report unavailable telemetry without raw error text. */}
   const ok=code==='complete'&&Array.isArray(rows);
   if(!ok)diagnosticFailure('observer',code==='complete'?'invalid_result':code);
   report.databaseObservations.push({requestedAt:at,slow:slow.map(r=>({path:r.path,actor:r.actor,startedAt:r.at})),ok,rows:rows??[]});
   resolve();
  };
  const cancel=()=>{
   try{child?.kill('SIGKILL');}catch{/* Settlement and cleanup must not depend on kill success. */}
   finish('cancelled');
  };
  try{
   child=spawn('supabase',['db','query','--linked','--project-ref',target,'--file',observationFile],{stdio:['ignore','pipe','pipe']});
   diagnosticChildren.add(cancel);
   let output='';child.stdout.on('data',d=>{output+=d;});child.stderr.resume();
   child.on('error',()=>finish('spawn_failed'));
   child.on('close',code=>finish(code===0?'complete':'process_failed',output));
   timer=setTimeout(()=>{
    try{child.kill('SIGKILL');}catch{/* Resolve even if the child cannot be signalled. */}
    finish('timeout');
   },10000);
  }catch{finish('spawn_failed');}
 }).catch(()=>diagnosticFailure('observer','failed')));
}
function startObserver(){
 if(!report.diagnostics.enabled)return;
 try{
  fs.writeFileSync(observationFile,`select clock_timestamp() as captured_at, a.pid,a.query_id::text,a.usename,a.state,a.query_start,a.state_change,a.wait_event_type,a.wait_event,pg_blocking_pids(a.pid) as blockers,md5(a.query) as query_fingerprint,
case when a.query like 'WITH pgrst_source%' and a.query not like '%set_config%' then a.query else null end as parameterized_query,
(select coalesce(jsonb_agg(jsonb_build_object('locktype',l.locktype,'mode',l.mode,'granted',l.granted,'relation',l.relation::text)),'[]') from pg_locks l where l.pid=a.pid) as locks,
(select count(*) from pg_stat_progress_vacuum) as active_vacuums
from pg_stat_activity a where a.datname=current_database() and a.pid<>pg_backend_pid() and a.state<>'idle';`,{mode:0o600});
  observer=setInterval(()=>{
   const slow=[...pendingReads.values()].filter(r=>performance.now()-r.ms>2000);
   if(!observing&&slow.length&&observationCount<12)observe(slow);
  },500);
 }catch{diagnosticFailure('observer','setup_failed');}
}
const reportLabel=process.env.JOURNEY_REPORT_LABEL||`run-${Date.now()}`;assert(/^[a-z0-9-]+$/.test(reportLabel));
const reportPath=`/tmp/orchestrio-journey-${reportLabel}.json`;
// Reserve a new artifact before creating fixtures; never overwrite prior evidence.
fs.writeFileSync(reportPath,JSON.stringify(report,null,2),{mode:0o600,flag:'wx'});
const save=()=>fs.writeFileSync(reportPath,JSON.stringify(report,null,2),{mode:0o600});
const pass=name=>{report.checks.push(name);console.log('PASS UX: '+name);save();};
function unwrap(r,label){if(r.error)throw new Error(label+' failed ('+r.error.code+')');return r.data;}
async function rpc(name,args={},index=0){return unwrap(await clients[index].rpc(name,args),name);}
async function rows(table,index=0){return unwrap(await clients[index].from(table).select('*').eq('project_id',project),table);}
async function poll(fn){for(let i=0;i<60;i++){const value=await fn();if(value)return value;await new Promise(r=>setTimeout(r,250));}throw new Error('Timed out: '+stage);}
async function fits(p=page){for(const width of [375,430,1280]){await p.setViewportSize({width,height:720});if(width===375 && stage==='balances')await p.screenshot({path:`/tmp/orchestrio-journey-${reportLabel}-balances-mobile.png`});assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'document overflow '+width);assert(await p.locator('[id^=headlessui-dialog-panel]').evaluateAll(es=>es.every(el=>el.scrollWidth<=el.clientWidth)),'dialog overflow '+width);}}
async function login(index){const ctx=await browser.newContext({timezoneId:'Pacific/Honolulu',permissions:['clipboard-read','clipboard-write']});await ctx.route('**/*',r=>{const u=new URL(r.request().url());return u.origin===origin||u.origin===env.VITE_SUPABASE_URL?r.continue():r.abort();});const p=await ctx.newPage();p.on('pageerror',e=>report.consoleErrors.push(e.name));p.on('console',m=>{if(m.type()==='error')report.browserConsoleErrors.push({stage,text:m.text().slice(0,240)});});const starts=new Map();p.on('request',r=>{const start={at:new Date().toISOString(),ms:performance.now()};starts.set(r,start);if(criticalPath(r.url()))pendingReads.set(r,{...start,path:new URL(r.url()).pathname,actor:index});});p.on('requestfinished',r=>pendingReads.delete(r));p.on('requestfailed',r=>pendingReads.delete(r));p.on('response',r=>{pendingReads.delete(r.request());if(criticalPath(r.url())){const req=r.request();report.criticalReads.push({path:new URL(r.url()).pathname,method:req.method(),actor:index,status:r.status(),startedAt:starts.get(req)?.at,ms:Math.round(performance.now()-(starts.get(req)?.ms??performance.now())),requestId:r.headers()['sb-request-id']??null});if(r.status()===200&&new URL(r.url()).pathname.endsWith('/get_my_notification_unread_state')){const record=report.criticalReads.at(-1);capture(r.json().then(value=>{record.hasUnread=value;assert.equal(typeof value,'boolean');}));}}if(r.status()>=500){capture((async()=>{const req=r.request(),u=new URL(r.url());const record={stage,actor:index,role:index===0?'owner':'member',project,status:r.status(),path:u.pathname,method:req.method(),parameters:u.search,origin:req.headers().origin??null,startedAt:starts.get(req)?.at,ms:Math.round(performance.now()-(starts.get(req)?.ms??performance.now())),headers:Object.fromEntries(Object.entries(r.headers()).filter(([k])=>['access-control-allow-origin','access-control-allow-credentials','content-type','vary','sb-request-id','cf-ray'].includes(k)))};report.networkErrors.push(record);try{const body=await r.json();record.code=body.code??null;record.statementTimeout=body.message?.includes('statement timeout')??false;}catch{record.code=req.method()==='HEAD'?'no-body-HEAD':'unavailable-body';}save();})());}});p.setDefaultTimeout(30000);await p.goto(origin+'/login');await p.getByLabel('Email',{exact:true}).fill(users[index].email);await p.getByLabel(/^Password/).fill(users[index].password);await p.getByRole('button',{name:'Log in',exact:true}).click();await p.waitForURL(origin+'/app');return p;}
async function goto(tab){await page.goto(`${origin}/app/projects/${project}/${tab}`);}
try{
 startObserver();
 for(let i=0;i<users.length;i++){const r=await clients[i].auth.signInWithPassword({email:users[i].email,password:users[i].password});assert(!r.error,'Synthetic authentication');users[i].id=r.data.user.id;}
 browser=await chromium.launch({headless:true,channel:'chrome'});page=await login(0);
 stage='create project';await page.goto(origin+'/app/projects');await page.getByRole('button',{name:'New project',exact:true}).first().click();await page.getByRole('button',{name:/Group Trip/}).click();await page.getByRole('button',{name:'Continue',exact:true}).click();await page.getByLabel('Project name').fill('Beta journey synthetic '+Date.now());await page.getByLabel('Start date').fill(DateTime.utc().toISODate());await page.getByRole('button',{name:'Create project',exact:true}).click();await page.waitForURL('**/overview');project=page.url().match(/projects\/([a-f0-9-]+)\//)[1];projects.push(project);report.project=project;save();
 assert.equal((await rows('project_areas')).length,0);await page.getByRole('link',{name:'Create your first category',exact:true}).waitFor();await fits();await page.screenshot({path:`/tmp/orchestrio-journey-${reportLabel}-empty.png`});
 await page.getByRole('link',{name:'Create your first category',exact:true}).click();const d=page.getByRole('dialog');await d.getByRole('button',{name:'Accommodation',exact:true}).waitFor();assert.equal(await d.getByRole('group',{name:'Suggested'}).getByRole('button').count(),4);await d.getByLabel('Category name *',{exact:true}).fill('Weekend plans');await d.getByRole('button',{name:'Save category',exact:true}).click();await d.locator('[id^=headlessui-dialog-panel]').waitFor({state:'hidden'});const category=(await poll(async()=>(await rows('project_areas'))[0])).id;
 await goto('overview');await page.getByRole('button',{name:'Export',exact:true}).waitFor();assert.equal(await page.getByRole('link',{name:'Create your first category',exact:true}).count(),0);
 pass('Real login → project → clear empty-state CTA → first Category');
 stage='invite and join';await goto('people');await page.getByRole('button',{name:'Copy invite link',exact:true}).click();await page.getByText('Invite link copied',{exact:true}).waitFor();const token=new URL(await page.getByLabel('Join link',{exact:true}).inputValue()).pathname.split('/').at(-1);
 const member=await login(1);await member.goto(origin+'/join/'+token);await member.getByRole('button',{name:'Request access',exact:true}).click();await member.getByText('Your access request is pending approval.',{exact:true}).waitFor();assert.equal(unwrap(await clients[1].from('projects').select('id').eq('id',project),'pending privacy').length,0);
 await goto('overview');await page.getByRole('button',{name:'Notifications',exact:true}).click();await page.getByRole('dialog').getByRole('button').filter({hasText:'New project access request'}).first().click();await page.waitForURL('**/people');await fits();await page.getByRole('button',{name:/^Approve /}).click();await page.getByText('Access approved.',{exact:true}).waitFor();await member.reload();await member.getByRole('link',{name:'Open project',exact:true}).click();
 const membership=await rows('project_members');const members=(await rows('v_member_directory')).filter(m=>m.status==='active'),owner=members.find(m=>m.member_id===membership.find(x=>x.user_id===users[0].id).id),debtor=members.find(m=>m.member_id===membership.find(x=>x.user_id===users[1].id).id);
 pass('Invite copy → real Member request → privacy before approval → People approval');
 stage='activity and retry';await goto('activities?area='+category);await page.getByRole('button',{name:'Add activity',exact:true}).click();await d.getByLabel('Activity title *',{exact:true}).fill('Book group dinner');await d.getByLabel(/^Activity type/).selectOption('task');await d.getByLabel(/^Assigned to/).selectOption(owner.member_id);await d.getByLabel('Due date',{exact:true}).fill(DateTime.utc().toISODate());await d.getByLabel('Cost (GBP, optional)',{exact:true}).fill('20');await d.getByRole('radio',{name:'Evenly',exact:true}).check();for(const m of members)await d.getByRole('checkbox',{name:m.display_name,exact:true}).check();await fits();
 const createRoute='**/rest/v1/rpc/create_activity_in_category';await page.route(createRoute,r=>r.abort());await d.getByRole('button',{name:'Create activity',exact:true}).click();await d.getByRole('alert').waitFor();assert.equal(await d.getByLabel('Activity title *',{exact:true}).inputValue(),'Book group dinner');assert.equal((await rows('commitments')).length,0);await page.unroute(createRoute);await d.getByRole('button',{name:'Create activity',exact:true}).click();await d.locator('[id^=headlessui-dialog-panel]').waitFor({state:'hidden'});const activity=await poll(async()=>(await rows('commitments'))[0]);assert.equal((await rows('commitments')).length,1);
 pass('Assigned/date/cost/even split in one form; failed save preserves draft and retry creates one Activity');
 stage='decision';await goto('decisions');await page.getByRole('button',{name:'New decision',exact:true}).click();await d.getByLabel('Question',{exact:true}).fill('Dinner time?');await d.getByLabel('Option 1',{exact:true}).fill('Early');await d.getByLabel('Option 2',{exact:true}).fill('Late');await d.getByRole('button',{name:'Save decision',exact:true}).click();await d.locator('[id^=headlessui-dialog-panel]').waitFor({state:'hidden'});const decision=await poll(async()=>(await rows('decisions'))[0]);
 await member.goto(`${origin}/app/projects/${project}/decisions/${decision.id}`);await member.getByRole('button',{name:'Vote for Early',exact:true}).click();await member.getByRole('button',{name:'✓ Your vote',exact:true}).waitFor();await page.goto(`${origin}/app/projects/${project}/decisions/${decision.id}`);await page.getByRole('button',{name:'Resolve decision',exact:true}).click();const option=(await rpc('get_decisions',{p_project:project,p_decision:decision.id}))[0].options.find(o=>o.title==='Early');await d.getByLabel('Select final option',{exact:true}).selectOption(option.id);await d.getByRole('button',{name:'Confirm resolution',exact:true}).click();await page.getByText('Early selected',{exact:true}).waitFor();pass('Decision create → collaborator vote → explicit Organizer resolution');
 stage='schedule and payment';await goto('activities?commitment='+activity.id);const payments=page.locator('#activity-payments');await payments.getByRole('button',{name:'Add schedule',exact:true}).click();await payments.getByLabel('Payment label',{exact:true}).fill('Dinner payment');await payments.getByLabel('Payment amount',{exact:true}).fill('20');await payments.getByLabel('Payment due date',{exact:true}).fill(DateTime.utc().toISODate());await payments.locator('form').getByRole('button',{name:'Add schedule',exact:true}).click();await payments.getByText('Dinner payment',{exact:true}).waitFor();const schedule=(await rows('activity_payment_schedules'))[0];
 await payments.getByRole('button',{name:'Add payment',exact:true}).click();await payments.getByLabel('Payment schedule',{exact:true}).selectOption(schedule.id);await payments.getByLabel('Amount',{exact:true}).fill('20');await payments.locator('form').getByRole('button',{name:'Add payment',exact:true}).click();await payments.getByLabel('Amount',{exact:true}).waitFor({state:'hidden'});assert.equal((await rows('v_project_financials'))[0].net_actual_spend_minor,2000);
 stage='reimbursement';const panel=page.locator('#activity-reimbursements');await panel.getByRole('button',{name:'Create reimbursements',exact:true}).click();await panel.getByRole('button',{name:'Create selected reimbursements',exact:true}).click();await poll(async()=>(await rows('v_reimbursements')).length===1);const request=(await rows('v_reimbursements'))[0];
 const link=await rpc('save_my_payment_link',{p_provider:'paypal',p_url:'https://paypal.me/OrchestrioJourney'});links.push(link);
 await member.goto(`${origin}/app/projects/${project}/activities?commitment=${activity.id}&section=reimbursements`);const card=member.locator(`[data-reimbursement-id="${request.id}"]`);await card.getByRole('heading',{name:/payment preferences$/}).waitFor();const destination=card.getByRole('link',{name:/PayPal/});assert.equal(await destination.getAttribute('target'),'_blank');const popup=member.waitForEvent('popup');await destination.click();await (await popup).close();assert.equal((await rows('v_project_member_settlements')).find(m=>m.member_id===debtor.member_id).remaining_minor,1000);
 await card.getByRole('button',{name:"I've paid",exact:true}).click();await member.getByRole('dialog',{name:'Mark payment as sent?',exact:true}).getByRole('button',{name:"Yes, I've paid",exact:true}).click();await card.getByText('Payment sent',{exact:true}).waitFor();
 await page.reload();const creditor=page.locator(`[data-reimbursement-id="${request.id}"]`);await creditor.getByRole('button',{name:'Confirm received',exact:true}).click();await page.getByRole('dialog',{name:'Confirm receipt?',exact:true}).getByRole('button',{name:'Confirm received',exact:true}).click();await creditor.getByText('Settled',{exact:true}).waitFor();assert((await rows('v_project_member_settlements')).every(m=>m.remaining_minor===0));assert.equal((await rows('v_project_financials'))[0].net_actual_spend_minor,2000);pass('Schedule → expense → reimbursement → blocked provider navigation → sent acknowledgement → receipt confirmation; £20 spend and zero balances');
 stage='complete and inspect';await d.getByRole('button',{name:'Complete',exact:true}).click();await poll(async()=>(await rows('commitments'))[0].status==='completed');
 for(const width of [375,430,1280]){await page.setViewportSize({width,height:width===1280?640:720});for(const tab of ['overview','activities','people','budget','calendar','timeline','health']){console.log('CHECK screen '+tab+' '+width);await goto(tab);await page.getByRole('button',{name:'Export',exact:true}).waitFor();await page.waitForTimeout(300);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Overflow '+tab+' '+width);assert.equal(await page.getByText('Something went wrong on this screen.',{exact:true}).count(),0);}}
 await goto('overview');await page.getByRole('button',{name:'Open project settings',exact:true}).click();await d.getByRole('button',{name:'Complete project',exact:true}).waitFor();await d.getByRole('button',{name:'Close dialog',exact:true}).click();await page.getByRole('button',{name:'Notifications',exact:true}).click();await page.getByRole('dialog').getByRole('heading',{name:'Notifications',exact:true}).waitFor();await fits();await page.screenshot({path:`/tmp/orchestrio-journey-${reportLabel}-notifications.png`});await Promise.all(captures);assert.deepEqual(report.consoleErrors,[]);assert.equal(await page.getByLabel('Notification status unavailable',{exact:true}).count(),0,'Unread status available');const latestUnread=report.criticalReads.filter(r=>r.actor===0&&r.path.endsWith('/get_my_notification_unread_state')).at(-1);if(latestUnread?.hasUnread===true)assert.equal(await page.getByLabel('Unread notifications',{exact:true}).count(),1,'True unread never renders as no unread');assert(report.criticalReads.some(r=>r.path.endsWith('/get_my_notification_unread_state')),'New unread RPC observed');assert(!report.criticalReads.some(r=>r.path.endsWith('/v_my_notification_inbox')&&r.method==='HEAD'),'No exact unread HEAD');assert.deepEqual(report.networkErrors,[]);assert.deepEqual(report.browserConsoleErrors.filter(e=>!(e.stage==='activity and retry' && /ERR_FAILED|Failed to fetch|^\[orchestrio\] mutation failed \{kind: server, code: \}$/.test(e.text))),[]);pass('Complete Activity; Balances, Health, Calendar, Timeline, People, Notes and project-completion control; 375/430/1280 widths and laptop height; no uncaught browser errors');
}catch(e){report.failedStage=stage;report.error=e.message.replace(/[a-f0-9]{64}/g,'[token]');console.error('FAIL journey at '+stage+': '+report.error);if(page)await page.screenshot({path:`/tmp/orchestrio-journey-${reportLabel}-failure.png`});process.exitCode=1;}
finally{
 clearInterval(observer);
 // Cancel owned diagnostics synchronously; do not await them before domain cleanup.
 for(const cancel of [...diagnosticChildren])cancel();
 let clean=true;
 try{
  for(const id of links)try{await rpc('delete_my_payment_link',{p_id:id});}catch{clean=false;}
  for(const id of projects)try{
   await rpc('soft_delete_project',{p_project:id});
   assert.equal(unwrap(await clients[0].from('projects').select('id').eq('id',id),'cleanup').length,0);
  }catch{clean=false;}
 }finally{
  report.cleanup=clean;
  try{await browser?.close();}catch{diagnosticFailure('browser','close_failed');}
  for(const c of clients)try{await c.auth.signOut({scope:'local'});}catch{diagnosticFailure('session','signout_failed');}
  const settled=await Promise.allSettled([...observations,...captures]);
  if(settled.some(r=>r.status==='rejected'))diagnosticFailure('diagnostics','unexpected_rejection');
  report.diagnostics.ok=report.diagnostics.errors.length===0;
  if(!clean||!report.diagnostics.ok)process.exitCode=1;
  console.log('Journey cleanup: '+clean);
  console.log('Journey diagnostics: '+(report.diagnostics.ok?'PASS':'FAIL'));
  save();
 }
}
