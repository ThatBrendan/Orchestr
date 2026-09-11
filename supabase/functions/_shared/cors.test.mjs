// Run: node supabase/functions/_shared/cors.test.mjs (uses root TypeScript dependency).
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import ts from 'typescript';
const config = { APP_URL: 'https://app.example.com/path', ALLOWED_ORIGINS: 'https://preview.example.com' };
globalThis.Deno = { env: { get: (key) => config[key] } };
const source = readFileSync(new URL('./cors.ts', import.meta.url), 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext } }).outputText;
const { corsHeaders, json } = await import(`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`);
for (const origin of ['http://localhost:5173', 'http://127.0.0.1:5173', 'https://app.example.com', 'https://preview.example.com']) {
  const req = new Request('https://example.com', { method: 'OPTIONS', headers: { origin } });
  const response = new Response(null, { status: 204, headers: corsHeaders(req) });
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), origin);
  assert.match(response.headers.get('Access-Control-Allow-Headers'), /authorization/);
  assert.match(response.headers.get('Access-Control-Allow-Methods'), /OPTIONS/);
  assert.equal(json(req, { error: 'unauthorized' }, 401).headers.get('Access-Control-Allow-Origin'), origin);
}
assert.equal(corsHeaders(new Request('https://example.com', { headers: { origin: 'https://untrusted.example' } }))['Access-Control-Allow-Origin'], undefined);
console.log('CORS checks passed: development, production, preview, error responses, untrusted origin.');
