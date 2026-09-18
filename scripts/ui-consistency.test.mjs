import test from 'node:test';
import assert from 'node:assert/strict';

import { paginateList, clampPage } from '../src/lib/pagination.ts';
import { userFacingActivityStatus } from '../src/lib/presentation.ts';

test('paginated overview keeps 5 items per page and resets if the list shrinks', () => {
  const items = Array.from({ length: 11 }, (_, index) => ({ id: index + 1 }));
  const page1 = paginateList(items, 1, 5);
  assert.equal(page1.items.length, 5);
  assert.deepEqual(page1.items.map((item) => item.id), [1, 2, 3, 4, 5]);
  assert.equal(page1.totalPages, 3);

  const page2 = paginateList(items, 2, 5);
  assert.deepEqual(page2.items.map((item) => item.id), [6, 7, 8, 9, 10]);

  const tiny = paginateList(Array.from({ length: 3 }, (_, index) => ({ id: index + 1 })), 3, 5);
  assert.equal(tiny.items.length, 3);
  assert.equal(tiny.page, 1);
  assert.equal(tiny.totalPages, 1);
  assert.equal(tiny.canGoPrevious, false);
  assert.equal(tiny.canGoNext, false);
});

test('pagination clamps invalid page indexes safely', () => {
  assert.equal(clampPage(0, 3), 1);
  assert.equal(clampPage(99, 3), 3);
  assert.equal(clampPage(2, 1), 1);
});

test('timeline statuses are mapped to user-facing pending and complete labels only', () => {
  assert.equal(userFacingActivityStatus('idea'), 'Pending');
  assert.equal(userFacingActivityStatus('researching'), 'Pending');
  assert.equal(userFacingActivityStatus('booked'), 'Pending');
  assert.equal(userFacingActivityStatus('completed'), 'Complete');
  assert.equal(userFacingActivityStatus('cancelled'), 'Cancelled');
});
