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
  const state = { project, decisions: [], categories: [], activities: [], tasks: [], payments: [], deleteFail: false, role:'organizer', unread:true, notificationUnread:false, invitations:[], user: structuredClone(user), calls: [], signupSession: false, error: null, nonceRequired: false };
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
    if(url.pathname.endsWith('/get_decisions')) {
      if(state.readDelay) await new Promise(r=>setTimeout(r,state.readDelay));
      if(state.decisionError) return reply({code:'57014',message:'PRIVATE'},500);
      return reply(state.decisions.filter(d=>!body.p_decision || d.id===body.p_decision));
    }
    if(url.pathname.endsWith('/create_decision_date')) {state.decisions.push(makeDecision(state,{id:body.p_id,title:body.p_title,description:body.p_description,voting_deadline:body.p_deadline_date?body.p_deadline_date+'T23:59:59Z':null,options:body.p_options.map((o,i)=>({...o,id:crypto.randomUUID(),sort_order:i,vote_count:0}))}));return reply(null);}
    if(url.pathname.endsWith('/edit_decision_date')) {const d=state.decisions.find(d=>d.id===body.p_decision);Object.assign(d,{title:body.p_title,description:body.p_description});if(!body.p_preserve_deadline)d.voting_deadline=body.p_deadline_date?body.p_deadline_date+'T23:59:59Z':null;return reply(null);}
    if(url.pathname.endsWith('/cast_decision_vote')) {const d=state.decisions.find(d=>d.id===body.p_decision);assert(d.can_vote);d.my_option_id=body.p_option;d.voting_started=true;d.vote_count=body.p_option?1:0;d.options.forEach(o=>o.vote_count=o.id===body.p_option?1:0);return reply(null);}
    if(url.pathname.endsWith('/resolve_decision')) {const d=state.decisions.find(d=>d.id===body.p_decision);assert(d.can_manage&&d.writable);Object.assign(d,{status:'resolved',resolved_option_id:body.p_option,can_vote:false});return reply(null);}
    if(url.pathname.endsWith('/soft_delete_decision')) {state.decisions=state.decisions.filter(d=>d.id!==body.p_decision);return reply(null);}
    if(url.pathname.endsWith('/convert_decision_to_activity')) {const d=state.decisions.find(d=>d.id===body.p_decision);d.converted_activity_id=crypto.randomUUID();return reply(d.converted_activity_id);}
    if(url.pathname.endsWith('/v_project_items') && state.activityError)return reply({code:'57014',message:'PRIVATE'},500);
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
      if(body.p_commitment){const a=state.activities.find(a=>a.id===body.p_commitment);Object.assign(a,body.p_fields);return reply(a);}
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
      if(url.searchParams.get('select')==='project_id')return reply({project_id:project.id});
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
  await page.evaluate(async path=>document.querySelector('#app').__vue_app__.config.globalProperties.$router.push(path),path);
}
async function fits(page,label) {
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),label);
}
function makeDecision(state,extra={}) {return {id:crypto.randomUUID(),project_id:state.project.id,title:'Where shall we meet?',description:null,status:'open',voting_deadline:null,voting_started:false,resolved_option_id:null,converted_activity_id:null,can_manage:true,writable:true,can_vote:true,deadline_reached:false,my_option_id:null,vote_count:0,options:[{id:crypto.randomUUID(),title:'Riverside',estimated_cost_minor:1200,vote_count:0},{id:crypto.randomUUID(),title:'Town centre',estimated_cost_minor:null,vote_count:0}],...extra};}
async function capture(page,name){await page.evaluate(()=>document.fonts.ready);await page.waitForTimeout(220);await fits(page,name);await page.screenshot({path:'/tmp/orchestrio-phase3-'+name+'.png',fullPage:true});}
try {
 for(const [width,height] of [[1280,900],[1024,768],[768,1024],[430,932],[390,844],[375,812]]) await test('Activity and Decision states '+width,async({page,state})=>{
  await page.setViewportSize({width,height});const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  await login(page);await go(page,'/app/projects/'+state.project.id+'/activities');await page.getByRole('button',{name:'Add activity',exact:true}).waitFor();await capture(page,'activities-empty-'+width);
  state.categories=[{id:crypto.randomUUID(),project_id:state.project.id,title:'Weekend plans'}];
  state.activities=['Book restaurant for the whole group','Walk by the river'].map((title,i)=>({id:crypto.randomUUID(),project_id:state.project.id,title,area_id:state.categories[0].id,activity_type:'other',kind:'other',status:i?'completed':'idea',owner_member_id:i?null:'00000000-0000-4000-8000-000000000020',starts_at:i?null:'2026-11-12T00:00:00Z',estimated_cost_minor:i?null:1250,deleted_at:null}));
  await page.reload();await page.getByRole('button',{name:'Open activity: Walk by the river',exact:true}).waitFor();await page.getByText('Unassigned',{exact:true}).waitFor();await page.getByText('£12.50',{exact:false}).waitFor();await capture(page,'activities-'+width);
  await page.getByRole('button',{name:'Open activity: Book restaurant for the whole group',exact:true}).click();await page.getByRole('dialog').getByRole('button',{name:'Edit',exact:true}).waitFor();await capture(page,'activity-detail-'+width);await page.keyboard.press('Escape');await page.getByRole('dialog').waitFor({state:'hidden'});
  await go(page,'/app/projects/'+state.project.id+'/decisions');await page.getByText('No decisions yet.',{exact:true}).waitFor();await capture(page,'decisions-empty-'+width);await page.getByRole('button',{name:'New decision',exact:true}).click();await page.getByLabel('Question',{exact:true}).waitFor();await capture(page,'decision-create-'+width);await page.keyboard.press('Escape');await page.getByLabel('Question',{exact:true}).waitFor({state:'detached'});
  const open=makeDecision(state);const voted=makeDecision(state,{title:'Which train?',voting_deadline:'2026-11-12T23:59:59Z',voting_started:true,vote_count:1});voted.my_option_id=voted.options[0].id;voted.options[0].vote_count=1;
  const resolved=makeDecision(state,{title:'Lunch choice',status:'resolved',can_vote:false});resolved.resolved_option_id=resolved.options[1].id;
  state.decisions=[resolved,open,voted];await page.reload();await page.getByRole('heading',{name:'Open decisions',exact:true}).waitFor();await capture(page,'decisions-'+width);
  const links=await page.locator('section a').allTextContents();assert(links.findIndex(t=>t.includes(open.title))<links.findIndex(t=>t.includes(resolved.title)));
  await page.getByRole('link',{name:new RegExp(open.title.replace('?','\\?'))}).click();await page.getByRole('button',{name:'Vote for Riverside',exact:true}).waitFor();await capture(page,'decision-open-'+width);assert((await page.getByRole('button',{name:'Vote for Riverside',exact:true}).boundingBox()).height>=44);await page.getByRole('button',{name:'Resolve decision',exact:true}).focus();await page.keyboard.press('Enter');await page.getByLabel('Select final option',{exact:true}).waitFor();await page.keyboard.press('Escape');await page.waitForTimeout(100);assert(await page.getByRole('button',{name:'Resolve decision',exact:true}).evaluate(el=>el===document.activeElement));
  await page.getByRole('link',{name:'All decisions',exact:true}).click();await page.getByRole('link',{name:/Which train/}).click();await page.getByRole('button',{name:'✓ Your vote',exact:true}).waitFor();await capture(page,'decision-voted-'+width);
  await page.getByRole('link',{name:'All decisions',exact:true}).click();await page.getByRole('link',{name:/Lunch choice/}).click();await page.getByText('Result: Town centre selected',{exact:true}).waitFor();await capture(page,'decision-resolved-'+width);assert.deepEqual(errors,[]);
 });
 await test('Decision create vote change remove edit resolve convert delete',async({page,state})=>{
  await login(page);await go(page,'/app/projects/'+state.project.id+'/decisions');await page.getByRole('button',{name:'New decision',exact:true}).click();let d=page.getByRole('dialog');
  await d.getByLabel('Question',{exact:true}).fill('Choose a venue');await d.getByLabel('Option 1',{exact:true}).fill('Riverside');await d.getByLabel('Option 2',{exact:true}).fill('Town centre');await d.getByLabel(/Estimated cost/).first().fill('12.50');
  await d.getByRole('button',{name:'Add option',exact:true}).click();await d.getByLabel('Option 3',{exact:true}).fill('Temporary');await d.getByRole('button',{name:'Remove option 3',exact:true}).click();await d.getByLabel('Deadline date (optional)',{exact:true}).fill('2026-11-12');
  await d.getByRole('button',{name:'Save decision',exact:true}).click();await d.waitFor({state:'hidden'});await page.getByRole('heading',{name:'Choose a venue',exact:true}).waitFor();assert.equal(state.decisions[0].options.length,2);assert.equal(state.decisions[0].options[0].estimated_cost_minor,1250);
  await page.getByRole('button',{name:'Vote for Riverside',exact:true}).click();await page.getByRole('button',{name:'✓ Your vote',exact:true}).waitFor();assert.equal(state.decisions[0].my_option_id,state.decisions[0].options[0].id);
  await page.getByRole('button',{name:'Vote for Town centre',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('[aria-pressed="true"]').length===1);await page.getByRole('button',{name:'Vote for Riverside',exact:true}).waitFor();assert.equal(state.decisions[0].my_option_id,state.decisions[0].options[1].id);
  await page.getByRole('button',{name:'Remove my vote',exact:true}).click();await page.getByRole('button',{name:'Remove my vote',exact:true}).waitFor({state:'hidden'});assert.equal(state.decisions[0].my_option_id,null);
  await page.getByRole('button',{name:'Edit decision',exact:true}).click();d=page.getByRole('dialog');assert(await d.getByLabel('Option 1',{exact:true}).isDisabled());await d.getByLabel('Question',{exact:true}).fill('Updated venue');await d.getByRole('button',{name:'Save decision',exact:true}).click();await d.waitFor({state:'hidden'});assert.equal(state.calls.find(c=>c.path.endsWith('/edit_decision_date')).body.p_options,null);assert.equal(state.calls.find(c=>c.path.endsWith('/edit_decision_date')).body.p_preserve_deadline,true);
  await page.getByRole('button',{name:'Resolve decision',exact:true}).click();d=page.getByRole('dialog');await d.getByLabel('Select final option',{exact:true}).selectOption(state.decisions[0].options[1].id);await d.getByRole('button',{name:'Confirm resolution',exact:true}).click();await page.getByText('Result: Town centre selected',{exact:true}).waitFor();assert.equal(await page.getByRole('button',{name:/Vote for/}).count(),0);
  state.categories=[{id:crypto.randomUUID(),title:'Plans'}];await page.getByRole('button',{name:'Create Activity',exact:true}).click();d=page.getByRole('dialog');await d.getByLabel('Category',{exact:true}).selectOption(state.categories[0].id);await d.getByRole('button',{name:'Confirm Create Activity',exact:true}).click();await page.getByRole('link',{name:'Open Activity',exact:true}).waitFor();
  await page.getByRole('button',{name:'Delete decision',exact:true}).click();await page.getByRole('button',{name:'Confirm delete',exact:true}).click();await page.getByText('No decisions yet.',{exact:true}).waitFor();assert.equal(state.decisions.length,0);
 });
 await test('Decision closed deadline and read-only authorization',async({page,state})=>{
  const d=makeDecision(state,{deadline_reached:true,voting_deadline:'2026-01-01T23:59:59Z',can_vote:false,can_manage:false,writable:false});state.decisions=[d];state.project.status='archived';state.role='viewer';await login(page);await go(page,'/app/projects/'+state.project.id+'/decisions/'+d.id);await page.getByText('This project is read-only.',{exact:true}).waitFor();await page.getByText(/Voting closed/).waitFor();for(const name of [/Vote for/,/Edit decision/,/Resolve decision/,/Delete decision/])assert.equal(await page.getByRole('button',{name}).count(),0);
  await go(page,'/app/projects/'+state.project.id+'/activities');await page.getByRole('heading',{name:'Activities',exact:true}).waitFor();assert.equal(await page.getByRole('button',{name:'Add activity',exact:true}).count(),0);
 });
 await test('Activity assignment timezone create edit and focus',async({page,state})=>{
  state.project.timezone='Europe/London';state.categories=[{id:crypto.randomUUID(),project_id:state.project.id,title:'Plans'}];await page.setViewportSize({width:375,height:812});await login(page);await go(page,'/app/projects/'+state.project.id+'/activities?area='+state.categories[0].id);
  await page.getByRole('button',{name:'Add activity',exact:true}).click();let d=page.getByRole('dialog');await d.getByLabel('Activity title *').fill('Prepare itinerary');await d.getByLabel('Activity type').selectOption('task');await d.getByLabel('Due date',{exact:true}).fill('2026-07-15');await d.getByLabel('Assigned to').selectOption('00000000-0000-4000-8000-000000000020');await d.getByLabel(/^Cost /).fill('12.50');await capture(page,'activity-create-375');await d.getByRole('button',{name:'Create activity',exact:true}).click();await page.getByRole('button',{name:'Open activity: Prepare itinerary',exact:true}).waitFor();
  assert.equal(state.activities[0].starts_at,'2026-07-14T23:00:00.000Z');assert.equal(state.activities[0].estimated_cost_minor,1250);assert.equal(state.activities[0].owner_member_id,'00000000-0000-4000-8000-000000000020');
  const row=page.getByRole('button',{name:'Open activity: Prepare itinerary',exact:true});await row.focus();await page.keyboard.press('Enter');await page.getByRole('dialog').getByRole('button',{name:'Edit',exact:true}).click();d=page.getByRole('dialog');await d.getByLabel('Activity title *').fill('Prepare revised itinerary');assert.equal(await d.getByLabel('Due date',{exact:true}).inputValue(),'2026-07-15');await capture(page,'activity-edit-375');await d.getByRole('button',{name:'Save activity',exact:true}).click();await page.getByRole('button',{name:'Open activity: Prepare revised itinerary',exact:true}).waitFor();await page.waitForTimeout(250);assert(await page.getByRole('button',{name:'Open activity: Prepare revised itinerary',exact:true}).evaluate(el=>el===document.activeElement),'Detail to edit restores row');assert.equal(state.activities.length,1);assert.equal(state.activities[0].title,'Prepare revised itinerary');
 });
 await test('Local loading error retry preserves navigation',async({page,state})=>{
  state.readDelay=1000;await login(page);await go(page,'/app/projects/'+state.project.id+'/decisions');await page.getByRole('status',{name:'Loading decisions',exact:true}).waitFor();await page.getByRole('link',{name:'Overview',exact:true}).waitFor();await page.getByText('No decisions yet.',{exact:true}).waitFor();state.readDelay=0;state.decisionError=true;await page.reload();await page.getByRole('button',{name:'Try again',exact:true}).waitFor({timeout:20000});assert(!(await page.locator('body').innerText()).includes('PRIVATE'));state.decisionError=false;await page.getByRole('button',{name:'Try again',exact:true}).click();await page.getByText('No decisions yet.',{exact:true}).waitFor();
  state.activityError=true;await go(page,'/app/projects/'+state.project.id+'/activities');await page.getByRole('button',{name:'Try again',exact:true}).waitFor({timeout:20000});await page.getByRole('link',{name:'Overview',exact:true}).waitFor();state.activityError=false;await page.getByRole('button',{name:'Try again',exact:true}).click();await page.getByText(/Activities are the work in your plan/).waitFor();
 });
 await test('Dialog keyboard focus restoration',async({page,state})=>{
  await login(page);await go(page,'/app/projects/'+state.project.id+'/decisions');const opener=page.getByRole('button',{name:'New decision',exact:true});await opener.focus();await page.keyboard.press('Enter');await page.getByLabel('Question',{exact:true}).waitFor();await page.keyboard.press('Escape');await page.waitForTimeout(250);assert(await opener.evaluate(el=>el===document.activeElement),'Decision create restores opener');
  await go(page,'/app/projects/'+state.project.id+'/activities');const add=page.getByRole('button',{name:'Add activity',exact:true});await add.focus();await page.keyboard.press('Enter');await page.getByLabel('Category name').waitFor();await page.keyboard.press('Escape');await page.waitForTimeout(250);assert(await add.evaluate(el=>el===document.activeElement),'Category dialog restores opener');
 });
 console.log(passed+' Activity/Decision browser scenarios passed.');
} finally {await browser.close();}
