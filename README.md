# Orchestrio

**Plan together. Execute clearly.**

Orchestrio is a collaborative planning and execution platform that brings **commitments, people, costs, responsibilities, deadlines, and progress** into one shared workspace.

Instead of coordinating complex plans across WhatsApp, email, spreadsheets, PDFs, booking confirmations, and notes, Orchestrio provides one place to see what is happening, who owns it, what it costs, and what needs attention.

## What can you plan?

Orchestrio is designed for plans involving multiple people, moving parts, costs, and deadlines, including:

* Group trips
* Weddings and events
* House moves
* Product and startup launches
* Team projects
* Other complex group plans

## Core features

**Commitments** — Organise activities, bookings, services, and other important parts of a plan.

**Ownership** — Assign responsibility so everyone knows who is handling what.

**Money** — Track costs, payments, refunds, outstanding amounts, and budget performance.

**Timeline** — Bring commitments, payment deadlines, tasks, and milestones into one chronological view.

**People** — See who is involved and what they are responsible for.

**Planning Health** — Surface issues such as overdue payments, incomplete bookings, overdue tasks, and budget risks.

## Tech stack

* Vue 3 + TypeScript
* Vite
* Tailwind CSS
* Vue Router
* TanStack Vue Query
* Pinia
* Supabase
* PostgreSQL + Row Level Security
* Vercel

## Status

Orchestrio is currently under active development.

The application foundation, authentication, project management, public landing experience, backend schema, security model, and core project workspace are in place.

Commitment management and the remaining execution workflows are currently being built.

## Local development

Install dependencies:

```bash id="22t5dx"
npm install
```

Create your environment file:

```bash id="8vnm81"
cp .env.example .env.local
```

Read [ENVIRONMENTS.md](ENVIRONMENTS.md) first. Add **local or isolated staging** Supabase configuration to `.env.local`, then run:

```bash id="qxfu0d"
npm run dev
```

The development server runs at:

```text id="gqemrf"
http://localhost:5173
```

## Checks

```bash id="db1vmw"
# Type checking
npx vue-tsc --noEmit

# Lint
npm run lint

# Production build
npm run build
```

## Database

Database changes are managed through Supabase migrations:

```bash id="i5pnva"
supabase/migrations/
```

Before remote migration work, verify the link and review the migration list:

```bash
npm run db:check-target -- staging YOUR_STAGING_PROJECT_REF
```

This command is read-only. `supabase db push` targets the linked remote; never run it without the checks and staging validation in [ENVIRONMENTS.md](ENVIRONMENTS.md). Production is never the first test target.

## Security

Supabase Row Level Security is the application's authorization boundary.

Never commit `.env` files or expose the Supabase `service_role` key in frontend code.

Development branch initialized for staging.

---

**Orchestrio** — from scattered planning to coordinated execution.
