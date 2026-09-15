import assert from 'node:assert/strict';
import { build } from 'vite';
// Bundle the same TS validators used by Vite, without loading developer env files.
const bundled = await build({ configFile: false, logLevel: 'silent', build: { write: false, minify: false, lib: { entry: 'scripts/environment.ts', formats: ['es'] }, rollupOptions: { external: ['node:crypto'] } } });
const result = Array.isArray(bundled) ? bundled[0] : bundled;
const { prepareEnvironment } = await import(`data:text/javascript;base64,${Buffer.from(result.output.find((item) => item.type === 'chunk').code).toString('base64')}`);
const local = { VITE_SUPABASE_URL: 'http://127.0.0.1:54321', VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test_fixture_only', VITE_APP_ENV: 'development', VITE_APP_URL: 'http://localhost:5173' };
const ref = 'abcdefghijklmnopqrst';
const staging = { ...local, VITE_SUPABASE_URL: `https://${ref}.supabase.co`, VITE_APP_ENV: 'staging', ORCHESTR_STAGING_PROJECT_REF: ref };
const preview = { ...staging, VERCEL: '1', VERCEL_ENV: 'preview', VERCEL_URL: 'test-preview.example.com', VERCEL_GIT_COMMIT_REF: 'feature/test' };
assert.equal(prepareEnvironment(local, 'serve').VITE_APP_ENV, 'development');
assert.equal(prepareEnvironment(staging, 'build').VITE_APP_ENV, 'staging');
assert.equal(prepareEnvironment(preview, 'build').VITE_APP_URL, 'https://test-preview.example.com');
const developOrigin = 'https://orchestrio-git-dev-thatbrendans-projects.vercel.app';
const branchPreview = { ...preview, VERCEL_GIT_COMMIT_REF: 'dev', VERCEL_BRANCH_URL: new URL(developOrigin).hostname, VERCEL_URL: 'orchestrio-immutable-build.example.com' };
assert.equal(prepareEnvironment(branchPreview, 'build').VITE_APP_URL, developOrigin);
assert.equal(prepareEnvironment({ ...branchPreview, VITE_APP_URL: 'https://orchestrio.io' }, 'build').VITE_APP_URL, developOrigin);
assert.throws(() => prepareEnvironment({ ...branchPreview, VERCEL_BRANCH_URL: 'https://bad.example/path' }, 'build'));
for (const patch of [
 { VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_secret_never_ship_this' },
 { VITE_SUPABASE_PUBLISHABLE_KEY: 'invalid-not-a-public-key' },
 { VITE_SERVICE_ROLE_KEY: 'sensitive' },
 { VITE_APP_ENV: 'unknown' },
 { VITE_APP_ENV: 'production' },
 { VITE_SUPABASE_URL: 'https://custom-backend.example.com' },
 { VITE_APP_URL: 'javascript:alert(1)' },
]) assert.throws(() => prepareEnvironment({ ...local, ...patch }, 'serve'));
assert.throws(() => prepareEnvironment({ ...preview, VITE_APP_ENV: 'production' }, 'build'));
assert.throws(() => prepareEnvironment({ ...preview, ORCHESTR_STAGING_PROJECT_REF: '' }, 'build'));
assert.throws(() => prepareEnvironment({ ...preview, VERCEL_URL: '' }, 'build'));
assert.throws(() => prepareEnvironment({ ...preview, VITE_SUPABASE_URL: local.VITE_SUPABASE_URL }, 'build'));
assert.throws(() => prepareEnvironment({ ...preview, VERCEL_ENV: 'production', VITE_APP_ENV: 'production' }, 'build'));
const jwt = (role) => `e30.${Buffer.from(JSON.stringify({ role })).toString('base64url')}.test`;
assert.equal(prepareEnvironment({ ...local, VITE_SUPABASE_PUBLISHABLE_KEY: jwt('anon') }, 'serve').VITE_APP_ENV, 'development');
assert.throws(() => prepareEnvironment({ ...local, VITE_SUPABASE_PUBLISHABLE_KEY: jwt('service_role') }, 'serve'));
assert.throws(() => prepareEnvironment({ ...local, VITE_OTHER: jwt('service_role') }, 'serve'));
process.stdout.write('Environment policy checks passed. No network requests or real credentials used.\n');
