import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'vite';
import { paginateList } from '../src/lib/pagination.ts';
const result = await build({ configFile:false, logLevel:'silent', build:{write:false,minify:false,lib:{entry:'src/lib/projectProfiles.ts',formats:['es']}} });
const { PROJECT_PROFILES, CATEGORY_SUGGESTIONS, categorySuggestions } = await import(`data:text/javascript;base64,${Buffer.from((Array.isArray(result)?result[0]:result).output.find(i=>i.type==='chunk').code).toString('base64')}`);
test('all profiles offer small optional registries; Blank is empty; existing names excluded',()=>{
 assert.equal(PROJECT_PROFILES.length,7);
 for(const profile of PROJECT_PROFILES){
  const suggestions=categorySuggestions(profile.value,[]);
  assert.deepEqual(suggestions,CATEGORY_SUGGESTIONS[profile.value]);
  assert(suggestions.length<=5);
  if(profile.value==='blank')assert.deepEqual(suggestions,[]);
  else {
   assert(suggestions.length>=4);
   assert.deepEqual(categorySuggestions(profile.value,suggestions.map(n=>` ${n.toUpperCase()} `)),[]);
  }
 }
 assert.deepEqual(categorySuggestions('group_trip',[]),['Accommodation','Transport','Food & Dining','Activities']);
});
for(const size of [5,10])test(`pagination boundaries and removal preserve ordering (${size})`,()=>{
 for(const n of [0,1,5,6,10,11,21,31]){
  const rows=Array.from({length:n},(_,i)=>i);
  const seen=[];
  for(let page=1;page<=Math.max(1,Math.ceil(n/size));page++){
   const current=paginateList(rows,page,size);seen.push(...current.items);
   assert.equal(current.canGoPrevious,page>1);
   assert.equal(current.canGoNext,page<Math.ceil(n/size));
  }
  assert.deepEqual(seen,rows);
  const after=paginateList(rows.slice(0,Math.max(0,n-1)),99,size);
  assert.equal(after.page,Math.max(1,Math.ceil((n-1)/size)));
  if(n>1)assert(after.items.length>0);
 }
});

test('Dashboard fetch is bounded, preserves server order and recovers an invalid final offset',async()=>{
 const path=await import('node:path');
 const built=await build({configFile:false,logLevel:'silent',plugins:[{name:'attention-test-client',enforce:'pre',resolveId(id){if(id==='@/lib/supabase')return '\0attention-client';},load(id){if(id==='\0attention-client')return 'export const supabase = { rpc: (...args) => globalThis.__attentionRpc(...args) };';}}],resolve:{alias:{'@/lib/errors':path.resolve('src/lib/errors.ts')}},build:{write:false,minify:false,lib:{entry:'src/services/derived.ts',formats:['es']}}});
 const api=await import(`data:text/javascript;base64,${Buffer.from((Array.isArray(built)?built[0]:built).output.find(i=>i.type==='chunk').code).toString('base64')}`);
 const calls=[],items=[{code:'second-in-alphabet'},{code:'first-in-alphabet'}];
 globalThis.__attentionRpc=(name,args,options)=>({range:async(start,end)=>{
  calls.push({name,options,start,end});
  return start>=10?{error:{code:'PGRST103',message:'Requested range not satisfiable'},data:null,count:2}:{error:null,data:items,count:2};
 }});
 try {
  assert.deepEqual(await api.getMyAttention(3),{items,total:2,page:1});
  assert.deepEqual(calls.map(c=>[c.start,c.end]),[[10,14],[0,4]]);
  assert(calls.every(c=>c.name==='get_my_attention'&&c.options.count==='exact'));
  globalThis.__attentionRpc=()=>({range:async()=>({error:{code:'42501',message:'Forbidden'},data:null,count:null})});
  await assert.rejects(()=>api.getMyAttention(1));
 }finally{delete globalThis.__attentionRpc;}
});
