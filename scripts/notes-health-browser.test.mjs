/** Run against local Vite only. Every backend request is mocked; no email or remote data is touched. */
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const origin = process.env.AUTH_TEST_ORIGIN || 'http://127.0.0.1:5173';
assert(['localhost', '127.0.0.1'].includes(new URL(origin).hostname), 'Tests require a local app');
const browser = await chromium.launch({ headless: true, channel: process.env.AUTH_TEST_BROWSER || 'chrome' });
const user = { id: '00000000-0000-4000-8000-000000000001', email: 'beta@example.test', aud: 'authenticated', role: 'authenticated', created_at: new Date().toISOString(), email_confirmed_at: new Date().toISOString(), app_metadata: { provider: 'email' }, user_metadata: {}, identities: [] };
let passed = 0;
async function fixture(options = {}) {
  const context = await browser.newContext(options);
  const violations=[];
  await context.exposeBinding('reportCsp',(_source,v)=>violations.push(v));
  await context.addInitScript(()=>document.addEventListener('securitypolicyviolation',event=>window.reportCsp({directive:event.violatedDirective,uri:event.blockedURI})));
  const page = await context.newPage();
  page.setDefaultTimeout(10000);
  const project = {id:'00000000-0000-4000-8000-000000000010',name:'Beta Trip',status:'active',profile:'group_trip',module_visibility:{},currency:'GBP',timezone:'UTC',starts_on:null,ends_on:null,description:null,deleted_at:null};
  const state = { project, notes:[], findings:[], categories: [], activities: [], tasks: [], payments: [], deleteFail: false, role:'organizer', unread:true, notificationUnread:false, invitations:[], user: structuredClone(user), calls: [], signupSession: false, error: null, nonceRequired: false };
  const token = () => {
    const payload = { sub: state.user.id, exp: Math.floor(Date.now()/1000)+3600, role: 'authenticated', aud: 'authenticated' };
    return { access_token: `e30.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.signature`, refresh_token: 'mock-refresh-token', expires_in: 3600, token_type: 'bearer', user: state.user };
  };
  await context.route('**/*', async route => {
    const req = route.request();
    const url = new URL(req.url());
    if (url.origin === origin && !url.pathname.startsWith('/auth/v1/') && !url.pathname.startsWith('/rest/v1/')) return route.continue();
    const body = req.postDataJSON();
    state.calls.push({ path: url.pathname, query: Object.fromEntries(url.searchParams), body, method: req.method() });
    const reply = (data, status = 200) => route.fulfill({ status, headers: {'x-supabase-api-version':'2024-01-01','access-control-expose-headers':'x-supabase-api-version'}, contentType: 'application/json', body: JSON.stringify(data) });
    if (state.failReads && (url.pathname.endsWith('/get_project_health') || url.pathname.endsWith('/get_my_notification_unread_state') || url.pathname.endsWith('/v_my_notification_inbox'))) return reply({code:'57014',message:'PRIVATE SQL statement timeout',details:'PRIVATE QUERY'},500);
    if(url.pathname.endsWith('/get_my_notification_unread_state')) return reply(state.notificationUnread);
    if(url.pathname.endsWith('/list_my_invitations')) return reply(state.invitations);
    if(url.pathname.endsWith('/mark_all_notifications_read')) {state.notificationUnread=false;return reply(2);}
    if(url.pathname.endsWith('/v_my_notification_inbox') && req.method()==='HEAD') return route.fulfill({status:200,headers:{'content-range':'*/0','access-control-expose-headers':'content-range'},body:''});
    if (url.pathname.startsWith('/auth/v1/')) {
      const endpoint = url.pathname.split('/').at(-1);
      if (state.error?.endpoint === endpoint) return reply({ code: state.error.code, msg: 'SECRET PROVIDER DETAIL' }, state.error.status || 400);
      if (endpoint === 'signup') return reply(state.signupSession ? token() : { ...state.user, email_confirmed_at: null });
      if (endpoint === 'token') {
        if (state.tokenDelay) await new Promise(resolve=>setTimeout(resolve,state.tokenDelay));
        return reply(token());
      }
      if (endpoint === 'user') {
        if (req.method() === 'PUT' && state.nonceRequired && body.nonce !== '123456') return reply({code:'reauthentication_needed', msg:'PRIVATE'}, 400);
        return reply(state.user);
      }
      return reply({});
    }
    const end=url.pathname.split('/').at(-1);
    if(state.failResource===end)return reply({code:'57014',message:'PRIVATE SQL'},500);
    if(state.readDelay && ['v_project_notes','get_project_health'].includes(end))await new Promise(r=>setTimeout(r,state.readDelay));
    if(end==='v_project_notes')return reply(state.notes);
    if(end==='create_project_note'){const id=crypto.randomUUID();state.notes.unshift({id,project_id:project.id,created_by:'00000000-0000-4000-8000-000000000020',creator_name:'Beta',title:body.p_title,body:body.p_body,created_at:'2026-10-25T12:00:00Z',updated_at:'2026-10-25T12:00:00Z'});return reply(id);}
    if(end==='update_project_note'){Object.assign(state.notes.find(n=>n.id===body.p_note),{title:body.p_title,body:body.p_body,updated_at:'2026-10-26T12:00:00Z'});return reply(body.p_note);}
    if(end==='soft_delete_project_note'){state.notes=state.notes.filter(n=>n.id!==body.p_note);return reply(body.p_note);}
    if(end==='get_project_health')return reply(state.findings);
    if(end==='get_project_health_summary')return reply([{status:'at_risk',attention_count:state.findings.filter(f=>!f.dismissed&&f.severity!=='ok').length}]);
    if(end==='finding_dismissals'){const f=req.method()==='DELETE'?state.findings.find(f=>'eq.'+f.code===url.searchParams.get('code')&&'eq.'+f.subject_id===url.searchParams.get('subject_id')):state.findings.find(f=>f.code===body.code&&f.subject_id===body.subject_id);assert(f.dismissible);if(state.dismissFail)return reply({code:'42501',message:'PRIVATE'},403);f.dismissed=req.method()!=='DELETE';f.snoozed_until=body?.snoozed_until??null;return reply(null);}
    if(end==='get_decisions')return reply([{id:body.p_decision,title:'Choose transport',options:[],status:'open',can_vote:false,can_manage:false,writable:true,vote_count:0}]);
    if(url.pathname.endsWith('/v_project_items'))return reply(state.activities.filter(a=>!a.deleted_at).map(a=>({...a,source:'commitment',financial_id:a.id,item_type:a.activity_type,assignee_member_id:a.owner_member_id,area_id:a.area_id??null,item_date:a.starts_at,cost_minor:a.estimated_cost_minor,paid_minor:0,outstanding_minor:a.estimated_cost_minor??0})));
    if(url.pathname.endsWith('/project_areas')) { if(req.method()==='POST') { const category={id:'00000000-0000-4000-8000-'+String(state.categories.length+80).padStart(12,'0'),project_id:project.id,...(Array.isArray(body)?body[0]:body)}; state.categories.push(category); return reply(category); } return reply(state.categories); }
    if(url.pathname.endsWith('/v_area_totals'))return reply([{area_id:null,item_count:state.activities.filter(a=>!a.deleted_at).length,spent_minor:0}]);
    if(url.pathname.endsWith('/complete_assigned_item')){const a=state.activities.find(a=>a.id===body.p_item);assert.equal(a.owner_member_id,'00000000-0000-4000-8000-000000000020');a.status='completed';return reply(null);}
    const mid='00000000-0000-4000-8000-000000000020';
    if(url.pathname.endsWith('/v_member_directory')) return reply([{member_id:mid,project_id:project.id,user_id:user.id,role:state.role,status:'active',display_name:'Beta'}]);
    if(url.pathname.endsWith('/create_project')) { Object.assign(state.project,{name:body.p_name, starts_on:body.p_starts_on,ends_on:body.p_ends_on});return reply(project.id); }
    if(url.pathname.endsWith('/create_activity_in_category')) {
      const a={id:'00000000-0000-4000-8000-'+String(state.activities.length+40).padStart(12,'0'),project_id:project.id,status:'idea',created_by:mid,cost_split_mode:'none',recurrence_frequency:null,actual_cost_minor:null,confirmed_cost_minor:null,deleted_at:null,area_id:body.p_category,...body.p_fields};
      state.activities.push(a);return reply(a);
    }
    if(url.pathname.endsWith('/save_activity_with_split')) {
      const a={id:'00000000-0000-4000-8000-'+String(state.activities.length+40).padStart(12,'0'),project_id:project.id,status:'idea',created_by:mid,cost_split_mode:'none',recurrence_frequency:null,actual_cost_minor:null,confirmed_cost_minor:null,deleted_at:null,...body.p_fields};
      state.activities.push(a);return reply(a);
    }
    if(url.pathname.endsWith('/soft_delete_commitment')) {
      if(state.deleteFail) return reply({code:'42501',message:'PRIVATE DATABASE DETAIL'},403);
      const a=state.activities.find(a=>a.id===body.p_commitment);a.deleted_at=new Date().toISOString();return reply(a.id);
    }
    if(url.pathname.endsWith('/commitments')) {
      if(req.method()==='PATCH') {
        const a=state.activities.find(a=>'eq.'+a.id===url.searchParams.get('id'));
        const paid=state.payments.filter(p=>p.commitment_id===a.id).reduce((sum,p)=>sum+p.amount_minor,0);
        if(body.status==='completed' && paid<(a.estimated_cost_minor??0))return reply({code:'P0001',message:'orchestr:financial_unsettled:Unsettled'},400);
        Object.assign(a,body);return reply(a);
      }
      assert.equal(url.searchParams.get('deleted_at'),'is.null');
      return reply(state.activities.filter(a=>!a.deleted_at));
    }
    if(url.pathname.endsWith('/v_commitment_financials')) {
      const a=state.activities.find(a=>'eq.'+a.id===url.searchParams.get('commitment_id'));
      const paid=state.payments.filter(p=>p.commitment_id===a?.id).reduce((sum,p)=>sum+(p.direction==='incoming'?-1:1)*p.amount_minor,0);
      return reply({commitment_id:a?.id,effective_cost_minor:a?.estimated_cost_minor??0,net_paid_minor:paid,outstanding_minor:Math.max(0,(a?.estimated_cost_minor??0)-paid)});
    }
    if(url.pathname.endsWith('/payments')) {
      if(req.method()==='POST'){const p={id:crypto.randomUUID(),...body};state.payments.push(p);return reply(p);}
      return reply(state.payments.filter(p=>'eq.'+p.commitment_id===url.searchParams.get('commitment_id')));
    }
    if(url.pathname.endsWith('/create_task_with_cost')) {const t={id:crypto.randomUUID(),status:'open',project_id:project.id,recurrence_frequency:null,...body.p_fields};state.tasks.push(t);return reply(t);}
    if(url.pathname.endsWith('/complete_assigned_task')) {const t=state.tasks.find(t=>t.id===body.p_task);assert.equal(t.assignee_member_id,mid);t.status='done';return reply(null);}
    if(url.pathname.endsWith('/tasks')) return reply(state.tasks);
    if(url.pathname.endsWith('/get_resource_comments')) return reply({items:[],next_cursor:null,can_comment:true});
    if (url.pathname.endsWith('/projects')) {
      if(req.method()==='PATCH') {
        assert.equal(url.searchParams.get('status'), `eq.${state.project.status}`);
        Object.assign(state.project,body);
      }
      return reply(state.project);
    }
    if(url.pathname.endsWith('/project_members')) return reply([{id:'00000000-0000-4000-8000-000000000020',project_id:project.id,user_id:user.id,role:state.role,status:'active',deleted_at:null}]);
    if(url.pathname.endsWith('/v_my_projects')) return reply([{...state.project,project_id:project.id,progress_pct:0,attention_count:0}]);
    if(url.pathname.endsWith('/v_my_activity_notifications')) return route.fulfill({status:200,contentType:'application/json',headers:{'content-range':state.unread?'0-0/1':'*/0','access-control-expose-headers':'content-range'},body:JSON.stringify(state.unread?[{id:'00000000-0000-4000-8000-000000000030',project_id:project.id,commitment_id:'00000000-0000-4000-8000-000000000040',activity_title:'Book restaurant',project_name:project.name,created_at:new Date().toISOString(),read_at:null}]:[])});
    if(url.pathname.endsWith('/mark_notification_read')) {state.unread=false;return reply(body.p_notification);}
    if (url.pathname.endsWith('/get_invitation')) return reply([{ project_name: 'Shared test project', inviter_name: 'Inviter', role:'member', status:'pending' }]);
    if (url.pathname.endsWith('/accept_invitation')) return reply('00000000-0000-4000-8000-000000000003');
    if (url.pathname.endsWith('/users')) return reply({ id:state.user.id, email:state.user.email, display_name:'Beta', timezone:'Europe/London', default_currency:'GBP' });
    return reply([]);
  });
  return { context, page, state, violations };
}
async function test(name, fn, options) {
  if (process.env.AUTH_TEST_FILTER && !name.includes(process.env.AUTH_TEST_FILTER)) return;
  const f = await fixture(options);
  try { await fn(f); assert.deepEqual(f.violations, [], "No CSP violations"); passed++; console.log(`PASS: ${name}`); }
  catch (e) { console.error((await f.page.textContent("body")).slice(0,1500),); throw e; }
  finally { await f.context.close(); }
}
async function login(page) {
  await page.goto(origin+'/login');
  await page.getByLabel('Email', {exact:true}).fill(user.email);
  await page.getByLabel(/^Password/).fill('password123');
  await page.getByRole('button',{name:'Log in',exact:true}).click();
  await page.waitForURL(origin+'/app');
}
async function go(page,path) {
  await page.waitForFunction(()=>!!document.querySelector('#app')?.__vue_app__);
  await page.evaluate(async path=>document.querySelector('#app').__vue_app__.config.globalProperties.$router.push(path),path);
}
async function fits(page,label) {
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),label);
}
const mid='00000000-0000-4000-8000-000000000020';
function note(state,title,body){return {id:crypto.randomUUID(),project_id:state.project.id,created_by:mid,creator_name:'Beta',title,body,created_at:'2026-10-20T12:00:00Z',updated_at:'2026-10-25T12:00:00Z'};}
function finding(code,severity,extra={}){return {code,severity,subject_type:'commitment',subject_id:crypto.randomUUID(),subject_label:'Prepare travel arrangements for the whole group',params:{},message:'This activity needs attention.',resolution:'Review the activity details.',dismissible:severity!=='blocker'&&severity!=='ok',dismissed:false,snoozed_until:null,affects_health:severity!=='ok',...extra};}
function populate(state){state.notes=[note(state,'Travel reference information','Arrival instructions and meeting point.\nPlease keep this information current.'),note(state,'Long project reference',Array.from({length:24},(_,i)=>'Section '+(i+1)+': Durable project information and reference details.').join('\n'))];state.findings=[finding('schedule_conflict','blocker'),finding('missing_owner','warning'),finding('missing_cost','info'),finding('on_budget','ok',{subject_type:'project',subject_label:null,message:'The project is within its budget.',resolution:''})];}
async function capture(page,name){await page.evaluate(()=>document.fonts.ready);await page.waitForTimeout(180);await fits(page,name);for(const d of await page.locator('[id^="headlessui-dialog-panel"]').all())assert(await d.evaluate(el=>el.scrollWidth<=el.clientWidth));await page.screenshot({path:'/tmp/orchestrio-phase6-'+name+'.png',fullPage:true});}
try{
 for(const [width,height] of [[1280,900],[1024,768],[768,1024],[430,932],[390,844],[375,812]])await test('Notes Health viewport '+width,async({page,state})=>{
  await page.setViewportSize({width,height});const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});populate(state);await login(page);await go(page,'/app/projects/'+state.project.id+'/notes');const title=page.getByRole('button',{name:'Long project reference',exact:true});await title.waitFor();assert.equal(await title.getAttribute('aria-expanded'),'false');await capture(page,'notes-'+width);await title.focus();await page.keyboard.press('Enter');assert.equal(await title.getAttribute('aria-expanded'),'true');await capture(page,'note-open-'+width);await page.getByRole('button',{name:'Edit note: Long project reference',exact:true}).click();await page.getByLabel('Title',{exact:true}).waitFor();await capture(page,'note-edit-'+width);await page.keyboard.press('Escape');await page.waitForTimeout(250);assert(await page.getByRole('button',{name:'Edit note: Long project reference',exact:true}).evaluate(el=>el===document.activeElement));
  await go(page,'/app/projects/'+state.project.id+'/health');await page.getByRole('heading',{name:'Scheduling conflict',exact:true}).waitFor();await capture(page,'health-'+width);const passed=page.locator('summary').filter({hasText:'Passed'});await passed.focus();await page.keyboard.press('Enter');await page.getByRole('heading',{name:'On budget',exact:true}).waitFor();await capture(page,'health-passed-'+width);
  state.findings=state.findings.filter(f=>f.severity==='ok');await page.reload();await page.getByText('No findings need attention.',{exact:true}).waitFor();await capture(page,'health-all-clear-'+width);state.findings=[];await page.reload();await page.getByText('Nothing here — all clear for this filter.',{exact:true}).waitFor();state.notes=[];await go(page,'/app/projects/'+state.project.id+'/notes');await page.getByText('No notes yet. Record information the project can refer back to.',{exact:true}).waitFor();await capture(page,'notes-empty-'+width);assert.deepEqual(errors,[]);
 });
 await test('Notes create edit validation delete and permissions',async({page,state})=>{
  await login(page);const base='/app/projects/'+state.project.id;await go(page,base+'/notes');await page.getByRole('button',{name:'+ Add note',exact:true}).click();let d=page.getByRole('dialog');assert(await d.getByRole('button',{name:'Save note',exact:true}).isDisabled());await d.getByLabel('Title',{exact:true}).fill('x'.repeat(121));await d.getByLabel('Note',{exact:true}).fill('Reference body');assert(await d.getByRole('button',{name:'Save note',exact:true}).isDisabled());await d.getByLabel('Title',{exact:true}).fill('  Shared reference  ');await d.getByRole('button',{name:'Save note',exact:true}).click();await page.getByRole('button',{name:'Shared reference',exact:true}).waitFor();assert.equal(state.notes[0].title,'Shared reference');await page.getByRole('button',{name:'Shared reference',exact:true}).click();await page.getByRole('button',{name:'Edit note: Shared reference',exact:true}).click();d=page.getByRole('dialog');await d.getByLabel('Note',{exact:true}).fill('Updated durable information');await d.getByRole('button',{name:'Save note',exact:true}).click();await page.getByText('Updated durable information',{exact:true}).waitFor();assert.equal(state.notes[0].body,'Updated durable information');
  state.role='member';state.notes.push({...note(state,'Another author','Other information'),created_by:crypto.randomUUID()});await page.reload();await page.getByRole('button',{name:'Another author',exact:true}).click();assert.equal(await page.getByRole('button',{name:'Edit note: Another author',exact:true}).count(),0);await page.getByRole('button',{name:'Shared reference',exact:true}).click();await page.getByRole('button',{name:'Delete note: Shared reference',exact:true}).click();await page.getByRole('dialog').getByRole('button',{name:'Delete note',exact:true}).click();await page.getByRole('button',{name:'Shared reference',exact:true}).waitFor({state:'detached'});assert.equal(state.notes.length,1);
  state.role='viewer';await page.reload();await page.getByText('You have read-only access to project notes.',{exact:true}).waitFor();assert.equal(await page.getByRole('button',{name:'+ Add note',exact:true}).count(),0);state.role='organizer';state.project.status='archived';await page.reload();await page.getByText('Archived projects are read-only until unarchived.',{exact:true}).waitFor();assert.equal(await page.getByRole('button',{name:'+ Add note',exact:true}).count(),0);
 });
 await test('Health dismissal snooze restore failure and authorization',async({page,state})=>{
  populate(state);await login(page);await go(page,'/app/projects/'+state.project.id+'/health');assert.equal(await page.getByRole('button',{name:'Dismiss: Scheduling conflict',exact:true}).count(),0);state.dismissFail=true;await page.getByRole('button',{name:'Dismiss: Missing owner',exact:true}).click();await page.getByText("You don't have permission to do that.",{exact:true}).waitFor();assert.equal(state.findings[1].dismissed,false);state.dismissFail=false;await page.getByRole('button',{name:'Dismiss: Missing owner',exact:true}).click();await page.getByRole('heading',{name:'Missing owner',exact:true}).waitFor({state:'detached'});assert(await page.getByRole('heading',{name:'Health',exact:true}).evaluate(el=>el===document.activeElement));await page.getByLabel('Show dismissed/snoozed').check();await page.getByRole('region',{name:'Dismissed and snoozed',exact:true}).getByRole('button',{name:'Restore',exact:true}).click();await page.getByRole('button',{name:'Dismiss: Missing owner',exact:true}).waitFor();await page.getByRole('button',{name:'Snooze 7 days: Missing owner',exact:true}).click();await page.getByText(/Snoozed until/).waitFor();assert(state.findings[1].snoozed_until);assert(state.calls.some(c=>c.path.endsWith('/finding_dismissals')&&c.body?.state==='snoozed'));
  state.role='viewer';await page.reload();await page.getByRole('heading',{name:'Health',exact:true}).waitFor();assert.equal(await page.getByRole('button',{name:/^Dismiss:/}).count(),0);
 });
 await test('Health ten-item pagination filters and canonical navigation',async({page,state})=>{
  state.findings=Array.from({length:12},(_,i)=>finding('missing_owner','warning',{subject_label:'Activity '+i}));state.findings.push(finding('on_budget','ok'));await login(page);const base='/app/projects/'+state.project.id;await go(page,base+'/health');await page.getByRole('button',{name:'Next',exact:true}).waitFor();assert.equal(await page.locator('article').count(),10);await page.getByRole('button',{name:'Next',exact:true}).click();assert.equal(await page.locator('article').count(),3);await page.getByRole('button',{name:'Passed · 1',exact:true}).click();await page.getByRole('heading',{name:'On budget',exact:true}).waitFor();assert.equal(await page.getByRole('button',{name:'Previous',exact:true}).count(),0);
  const activity=crypto.randomUUID(),decision=crypto.randomUUID();state.activities=[{id:activity,project_id:state.project.id,title:'Train reservation',activity_type:'other',kind:'transport',status:'idea',deleted_at:null}];state.findings=[finding('missing_owner','warning',{subject_id:activity}),finding('decision_needs_resolution','warning',{subject_type:'decision',subject_id:decision}),finding('payment_due_soon','warning',{subject_type:'payment_schedule',params:{activity_id:activity}})];await page.reload();
  for(const [label,part] of [['Review activity','commitment='+activity],['Open decision','/decisions/'+decision],['Open payments','section=payments']]){await go(page,base+'/health');await page.getByRole('link',{name:label,exact:true}).click();await page.waitForURL(url=>url.href.includes(part));}
 });
 await test('Notes limit and local read recovery',async({page,state})=>{
  state.notes=Array.from({length:20},(_,i)=>note(state,'Reference '+i,'Information'));state.readDelay=800;await login(page);const base='/app/projects/'+state.project.id;await go(page,base+'/notes');await page.getByRole('status',{name:'Loading notes',exact:true}).waitFor();await page.getByText("You've reached the 20-note limit for this project.",{exact:true}).waitFor();assert(await page.getByRole('button',{name:'+ Add note',exact:true}).isDisabled());state.readDelay=0;state.failResource='v_project_notes';await page.reload();await page.getByRole('button',{name:'Try again',exact:true}).waitFor({timeout:20000});assert(!(await page.locator('body').innerText()).includes('PRIVATE'));await page.getByRole('link',{name:'Overview',exact:true}).waitFor();state.failResource=null;await page.getByRole('button',{name:'Try again',exact:true}).click();await page.getByRole('button',{name:'Reference 0',exact:true}).waitFor();
  state.failResource='get_project_health';await go(page,base+'/health');await page.getByRole('button',{name:'Try again',exact:true}).waitFor({timeout:20000});state.failResource=null;await page.getByRole('button',{name:'Try again',exact:true}).click();await page.getByText('Nothing here — all clear for this filter.',{exact:true}).waitFor();
 });
 console.log(passed+' Notes/Health browser scenarios passed.');
}finally{await browser.close();}
