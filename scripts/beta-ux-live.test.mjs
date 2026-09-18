/** Develop-only real browser walkthrough. Requires temporary synthetic accounts
 * provided in BETA_FIXTURE_FILE; never emits their credentials or sends mail. */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {chromium} from 'playwright';
import {createClient} from '@supabase/supabase-js';
const target='msfkczsoutbeyhjvegnw';
assert.equal(fs.readFileSync('supabase/.temp/project-ref','utf8').trim(),target);
assert(fs.readFileSync('.env.local','utf8').includes('https://'+target+'.supabase.co'));
const fixtureFile=process.env.BETA_FIXTURE_FILE;
assert(fixtureFile,'BETA_FIXTURE_FILE required');
const fixture=JSON.parse(fs.readFileSync(fixtureFile,'utf8'));
const origin='http://127.0.0.1:4187';
const env=Object.fromEntries(fs.readFileSync('.env.local','utf8').split('\n').filter(l=>l.includes('=')&&!l.startsWith('#')).map(l=>{const i=l.indexOf('=');return [l.slice(0,i),l.slice(i+1).replace(/^['"]|['"]$/g,'')];}));
const backend=createClient('https://'+target+'.supabase.co',env.VITE_SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const auth=await backend.auth.signInWithPassword({email:fixture.users[0].email,password:fixture.users[0].password});assert.ifError(auth.error);
const browser=await chromium.launch({headless:true,channel:'chrome'});
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'beta-live-'));
let page;
async function go(p,url){await p.waitForFunction(()=>document.querySelector('#app')?.__vue_app__?.config);await p.evaluate(url=>document.querySelector('#app').__vue_app__.config.globalProperties.$router.push(url),url);}
async function signIn(user){
 const ctx=await browser.newContext();const p=await ctx.newPage();p.setDefaultTimeout(15000);
 await p.goto(origin+'/login');await p.getByLabel('Email',{exact:true}).fill(user.email);await p.getByLabel(/^Password/).fill(user.password);await p.getByRole('button',{name:'Log in',exact:true}).click();await p.waitForURL(origin+'/app');return p;
}
async function activity(title,cost){
 await page.getByRole('button',{name:'New activity',exact:true}).click();const d=page.getByRole('dialog');
 await d.getByLabel('Title').fill(title);await d.getByLabel('Activity Type').selectOption('other');
 if(cost)await d.getByLabel(/^Cost /).fill(cost);
 await d.getByRole('button',{name:'Create activity',exact:true}).click();await page.getByRole('dialog').waitFor({state:'hidden'});
}
async function task(title,cost,viewer=false,linked=false){
 if(await page.getByText(title,{exact:true}).count())return;
 await page.getByRole('button',{name:'Add task',exact:true}).click();await page.getByLabel('Task title').fill(title);
 if(cost)await page.getByLabel('Task cost').fill(cost);
 if(viewer)await page.getByLabel('Assigned to',{exact:true}).selectOption({label:'Viewer C'});
 if(linked)await page.getByLabel('Linked activity').selectOption({label:'Book restaurant'});
 await page.getByRole('button',{name:'Add task',exact:true}).click();await page.getByText(title,{exact:true}).first().waitFor();
}
try {
 page=await signIn(fixture.users[0]);
 if(fixture.project) await go(page,'/app/projects/'+fixture.project+'/overview');
 else {
 await go(page,'/app/projects');
 await page.getByRole('button',{name:'New project',exact:true}).first().click();
 await page.getByRole('button',{name:/Blank Project/}).click();await page.getByRole('button',{name:'Continue',exact:true}).click();
 await page.getByLabel('Project name').fill('Beta UX Test');await page.getByLabel('Start date').fill(new Date().toISOString().slice(0,10));await page.getByRole('button',{name:'Create project',exact:true}).click();
 }
 await page.waitForURL('**/overview');const project=page.url().match(/projects\/([a-f0-9-]+)\//)[1];assert.match(project,/^[a-f0-9-]{36}$/);
 fixture.project=project;fs.writeFileSync(fixtureFile,JSON.stringify(fixture),{mode:0o600});
 const sql=fixture.users.slice(1).map((u,i)=>`insert into public.project_members(project_id,user_id,display_name,email,role,status) values('${project}','${u.id}','${u.name}','${u.email}','${i===0?'member':'viewer'}','active') on conflict do nothing;`).join('\n');
 const file=path.join(dir,'members.sql');fs.writeFileSync(file,'begin;\n'+sql+'\ncommit;', {mode:0o600});
 const r=spawnSync('supabase',['db','query','--linked','--project-ref',target,'--file',file],{encoding:'utf8',timeout:60000});assert.equal(r.status,0,'Create synthetic project memberships');
 await page.reload();await go(page,'/app/projects/'+project+'/activities');
 await page.getByRole('button',{name:/Book restaurant/}).first().or(page.getByText('No activities planned yet.')).first().waitFor();
 if(!await page.getByRole('button',{name:/Book restaurant/}).count()) await activity('Book restaurant','100');
 let d=page.getByRole('dialog');
 const state=await backend.from('commitments').select('status').eq('project_id',project).eq('title','Book restaurant').is('deleted_at',null).single();assert.ifError(state.error);
 if(state.data.status!=='completed'){
 await page.getByRole('button',{name:/Book restaurant/}).click();
 const existingPayments=await backend.from('payments').select('id').eq('project_id',project).eq('type','deposit').eq('status','paid');assert.ifError(existingPayments.error);
 if(!existingPayments.data.length){
 await d.getByRole('button',{name:'Add payment',exact:true}).click();await d.getByLabel('Amount',{exact:true}).fill('30');await d.getByRole('button',{name:'Add payment',exact:true}).click();
 }
 await page.waitForFunction(()=>document.body.textContent.includes('£70.00')); await d.getByRole('button',{name:'Complete',exact:true}).click();await page.getByText(/£70.00 is still outstanding/).waitFor();await page.getByRole('button',{name:'Record payment',exact:true}).click();
 await d.getByLabel('Payment type').selectOption('balance');assert.equal(await d.getByLabel('Amount',{exact:true}).inputValue(),'70');await d.getByRole('button',{name:'Add payment',exact:true}).click();await d.getByRole('button',{name:'Add payment',exact:true}).waitFor();
 await page.waitForFunction(()=>document.body.textContent.includes('£0.00'));
 await d.getByRole('button',{name:'Complete',exact:true}).click();await d.getByText('Completed',{exact:true}).waitFor();await d.getByRole('button',{name:'Close',exact:true}).click();
 }
 console.log('PASS live: project → unassigned £100 Activity → £30 deposit → completion gate → £70 balance → complete');
 if(!await page.getByRole('button',{name:/Delete regression/}).count())await activity('Delete regression');await page.getByRole('button',{name:/Delete regression/}).click();d=page.getByRole('dialog');await d.getByText('More',{exact:true}).click();await d.getByRole('button',{name:'Delete activity',exact:true}).click();await page.getByRole('button',{name:'Delete',exact:true}).click();await page.getByText('Activity deleted.',{exact:true}).waitFor();await page.getByRole('button',{name:/Delete regression/}).waitFor({state:'hidden'});await page.reload();await page.getByRole('button',{name:/Book restaurant/}).waitFor();assert.equal(await page.getByRole('button',{name:/Delete regression/}).count(),0);console.log('PASS live: soft delete remains gone after refresh');
 await task('Standalone cost task','25');await task('Shared cost task',null,false,true);await task('Viewer assigned task',null,true);await task('Unassigned task');
 const viewer=await signIn(fixture.users[2]);await go(viewer,'/app/projects/'+project+'/activities');await viewer.getByText('Viewer assigned task',{exact:true}).waitFor();
 assert.equal(await viewer.getByRole('button',{name:'New activity',exact:true}).count(),0);assert.equal(await viewer.getByRole('button',{name:'Add task',exact:true}).count(),0);
 assert(await viewer.getByRole('checkbox',{name:'Complete Unassigned task',exact:true}).isDisabled());await viewer.getByRole('checkbox',{name:'Complete Viewer assigned task',exact:true}).check();await viewer.waitForFunction(()=>document.body.textContent.includes('Done'));
 assert(await viewer.getByRole('checkbox',{name:'Complete Viewer assigned task',exact:true}).isDisabled());console.log('PASS live: assigned Viewer completes own task; editing and other completion controls denied');
 const member=await signIn(fixture.users[1]);await go(member,'/app/projects/'+project+'/activities');assert(await member.getByRole('button',{name:'New activity',exact:true}).isVisible());await member.getByRole('checkbox',{name:'Complete Unassigned task',exact:true}).check();console.log('PASS live: Member retains task permissions');
 for(const width of [375,430,768,1280]){await page.setViewportSize({width,height:900});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));}console.log('PASS live: no horizontal overflow at 375/430/768/1280');
 await go(page,'/app/projects/'+project+'/budget');await page.getByText('£125.00',{exact:true}).first().waitFor();console.log('PASS live: £100 Activity + £25 independent Task + shared Task = £125');
 fixture.passed=true;fs.writeFileSync(fixtureFile,JSON.stringify(fixture),{mode:0o600});
} catch(e){if(page)console.error((await page.textContent('body')).slice(-2500));throw e;}
finally{await backend.auth.signOut();await browser.close();fs.rmSync(dir,{recursive:true,force:true});}
