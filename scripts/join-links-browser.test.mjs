/** Real browser/UI, mocked HTTP boundary. No remote users, mail or project data created.
 * Authoritative SQL/security behavior is exercised separately by suite 33.
 */
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
const origin=process.env.AUTH_TEST_ORIGIN || 'http://localhost:5173';
assert(['localhost','127.0.0.1'].includes(new URL(origin).hostname));
const browser=await chromium.launch({headless:true,channel:'chrome'});
const project={id:'33000000-0000-4000-8000-000000000100',name:'Private Join Project',status:'active',profile:'team_project',module_visibility:{},currency:'GBP',timezone:'UTC',starts_on:null,ends_on:null,deleted_at:null};
const ownerId='33000000-0000-4000-8000-000000000001';
let activeToken=null, generation=0; const requests=[],members=new Set([ownerId]),notifications=[];
const contexts=[];
async function session(id,name) {
 const context=await browser.newContext();contexts.push(context);const page=await context.newPage();page.setDefaultTimeout(12000);
 const calls=[];let signedIn=false,signupRedirect=null;
 const user={id,email:`${name.toLowerCase()}@example.test`,aud:'authenticated',role:'authenticated',created_at:new Date().toISOString(),email_confirmed_at:new Date().toISOString(),app_metadata:{provider:'email'},user_metadata:{},identities:[]};
 const token=()=>({access_token:`e30.${Buffer.from(JSON.stringify({sub:id,exp:Math.floor(Date.now()/1000)+3600,role:'authenticated',aud:'authenticated'})).toString('base64url')}.signature`,refresh_token:'mock-refresh',expires_in:3600,token_type:'bearer',user});
 await context.route('**/*',async route=>{
  const req=route.request(),url=new URL(req.url());
  if(url.origin===origin&&!url.pathname.startsWith('/auth/v1/')&&!url.pathname.startsWith('/rest/v1/'))return route.continue();
  const body=req.postDataJSON(); calls.push(url.pathname);
  const reply=(data,status=200,headers={})=>route.fulfill({status,contentType:'application/json',headers,body:JSON.stringify(data)});
  const end=url.pathname.split('/').at(-1);
  if(url.pathname.startsWith('/auth/v1/')) {
   if(end==='signup'){signupRedirect=url.searchParams.get('redirect_to');return reply({...user,email_confirmed_at:null});}
   if(end==='token'){signedIn=true;return reply(token());}
   if(end==='user')return reply(user);
   return reply({});
  }
  const state=()=>body.p_token!==activeToken||!activeToken?{state:'unavailable'}:!signedIn?{state:'sign_in'}:members.has(id)?{state:'member',project_id:project.id}:requests.some(r=>r.user===id&&r.status==='pending')?{state:'pending'}:{state:'eligible'};
  if(end==='resolve_project_join_link')return reply(state());
  if(end==='request_project_access'){
   if(state().state==='eligible'){const r={id:crypto.randomUUID(),user:id,display_name:name,status:'pending',requested_at:new Date().toISOString()};requests.push(r);notifications.push({id:crypto.randomUUID(),recipient:ownerId,kind:'project_join_requested',join_request_id:r.id});}
   return reply(state());
  }
  if(end==='ensure_project_join_link'&&activeToken)return reply(activeToken);
  if(end==='ensure_project_join_link'||end==='regenerate_project_join_link'){activeToken=(++generation).toString(16).padStart(64,'0');return reply(activeToken);}
  if(end==='disable_project_join_link'){activeToken=null;return reply(null);}
  if(end==='get_project_join_access'){const pending=requests.filter(r=>r.status==='pending');return reply({active:!!activeToken,token:activeToken,pending_count:pending.length,requests:pending.slice(body.p_offset,body.p_offset+25)});}
  if(end==='review_project_join_request'){
   const r=requests.find(r=>r.id===body.p_request);r.status=body.p_approve?'approved':'declined';
   if(body.p_approve){members.add(r.user);notifications.push({id:crypto.randomUUID(),recipient:r.user,kind:'project_member_approved',join_request_id:r.id});}
   return reply(null);
  }
  if(end==='get_my_notification_unread_state')return reply(members.has(id)&&notifications.some(n=>n.recipient===id&&!n.read_at));
  if(end==='v_my_join_notifications'||end==='v_my_notification_inbox'){
   const rows=notifications.filter(n=>members.has(id)&&n.recipient===id&&!n.read_at).map(n=>({...n,resource_type:'project',resource_id:project.id,section:n.kind==='project_join_requested'?'people':null,title:n.kind==='project_member_approved'?"You're in":'Access requested',body:project.name,project_id:project.id,project_name:project.name,created_at:new Date().toISOString(),read_at:null}));
   return reply(rows,200,{'content-range':rows.length?`0-${rows.length-1}/${rows.length}`:'*/0','access-control-expose-headers':'content-range'});
  }
  if(end==='mark_notification_read'){const n=notifications.find(n=>n.id===body.p_notification);if(n)n.read_at=new Date().toISOString();return reply(body.p_notification);}
  if(end==='users')return reply({id,email:user.email,display_name:name,timezone:'UTC',default_currency:'GBP'});
  if(end==='projects')return reply(members.has(id)?project:null);
  if(end==='project_members')return reply(members.has(id)?{id:'33000000-0000-4000-8000-000000000020',project_id:project.id,user_id:id,role:id===ownerId?'organizer':'member',status:'active',deleted_at:null}:null);
  if(end==='v_my_projects')return reply(members.has(id)?[{...project,project_id:project.id,progress_pct:0,attention_count:0}]:[]);
  if(end==='v_my_activity_notifications')return reply([],200,{'content-range':'*/0','access-control-expose-headers':'content-range'});
  if(end==='get_invitation')return reply([{project_name:'Direct invitation project',inviter_name:'Inviter',role:'member',status:'pending'}]);
  if(end==='accept_invitation'){members.add(id);return reply(project.id);}
  return reply([]);
 });
 async function login(destination='/app'){
  await page.goto(origin+'/login?redirect='+encodeURIComponent(destination));
  await page.getByLabel('Email',{exact:true}).fill(user.email);await page.getByLabel(/^Password/).fill('password123');
  await page.getByRole('button',{name:'Log in',exact:true}).click();await page.waitForURL(origin+destination);
 }
 return {page,context,calls,login,get signupRedirect(){return signupRedirect;}};
}
async function fits(page){assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'No horizontal page overflow');for(const d of await page.getByRole('dialog').all())assert(await d.evaluate(el=>el.scrollWidth<=el.clientWidth),'No dialog overflow');}
async function settings(page){await page.goto(origin+`/app/projects/${project.id}/people`);await page.getByRole('heading',{name:'Invite link',exact:true}).waitFor();}
try{
 const owner=await session(ownerId,'Organiser');await owner.login();await settings(owner.page);
 await owner.page.getByLabel('Checking notifications',{exact:true}).waitFor({state:'hidden'});
 assert.equal(await owner.page.getByLabel('Unread notifications',{exact:true}).count(),0);
 assert.equal(await owner.page.getByLabel('Notification status unavailable',{exact:true}).count(),0);
 assert(owner.calls.some(p=>p.endsWith('/get_my_notification_unread_state')));
 await owner.page.getByRole('button',{name:'Copy invite link',exact:true}).click();
 const field=owner.page.getByLabel('Join link');await field.waitFor();
 const firstToken=activeToken;assert.equal(new URL(await field.inputValue()).pathname,'/join/'+firstToken);
 await owner.page.evaluate(()=>{Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async text=>{window.copiedJoinLink=text;}}});});
 await owner.page.getByRole('button',{name:'Copy invite link',exact:true}).click();await owner.page.getByText('Invite link copied',{exact:true}).waitFor();assert.equal(new URL(await owner.page.evaluate(()=>window.copiedJoinLink)).pathname,'/join/'+firstToken);
 await owner.page.evaluate(()=>{Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async()=>{throw Error('denied');}}});});
 await owner.page.getByRole('button',{name:'Copy invite link',exact:true}).click();await owner.page.getByText('Copy the invite link from the field below.',{exact:true}).waitFor();
 await settings(owner.page);
 assert.equal(new URL(await owner.page.getByLabel('Join link',{exact:true}).inputValue()).pathname,'/join/'+firstToken);
 const alice=await session('33000000-0000-4000-8000-000000000004','Alice');
 await alice.page.goto(origin+'/join/'+firstToken);await alice.page.getByText(/Sign in or create an account to request access/).waitFor();assert(!(await alice.page.textContent('body')).includes(project.name));assert(!alice.calls.some(p=>/\/projects$|\/commitments$|\/project_members$/.test(p)));
 await alice.page.getByRole('link',{name:'Log in',exact:true}).click();await alice.page.getByLabel('Email',{exact:true}).fill('alice@example.test');await alice.page.getByLabel(/^Password/).fill('password123');await alice.page.getByRole('button',{name:'Log in',exact:true}).click();await alice.page.waitForURL(origin+'/join/'+firstToken);
 await alice.page.getByRole('button',{name:'Request access',exact:true}).click();await alice.page.getByText('Your access request is pending approval.',{exact:true}).waitFor();await alice.page.reload();await alice.page.getByText('Your access request is pending approval.',{exact:true}).waitFor();assert.equal(requests.filter(r=>r.user.endsWith('004')).length,1);
 await settings(owner.page);await owner.page.getByRole('button',{name:'Approve Alice',exact:true}).waitFor();
 await owner.page.getByLabel('Unread notifications',{exact:true}).waitFor();
 await owner.page.getByRole('button',{name:'Notifications',exact:true}).click();
 await owner.page.getByRole('button',{name:/Access requested/}).click();
 await owner.page.waitForURL(origin+`/app/projects/${project.id}/people`);
 await owner.page.getByLabel('Unread notifications',{exact:true}).waitFor({state:'hidden'});
 assert.equal(await owner.page.getByLabel('Notification status unavailable',{exact:true}).count(),0);
 for(const width of [375,430,768,1280]){
  await owner.page.setViewportSize({width,height:1000});await alice.page.setViewportSize({width,height:900});await fits(owner.page);await fits(alice.page);

 }
 await owner.page.getByRole('button',{name:'Disable link',exact:true}).click();await owner.page.getByText('Join link disabled.',{exact:true}).waitFor();await owner.page.getByRole('button',{name:'Copy invite link',exact:true}).click();await owner.page.getByText('Invite link copied',{exact:true}).waitFor();const secondToken=activeToken;assert.notEqual(secondToken,firstToken);
 await alice.page.reload();await alice.page.getByText('This join link is no longer available.',{exact:true}).waitFor();
 await owner.page.getByRole('button',{name:'Approve Alice',exact:true}).click();await owner.page.getByText('Access approved.',{exact:true}).waitFor();assert(members.has('33000000-0000-4000-8000-000000000004'));
 await alice.page.goto(origin+'/join/'+secondToken);await alice.page.getByRole('link',{name:'Open project',exact:true}).click();await alice.page.getByRole('heading',{name:project.name,exact:true}).waitFor();assert.equal(await alice.page.getByRole('button',{name:'Open project settings'}).count(),0);
 await alice.page.getByLabel('Unread notifications',{exact:true}).waitFor();
 await alice.page.getByRole('button',{name:'Notifications',exact:true}).click();await alice.page.getByText("You're in",{exact:true}).waitFor();await alice.page.getByRole('button',{name:/You're in/}).click();
 await alice.page.waitForURL(origin+`/app/projects/${project.id}/overview`);
 await alice.page.getByLabel('Unread notifications',{exact:true}).waitFor({state:'hidden'});
 assert.equal(await alice.page.getByLabel('Notification status unavailable',{exact:true}).count(),0);
 const bob=await session('33000000-0000-4000-8000-000000000005','Bob');await bob.login('/join/'+secondToken);await bob.page.getByRole('button',{name:'Request access',exact:true}).click();await bob.page.getByText('Your access request is pending approval.',{exact:true}).waitFor();
 await settings(owner.page);await owner.page.getByRole('button',{name:'Decline Bob',exact:true}).click();await owner.page.getByText('Access request declined.',{exact:true}).waitFor();assert(!members.has('33000000-0000-4000-8000-000000000005'));
 await bob.page.getByRole('button',{name:'Check status',exact:true}).click();await bob.page.getByRole('button',{name:'Request access',exact:true}).click();await bob.page.getByText('Your access request is pending approval.',{exact:true}).waitFor();
 await settings(owner.page);await owner.page.getByRole('button',{name:'Disable link',exact:true}).click();await owner.page.getByText('Join link disabled.',{exact:true}).waitFor();await owner.page.getByRole('button',{name:'Approve Bob',exact:true}).waitFor();assert(members.has('33000000-0000-4000-8000-000000000004'));
 await bob.page.reload();await bob.page.getByText('This join link is no longer available.',{exact:true}).waitFor();
 await owner.page.getByRole('button',{name:'Copy invite link',exact:true}).click();await owner.page.getByLabel('Join link').waitFor();
 const fresh=await session('33000000-0000-4000-8000-000000000006','Fresh');await fresh.page.goto(origin+'/join/'+activeToken);await fresh.page.getByRole('link',{name:'Create account',exact:true}).click();
 await fresh.page.waitForURL('**/signup?**');
 assert(new URL(fresh.page.url()).searchParams.get('redirect')==='/join/'+activeToken);
 for(const width of [375,430,768,1280]){await fresh.page.setViewportSize({width,height:900});await fresh.page.goto(origin+'/join/'+activeToken);await fresh.page.getByRole('link',{name:'Create account',exact:true}).waitFor();await fits(fresh.page);}
 await fresh.page.getByRole('link',{name:'Create account',exact:true}).click();await fresh.page.waitForURL('**/signup?**');
 await fresh.page.getByLabel('Email',{exact:true}).fill('fresh@example.test');await fresh.page.getByLabel(/^Password/).fill('password123');await fresh.page.getByLabel('Confirm password',{exact:true}).fill('password123');await fresh.page.getByRole('button',{name:'Create account',exact:true}).click();await fresh.page.getByRole('heading',{name:'Check your email'}).waitFor();
 assert.equal(new URL(fresh.signupRedirect).searchParams.get('redirect'),'/join/'+activeToken);
 const callback=new URL(fresh.signupRedirect);callback.searchParams.set('code','mock-confirmation-code');
 await fresh.page.goto(origin+callback.pathname+callback.search);await fresh.page.waitForURL(origin+'/join/'+activeToken);await fresh.page.getByRole('button',{name:'Request access',exact:true}).waitFor();
 await fresh.page.goto(origin+'/join/not-valid');await fresh.page.getByText('This join link is no longer available.',{exact:true}).waitFor();
 console.log('PASS browser: organiser create/copy/fallback, logged-out privacy, login continuation, request/pending/refresh, approval/member navigation/notification, decline/re-request, regeneration, disable, four responsive widths. Mocked HTTP; SQL authorization is tested separately.');
}finally{await Promise.all(contexts.map(c=>c.close()));await browser.close();}
