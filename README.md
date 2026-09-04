# Orchestr

**Plan together. Execute clearly.**

Orchestr is a collaborative planning and execution platform that brings **commitments, people, costs, responsibilities, deadlines, and progress** into one shared workspace.

Instead of coordinating complex plans across WhatsApp, email, spreadsheets, PDFs, booking confirmations, and notes, Orchestr provides one place to see what is happening, who owns it, what it costs, and what needs attention.

## What can you plan?

Orchestr is designed for plans involving multiple people, moving parts, costs, and deadlines, including:

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

**Planning Health** — Surface issues such as missing owners, overdue payments, incomplete bookings, overdue tasks, and budget risks.

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

Orchestr is currently under active development.

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

Add your Supabase configuration to `.env.local`, then run:

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

To apply pending migrations to the linked project:

```bash id="l9xv46"
supabase db push
```

## Security

Supabase Row Level Security is the application's authorization boundary.

Never commit `.env` files or expose the Supabase `service_role` key in frontend code.

---

**Orchestr** — from scattered planning to coordinated execution.
