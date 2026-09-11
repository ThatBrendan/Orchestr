import assert from 'node:assert/strict';
import { build } from 'vite';
const output = await build({ configFile: false, logLevel: 'silent', build: { write: false, minify: false, lib: { entry: 'src/lib/activityWorkflows.ts', formats: ['es'] } } });
const result = Array.isArray(output) ? output[0] : output;
const api = await import(`data:text/javascript;base64,${Buffer.from(result.output.find((item) => item.type === 'chunk').code).toString('base64')}`);
for (const type of ['task','booking','purchase','event','other']) {
  assert.equal(api.activityWorkflow(type).defaultStatus,'idea');
  assert.equal(api.commitmentStatusLabel(type,'idea'),'Not started');
  for (const status of ['researching','confirmed','booked']) assert.equal(api.commitmentStatusLabel(type,status),'In progress');
  assert.equal(api.commitmentStatusLabel(type,'completed'),'Completed');
  assert.equal(api.commitmentStatusLabel(type,'cancelled'),'Cancelled');
  assert.equal(api.commitmentStatusActions(type,'idea')[0].label,'Start');
  for (const state of ['idea','researching','confirmed','booked','completed','cancelled']) {
    assert.ok(api.commitmentStatusActions(type,state).every(action => ['Start','Complete'].includes(action.label)));
  }
  if (type !== 'booking') {
    assert.ok(api.commitmentStatusActions(type,'idea').some(a => a.to === 'completed'));
    assert.deepEqual(api.commitmentStatusActions(type,'researching'),[{to:'completed',label:'Complete'}]);
  }
  assert.deepEqual(api.commitmentStatusActions(type,'completed'),[]);
  assert.equal(api.secondaryActivityActions(type,'idea')[0].label,'Cancel activity');
  assert.equal(api.secondaryActivityActions(type,'cancelled')[0].to,'researching');
}
assert.equal(api.bookingStatusLabel('booked',false),'Booked');
assert.equal(api.bookingStatusLabel('completed',false),'Booked');
assert.equal(api.bookingStatusLabel('researching',true),'Booked');
assert.equal(api.bookingStatusLabel('confirmed',false),'Ready to book');
assert.equal(api.bookingStatusLabel('idea',false),'Not booked');
assert.deepEqual(api.commitmentStatusActions('booking','researching'),[]);
assert.equal(api.bookingStatusActions('researching')[0].to,'confirmed');
assert.equal(api.bookingStatusActions('confirmed')[0].to,'booked');
assert.equal(api.commitmentStatusActions('booking','booked')[0].to,'completed');
assert.equal(api.secondaryActivityActions('booking','completed')[0].to,'booked');
assert.equal(api.executionStatusLabel('skipped'),'skipped');
process.stdout.write('Activity execution presentation tests passed across every Type and historical status.\n');
