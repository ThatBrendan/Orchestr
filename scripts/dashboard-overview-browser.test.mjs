/** Run against local Vite only. Every backend request is mocked; no email or remote data is touched. */
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const origin = process.env.AUTH_TEST_ORIGIN || 'http://127.0.0.1:5173';
assert(['localhost', '127.0.0.1'].includes(new URL(origin).hostname), 'Tests require a local app');
const browser = await chromium.launch({ headless: true, channel: process.env.AUTH_TEST_BROWSER || 'chrome' });
const user = { id: '00000000-0000-4000-8000-000000000001', email: 'beta@example.test', aud: 'authenticated', role: 'authenticated', created_at: new Date().toISOString(), email_confirmed_at: new Date().toISOString(), app_metadata: { provider: 'email' }, user_metadata: {}, identities: [] };
async function fixture(options = {}) {
  const context = await browser.newContext(options);
  const violations=[];
  await context.exposeBinding('reportCsp',(_source,v)=>violations.push(v));
  await context.addInitScript(()=>document.addEventListener('securitypolicyviolation',event=>window.reportCsp({directive:event.violatedDirective,uri:event.blockedURI})));
  const page = await context.newPage();
  page.setDefaultTimeout(10000);
  const project = {id:'00000000-0000-4000-8000-000000000010',name:'Beta Trip',status:'active',profile:'group_trip',module_visibility:{},currency:'GBP',timezone:'UTC',starts_on:null,ends_on:null,description:null,deleted_at:null};
  const state = { project, attention: [], events: [], emptyUser: false, failSummary: false, categories: [], activities: [], tasks: [], payments: [], deleteFail: false, role:'organizer', unread:true, notificationUnread:false, invitations:[], user: structuredClone(user), calls: [], signupSession: false, error: null, nonceRequired: false };
  const token = () => {
    const payload = { sub: state.user.id, exp: Math.floor(Date.now()/1000)+3600, role: 'authenticated', aud: 'authenticated' };
    return { access_token: `e30.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.signature`, refresh_token: 'mock-refresh-token', expires_in: 3600, token_type: 'bearer', user: state.user };
  };
  await context.route('**/*', async route => {
    const req = route.request();
    const url = new URL(req.url());
    if (url.origin === origin && !url.pathname.startsWith('/auth/v1/') && !url.pathname.startsWith('/rest/v1/')) return route.continue();
    if(state.delayReads && ['/get_my_attention','/get_project_health','/v_my_projects','/v_project_financials','/get_project_timeline_events'].some(path=>url.pathname.endsWith(path))) await new Promise(resolve=>setTimeout(resolve,state.delayReads));
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
    if(url.pathname.endsWith('/get_my_attention')) {
      if(state.failSummary)return reply({code:'57014',message:'PRIVATE'},500);
      const start=Number(url.searchParams.get('offset')||0), rows=state.attention.slice(start,start+5);
      return route.fulfill({status:200,contentType:'application/json',headers:{'content-range':rows.length?start+'-'+(start+rows.length-1)+'/'+state.attention.length:'*/0','access-control-expose-headers':'content-range'},body:JSON.stringify(rows)});
    }
    if(url.pathname.endsWith('/get_project_health')) return state.failSummary ? reply({code:'57014',message:'PRIVATE'},500) : reply(state.attention);
    if(url.pathname.endsWith('/get_project_timeline_events')) return reply(state.events);
    if(url.pathname.endsWith('/v_project_financials')) return reply({project_id:project.id,total_target_minor:100000,net_actual_spend_minor:25000,settled_variance_minor:75000});
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
    if(url.pathname.endsWith('/v_my_projects')) return reply(state.emptyUser?[]:[{...state.project,project_id:project.id,progress_pct:40,attention_count:state.attention.length,committed_spend_minor:40000,total_target_minor:100000}]);
    if(url.pathname.endsWith('/v_my_activity_notifications')) return route.fulfill({status:200,contentType:'application/json',headers:{'content-range':state.unread?'0-0/1':'*/0','access-control-expose-headers':'content-range'},body:JSON.stringify(state.unread?[{id:'00000000-0000-4000-8000-000000000030',project_id:project.id,commitment_id:'00000000-0000-4000-8000-000000000040',activity_title:'Book restaurant',project_name:project.name,created_at:new Date().toISOString(),read_at:null}]:[])});
    if(url.pathname.endsWith('/mark_notification_read')) {state.unread=false;return reply(body.p_notification);}
    if (url.pathname.endsWith('/get_invitation')) return reply([{ project_name: 'Shared test project', inviter_name: 'Inviter', role:'member', status:'pending' }]);
    if (url.pathname.endsWith('/accept_invitation')) return reply('00000000-0000-4000-8000-000000000003');
    if (url.pathname.endsWith('/users')) return reply({ id:state.user.id, email:state.user.email, display_name:'Beta', timezone:'Europe/London', default_currency:'GBP' });
    return reply([]);
  });
  return { context, page, state, violations };
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
}// Local presentation fixtures reuse the beta-browser setup; all remote requests are intercepted.
const fs = await import('node:fs/promises');
const evidence = '/tmp/orchestrio-dashboard-overview';
await fs.mkdir(evidence, {recursive:true});
const results=[];
const sizes=[[1280,900],[1024,768],[768,1024],[430,932],[390,844],[375,812]];
function populate(state) {
 state.categories=[{id:'00000000-0000-4000-8000-000000000080',project_id:state.project.id,title:'Plans'}];
 state.attention=Array.from({length:6},(_,i)=>({project_id:state.project.id,project_name:state.project.name,code:'fixture-'+i,severity:'warning',subject_type:i===0?'decision':i===1?'payment_schedule':i===2?'commitment':'project',subject_id:'00000000-0000-4000-8000-00000000004'+i,subject_label:['Choose a venue','Venue deposit','Book transport','Project readiness','Confirm dates','Final check'][i],params:{activity_id:'00000000-0000-4000-8000-000000000041'},message:['Voting closes tomorrow','Payment is due tomorrow','Transport needs an owner','Review project details','Check the project dates','Review remaining plans'][i],resolution:['Choose your preferred option.','Review the payment schedule.','Assign someone to coordinate this.','Check what needs completing.','Confirm the dates with your team.','Review the final details.'][i],dismissed:false}));
 state.events=Array.from({length:6},(_,i)=>({project_id:state.project.id,event_type:i===1?'payment_due':'commitment_start',subject_type:i===1?'payment_schedule':i===2?'decision':'commitment',subject_id:'00000000-0000-4000-8000-00000000004'+i,title:['Confirm venue','Venue deposit','Choose dinner','Book transport','Check arrival times','Final meeting'][i],occurs_at:new Date(Date.now()+(i+1)*86400000).toISOString(),all_day:i===1,status:i===1?'scheduled':i===2?'voting_open':'booked',is_recurring_occurrence:false}));
}
async function capture(page,name,width) {
 await page.evaluate(()=>document.fonts.ready);await page.waitForTimeout(220);
 await fits(page,name+' '+width);
 await page.screenshot({path:`${evidence}/${name}-${width}.png`,fullPage:true});
 results.push({name,width,path:new URL(page.url()).pathname});
}
try {
 for(const [width,height] of sizes) {
  for(const scenario of ['populated','clear','empty']) {
   const f=await fixture({viewport:{width,height}}),{page,state}=f;
   const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error') errors.push(m.text());});
   if(scenario!=='empty')populate(state);
   if(scenario==='clear')state.attention=[];
   if(scenario==='empty')state.emptyUser=true;
   await login(page);
   await page.getByRole('heading',{name:'Projects',exact:true}).waitFor();
   if(scenario!=='empty')await page.getByRole('link',{name:'Open project: Beta Trip',exact:true}).waitFor();
   await capture(page,'dashboard-'+scenario,width);
   if(scenario==='populated') {
    assert.equal(await page.getByRole('link').filter({hasText:'Open decision'}).count(),1);
    await page.getByRole('navigation',{name:'Needs attention pages'}).getByRole('button',{name:'Next',exact:true}).click();
    await page.getByText('Final check ·',{exact:true}).waitFor();
    await page.getByRole('navigation',{name:'Needs attention pages'}).getByRole('button',{name:'Previous',exact:true}).click();
    await page.getByText('Choose a venue ·',{exact:true}).waitFor();
    assert((await page.getByRole('link').filter({hasText:'Open decision'}).getAttribute('href')).includes('/decisions/'));
   }
   await page.getByRole('button',{name:'New project',exact:true}).click();
   await page.getByRole('heading',{name:'What are you planning?',exact:true}).waitFor();
   await page.keyboard.press('Escape');
   await page.getByRole('button',{name:'Close dialog',exact:true}).waitFor({state:'hidden'});
   await page.waitForTimeout(300);
   assert(await page.getByRole('button',{name:'New project',exact:true}).evaluate(e=>document.activeElement===e),'Creation dialog restores focus');
   const base='/app/projects/'+state.project.id;
   if(scenario==='empty')await go(page,base+'/overview');
   else {await page.getByRole('link',{name:'Open project: Beta Trip',exact:true}).focus();await page.keyboard.press('Enter');}
   await page.getByRole('heading',{name:'People',exact:true}).waitFor();
   assert(await page.locator('h2').first().evaluate(e=>document.activeElement===e),'Overview receives navigation focus');
   if(scenario==='populated')await page.getByText('Choose a venue ·',{exact:true}).waitFor();
   if(scenario==='empty')await page.getByRole('link',{name:'Create your first category',exact:true}).waitFor();
   await capture(page,'overview-'+scenario,width);
   if(scenario==='populated') {
    assert.equal(await page.getByText('Final check ·',{exact:true}).count(),0);
    await page.getByRole('button',{name:'Next needs attention page',exact:true}).click();
    await page.getByText('Final check ·',{exact:true}).waitFor();
    await page.getByRole('button',{name:'Previous needs attention page',exact:true}).click();
    await page.getByText('Choose a venue ·',{exact:true}).waitFor();
    await page.getByRole('link',{name:/View Budget/}).click();await page.waitForURL(origin+base+'/budget');
    await go(page,base+'/overview');await page.getByRole('link',{name:/View People/}).click();await page.waitForURL(origin+base+'/people');
    await go(page,base+'/overview');await page.getByRole('link',{name:/View calendar/}).click();await page.waitForURL(origin+base+'/calendar');
    await go(page,base+'/overview');
    const payment=page.getByRole('link').filter({hasText:'Open payments'}).first();
    await payment.click();await page.waitForURL(/section=payments/);
    await go(page,base+'/overview');
   }
   await page.getByRole('button',{name:'Account menu',exact:true}).click();await page.getByRole('menu').waitFor();await page.keyboard.press('ArrowDown');await page.keyboard.press('Escape');
   await page.getByRole('link',{name:width<768?'Home':'Dashboard',exact:true}).click();await page.waitForURL(origin+'/app');
   assert.deepEqual(errors,[]);assert.deepEqual(f.violations,[]);
   await f.context.close();
   console.log(`PASS ${scenario} at ${width}×${height}`);
  }
 }
 for(const [width,height] of [[1280,900],[390,844]]) {
  const f=await fixture({viewport:{width,height}}),{page,state}=f;populate(state);state.delayReads=1500;
  await login(page);await capture(page,'dashboard-loading',width);
  await page.getByRole('link',{name:'Open project: Beta Trip',exact:true}).waitFor();
  await go(page,'/app/projects/'+state.project.id+'/overview');await capture(page,'overview-loading',width);
  await page.getByText('Choose a venue ·',{exact:true}).waitFor();
  state.delayReads=0;state.failSummary=true;
  await page.reload();await page.getByRole('button',{name:'Try again',exact:true}).waitFor({timeout:20000});
  assert(await page.getByRole('link',{name:/View Budget/}).isVisible());
  await capture(page,'overview-error',width);
  state.failSummary=false;await page.getByRole('button',{name:'Try again',exact:true}).click();await page.getByText('Choose a venue ·',{exact:true}).waitFor();
  state.failSummary=true;await go(page,'/app');await page.getByRole('button',{name:'Try again',exact:true}).waitFor({timeout:20000});
  assert(await page.getByRole('link',{name:'Open project: Beta Trip',exact:true}).isVisible());
  await capture(page,'dashboard-error',width);
  assert(!(await page.locator('body').innerText()).includes('PRIVATE'));
  state.failSummary=false;await page.getByRole('button',{name:'Try again',exact:true}).click();await page.getByText('Choose a venue ·',{exact:true}).waitFor();
  await page.getByRole('button',{name:'New project',exact:true}).click();
  await page.getByRole('button',{name:'Continue',exact:true}).click();
  await page.getByLabel('Project name').fill('Coordinating together');await page.getByLabel('Start date').fill('2026-11-01');
  await page.getByRole('button',{name:'Create project',exact:true}).click();await page.waitForURL('**/overview');
  assert.equal(state.calls.filter(c=>c.path.endsWith('/create_project')).length,1);
  await f.context.close();console.log('PASS loading, isolated errors, retry and Dashboard creation at '+width);
 }
 await fs.writeFile(evidence+'/results.json',JSON.stringify(results,null,2));
} finally {await browser.close();}
