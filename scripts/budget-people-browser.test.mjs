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
  const browserErrors=[];page.on('pageerror',e=>browserErrors.push(e.stack));page.on('console',m=>{if(m.type()==='error')browserErrors.push(m.text());});
  page.setDefaultTimeout(10000);
  const project = {id:'00000000-0000-4000-8000-000000000010',name:'Beta Trip',status:'active',profile:'group_trip',module_visibility:{},currency:'GBP',timezone:'UTC',starts_on:null,ends_on:null,description:null,deleted_at:null};
  const state = { project, financials:{total_target_minor:null,net_actual_spend_minor:0,settled_variance_minor:null}, budgetCategories:[], balances:[], balanceLines:[], history:[], requests:[], projectInvites:[], roster:null, linkToken:null, reimbursements:[], acknowledged:true, categories: [], activities: [], tasks: [], payments: [], deleteFail: false, role:'organizer', unread:true, notificationUnread:false, invitations:[], user: structuredClone(user), calls: [], signupSession: false, error: null, nonceRequired: false };
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
    if(state.failResource===end)return reply({code:'57014',message:'PRIVATE'},500);
    if(state.readDelay && ['v_project_financials','v_member_directory'].includes(end))await new Promise(r=>setTimeout(r,state.readDelay));
    if(end==='v_project_financials')return reply({project_id:project.id,...state.financials});
    if(end==='v_budget_category_actuals')return reply(state.budgetCategories);
    if(end==='v_project_member_settlements')return reply(state.balances);
    if(end==='v_project_settlement_totals')return reply(null);
    if(end==='v_item_member_balances')return reply(state.balanceLines);
    if(end==='v_reimbursements')return reply(state.reimbursements);
    if(end==='v_reimbursement_payment_status')return reply({active_acknowledgement_id:state.acknowledged?'fixture-ack':null,confirmation_state:null,history:[]});
    if(end==='get_reimbursement_payment_options')return reply(['monzo','revolut','paypal','custom'].map((provider,i)=>({id:String(i),provider,display_label:provider==='custom'?'Personal link':provider,payment_url:['https://monzo.me/fixture','https://revolut.me/fixture','https://paypal.me/fixture','https://example.test/pay'][i],is_default:i===0})));
    if(end==='get_project_join_access')return reply({active:!!state.linkToken,token:state.linkToken,pending_count:state.requests.length,requests:state.requests.slice(body.p_offset,body.p_offset+25)});
    if(end==='ensure_project_join_link'){state.linkToken??='a'.repeat(64);return reply(state.linkToken);}
    if(end==='disable_project_join_link'){state.linkToken=null;return reply(null);}
    if(end==='review_project_join_request'){state.requests=state.requests.filter(r=>r.id!==body.p_request);return reply(null);}
    if(end==='invitations')return reply(state.projectInvites);
    if(end==='create_invitation'){const id=crypto.randomUUID();state.projectInvites.push({id,email:body.p_email,role:body.p_role,status:'pending',expires_at:'2099-01-01',created_at:new Date().toISOString()});return reply(id);}
    if(end==='set_project_budget'){state.financials.total_target_minor=body.p_amount;return reply(null);}
    if(end==='record_item_settlement'){state.history.push({id:crypto.randomUUID(),commitment_id:body.p_item,paid_by_member_id:body.p_from,amount_minor:body.p_amount,paid_on:body.p_date,status:'paid',settlement_group_id:crypto.randomUUID()});return reply(null);}
    if(end==='cancel_item_settlement'){state.history.find(h=>h.settlement_group_id===body.p_group).status='cancelled';return reply(null);}
    if(end==='payments' && url.searchParams.has('settlement_group_id'))return reply(state.history);
    if(end==='v_member_directory' && state.roster)return reply(state.roster);
    if(end==='project_members' && req.method()==='PATCH'){const m=state.roster.find(m=>'eq.'+m.member_id===url.searchParams.get('id'));Object.assign(m,body);return reply(m);}
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
  return { context, page, state, violations, browserErrors };
}
async function test(name, fn, options) {
  if (process.env.AUTH_TEST_FILTER && !name.includes(process.env.AUTH_TEST_FILTER)) return;
  const f = await fixture(options);
  try { await fn(f); assert.deepEqual(f.violations, [], "No CSP violations"); passed++; console.log(`PASS: ${name}`); }
  catch (e) { console.error(f.browserErrors);console.error((await f.page.textContent("body")).slice(0,1500),); throw e; }
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
const mid='00000000-0000-4000-8000-000000000020';
function populated(state){
 state.financials={total_target_minor:100000,net_actual_spend_minor:45000,settled_variance_minor:55000};
 state.budgetCategories=[{kind:'transport',target_minor:60000,actual_minor:30000,net_paid_minor:30000},{kind:'food',target_minor:null,actual_minor:15000,net_paid_minor:15000}];
 state.roster=[{member_id:mid,project_id:state.project.id,user_id:user.id,display_name:'Beta',role:'organizer',status:'active'},{member_id:crypto.randomUUID(),display_name:'Alexandra with a very long family name',role:'member',status:'active'},{member_id:crypto.randomUUID(),display_name:'Sam',role:'viewer',status:'active'}];
 state.balances=state.roster.map((m,i)=>({...m,member_status:m.status,currency:'GBP',allocated_minor:15000,paid_minor:[0,30000,15000][i],remaining_minor:[15000,-15000,0][i]}));
 const activity=crypto.randomUUID();state.activities=[{id:activity,project_id:state.project.id,title:'Train tickets for the group',activity_type:'other',kind:'transport',status:'idea',estimated_cost_minor:45000,owner_member_id:mid,deleted_at:null}];
 state.balanceLines=state.balances.map(m=>({...m,commitment_id:activity,item_id:activity,item_title:'Train tickets for the group',area_title:'Travel'}));
 state.requests=[{id:crypto.randomUUID(),display_name:'Riley',requested_at:'2026-10-24T10:00:00Z'},{id:crypto.randomUUID(),display_name:'Jordan',requested_at:'2026-10-24T11:00:00Z'}];
 state.projectInvites=[{id:crypto.randomUUID(),email:'avery.long.invitation.address@example.test',role:'member',status:'pending',expires_at:'2099-01-01',created_at:'2026-10-24'},{id:crypto.randomUUID(),email:'expired@example.test',role:'viewer',status:'pending',expires_at:'2020-01-01',created_at:'2020-01-01'}];
 state.reimbursements=[{id:crypto.randomUUID(),project_id:state.project.id,commitment_id:activity,debtor_member_id:mid,creditor_member_id:state.roster[1].member_id,debtor_name:'Beta',creditor_name:state.roster[1].display_name,activity_title:'Train tickets for the group',status:'open',amount_minor:15000,currency:'GBP',is_debtor:true,is_creditor:false,needs_review:false}];
}
async function capture(page,name){await page.evaluate(()=>document.fonts.ready);await page.waitForTimeout(180);await fits(page,name);for(const p of await page.locator('[id^="headlessui-dialog-panel"]').all())assert(await p.evaluate(el=>el.scrollWidth<=el.clientWidth),'Dialog fits');await page.screenshot({path:'/tmp/orchestrio-phase4-'+name+'.png',fullPage:true});}
try {
 for(const [width,height] of [[1280,900],[1024,768],[768,1024],[430,932],[390,844],[375,812]])await test('Budget and People viewport '+width,async({page,state})=>{
  const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});await page.setViewportSize({width,height});await login(page);await go(page,'/app/projects/'+state.project.id+'/budget');await page.getByText('Split an Activity cost to see what each person owes.',{exact:true}).waitFor();await capture(page,'budget-empty-'+width);
  populated(state);await page.reload();await page.getByText('Owes £150.00',{exact:true}).first().waitFor();await page.getByText('Is owed £150.00',{exact:true}).first().waitFor();await page.getByText('Settled',{exact:true}).first().waitFor();await capture(page,'budget-'+width);
  const summary=page.locator('summary').filter({hasText:'Beta'}).first();await summary.focus();await page.keyboard.press('Enter');await page.getByRole('button',{name:'Mark settled',exact:true}).waitFor();await page.getByText('Payment sent — awaiting confirmation',{exact:true}).first().waitFor();await capture(page,'balance-detail-'+width);assert(await summary.evaluate(el=>el.parentElement.open));
  state.balances.forEach(m=>m.remaining_minor=0);await page.reload();await page.getByText('Everyone is settled.',{exact:true}).waitFor();await capture(page,'budget-settled-'+width);
  await go(page,'/app/projects/'+state.project.id+'/people');await page.getByRole('button',{name:'Approve Riley',exact:true}).waitFor();await page.getByText('Expired · Viewer',{exact:true}).waitFor();await capture(page,'people-'+width);
  await page.getByLabel('Manage Alexandra with a very long family name',{exact:true}).click();await page.getByLabel('Role for Alexandra with a very long family name',{exact:true}).waitFor();await capture(page,'people-manage-'+width);
  state.requests=[];state.projectInvites=[];state.roster=[state.roster[0]];state.balances=[];await page.reload();await page.getByText('No pending join requests.',{exact:true}).waitFor();await page.getByText('No outstanding invitations.',{exact:true}).waitFor();await capture(page,'people-empty-invites-'+width);assert.deepEqual(errors,[]);
 });
 await test('Budget target, drilldown, settlement and history',async({page,state})=>{
  populated(state);await login(page);await go(page,'/app/projects/'+state.project.id+'/budget');await page.getByRole('button',{name:'Edit budget',exact:true}).click();let dialog=page.getByRole('dialog');await dialog.getByLabel(/Approximate total budget/).fill('1250.50');await dialog.getByRole('button',{name:'Save budget',exact:true}).click();await page.getByText('£1,250.50',{exact:true}).waitFor();assert.equal(state.calls.find(c=>c.path.endsWith('/set_project_budget')).body.p_amount,125050);
  await page.locator('summary').filter({hasText:'Beta'}).first().click();await page.getByRole('button',{name:'Mark settled',exact:true}).click();dialog=page.getByRole('dialog');await dialog.getByLabel('Amount',{exact:true}).fill('25');await dialog.getByLabel('Date',{exact:true}).fill('2026-10-24');await dialog.getByRole('button',{name:'Record settlement',exact:true}).click();await page.getByText('Settlement history',{exact:true}).click();await page.getByRole('button',{name:'Cancel settlement',exact:true}).waitFor();assert.equal(state.history[0].amount_minor,2500);assert.equal(state.calls.find(c=>c.path.endsWith('/record_item_settlement')).body.p_item,state.activities[0].id);
  await page.getByRole('button',{name:'Cancel settlement',exact:true}).click();await page.getByRole('button',{name:'Confirm cancellation',exact:true}).click();await page.getByText(/£25.00 · Cancelled/).waitFor();assert.equal(state.history[0].status,'cancelled');
  await page.getByRole('button',{name:'Edit budget',exact:true}).click();await page.getByRole('button',{name:'Clear budget',exact:true}).click();await page.getByRole('dialog',{name:'Clear budget',exact:true}).getByRole('button',{name:'Clear budget',exact:true}).click();await page.getByRole('button',{name:'Set budget',exact:true}).waitFor();assert.equal(state.financials.total_target_minor,null);
  await page.getByRole('link',{name:'Train tickets for the group',exact:true}).click();await page.waitForURL('**/*commitment='+state.activities[0].id);
 });
 await test('Membership role removal invitation and join actions',async({page,state})=>{
  populated(state);await login(page);await go(page,'/app/projects/'+state.project.id+'/people');await page.getByRole('button',{name:'Approve Riley',exact:true}).click();await page.getByText('Access approved.',{exact:true}).waitFor();await page.getByRole('button',{name:'Decline Jordan',exact:true}).click();await page.getByText('Access request declined.',{exact:true}).waitFor();assert.deepEqual(state.calls.filter(c=>c.path.endsWith('/review_project_join_request')).map(c=>c.body.p_approve),[true,false]);
  await page.getByRole('button',{name:'Copy invite link',exact:true}).click();await page.getByLabel('Join link',{exact:true}).waitFor();assert((await page.getByLabel('Join link',{exact:true}).inputValue()).endsWith('/join/'+state.linkToken));await page.getByText('Link settings',{exact:true}).click();await page.getByRole('button',{name:'Disable link',exact:true}).click();await page.getByText('Join link disabled.',{exact:true}).waitFor();assert.equal(state.linkToken,null);
  await page.getByLabel('Manage Sam',{exact:true}).click();await page.getByLabel('Role for Sam',{exact:true}).selectOption('member');await page.getByText('Role updated.',{exact:true}).waitFor();assert.equal(state.roster[2].role,'member');await page.getByRole('button',{name:'Remove Sam',exact:true}).click();await page.getByRole('dialog').getByRole('button',{name:'Remove',exact:true}).click();await page.getByText('1 former member has been removed.',{exact:true}).waitFor();
  await page.getByRole('button',{name:'Create invitation',exact:true}).click();const d=page.getByRole('dialog');await d.getByLabel('Email address').fill('new@example.test');await d.getByLabel('Role').selectOption('viewer');await d.getByRole('button',{name:'Create invitation',exact:true}).click();await page.getByText('new@example.test',{exact:true}).waitFor();assert.equal(state.projectInvites.at(-1).role,'viewer');assert.equal(state.calls.filter(c=>c.path.includes('/functions/')).length,0);
 });
 await test('Read-only membership and balances',async({page,state})=>{
  populated(state);state.role='member';state.roster[0].role='member';await login(page);await go(page,'/app/projects/'+state.project.id+'/people');await page.getByText('Alexandra with a very long family name',{exact:true}).waitFor();assert.equal(await page.locator('summary').filter({hasText:'Manage'}).count(),0);
  state.project.status='archived';state.role='organizer';await page.reload();await page.getByText('This project is archived — membership is read-only.',{exact:true}).waitFor();assert(await page.getByRole('button',{name:'Copy invite link',exact:true}).isDisabled());assert.equal(await page.getByRole('button',{name:'Create invitation',exact:true}).count(),0);
  await go(page,'/app/projects/'+state.project.id+'/budget');await page.locator('summary').filter({hasText:'Beta'}).first().click();assert.equal(await page.getByRole('button',{name:'Mark settled',exact:true}).count(),0);assert.equal(await page.getByRole('button',{name:'Edit budget',exact:true}).count(),0);
 });
 await test('Local budget and balance failures preserve other surfaces',async({page,state})=>{
  populated(state);state.failResource='v_project_financials';await login(page);await go(page,'/app/projects/'+state.project.id+'/budget');await page.getByRole('button',{name:'Try again',exact:true}).waitFor({timeout:20000});await page.getByText('Owes £150.00',{exact:true}).first().waitFor();assert(!(await page.locator('body').innerText()).includes('PRIVATE'));state.failResource=null;await page.getByRole('button',{name:'Try again',exact:true}).click();await page.getByRole('button',{name:'Edit budget',exact:true}).waitFor();
  state.failResource='v_project_member_settlements';await page.reload();await page.getByRole('button',{name:'Try again',exact:true}).waitFor({timeout:20000});await page.getByRole('heading',{name:'By category',exact:true}).waitFor();await go(page,'/app/projects/'+state.project.id+'/people');await page.getByText('Balance information is unavailable. Membership controls are still available.',{exact:true}).waitFor();await page.getByRole('button',{name:'Approve Riley',exact:true}).waitFor();
 });
 await test('Provider navigation leaves financial state unchanged',async({page,state})=>{
  populated(state);state.acknowledged=false;await login(page);await go(page,'/app/projects/'+state.project.id+'/budget');await page.locator('summary').filter({hasText:'Beta'}).first().click();await page.getByRole('link',{name:/You owe Alexandra/}).first().click();await page.waitForURL('**/*section=reimbursements*');const card=page.locator('[data-reimbursement-id="'+state.reimbursements[0].id+'"]');await card.getByRole('heading',{name:/payment preferences/}).waitFor();const before=JSON.stringify(state.financials);
  for(const label of ['Pay with Monzo','Pay with Revolut','Pay with PayPal','Open custom link: Personal link']){const link=card.getByRole('link',{name:new RegExp(label)});assert.equal(await link.getAttribute('target'),'_blank');assert((await link.getAttribute('rel')).includes('noopener'));const popup=page.waitForEvent('popup');await link.focus();await page.keyboard.press('Enter');await (await popup).close();}
  assert.equal(JSON.stringify(state.financials),before);assert.equal(state.acknowledged,false);assert.equal(state.calls.filter(c=>/acknowledge_reimbursement|record_item_settlement|confirm_reimbursement/.test(c.path)).length,0);
 });
 await test('Loading and modal focus at mobile width',async({page,state})=>{
  populated(state);state.readDelay=900;await page.setViewportSize({width:375,height:812});await login(page);await go(page,'/app/projects/'+state.project.id+'/budget');await page.getByRole('status',{name:'Loading budget',exact:true}).waitFor();const edit=page.getByRole('button',{name:'Edit budget',exact:true});await edit.focus();await page.keyboard.press('Enter');await page.getByLabel(/Approximate total budget/).waitFor();await capture(page,'budget-dialog-375');await page.keyboard.press('Escape');await page.waitForTimeout(250);assert(await edit.evaluate(el=>el===document.activeElement));
  await go(page,'/app/projects/'+state.project.id+'/people');await page.getByRole('button',{name:'Create invitation',exact:true}).focus();await page.keyboard.press('Enter');await page.getByLabel('Email address').waitFor();await capture(page,'invite-dialog-375');await page.keyboard.press('Escape');await page.waitForTimeout(250);assert(await page.getByRole('button',{name:'Create invitation',exact:true}).evaluate(el=>el===document.activeElement));
 });
 console.log(passed+' Budget/People browser scenarios passed.');
}finally{await browser.close();}
