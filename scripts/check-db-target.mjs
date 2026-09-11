import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';

const [environment, expectedRef] = process.argv.slice(2);
if (!['staging', 'production'].includes(environment) || !/^[a-z0-9]{20}$/.test(expectedRef ?? '')) {
  throw new Error('Usage: npm run db:check-target -- staging|production EXPECTED_PROJECT_REF');
}
const fingerprint = JSON.parse(readFileSync(new URL('./production-project.json', import.meta.url), 'utf8')).sha256;
const production = createHash('sha256').update(expectedRef).digest('hex') === fingerprint;
if ((environment === 'production') !== production) throw new Error('Environment does not match the approved production identity.');
const linked = readFileSync('supabase/.temp/project-ref', 'utf8').trim();
if (linked !== expectedRef) throw new Error('Linked project differs from expected target. Stop and inspect your Supabase link.');
process.stdout.write(`Verified linked ${environment} target: ${linked}\nRead-only migration comparison follows. No migrations will be applied.\n`);
const result = spawnSync('supabase', ['migration', 'list', '--linked'], { stdio: 'inherit', shell: false });
if (result.error) throw new Error('Could not run Supabase CLI.');
process.exitCode = result.status ?? 1;
