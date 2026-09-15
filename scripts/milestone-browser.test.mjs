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
  const page = await context.newPage();
  page.setDefaultTimeout(10000);
  const project = {id:'00000000-0000-4000-8000-000000000010',name:'Beta Trip',status:'active',profile:'group_trip',module_visibility:{},currency:'GBP',timezone:'UTC',starts_on:null,ends_on:null,description:null,deleted_at:null};
  const state = { project, role:'organizer', unread:true, user: structuredClone(user), calls: [], signupSession: false, error: null, nonceRequired: false };
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
    if (url.pathname.endsWith('/projects')) {
      if(req.method()==='PATCH') {
        assert.equal(url.searchParams.get('status'), `eq.${state.project.status}`);
        Object.assign(state.project,body);
      }
      return reply(state.project);
    }
    if(url.pathname.endsWith('/commitments')) return reply([{id:'00000000-0000-4000-8000-000000000040',project_id:project.id,title:'Book restaurant',kind:'other',activity_type:'booking',status:'researching',cost_split_mode:'none',recurrence_rule:null,cost_minor:0,currency:'GBP',deleted_at:null}]);
    if(url.pathname.endsWith('/project_members')) return reply([{id:'00000000-0000-4000-8000-000000000020',project_id:project.id,user_id:user.id,role:state.role,status:'active',deleted_at:null}]);
    if(url.pathname.endsWith('/v_my_projects')) return reply([{...state.project,project_id:project.id,progress_pct:0,attention_count:0}]);
    if(url.pathname.endsWith('/v_my_activity_notifications')) return route.fulfill({status:200,contentType:'application/json',headers:{'content-range':state.unread?'0-0/1':'*/0','access-control-expose-headers':'content-range'},body:JSON.stringify(state.unread?[{id:'00000000-0000-4000-8000-000000000030',project_id:project.id,commitment_id:'00000000-0000-4000-8000-000000000040',activity_title:'Book restaurant',project_name:project.name,created_at:new Date().toISOString(),read_at:null}]:[])});
    if(url.pathname.endsWith('/mark_notification_read')) {state.unread=false;return reply(body.p_notification);}
    if (url.pathname.endsWith('/get_invitation')) return reply([{ project_name: 'Shared test project', inviter_name: 'Inviter', role:'member', status:'pending' }]);
    if (url.pathname.endsWith('/accept_invitation')) return reply('00000000-0000-4000-8000-000000000003');
    if (url.pathname.endsWith('/users')) return reply({ id:state.user.id, email:state.user.email, display_name:'Beta', timezone:'Europe/London', default_currency:'GBP' });
    return reply([]);
  });
  return { context, page, state };
}
async function test(name, fn, options) {
  if (process.env.AUTH_TEST_FILTER && !name.includes(process.env.AUTH_TEST_FILTER)) return;
  const f = await fixture(options);
  try { await fn(f); passed++; console.log(`PASS: ${name}`); }
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
    await test(`complete, cancel, past, reopen and notification at ${width}px`,async({page,state})=>{
      await page.setViewportSize({width,height:900});
      await login(page);
      const base='/app/projects/'+state.project.id;
      await go(page,base+'/settings');
      await page.locator('#app').getByRole('button',{name:'Complete project',exact:true}).click();
      const dialog=page.getByRole('dialog');
      await dialog.getByText('Complete this project?',{exact:true}).waitFor();
      await fits(page,'confirmation');
      assert.equal(state.calls.filter(c=>c.method==='PATCH').length,0);
      await dialog.getByRole('button',{name:'Cancel',exact:true}).click();
      assert.equal(state.project.status,'active');
      await page.locator('#app').getByRole('button',{name:'Complete project',exact:true}).click();
      await dialog.getByRole('button',{name:'Complete project',exact:true}).click();
      await dialog.waitFor({state:'hidden'});
      await page.locator('#app').getByRole('button',{name:'Reopen project',exact:true}).waitFor();
      assert.equal(state.project.status,'completed');
      assert.equal(state.project.ends_on,null);
      await go(page,'/app/projects');
      await page.getByText('No active projects yet.',{exact:true}).waitFor();
      await page.getByRole('button',{name:'Past',exact:true}).click();
      await page.getByRole('link').filter({hasText:'Beta Trip'}).waitFor();
      await fits(page,'past cards');
      await page.getByRole('link').filter({hasText:'Beta Trip'}).click();
      await go(page,base+'/settings');
      await page.locator('#app').getByRole('button',{name:'Reopen project',exact:true}).click();
      await dialog.getByRole('button',{name:'Reopen project',exact:true}).click();
      await dialog.waitFor({state:'hidden'});
      await page.locator('#app').getByRole('button',{name:'Complete project',exact:true}).waitFor();
      await fits(page,'complete CTA');
      await go(page,'/app/projects');
      await page.getByRole('button',{name:'Active',exact:true}).click();
      await page.getByRole('link').filter({hasText:'Beta Trip'}).waitFor();
      await fits(page,'active tabs');
      const bell=page.getByRole('button',{name:'Notifications',exact:true,includeHidden:true});
      assert((await bell.textContent()).includes('1'));
      await bell.click();
      await dialog.getByRole('button').filter({hasText:'Book restaurant'}).waitFor();
      await fits(page,'notification');
      await page.waitForTimeout(400); // Let the modal enter animation finish for visual verification.
      await page.screenshot({path:`/tmp/orchestrio-notifications-${width}.png`});
      await dialog.getByRole('button').filter({hasText:'Book restaurant'}).click();
      await page.waitForURL(baseURL=>baseURL.pathname===base+'/activities' && baseURL.searchParams.get('commitment')==='00000000-0000-4000-8000-000000000040');
      await page.getByRole('dialog').getByText('Book restaurant',{exact:true}).first().waitFor();
      assert.equal(state.unread,false);
      assert(!(await bell.textContent()).includes('1'));
      await fits(page,'notification destination');
    });
  }
  for(const role of ['member','viewer']) await test(`${role} cannot see completion or reopen actions`,async({page,state})=>{
    state.role=role;
    await login(page);
    await go(page,'/app/projects/'+state.project.id+'/settings');
    await page.getByText('Only an organizer can change project settings.').waitFor();
    assert.equal(await page.locator('#app').getByRole('button',{name:'Complete project',exact:true}).count(),0);
    assert.equal(await page.locator('#app').getByRole('button',{name:'Reopen project',exact:true}).count(),0);
  });
} finally {await browser.close();}
console.log(`${passed} milestone browser scenarios passed; backend mocked.`);
