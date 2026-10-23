import assert from 'node:assert/strict';
import { build } from 'vite';
const output = await build({ configFile: false, logLevel: 'silent', build: { write: false, minify: false, lib: { entry: 'src/lib/executionCalendar.ts', formats: ['es'] } } });
const result = Array.isArray(output) ? output[0] : output;
const api = await import(`data:text/javascript;base64,${Buffer.from(result.output.find(item => item.type === 'chunk').code).toString('base64')}`);
const timed={entry_id:'activity:a',source_id:'a',activity_id:'a',project_id:'p',source_type:'activity',start_at:'2026-10-07T23:30:00Z',start_date:null,end_date:null,end_at:null,all_day:false,status:'idea',activity_type:'event'};
assert.equal(api.entryDay(timed,'Pacific/Kiritimati'),'2026-10-08');
assert.equal(api.entryDay(timed,'America/Los_Angeles'),'2026-10-07');
assert.equal(api.calendarStatus(timed),'Pending');
const span={...timed,end_at:'2026-10-09T10:00:00Z'};
assert.equal(api.entryOnDay(span,'2026-10-08','Pacific/Kiritimati'),true);
assert.equal(api.entryOnDay(span,'2026-10-09','Pacific/Kiritimati'),true);
assert.equal(api.entryOnDay(span,'2026-10-10','Pacific/Kiritimati'),false);
const allDay={...timed,all_day:true,start_at:null,start_date:'2026-10-08',end_date:'2026-10-10'};
for(const zone of ['UTC','Pacific/Kiritimati','America/Los_Angeles']) {
  assert.equal(api.entryDay(allDay,zone),'2026-10-08');
  assert.equal(api.entryOnDay(allDay,'2026-10-10',zone),true);
  assert.equal(api.entryOnDay(allDay,'2026-10-11',zone),false);
}
for(const stamp of ['2026-03-29T22:30:00Z','2026-10-25T23:30:00Z']) assert.equal(api.entryDay({...timed,start_at:stamp},'Europe/London'),stamp.slice(0,10));
assert.equal(api.entryDay({...timed,start_at:'2026-03-29T23:00:00Z'},'Europe/London'),'2026-03-30');
assert.deepEqual(api.calendarRoute({...timed,source_type:'payment_schedule'}).query,{commitment:'a',section:'payments'});
assert.deepEqual(api.calendarRoute({...timed,source_type:'activity_occurrence',occurrence_date:'2026-10-08'}).query,{commitment:'a',occurrence:'2026-10-08'});
assert.deepEqual(api.calendarRoute({...timed,source_type:'decision'}),{name:'project.decision',params:{projectId:'p',decisionId:'a'}});
for(const [status,label] of [['part_paid','Part paid'],['paid','Paid'],['upcoming','Upcoming']]) assert.equal(api.calendarStatus({...timed,source_type:'payment_schedule',status}),label);
console.log('PASS Calendar project date placement, DST, span boundaries, date-only invariance, source status and canonical routes.');
