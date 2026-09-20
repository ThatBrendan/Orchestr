/** Actual develop HTTP + Chrome. Reuses three synthetic accounts; no email or auth-user creation.
 * SHARE_FIXTURE_FILE contains private credentials. One isolated project is soft-deleted in cleanup.
 */
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { createClient } from '@supabase/supabase-js';
const target='msfkczsoutbeyhjvegnw', origin=process.env.AUTH_TEST_ORIGIN || 'http://localhost:5173';
assert(['localhost','127.0.0.1'].includes(new URL(origin).hostname));
assert.equal(fs.readFileSync('supabase/.temp/project-ref','utf8').trim(),target);
const env=Object.fromEntries(fs.readFileSync('.env.local','utf8').split('\n').filter(l=>l.includes('=')&&!l.startsWith('#')).map(l=>{const i=l.indexOf('=');return [l.slice(0,i),l.slice(i+1).replace(/^['"]|['"]$/g,'')];}));
assert.equal(env.VITE_SUPABASE_URL,`https://${target}.supabase.co`);
assert(process.env.SHARE_FIXTURE_FILE,'SHARE_FIXTURE_FILE required');
const users=JSON.parse(fs.readFileSync(process.env.SHARE_FIXTURE_FILE,'utf8')).users.slice(0,3);
assert.equal(users.length,3);assert(users.every(u=>u.id&&u.email.endsWith('@example.test')&&u.password));
const clients=users.map(()=>createClient(env.VITE_SUPABASE_URL,env.VITE_SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}}));
for(let i=0;i<3;i++)assert.ifError((await clients[i].auth.signInWithPassword({email:users[i].email,password:users[i].password})).error);
const browser=await chromium.launch({headless:true,channel:'chrome'});
let project,activity;
const report={target,project:null,activity:null,checks:[],cleanup:false};
const reportPath=process.env.SHARE_RESULT_FILE || '/tmp/orchestrio-share-live-result.json';
const projectName='Share envelope smoke '+new Date().toISOString(), title='Private share smoke Activity';
function save(){fs.writeFileSync(reportPath,JSON.stringify(report,null,2),{mode:0o600});}
function pass(s){report.checks.push(s);console.log('PASS live share: '+s);save();}
async function rpc(client,name,args){const r=await client.rpc(name,args);assert.ifError(r.error);return r.data;}
async function login(page,user){await page.getByLabel('Email',{exact:true}).fill(user.email);await page.getByLabel(/^Password/).fill(user.password);await page.getByRole('button',{name:'Log in',exact:true}).click();}
async function pageFor(user,signIn=true){const ctx=await browser.newContext({permissions:['clipboard-read','clipboard-write']});const page=await ctx.newPage();page.setDefaultTimeout(20000);page.on('request',r=>{const u=new URL(r.url());if(u.hostname.endsWith('.supabase.co'))assert.equal(u.hostname,target+'.supabase.co');});if(signIn){await page.goto(origin+'/login');await login(page,user);await page.waitForURL(origin+'/app');}return page;}
const canonical=()=>`${origin}/app/projects/${project}/areas?commitment=${activity}`;
async function open(page){await page.goto(canonical());await page.getByRole('heading',{name:title,exact:true}).waitFor();}
async function share(page){await page.getByRole('button',{name:'Share',exact:true}).click();await page.getByRole('heading',{name:'Share activity',exact:true}).waitFor();}
async function copy(page){await page.bringToFront();await page.getByRole('button',{name:'Copy link',exact:true}).click();await page.getByText('Link copied',{exact:true}).waitFor();const value=await page.evaluate(()=>navigator.clipboard.readText());assert(/^\/s\/[a-f0-9]{64}$/.test(new URL(value).pathname));return value;}
async function unavailable(page){await page.getByText("This shared item isn't available to your account.",{exact:true}).waitFor();assert(!(await page.textContent('body')).includes(title));assert(!(await page.textContent('body')).includes(projectName));}
async function rows(client,table){const r=await client.from(table).select('*').eq('project_id',project).order('id');assert.ifError(r.error);return r.data;}
try {
 project=await rpc(clients[0],'create_project',{p_name:projectName,p_timezone:'UTC',p_currency:'GBP',p_starts_on:new Date().toISOString().slice(0,10),p_profile:'team_project'});report.project=project;save();
 // Use existing direct-invitation domain RPCs; no email sender/Edge Function is invoked.
 await rpc(clients[0],'create_invitation',{p_project_id:project,p_email:users[1].email,p_role:'member'});
 const invitations=await rpc(clients[1],'list_my_invitations');const invitation=invitations.find(i=>i.project_id===project);assert(invitation);
 await rpc(clients[1],'accept_invitation',{p_token:invitation.token});
 const cat=await clients[0].from('project_areas').insert({project_id:project,title:'Private smoke category'}).select().single();assert.ifError(cat.error);
 const created=await rpc(clients[0],'create_activity_in_category',{p_project:project,p_category:cat.data.id,p_fields:{title,kind:'other',activity_type:'task',notes:'Private smoke notes'},p_split:null});activity=created.id;report.activity=activity;save();
 const beforeActivity=await rows(clients[0],'commitments'),beforeMembers=await rows(clients[0],'project_members');
 const owner=await pageFor(users[0]);await open(owner);await share(owner);await owner.getByRole('button',{name:'Create link',exact:true}).click();await owner.getByLabel('Share link',{exact:true}).waitFor();
 const linkA=await copy(owner),pathA=new URL(linkA).pathname;pass('Organizer creates and copies an Activity share link through normal Activity UI');
 await owner.getByRole('dialog',{name:'Share activity',exact:true}).getByRole('button',{name:'Close dialog',exact:true}).click();
 await owner.getByRole('dialog',{name:title,exact:true}).getByRole('button',{name:'Close',exact:true}).click();
 await open(owner);await share(owner);assert(await copy(owner)===linkA,'Reopening must recover unchanged link');pass('Close/reopen Activity recovers the same current URL');
 for(const width of [375,430,768,1280]){await owner.setViewportSize({width,height:950});assert(await owner.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));for(const d of await owner.locator('[id^=headlessui-dialog-panel]').all())assert(await d.evaluate(el=>el.scrollWidth<=el.clientWidth));await owner.getByRole('button',{name:'Regenerate link',exact:true}).click();await owner.getByRole('heading',{name:'Regenerate link?',exact:true}).waitFor();for(const d of await owner.getByRole('dialog').all())assert(await d.evaluate(el=>el.scrollWidth<=el.clientWidth));await owner.getByRole('button',{name:'Cancel',exact:true}).last().click();}
 pass('Share controls and confirmation fit 375/430/768/1280 px');
 const member=await pageFor(users[1],false);await member.goto(origin+pathA);await member.getByText('Sign in to open this shared item.',{exact:true}).waitFor();assert(!(await member.textContent('body')).includes(title));
 await member.getByRole('link',{name:'Log in',exact:true}).click();await login(member,users[1]);await member.waitForURL(canonical());await member.getByRole('heading',{name:title,exact:true}).waitFor();pass('Logged-out Member signs in, resumes share route, opens canonical Activity detail');
 const outsider=await pageFor(users[2]);await outsider.goto(origin+pathA);await unavailable(outsider);
 for(const table of ['projects','commitments','project_areas','project_members']){const r=await clients[2].from(table).select('id').eq(table==='projects'?'id':'project_id',project);assert.ifError(r.error);assert.equal(r.data.length,0);}
 for(const width of [375,430,768,1280]){await outsider.setViewportSize({width,height:900});assert(await outsider.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));}
 pass('Nonmember receives generic unavailable; no project, Activity, Category or People data');
 await owner.getByRole('button',{name:'Regenerate link',exact:true}).click();await owner.getByRole('button',{name:'Regenerate',exact:true}).click();await owner.getByText('Link ready to copy.',{exact:true}).waitFor();const linkB=await copy(owner),pathB=new URL(linkB).pathname;assert(linkA!==linkB,'Regeneration changes URL');
 await member.goto(origin+pathA);await unavailable(member);await member.goto(origin+pathB);await member.waitForURL(canonical());await member.getByRole('heading',{name:title,exact:true}).waitFor();
 await owner.getByRole('dialog',{name:'Share activity',exact:true}).getByRole('button',{name:'Close dialog',exact:true}).click();await share(owner);assert(await copy(owner)===linkB,'New URL must remain recoverable');pass('Regeneration invalidates A; B routes correctly and remains recoverable');
 await owner.getByRole('button',{name:'Disable link',exact:true}).click();await owner.getByText('Link disabled.',{exact:true}).waitFor();assert.equal(await owner.getByRole('button',{name:'Copy link',exact:true}).count(),0);
 await member.goto(origin+pathB);await unavailable(member);await open(member);
 assert.deepEqual(await rows(clients[0],'commitments'),beforeActivity);assert.deepEqual(await rows(clients[0],'project_members'),beforeMembers);
 pass('Disable invalidates B without changing Activity, memberships or normal Member access');
} catch(error){throw new Error(String(error.message).replace(/[a-f0-9]{64}/g,'[redacted-token]'));}
finally {
 try {
  if(project){if(activity)await rpc(clients[0],'disable_resource_share_link',{p_resource_type:'activity',p_resource_id:activity});await rpc(clients[0],'soft_delete_project',{p_project:project});const r=await clients[0].from('projects').select('id').eq('id',project).is('deleted_at',null);assert.ifError(r.error);assert.equal(r.data.length,0);report.cleanup=true;console.log('Synthetic share project soft-deleted: '+project);}
 } finally {save();await browser.close();for(const c of clients)await c.auth.signOut({scope:'local'});}
}
