import assert from 'node:assert/strict';
import { build } from 'vite';
const output = await build({ configFile: false, logLevel: 'silent', build: { write: false, minify: false, lib: { entry: 'src/lib/budgetVisual.ts', formats: ['es'] } } });
const result = Array.isArray(output) ? output[0] : output;
const { budgetVisual } = await import(`data:text/javascript;base64,${Buffer.from(result.output.find((item) => item.type === 'chunk').code).toString('base64')}`);
const example = budgetVisual(100000, 120000, 95000);
assert.equal(example.within, 100000);
assert.equal(example.over, 20000);
assert.equal(example.plannedWidth + example.overWidth, 100);
assert.equal(example.paidWidth, 95000 / 120000 * 100);
for (const [target, planned, paid] of [[null, 120000, 95000], [0, 0, 0], [0, 120000, 95000], [100000, 20000, 150000], [null, 0, -2000], [100000, 100000, 0], [100000, 50000, 0]]) {
  const v = budgetVisual(target, planned, paid);
  assert.equal(v.within + v.over, planned);
  for (const w of [v.plannedWidth, v.overWidth, v.paidWidth]) assert.ok(Number.isFinite(w) && w >= 0 && w <= 100);
  assert.ok(v.plannedWidth + v.overWidth <= 100.000001);
  if (target == null) assert.equal(v.over, 0);
}
process.stdout.write('Budget visual tests passed: over/under/exact/unset/zero target, paid above planned, net refunds.\n');
