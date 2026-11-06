# Orchestrio landing page specification

## Product audit

The public site uses Vue components in `src/components/marketing`, Vue Router, metadata and indexing policy in `src/publicSite.ts`, and static rendering through `src/prerender.ts` and `scripts/build-public.mjs`. Marketing design is minimalist, with shared header/footer, existing typography and branded CTA buttons. Signup is `/signup`; authenticated visitors are directed to the dashboard.

Product code confirms shared project creation, invitations/membership, activities with owners, dates and statuses, decision options and voting, timelines/calendars, notes/comments, budgets, cost splits, reimbursements and payment links. Payments happen outside Orchestrio. Product code does not support booking travel, venues or suppliers. Generic task list functionality is not asserted; responsibilities are described through activity owners. Automated notifications are not presented as a promise.

## Homepage

- **URL:** `/`
- **Audience:** People coordinating a plan or project with others.
- **Primary keyword:** group planning app
- **Secondary keywords:** shared planning app; collaborative planning app; planning app for groups; group organiser app; app for planning together
- **Intent:** Find a tool that makes organising something with other people easier.
- **Title:** Group Planning App for Shared Plans | Orchestrio
- **Description:** Plan together in one shared workspace. Orchestrio keeps people, activities, decisions, dates and shared costs connected beyond the group chat.
- **H1:** Plans need more than messages.
- **Structure:** H2 The plan is everywhere; H2 A shared place to move plans forward; H2 How it works (H3 Create a project, Invite people, Organise activities and decisions); H2 What can you organise?; H2 A conversation is not the whole plan; H2 Start your first shared plan.
- **Feature demonstrations:** Activities, people, decisions, dates, money and progress, consistent with existing product preview.
- **Differentiation:** Complements chat by keeping decisions, ownership, dates and costs connected in a shared project.
- **Internal links:** Group trip planning and group event planning pages; existing public sections and legal/about links.
- **Primary CTA:** Get started → `/signup` (or dashboard for signed-in users).
- **Conversion objective:** Create an account and start a shared project.

## Group trip planning

- **URL:** `/group-trip-planning`
- **Audience:** Friends and families coordinating a trip or holiday.
- **Primary keyword:** group trip planner
- **Secondary keywords:** plan a trip with friends; group holiday planner; group travel planning app; group trip planning; shared travel itinerary; organise a group holiday
- **Intent:** Coordinate decisions, activities, people, dates and costs for a shared trip.
- **Title:** Group Trip Planner for Friends & Family | Orchestrio
- **Description:** Plan a group trip together with shared activities, decisions, dates, responsibilities and cost tracking in one workspace.
- **H1:** Plan a group trip beyond the group chat.
- **Structure:** H2 Why group trip planning gets scattered; H2 Keep the trip moving together; H2 One shared place for trip details (H3 Activities and dates, Decisions and responsibilities, Shared costs); H2 Trips take many shapes; H2 Keep chat for conversation and the plan for coordination; H2 FAQs (organising a trip, planning a holiday together, costs, updates); H2 Plan your next trip together.
- **Feature demonstrations:** Projects, invitations, activities and owners, decisions/votes, dates, cost splits and reimbursements.
- **Differentiation:** Coordination workspace alongside chat; no itinerary booking or travel reservation claim.
- **Internal links:** Homepage and group event planning.
- **Primary CTA:** Get started → `/signup`.
- **Conversion objective:** Create an account and set up the trip project.

## Group event planning

- **URL:** `/group-event-planning`
- **Audience:** Friends and families coordinating a celebration or event.
- **Primary keyword:** group event planning app
- **Secondary keywords:** organise an event with friends; shared event planning; group celebration planning; party planning app; organise a group celebration
- **Intent:** Coordinate event arrangements and responsibilities with participants.
- **Title:** Group Event Planning App | Orchestrio
- **Description:** Organise a celebration together with shared activities, decisions, responsibilities, dates and cost tracking in one workspace.
- **H1:** Organise an event together, beyond the group chat.
- **Structure:** H2 Event details spread across too many places; H2 A shared plan everyone can follow; H2 Coordinate the work together (H3 Activities and decisions, People and owners, Dates and costs); H2 From birthdays to reunions; H2 Turn event conversation into coordinated action; H2 FAQs (organising an event, party planning, dividing responsibilities, costs); H2 Start organising your event.
- **Feature demonstrations:** Projects, invitations, activities and owners, decisions/votes, dates, cost splits and reimbursements.
- **Differentiation:** Shared execution workspace, without claims of venue marketplaces, supplier directories, seating charts or RSVP systems.
- **Internal links:** Homepage and group trip planning.
- **Primary CTA:** Get started → `/signup`.
- **Conversion objective:** Create an account and set up the event project.
