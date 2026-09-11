import assert from 'node:assert/strict';
import { build } from 'vite';
const output = await build({ configFile: false, logLevel: 'silent', build: { write: false, minify: false, lib: { entry: 'src/lib/costSharing.ts', formats: ['es'] } } });
const result = Array.isArray(output) ? output[0] : output;
const { evenShares } = await import(`data:text/javascript;base64,${Buffer.from(result.output.find((item) => item.type === 'chunk').code).toString('base64')}`);
assert.deepEqual(evenShares(60000, ['c','a','b']), { a: 20000, b: 20000, c: 20000 });
assert.deepEqual(evenShares(10000, ['c','b','a']), { a: 3334, b: 3333, c: 3333 });
for (const cost of [0,1,2,99,10000,60000,Number.MAX_SAFE_INTEGER]) {
  const shares = Object.values(evenShares(cost, ['b','c','a']));
  assert.equal(shares.reduce((a,b) => a+BigInt(b),0n),BigInt(cost));
  assert.ok(Math.max(...shares)-Math.min(...shares)<=1);
}
assert.throws(() => evenShares(10, []));
assert.throws(() => evenShares(10, ['a','a']));
assert.throws(() => evenShares(-1, ['a']));
assert.throws(() => evenShares(1.1, ['a']));
process.stdout.write('Cost sharing rounding tests passed.\n');
