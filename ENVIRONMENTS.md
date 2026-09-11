# Environment separation

## Current state and release blockers

The hosted project identified in the task is the intended **production** project. Inspection found both the developer's ignored `.env.local` and `supabase/.temp/project-ref` pointing at it. Neither file was changed. No cloud settings, migrations, production data, branches, keys, or deployments were changed.

**Preview deployments must never receive production database credentials.** This is release-blocking. The repository can reject a bad build, but cannot change already deployed sites or remove values already stored in Vercel. Audit those settings before onboarding.

A read-only `supabase branches list` returned no existing branches. This does not establish plan entitlement, pricing approval, or whether Branching can be enabled. Prefer a persistent `develop` Supabase branch if your account supports it and you approve its cost. Otherwise create a separate `orchestrio-development` project. Never enable paid features or copy production data just to satisfy this setup.

| Environment | Git | Vercel | Supabase | Data |
|---|---|---|---|---|
| Local | feature/* or dev | local Vite | local CLI/Docker | synthetic fixtures |
| Hosted development | feature/* or dev | local Vite, Development scope | isolated persistent develop branch or development project | synthetic/test users |
| Staging | dev and feature/* | Preview | same isolated staging backend | synthetic/test users |
| Production | main | Production | current intended production project | production data |

Only main exists locally. Recommended workflow: feature/* → PR to dev → staging tests → PR to main → reviewed production release. Shared staging data means feature previews share test state; avoid incompatible feature migrations there. Test those locally or use separately provisioned isolated branches with matching project-ref overrides.

## Repository safeguards

Vite validates configuration before serving or building. Missing configuration fails closed. Development startup and Vercel Preview reject production, even if VITE_APP_ENV is mislabeled. Hosted non-production must match an explicit ORCHESTR_STAGING_PROJECT_REF. Production builds require the approved production project; Vercel Production additionally requires main and production mode. The app repeats public-variable and key validation at runtime.

`scripts/production-project.json` contains only SHA-256 fingerprints of the known production project ref and current public publishable key. It contains no usable URL or key, and is never injected into browser configuration. This deliberate build-only guard catches the existing accidental production target even when local env values are wrong. When production identity/public keys change, review and update these guard fingerprints. Opaque publishable keys cannot be cryptographically matched to a project offline; verify URL/key pairs in each project's Dashboard. Rotated keys require updating the fingerprint guard.

Secret-looking VITE names, sb_secret values, PEM keys, and legacy service_role JWTs are rejected. The configured Supabase key must be publishable or an anon JWT; legacy JWT project-ref mismatches are rejected. Errors do not print values. Canonical Supabase URLs are required for identity checking; custom API domains are intentionally unsupported until an explicit reviewed mapping is implemented.

No database authorization is delegated to these build checks. RLS remains the data boundary. Non-production headers display a small environment label; production does not.

## Variables

Public/browser configuration:

- VITE_SUPABASE_URL
- VITE_SUPABASE_PUBLISHABLE_KEY
- VITE_APP_ENV
- VITE_APP_URL
- VITE_SENTRY_DSN (optional)

Build-only configuration:

- ORCHESTR_STAGING_PROJECT_REF (required for hosted non-production)
- VERCEL, VERCEL_ENV, VERCEL_URL, VERCEL_GIT_COMMIT_REF (Vercel system variables)

CLI/server-only variables as needed:

- SUPABASE_ACCESS_TOKEN
- SUPABASE_DB_PASSWORD
- PGPASSWORD
- APP_URL
- ALLOWED_ORIGINS

Never put a database password, access token, secret key, or service-role credential in VITE_ variables. `.env.local` stays ignored; `.env.example` has no real credentials and now uses the authoritative publishable-key name. Do not add production `.env` files to Git.

## Ordered manual setup

### 1. Supabase Dashboard

1. Open the intended production project. Verify its project ref against your records and treat its existing data as production. Review backups and access without resetting or reseeding it.
2. Inspect the branch selector/Branching settings and Billing. If persistent Branching is available and its cost is approved, create a persistent branch named `develop`, without production data. Do not enable automatic production merges/deployments as part of this setup.
3. If Branching is unavailable/unapproved, create a separate project named `orchestrio-development`. Choose region/plan deliberately. Do not manually recreate tables.
4. Record the new backend's canonical URL, public key, and project ref privately. Ensure it has independent Auth, Storage, and Edge Function settings.
5. In a staging checkout, link explicitly and inspect migration history before applying repository migrations:

```sh
supabase link --project-ref YOUR_STAGING_PROJECT_REF
npm run db:check-target -- staging YOUR_STAGING_PROJECT_REF
supabase db push --dry-run
# Only after reviewing the verified target and migration plan:
supabase db push
```

`db:check-target` only verifies identity and runs `supabase migration list --linked`; it never links, resets, seeds, or pushes. Do not use migration repair or --include-all to conceal an unexplained history mismatch. Persistent branches may already contain migrations: compare first.

Supabase documents persistent branch provisioning and independent branch secrets in its [branch configuration guide](https://supabase.com/docs/guides/deployment/branching/configuration). CLI alternative, only after approval: `supabase --experimental branches create develop --persistent --project-ref YOUR_PRODUCTION_PROJECT_REF`. No creation command was run here. Keep cloud seeding disabled; no `[remotes]` entries with invented project refs were added.

### 2. Auth and Storage

Configure Auth → URL Configuration separately on each backend:

- Local: Site URL is localhost port 5173; retain `/auth/callback` and its redirect query support, plus `/invite/**`.
- Staging: Site URL is a stable staging URL. Allow localhost callbacks for developers using this backend. Allow your actual project's Preview deployment URLs with `/auth/callback**` and `/invite/**`.
- Production: Site URL is the approved production app URL from the task. Allow its `/auth/callback**` and `/invite/**` only; avoid localhost and Preview URLs here.

For rotating previews, use a pattern limited to your actual project/team hostname (for example `https://YOUR_PROJECT-*-YOUR_TEAM.vercel.app/**`), or register explicit preview URLs. Do not allow all vercel.app sites. Match the URL emitted by VERCEL_URL. Follow Supabase's [redirect wildcard rules](https://supabase.com/docs/guides/auth/redirect-urls). Do not remove the callback route.

Storage buckets `avatars`, `project-media`, and `attachments` are declared in repository migrations with their policies. Apply those migrations independently; do not copy production objects. Configure any Auth email/SMTP providers independently, with test-only users/addresses outside production.

### 3. Vercel Dashboard

1. Open Project Settings → Git and verify Production Branch is main. Keep dev and feature branches in Preview.
2. Open Settings → Environment Variables. Remove production backend values from Preview and Development, including branch-specific overrides and integration-managed duplicates.
3. Set the four required public variables in **Production only**, using production URL/public key, production app environment and the approved production app URL. Optional Sentry belongs to the corresponding environment.
4. Set Preview backend URL/public key to staging, VITE_APP_ENV to staging, and ORCHESTR_STAGING_PROJECT_REF to that same staging ref. Apply to all non-production branches unless an override points at another isolated non-production backend.
5. Leave Preview VITE_APP_URL unset: Vite derives it as HTTPS plus VERCEL_URL for each deployment. Never reuse the production app URL or a stale preview hostname.
6. Development scope uses isolated staging credentials with VITE_APP_ENV=development, a localhost app URL, and the same staging-ref check. Local Docker users instead use their own `.env.local`.
7. Ensure system environment variables are exposed to builds. Retain the repository's build command. Review fork/Preview access and deployment protection. Redeploy each affected scope after fixing variables; old deployments do not retroactively inherit new values. Verify the non-production label and actual backend in browser requests.

Vercel documents [environment scoping](https://vercel.com/docs/environment-variables) and [deployment URL/system variables](https://vercel.com/docs/environment-variables/system-environment-variables). No Vercel settings were inspected remotely or changed. A manually promoted prebuilt Preview artifact is still a staging build; create a fresh Production build rather than promoting that artifact.

### 4. Git/GitHub

Create dev from the intended integration baseline yourself, then push it and enable PR review/branch protection. Work on feature/*, merge into dev, test staging, then merge into main. Keep production migration approval separate from automatic Preview frontend builds. Review any Supabase GitHub integration before enabling it: it can apply migrations/configuration automatically.

No Git branches were created or pushed by this task.

## Local development with and without Docker

Replace the current production-backed `.env.local` with local or isolated staging values before normal development. The file was intentionally left intact; startup now rejects its unsafe target. A staging backend supports ordinary frontend development without Docker.

For local database work:

```sh
supabase start
supabase status
supabase db reset --local
supabase test db
```

Reset is destructive to the **local** database. Never add --linked or a remote --db-url to reset. `npm run db:status` and `npm run db:test` are read-only status/local tests respectively. Use local Supabase for migration development, RLS tests, destructive scenarios and pgTAP.

Automatic seed execution is disabled in config.toml. The existing seed contains fictional example.com users with a shared test password; it must not be used as production or publicly exposed staging authentication. The seed now requires an explicit SQL opt-in and includes profiles, activities, tasks/calendar data, a weekly activity and project notes. It contains no production IDs or user records.

For a freshly reset **local** database only, obtain its password privately from the local setup, then run:

```sh
# PGPASSWORD must contain your LOCAL database password. Do not paste it into Git.
PGOPTIONS='-c orchestr.allow_test_seed=on' psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -1 -f supabase/seed.sql
```

This fixes the host/port to local loopback and wraps the seed in a transaction. The seed is not idempotent; use a fresh local database. Staging should use synthetic users created through its own Auth flow and synthetic scenarios entered in the app; do not upload this shared-password local seed automatically. No seed was executed in this task.

## Migrations and production release

Migration files are authoritative. Feature work → new migration → local apply/test → reviewed commit → staging apply → E2E → merge main → reviewed production apply. Production must never be the first test target.

`supabase db push` targets whichever remote is currently linked, **not** the backend in `.env.local`. The link here remains production. Before **every** remote push, verify Dashboard identity, current Git branch, and `supabase migration list`. Prefer a separate checkout per remote link; recheck even then.

For a reviewed production release, explicitly link the production ref and run `npm run db:check-target -- production YOUR_PRODUCTION_PROJECT_REF`, inspect the migration comparison, run a dry run, and only then manually apply. No push-to-production convenience script exists. None of these remote mutations was run during this task.

## Edge Functions

`invitations-send` uses Supabase-injected SUPABASE_URL/SUPABASE_ANON_KEY for the project where it is deployed. It authenticates POST requests and enforces organizer membership. No email provider secret is currently needed: delivery is deferred.

Set APP_URL and optional comma-separated ALLOWED_ORIGINS independently for each function environment. Use explicit origins for Preview CORS; the existing helper does not implement wildcard CORS. Do not copy production secret values. Production/local development origins are still accepted by the existing helper; CORS is not an environment or authorization boundary, so frontend build isolation and Auth/RLS remain required.

Manual commands, always with the reviewed target ref:

```sh
supabase secrets set --project-ref YOUR_TARGET_PROJECT_REF --env-file YOUR_IGNORED_FUNCTION_ENV_FILE
supabase functions deploy invitations-send --project-ref YOUR_TARGET_PROJECT_REF
```

Keep function env files named `.env.*` so Git ignores them; do not prefix their secrets with VITE_. This task changed no function code and deployed nothing.

## Release checklist

- [ ] Correct Git branch and explicit Supabase target verified
- [ ] TypeScript, lint and build pass
- [ ] Migration tested outside production
- [ ] pgTAP passes where available
- [ ] Staging E2E passes
- [ ] Production migration reviewed and dry-run inspected
- [ ] Vercel Production uses Production Supabase
- [ ] Preview and Development contain no production backend credentials
- [ ] Function environment/secrets and Auth redirects verified
- [ ] Storage remains isolated; no production data copied
- [ ] Fresh deployment uses the correct environment indicator/backend

## Verification in this task

TypeScript passed. Lint: zero errors, one existing intentional static-SVG warning. Environment-policy tests passed. The existing local production configuration failed the build as intended. A build with synthetic local public settings passed. The fixture-configured Vite server started and served the application HTML and transformed config; this does not verify backend connectivity. `.env.local` remains ignored. Database/seed tests and live staging E2E remain pending provisioning/local Docker. No cloud mutation, commit, push, deployment, key rotation or paid resource creation occurred.

## Files changed

- `.env.example`
- `README.md`
- `ENVIRONMENTS.md`
- `eslint.config.js` (Node globals scoped to scripts only; no rule relaxed)
- `package.json` (safe status/test/target-check commands)
- `scripts/environment.ts`
- `scripts/environment.test.mjs`
- `scripts/check-db-target.mjs`
- `scripts/production-project.json` (fingerprints only)
- `src/lib/environment.ts`
- `src/config.ts`
- `src/env.d.ts`
- `src/components/layout/AppTopBar.vue`
- `supabase/config.toml`
- `supabase/seed.sql`
- `vite.config.ts`

Safety scan found no usable production URL or production credential in tracked application configuration. The production connection and public key were in ignored developer configuration; only irreversible fingerprints are now committed as safety checks. Existing `.env.local` and Supabase link files were not edited. Preview/Production isolation in the actual Vercel account remains unverified and release-blocking until the manual audit above is complete.
