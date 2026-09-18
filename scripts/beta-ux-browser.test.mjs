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
  const state = { project, categories: [], activities: [], tasks: [], payments: [], deleteFail: false, role:'organizer', unread:true, user: structuredClone(user), calls: [], signupSession: false, error: null, nonceRequired: false };
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
try {
 for(const width of [375,430,768,1280]) {
  await test('Activity/payment/delete at '+width+'px',async({page,state})=>{
   await page.setViewportSize({width,height:900});await login(page);
   await go(page,'/app/projects/'+state.project.id+'/activities');
  assert.equal(await page.getByRole('button',{name:'Add activity',exact:true}).count(),0);
  await page.getByRole('button',{name:'New category',exact:true}).click();
  let categoryDialog=page.getByRole('dialog');
  await categoryDialog.getByLabel('Category name').fill('Transport');
  await categoryDialog.getByRole('button',{name:'Save category',exact:true}).click();
  await page.getByRole('button',{name:'Add activity',exact:true}).click();
   let dialog=page.getByRole('dialog');
   assert.equal(await dialog.getByText('Owner',{exact:true}).count(),0);
   assert.equal(await dialog.getByRole('button',{name:/Add location/}).count(),0);
  await dialog.getByLabel('Activity title *').fill('Book restaurant');
  await dialog.getByLabel('Activity type').selectOption('other');
   await dialog.getByLabel(/^Cost /).fill('100');
    assert.equal(await dialog.getByLabel('Category').count(),0);
    assert.equal(await dialog.getByText('Additional details',{exact:true}).count(),0);
    await dialog.getByRole('button',{name:'Create activity',exact:true}).click();
  await page.getByRole('dialog').waitFor({state:'hidden'});await go(page,'/app/projects/'+state.project.id+'/areas?area='+state.categories[0].id);
   await page.getByRole('button',{name:/Book restaurant/}).click();
   dialog=page.getByRole('dialog');
   assert.equal(await dialog.getByText('Actual / final:',{exact:false}).count(),0);
   assert.equal(await dialog.getByText('Cost sharing',{exact:true}).count(),0);
   await dialog.getByRole('button',{name:'Add payment',exact:true}).click();
   await dialog.getByLabel('Amount',{exact:true}).fill('30');
   await dialog.getByRole('button',{name:'Add payment',exact:true}).click();
   await page.waitForFunction(()=>document.body.textContent.includes('£70.00'));
   assert.equal(state.payments[0].status,'paid');assert(state.payments[0].paid_on);assert.equal(state.payments[0].amount_minor,3000);
   await dialog.getByRole('button',{name:'Complete',exact:true}).click();
   await page.getByText(/£70.00 is still outstanding/).waitFor();
   await page.getByRole('button',{name:'Record payment',exact:true}).click();
   await dialog.getByLabel('Payment type').selectOption('full');
   assert.equal(await dialog.getByLabel('Amount',{exact:true}).inputValue(),'70');
   await dialog.getByLabel('Payment type').selectOption('balance');
   assert.equal(await dialog.getByLabel('Amount',{exact:true}).inputValue(),'70');
   await dialog.getByRole('button',{name:'Add payment',exact:true}).click();
   await page.waitForFunction(()=>document.body.textContent.includes('£0.00'));
   await dialog.getByRole('button',{name:'Complete',exact:true}).click();
   await dialog.getByText('Completed',{exact:true}).waitFor();
  await fits(page,'Area dialog fits');
   await dialog.getByText('More',{exact:true}).click();
   state.deleteFail=true;
  await dialog.getByRole('button',{name:'Delete activity',exact:true}).click();
   await page.getByRole('button',{name:'Delete',exact:true}).click();
   await page.getByText("You don't have permission to do that.").waitFor();
   assert.equal(state.activities[0].deleted_at,null);
   state.deleteFail=false;
   await page.getByRole('button',{name:'Delete',exact:true}).click();
  await page.getByText('No activities in this Category yet.').waitFor();
  await page.reload();await page.getByText('No activities in this Category yet.').waitFor();
  await fits(page,'Activities after delete fit');
  });
 }
 await test('Required project date and direct navigation',async({page,state})=>{
  await login(page);await go(page,'/app/projects');
  await page.getByRole('button',{name:/New project/}).first().click();
  await page.getByRole('button',{name:'Continue',exact:true}).click();
  await page.getByRole('button',{name:'Create project',exact:true}).click();
  await page.getByText('Give the project a name.').waitFor();
  await page.getByLabel('Project name').fill('Beta UX Test');
  await page.getByRole('button',{name:'Create project',exact:true}).click();
  await page.getByText('Choose a start date.').waitFor();
  await page.getByLabel('Start date').fill('2026-09-16');
  await page.getByRole('button',{name:'Create project',exact:true}).click();
  await page.waitForURL('**/overview');assert.equal(state.project.ends_on,null);
 });
 await test('Activity Cost and assigned Viewer controls',async({page,state})=>{
  await login(page);await go(page,'/app/projects/'+state.project.id+'/areas');
    await page.getByRole('button',{name:'New category',exact:true}).click();let categoryDialog=page.getByRole('dialog');
    await categoryDialog.getByLabel('Category name').fill('Transport');
    await categoryDialog.getByRole('button',{name:'Save category',exact:true}).click();
    await page.getByRole('button',{name:'Add activity',exact:true}).click();let d=page.getByRole('dialog');
  await d.getByLabel('Activity title *').fill('Cost activity');await d.getByLabel(/^Cost /).fill('12.50');await d.getByLabel('Activity type').selectOption('task');
  await d.getByRole('button',{name:'Create activity',exact:true}).click();await d.waitFor({state:'hidden'});
  assert.equal(state.calls.find(c=>c.path.endsWith('/create_activity_in_category')).body.p_fields.estimated_cost_minor,1250);
  state.role='viewer';const item=state.activities[0];item.estimated_cost_minor=null;item.owner_member_id='00000000-0000-4000-8000-000000000020';
  await page.reload();await page.getByText('Cost activity',{exact:true}).waitFor();await go(page,'/app/projects/'+state.project.id+'/areas?commitment='+item.id);d=page.getByRole('dialog');
  assert.equal(await d.getByRole('button',{name:'Edit',exact:true}).count(),0);await d.getByRole('button',{name:'Complete',exact:true}).click();await d.getByText('Completed',{exact:true}).waitFor();
  assert(state.calls.some(c=>c.path.endsWith('/complete_assigned_item')));
  item.status='idea';item.owner_member_id=null;await page.reload();d=page.getByRole('dialog');await d.getByText('Cost activity',{exact:true}).waitFor();assert.equal(await d.getByRole('button',{name:'Complete',exact:true}).count(),0);
 });
 await test('Public copy and responsive layout',async({page})=>{
  for(const width of [375,430,768,1280]){
   await page.setViewportSize({width,height:900});await page.goto(origin+'/');
   await page.getByRole('heading',{name:'Plan together. Keep everything in one place.'}).waitFor();
   assert(!(await page.textContent('main')).includes('It fragments'));await fits(page,'Landing fits');
  }
  await page.goto(origin+'/about');await page.getByText(/I'm Brendan Ugo-Emeribe, founder of Orchestrio/).waitFor();await fits(page,'About fits');
 });
 console.log(passed+' Beta browser scenarios passed.');
} finally {await browser.close();}
