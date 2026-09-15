import assert from 'node:assert/strict';
import { build } from 'vite';

async function load(entry) {
  const result = await build({ configFile: false, logLevel: 'silent', build: { write: false, minify: false, lib: { entry, formats: ['es'] } } });
  const output = Array.isArray(result) ? result[0] : result;
  return import(`data:text/javascript;base64,${Buffer.from(output.output.find(item => item.type === 'chunk').code).toString('base64')}`);
}
const { safeRedirect, passwordError, authCallbackUrl, readAuthLink, RECOVERY_SENT } = await load('src/lib/authPolicy.ts');
const { toAuthAppError } = await load('src/lib/errors.ts');
for (const path of ['/app', '/app/projects/123?tab=people#members', '/invite/abc-123', '/admin/users']) assert.equal(safeRedirect(path), path);
for (const path of [null, [], '', 'https://evil.example', '//evil.example/app', '/\\evil.example', '/app\\evil', '/app/../login', '/app/%2e%2e/login', '/app/%252e%252e/login', '/%2f%2fevil.example', '/app/%5cevil', '/app\n', '/app?x=%0d%0a', '/app/%', '/login', '/signup', '/auth/callback', '/reset-password', '/invite/', '/application', '/app/../../app']) assert.equal(safeRedirect(path), null, String(path));
assert.equal(authCallbackUrl('https://orchestrio.io/', '/invite/token', 'signup'), 'https://orchestrio.io/auth/callback?redirect=%2Finvite%2Ftoken&mode=signup');
assert.equal(authCallbackUrl('https://orchestrio-git-dev-thatbrendans-projects.vercel.app', null, 'signup'), 'https://orchestrio-git-dev-thatbrendans-projects.vercel.app/auth/callback?mode=signup');
assert.equal(authCallbackUrl('https://preview.example', '//evil.example', 'recovery'), 'https://preview.example/auth/callback?mode=recovery');
assert.equal(passwordError(''), 'Use a password of at least 8 characters.');
assert(passwordError('1234567'));
assert.equal(passwordError('12345678', '12345678'), null);
assert.equal(passwordError('12345678', ''), 'Passwords do not match.');
assert.equal(passwordError('12345678', '12345679'), 'Passwords do not match.');
assert.equal(readAuthLink('https://app.example/auth/callback?code=secret&mode=signup').signup, true);
assert.equal(readAuthLink('https://app.example/auth/callback?mode=recovery#error=access_denied').hasError, true);
assert.equal(readAuthLink('https://app.example/reset-password#access_token=secret&type=recovery').recovery, true);
assert.equal(readAuthLink('https://app.example/?code=secret&redirect=%2Finvite%2Ftoken').redirect, '/invite/token');
assert.equal(readAuthLink('https://app.example/#access_token=secret&type=signup').signup, true);
assert(!JSON.stringify(readAuthLink('https://app.example/auth/callback?code=SECRET')).includes('SECRET'));
assert.equal(toAuthAppError({code:'invalid_credentials'}).message, 'Email or password is incorrect.');
assert.equal(toAuthAppError({code:'reauthentication_needed'}, 'password').code, 'reauthentication_needed');
assert.equal(toAuthAppError({code:'over_email_send_rate_limit'}, 'email').kind, 'rate_limit');
assert.equal(toAuthAppError(new Error('AuthApiError raw provider detail'), 'email').message, 'Unable to send the email right now. Try again shortly.');
assert(RECOVERY_SENT.startsWith('If an account exists'));
console.log('PASS: auth redirects, environment callbacks, password policy, link parsing, safe errors and recovery copy.');
