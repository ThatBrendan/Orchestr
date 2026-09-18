/** Run existing pgTAP files on the explicitly authorized develop branch, rollback only.
 * Usage: node scripts/db-rollback-tests.mjs [test filename ...]
 * DB_TEST_MIGRATION may name an unapplied migration to test in the same transaction.
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
const target='msfkczsoutbeyhjvegnw';
if(fs.readFileSync('supabase/.temp/project-ref','utf8').trim()!==target) throw new Error('Develop link required');
function statements(sql) {
 const out=[]; let start=0,q=null,comment=null;
 for(let i=0;i<sql.length;i++){
  if(comment==='line'){if(sql[i]==='\n')comment=null;continue;}
  if(comment==='block'){if(sql.slice(i,i+2)==='*/'){comment=null;i++;}continue;}
  if(q){if(sql.startsWith(q,i)){if(q.length===1 && sql[i+1]===q){i++;continue;}i+=q.length-1;q=null;}continue;}
  if(sql.slice(i,i+2)==='--'){comment='line';i++;continue;}
  if(sql.slice(i,i+2)==='/*'){comment='block';i++;continue;}
  if(sql[i]==="'"||sql[i]==='"'){q=sql[i];continue;}
  if(sql[i]==='$'){const m=sql.slice(i).match(/^\$[a-zA-Z_0-9]*\$/);if(m){q=m[0];i+=q.length-1;continue;}}
  if(sql[i]===';'){out.push(sql.slice(start,i+1));start=i+1;}
 }
 return out;
}
const guard=`create function pg_temp.check_tap(result text) returns void language plpgsql as $guard$ begin if result like 'not ok%' or result like '# Looks like%' then raise exception '%',result; end if; end $guard$;`;
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'orchestrio-db-test-'));
const files=process.argv.slice(2).length?process.argv.slice(2):fs.readdirSync('supabase/tests').filter(f=>f.endsWith('.sql')).sort();
let failures=0;
try {
 for(const file of files){
  const source=process.env.DB_TEST_BASELINE ? spawnSync('git',['show','HEAD:supabase/tests/'+file],{encoding:'utf8'}).stdout : fs.readFileSync(path.join('supabase/tests',file),'utf8');
  const test=statements(source).map(stmt=>{
   const stripped=stmt.replace(/--[^\n]*/g,'').trim();
   if(/^(begin|rollback)\s*;$/i.test(stripped))return '';
   if(/^select \* from finish\(\);$/i.test(stripped))return 'select pg_temp.check_tap(result) from finish() result;';
   const m=stmt.match(/^(\s*(?:--[^\n]*\n\s*)*)select\s+((?:is|isnt|ok|lives_ok|throws_ok|results_eq|has_table|has_function|has_column|cmp_ok|col_type_is|has_index|has_trigger|policies_are|has_type|hasnt_table|has_view|is_empty|set_eq)\s*\([\s\S]*)\s*;\s*$/i);
   return m?m[1]+'select pg_temp.check_tap('+m[2]+');':stmt;
  }).join('\n');
  const migration=process.env.DB_TEST_MIGRATION?fs.readFileSync(process.env.DB_TEST_MIGRATION,'utf8'):'';
  const sql=path.join(dir,file);
  fs.writeFileSync(sql,'begin;\ncreate extension if not exists pgtap with schema extensions;\nset local search_path=public,extensions;\n'+migration+'\n'+guard+'\n'+test+'\nrollback;');
  const r=spawnSync('supabase',['db','query','--linked','--project-ref',target,'--file',sql],{encoding:'utf8',timeout:60000});
  if(r.status!==0){failures++;console.error('FAIL '+file+'\n'+r.stdout+'\n'+r.stderr);}
  else console.log('PASS '+file);
 }
} finally {fs.rmSync(dir,{recursive:true,force:true});}
console.log(`${files.length-failures}/${files.length} SQL files passed (all fixtures rolled back).`);
process.exitCode=failures?1:0;
