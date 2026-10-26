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
  const state = { project, calendar:[], timeline:[], categories: [], activities: [], tasks: [], payments: [], deleteFail: false, role:'organizer', unread:true, notificationUnread:false, invitations:[], user: structuredClone(user), calls: [], signupSession: false, error: null, nonceRequired: false };
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
    if(state.failRead===end)return reply({code:'57014',message:'PRIVATE QUERY'},500);
    if(state.readDelay && ['get_project_calendar','get_project_timeline_events'].includes(end))await new Promise(r=>setTimeout(r,state.readDelay));
    if(end==='get_project_calendar')return reply(state.calendar.filter(e=>{const day=e.start_date??e.start_at.slice(0,10);return day>=body.p_range_start&&day<body.p_range_end;}));
    if(end==='get_project_timeline_events')return reply(state.timeline);
    if(end==='get_decisions')return reply([{id:body.p_decision,project_id:project.id,title:'Choose train',status:'open',options:[],can_manage:false,can_vote:false,writable:true,vote_count:0}]);
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
  await page.evaluate(async path=>document.querySelector('#app').__vue_app__.config.globalProperties.$router.push(path),path);
}
async function fits(page,label) {
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),label);
}
function populate(state){
 const activity=crypto.randomUUID(),decision=crypto.randomUUID();state.project.timezone='Europe/London';state.activities=[{id:activity,title:'Evening arrival with a long readable title',activity_type:'event',kind:'transport',project_id:state.project.id,status:'idea',starts_at:'2026-10-07T23:30:00Z',estimated_cost_minor:null,deleted_at:null}];
 const base={project_id:state.project.id,activity_id:activity,activity_title:'Evening arrival with a long readable title',activity_type:'event',start_at:null,end_at:null,start_date:'2026-10-08',end_date:null,all_day:true,status:'idea',category_name:'Travel',assigned_member:'Beta',amount_minor:null,currency_code:'GBP',occurrence_date:null};
 state.calendar=[{...base,entry_id:'activity:'+activity,source_type:'activity',source_id:activity,title:state.activities[0].title,start_at:'2026-10-07T23:30:00Z',start_date:null,all_day:false},{...base,entry_id:'decision:'+decision,source_type:'decision',source_id:decision,title:'Choose train',status:'open',start_at:'2026-10-08T22:59:59Z',start_date:null,all_day:false},{...base,entry_id:'payment:one',source_type:'payment_schedule',source_id:crypto.randomUUID(),title:'Pay train deposit',status:'upcoming',amount_minor:12500},{...base,entry_id:'occurrence:one',source_type:'activity_occurrence',source_id:activity,title:'Weekly check-in',status:'pending',occurrence_date:'2026-10-08'},{...base,entry_id:'activity:span',source_type:'activity',source_id:activity,title:'Three-day visit',end_date:'2026-10-10'}];
 state.timeline=[{project_id:state.project.id,subject_id:activity,subject_type:'commitment',title:'Past preparation',occurs_at:'2026-10-06T11:00:00Z',event_type:'commitment_start',status:'completed',all_day:false},{project_id:state.project.id,subject_id:decision,subject_type:'decision',title:'Choose train',occurs_at:'2026-10-08T22:59:59Z',event_type:'decision_deadline',status:'voting_open',all_day:false},{project_id:state.project.id,subject_id:activity,subject_type:'payment_schedule',title:'Pay train deposit',occurs_at:'2026-10-09T00:00:00Z',event_type:'payment_due',status:'upcoming',all_day:true},{project_id:state.project.id,subject_id:activity,subject_type:'commitment',title:'Weekly check-in',occurs_at:'2026-10-10T09:00:00Z',event_type:'recurring_commitment_due',status:'pending',all_day:false,is_recurring_occurrence:true,occurrence_date:'2026-10-10'}].reverse();
}
async function capture(page,name){await page.evaluate(()=>document.fonts.ready);await page.waitForTimeout(200);await fits(page,name);await page.screenshot({path:'/tmp/orchestrio-phase5-'+name+'.png',fullPage:true});}
try{
 for(const [width,height] of [[1280,900],[1024,768],[768,1024],[430,932],[390,844],[375,812]])await test('Calendar Timeline viewport '+width,async({page,state})=>{
  await page.clock.setFixedTime(new Date('2026-10-07T23:45:00Z'));const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});await page.setViewportSize({width,height});populate(state);await login(page);await go(page,'/app/projects/'+state.project.id+'/calendar');await page.getByRole('heading',{name:'October 2026',exact:true}).waitFor();
  assert.equal(await page.getByRole('button',{name:width<640?'Agenda':'Month',exact:true}).getAttribute('aria-pressed'),'true');await page.getByRole('button',{name:'Month',exact:true}).click();await page.getByRole('table',{name:'Month calendar',exact:true}).waitFor();await capture(page,'month-'+width);if(width>=1024){await page.getByRole('button',{name:'3 more entries for 8 October',exact:true}).click();await page.getByRole('heading',{name:'Thursday, 8 October 2026 · Today',exact:true}).waitFor();await page.getByRole('button',{name:'Show all dates',exact:true}).click();}const day=page.getByRole('button',{name:'Thursday, 8 October 2026, 5 entries',exact:true});assert.equal(await day.getAttribute('aria-current'),'date');assert((await day.boundingBox()).height>=44);await day.focus();await page.keyboard.press('Enter');await page.getByRole('heading',{name:'Thursday, 8 October 2026 · Today',exact:true}).waitFor();assert.equal(await day.getAttribute('aria-pressed'),'true');await capture(page,'dense-day-'+width);
  await page.getByRole('button',{name:'Show all dates',exact:true}).click();await page.getByRole('button',{name:'Agenda',exact:true}).click();await page.getByRole('heading',{name:'Saturday, 10 October 2026',exact:true}).waitFor();await page.getByText(/00:30 · Activity/).waitFor();await capture(page,'agenda-'+width);
  await page.getByRole('group',{name:'Calendar sources',exact:true}).getByRole('button',{name:'Decisions',exact:true}).click();assert.equal(await page.getByRole('link',{name:/Payment due:/}).count(),0);await page.getByRole('link',{name:'Decision deadline: Choose train, Open',exact:true}).waitFor();await page.getByRole('button',{name:'All',exact:true}).click();await page.getByRole('button',{name:'Next month',exact:true}).click();await page.getByRole('heading',{name:'November 2026',exact:true}).waitFor();await page.getByText(/Nothing scheduled in this range/).waitFor();await capture(page,'empty-range-'+width);await page.getByRole('button',{name:'Previous month',exact:true}).click();await page.getByRole('heading',{name:'October 2026',exact:true}).waitFor();await page.getByRole('button',{name:'Today',exact:true}).click();
  await go(page,'/app/projects/'+state.project.id+'/timeline');await page.getByRole('link',{name:/Past preparation/}).waitFor();const texts=await page.locator('ol a').allTextContents();assert(texts[0].includes('Past preparation'));assert(texts[1].includes('Choose train'));assert(texts[0].includes('Past'));assert(texts[1].includes('Upcoming'));await capture(page,'timeline-'+width);
  state.timeline=state.timeline.slice(0,1);await page.reload();await page.getByRole('link',{name:/Weekly check-in/}).waitFor();await capture(page,'timeline-sparse-'+width);state.timeline=[];await page.reload();await page.getByText('Nothing on the timeline yet.',{exact:true}).waitFor();await capture(page,'timeline-empty-'+width);state.calendar=[];await go(page,'/app/projects/'+state.project.id+'/calendar');await page.getByText(/Nothing scheduled in this range/).waitFor();await capture(page,'calendar-empty-'+width);assert.deepEqual(errors,[]);
 });
 await test('Canonical Calendar and Timeline destinations',async({page,state})=>{
  await page.clock.setFixedTime(new Date('2026-10-07T23:45:00Z'));populate(state);await login(page);const base='/app/projects/'+state.project.id;
  for(const [label,part] of [['Activity · event: Evening arrival with a long readable title, Pending','commitment='+state.activities[0].id],['Decision deadline: Choose train, Open','/decisions/'+state.calendar[1].source_id],['Payment due: Pay train deposit, Upcoming','section=payments'],['Activity · event: Weekly check-in, Pending','occurrence=2026-10-08']]){await go(page,base+'/calendar');await page.getByRole('button',{name:'Agenda',exact:true}).click();const link=page.getByRole('link',{name:label,exact:true}).first();await link.focus();await page.keyboard.press('Enter');await page.waitForURL(url=>url.href.includes(part));}
  for(const [label,part] of [['Past preparation','commitment='+state.activities[0].id],['Choose train','/decisions/'+state.calendar[1].source_id],['Pay train deposit','section=payments'],['Weekly check-in','occurrence=2026-10-10']]){await go(page,base+'/timeline');await page.getByRole('link',{name:new RegExp(label)}).click();await page.waitForURL(url=>url.href.includes(part));}
 });
 await test('Local loading and retry retains project navigation',async({page,state})=>{
  await page.clock.setFixedTime(new Date('2026-10-07T23:45:00Z'));populate(state);state.readDelay=900;await login(page);await go(page,'/app/projects/'+state.project.id+'/calendar');await page.getByRole('status',{name:'Loading calendar',exact:true}).waitFor();await page.getByRole('heading',{name:'October 2026',exact:true}).waitFor();state.readDelay=0;state.failRead='get_project_calendar';await page.reload();await page.getByRole('button',{name:'Try again',exact:true}).waitFor({timeout:20000});assert(!(await page.locator('body').innerText()).includes('PRIVATE'));await go(page,'/app/projects/'+state.project.id+'/timeline');await page.getByRole('link',{name:/Past preparation/}).waitFor();state.failRead='get_project_timeline_events';await page.reload();await page.getByRole('button',{name:'Try again',exact:true}).waitFor({timeout:20000});state.failRead=null;await page.getByRole('button',{name:'Try again',exact:true}).click();await page.getByRole('link',{name:/Past preparation/}).waitFor();await page.getByRole('link',{name:'Overview',exact:true}).waitFor();
 });
 console.log(passed+' Calendar/Timeline browser scenarios passed.');
}finally{await browser.close();}
