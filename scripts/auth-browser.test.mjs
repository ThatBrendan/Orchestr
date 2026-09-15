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
  const state = { user: structuredClone(user), calls: [], signupSession: false, error: null, nonceRequired: false };
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
async function signup(page, path='/signup') {
  await page.goto(origin+path);
  await page.getByLabel('Email', {exact:true}).fill(user.email);
  await page.getByLabel(/^Password/).fill('password123');
  await page.getByLabel('Confirm password', {exact:true}).fill('password123');
  await page.getByRole('button', {name:'Create account',exact:true}).click();
}
async function login(page) {
  await page.goto(origin+'/login');
  await page.getByLabel('Email', {exact:true}).fill(user.email);
  await page.getByLabel(/^Password/).fill('password123');
  await page.getByRole('button',{name:'Log in',exact:true}).click();
  await page.waitForURL(origin+'/app');
}
async function recover(page) {
  await page.goto(origin+'/forgot-password');
  await page.getByLabel('Email',{exact:true}).fill(user.email);
  await page.getByRole('button',{name:'Send reset link'}).click();
  await page.getByRole('status').filter({hasText:'If an account exists'}).waitFor();
  await page.goto(origin+'/auth/callback?mode=recovery&code=mock-code');
  await page.waitForURL(origin+'/reset-password');
  await page.getByLabel(/^New password/).waitFor();
}
try {
  await test('signup without session, check email, resend, rate limit, protected route', async ({page,state}) => {
    await signup(page, '/signup?redirect=%2Finvite%2Fmock-token');
    await page.getByRole('heading',{name:'Check your email'}).waitFor();
    assert(new URL(page.url()).pathname === '/signup');
    for (const width of [320,375,390,430,768,1280]) {
      await page.setViewportSize({width,height:900});
      assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth), `Check email at ${width}`);
    }
    await page.getByRole('button',{name:'Resend confirmation email'}).click();
    await page.getByRole('status').filter({hasText:'Confirmation email sent.'}).waitFor();
    const signupCall = state.calls.find(c=>c.path.endsWith('/signup'));
    const resendCall = state.calls.find(c=>c.path.endsWith('/resend'));
    assert.equal(resendCall.body.type, 'signup');
    assert.equal(signupCall.query.redirect_to, resendCall.query.redirect_to);
    assert.equal(new URL(signupCall.query.redirect_to).searchParams.get('redirect'), '/invite/mock-token');
    state.error = {endpoint:'resend',code:'over_email_send_rate_limit',status:429};
    await page.getByRole('button',{name:'Resend confirmation email'}).click();
    await page.getByRole('status').filter({hasText:'Too many attempts'}).waitFor();
    await page.goto(origin+'/app');
    await page.waitForURL(/\/login/);
  });
  await test('confirmation returned to homepage hands off to callback and dashboard', async ({page}) => {
    await signup(page);
    await page.getByRole('heading',{name:'Check your email'}).waitFor();
    await page.goto(origin+'/?code=mock-code');
    await page.waitForURL(origin+'/app');
    await page.getByRole('heading').filter({hasText:'Beta'}).waitFor();
  });
  for (const [name, redirect, destination] of [
    ['default dashboard', '', '/app'],
    ['safe internal destination', '/app/settings', '/app/settings'],
    ['external destination rejected', 'https://evil.example', '/app'],
    ['homepage destination rejected', '/', '/app'],
  ]) {
    await test(`confirmation callback: ${name}`, async ({page}) => {
      await signup(page);
      await page.getByRole('heading',{name:'Check your email'}).waitFor();
      await page.goto(origin+'/auth/callback?mode=signup&code=mock-code&redirect='+encodeURIComponent(redirect));
      await page.waitForURL(origin+destination);
    });
  }
  await test('already-authenticated callback keeps safe destination without a new link', async ({page}) => {
    await login(page);
    await page.goto(origin+'/auth/callback?redirect=%2Fapp%2Fsettings');
    await page.waitForURL(origin+'/app/settings');
  });
  await test('homepage confirmation preserves the explicit invite destination', async ({page}) => {
    await signup(page, '/signup?redirect=%2Finvite%2Fmock-token');
    await page.getByRole('heading',{name:'Check your email'}).waitFor();
    await page.goto(origin+'/?code=mock-code&redirect=%2Finvite%2Fmock-token');
    await page.waitForURL(origin+'/invite/mock-token');
    await page.getByText('Shared test project',{exact:true}).waitFor();
  });
  await test('homepage recovery remains separate from dashboard', async ({page}) => {
    await page.goto(origin+'/forgot-password');
    await page.getByLabel('Email',{exact:true}).fill(user.email);
    await page.getByRole('button',{name:'Send reset link'}).click();
    await page.getByRole('status').filter({hasText:'If an account exists'}).waitFor();
    await page.goto(origin+'/?code=mock-recovery-code');
    await page.waitForURL(origin+'/reset-password');
    await page.getByLabel(/^New password/).waitFor();
  });
  await test('ordinary authenticated homepage remains public without replaying confirmation', async ({page}) => {
    await signup(page);
    await page.getByRole('heading',{name:'Check your email'}).waitFor();
    await page.goto(origin+'/?code=mock-code');
    await page.waitForURL(origin+'/app');
    await page.evaluate(async () => { await document.querySelector('#app').__vue_app__.config.globalProperties.$router.push('/'); });
    await page.getByRole('link',{name:'Open Orchestrio',exact:true}).first().waitFor();
    assert.equal(new URL(page.url()).pathname,'/');
    await page.reload();
    await page.getByRole('link',{name:'Open Orchestrio',exact:true}).first().waitFor();
    assert.equal(new URL(page.url()).pathname,'/');
  });
  await test('callback waits for delayed PKCE session resolution', async ({page,state}) => {
    state.tokenDelay = 700;
    await signup(page);
    await page.getByRole('heading',{name:'Check your email'}).waitFor();
    await page.goto(origin+'/auth/callback?mode=signup&code=mock-code');
    await page.waitForURL(origin+'/app');
    await page.getByRole('heading').filter({hasText:'Beta'}).waitFor();
  });
  await test('failed homepage confirmation never accepts an unrelated existing session', async ({page}) => {
    await login(page);
    await page.goto(origin+'/?code=missing-verifier');
    await page.waitForURL(origin+'/auth/callback');
    await page.getByRole('alert').filter({hasText:'invalid or expired'}).waitFor();
  });
  await test('confirmed signup callback preserves invitation and acceptance RPC', async ({page,state}) => {
    await signup(page, '/signup?redirect=%2Finvite%2Fmock-token');
    await page.getByRole('heading',{name:'Check your email'}).waitFor();
    await page.goto(origin+'/auth/callback?mode=signup&redirect=%2Finvite%2Fmock-token&code=mock-code');
    await page.waitForURL(origin+'/invite/mock-token');
    await page.getByText('Shared test project',{exact:true}).waitFor();
    await page.getByRole('button',{name:'Accept invitation',exact:true}).click();
    await page.waitForFunction(() => document.body.textContent.includes("You've joined the project."));
    assert(state.calls.some(c=>c.path.endsWith('/accept_invitation') && c.body.p_token==='mock-token'));
  });
  await test('existing login and immediate-session signup still work', async ({page,state}) => {
    state.signupSession = true;
    await signup(page);
    await page.waitForURL(origin+'/app');
  });
  await test('forgot password generic response for missing user and sanitized errors', async ({page,state}) => {
    state.error = {endpoint:'recover',code:'user_not_found'};
    await page.goto(origin+'/login');
    await page.getByRole('link',{name:'Forgot password?'}).click();
    await page.waitForURL(origin+'/forgot-password');
    await page.getByLabel('Email').fill('unknown@example.test');
    await page.getByRole('button',{name:'Send reset link'}).click();
    await page.getByRole('status').filter({hasText:'If an account exists'}).waitFor();
    assert(!(await page.textContent('body')).includes('SECRET'));
  });
  await test('PKCE PASSWORD_RECOVERY, refresh, route lock, mismatch, update and logout', async ({page,state}) => {
    await recover(page);
    await page.reload();
    await page.getByLabel(/^New password/).waitFor();
    // Navigate inside the SPA: protected routes cannot bypass recovery.
    await page.evaluate(async () => { await document.querySelector('#app').__vue_app__.config.globalProperties.$router.push('/app'); });
    assert.equal(new URL(page.url()).pathname, '/reset-password');
    for (const width of [320,375,390,430,768,1280]) {
      await page.setViewportSize({width,height:900});
      const layout=await page.evaluate(()=>({overflow:document.documentElement.scrollWidth>innerWidth,sizes:[...document.querySelectorAll('input')].map(el=>parseFloat(getComputedStyle(el).fontSize))}));
      assert(!layout.overflow && layout.sizes.every(size=>size>=16), `Reset form at ${width}`);
    }
    await page.setViewportSize({width:320,height:900});
    await page.screenshot({animations:'disabled',path:'/tmp/orchestrio-reset-mobile.png'});
    await page.getByLabel(/^New password/).fill('newpassword123');
    await page.getByLabel('Confirm new password',{exact:true}).fill('different123');
    await page.getByRole('button',{name:'Update password',exact:true}).click();
    await page.getByRole('alert').filter({hasText:'Passwords do not match.'}).waitFor();
    assert(!state.calls.some(c=>c.path.endsWith('/user') && c.method==='PUT'));
    await page.getByLabel('Confirm new password',{exact:true}).fill('newpassword123');
    await page.getByRole('button',{name:'Update password',exact:true}).click();
    await page.getByRole('status').filter({hasText:'Password updated successfully.'}).waitFor();
    await page.getByRole('button',{name:'Continue to log in'}).click();
    await page.waitForURL(origin+'/login');
    assert(state.calls.some(c=>c.path.endsWith('/logout')));
  });
  await test('invalid reset link, bare reset route, failed callback with existing session', async ({page,state}) => {
    await page.goto(origin+'/reset-password');
    await page.getByRole('alert').filter({hasText:'invalid or expired'}).waitFor();
    await login(page);
    // Missing PKCE verifier must not let the existing user's session validate another link.
    await page.goto(origin+'/auth/callback?mode=recovery&code=missing-verifier');
    await page.getByRole('alert').filter({hasText:'invalid or expired'}).waitFor();
    assert.equal(await page.getByLabel(/^New password/).count(),0);
    state.error = {endpoint:'token',code:'otp_expired'};
    await page.goto(origin+'/auth/callback?mode=recovery#error=access_denied&error_code=otp_expired&error_description=SECRET');
    await page.getByRole('alert').filter({hasText:'invalid or expired'}).waitFor();
    assert(!(await page.textContent('body')).includes('SECRET'));
  });
  await test('Settings change password and backend-required email reauthentication', async ({page,state}) => {
    await login(page);
    await page.goto(origin+'/app/settings');
    for (const width of [320,375,390,430,768,1280]) {
      await page.setViewportSize({width,height:900});
      assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth), `Settings at ${width}`);
    }
    await page.getByLabel(/^New password/).fill('changedpassword123');
    await page.getByLabel('Confirm new password',{exact:true}).fill('changedpassword123');
    state.nonceRequired = true;
    await page.getByRole('button',{name:'Change password',exact:true}).click();
    await page.getByRole('button',{name:'Send verification code'}).click();
    await page.getByRole('status').filter({hasText:'Check your email'}).waitFor();
    await page.getByLabel('Email verification code').fill('123456');
    await page.getByRole('button',{name:'Change password',exact:true}).click();
    await page.getByRole('status').filter({hasText:'Password updated successfully.'}).waitFor();
    assert(state.calls.some(c=>c.path.endsWith('/reauthenticate')));
    assert(state.calls.some(c=>c.body?.nonce==='123456'));
  });
  await test('cross-user auth event clears query cache and project context', async ({page,state}) => {
    await login(page);
    state.user = {...state.user, id:'00000000-0000-4000-8000-000000000002',email:'other@example.test'};
    const result = await page.evaluate(async () => {
      const app=document.querySelector('#app').__vue_app__;
      const queryClient=app._context.provides.VUE_QUERY_CLIENT;
      const pinia=app.config.globalProperties.$pinia;
      // Use the exact SDK module loaded by Vite, including any HMR timestamp.
      const sdkUrl=performance.getEntriesByType('resource').find(entry=>new URL(entry.name).pathname==='/src/lib/supabase.ts').name;
      const {supabase}=await import(sdkUrl);
      queryClient.setQueryData(['private-user-a'],{secret:'User A'});
      const ctx=pinia._s.get('project-context');
      ctx.context={projectId:'private-a'};
      const changed = new Promise(resolve => {
        const {data} = supabase.auth.onAuthStateChange((event,session) => {
          if(event==='SIGNED_IN' && session?.user.email==='other@example.test') { data.subscription.unsubscribe(); resolve(); }
        });
      });
      await supabase.auth.signInWithPassword({email:'other@example.test',password:'mock-password'});
      await changed;
      return {cache:queryClient.getQueryData(['private-user-a']),context:ctx.context};
    });
    assert.equal(result.cache,undefined);
    assert.equal(result.context,null);
  });
  await test('unconfirmed login remains blocked and can resend', async ({page,state}) => {
    state.error={endpoint:'token',code:'email_not_confirmed'};
    await page.goto(origin+'/login?redirect=%2Finvite%2Fmock-token');
    await page.getByLabel('Email',{exact:true}).fill(user.email);
    await page.getByLabel('Password',{exact:true}).fill('password123');
    await page.getByRole('button',{name:'Log in',exact:true}).click();
    await page.getByText('Confirm your email address before logging in.',{exact:true}).waitFor();
    assert.equal(new URL(page.url()).pathname,'/login');
    await page.getByRole('button',{name:'Resend confirmation email'}).click();
    await page.getByRole('status').filter({hasText:'Confirmation email sent.'}).waitFor();
    assert.equal(new URL(state.calls.find(c=>c.path.endsWith('/resend')).query.redirect_to).searchParams.get('redirect'),'/invite/mock-token');
  });
  await test('signup password mismatch never calls the backend', async ({page,state}) => {
    await page.goto(origin+'/signup');
    await page.getByLabel('Email',{exact:true}).fill(user.email);
    await page.getByLabel(/^Password/).fill('password123');
    await page.getByLabel('Confirm password',{exact:true}).fill('different123');
    await page.getByRole('button',{name:'Create account',exact:true}).click();
    await page.getByText('Passwords do not match.',{exact:true}).waitFor();
    assert(!state.calls.some(c=>c.path.endsWith('/signup')));
  });
  await test('touch tablet inputs retain the iOS zoom sizing protection', async ({page}) => {
    await page.setViewportSize({width:768,height:1024});
    await page.goto(origin+'/signup');
    await page.getByRole('heading').waitFor();
    assert(await page.evaluate(()=>[...document.querySelectorAll('input')].every(el=>parseFloat(getComputedStyle(el).fontSize)>=16)));
  }, {hasTouch:true});
  await test('mobile widths: all auth pages, no overflow, inputs at least 16px, noindex', async ({page}) => {
    for (const width of [320,375,390,430,768,1280]) {
      await page.setViewportSize({width,height:900});
      for (const path of ['/login','/signup','/forgot-password','/reset-password','/auth/callback']) {
        await page.goto(origin+path);
        await page.locator('h1').waitFor();
        const layout=await page.evaluate(()=>({overflow:document.documentElement.scrollWidth>innerWidth, sizes:[...document.querySelectorAll('input')].map(el=>parseFloat(getComputedStyle(el).fontSize)),robots:document.querySelector('meta[name="robots"]')?.content}));
        assert(!layout.overflow,`${path} overflows at ${width}`);
        if(width<768) assert(layout.sizes.every(size=>size>=16),`${path} input size at ${width}`);
        assert.equal(layout.robots,'noindex, nofollow');
        if(width===320 && path==='/signup') await page.screenshot({animations:'disabled',path:'/tmp/orchestrio-signup-mobile.png'});
      }
    }
  });
} finally { await browser.close(); }
console.log(`${passed} browser scenarios passed. Backend mocked; develop email E2E remains separate.`);
