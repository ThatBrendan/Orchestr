-- ============================================================================
-- 20260904120100_tables
-- All 14 entity tables: columns, PK/FK/unique/check, indexes, generic triggers.
-- Domain triggers -> 20260904120300 ; audit -> 20260904120200 ; RLS -> 20260904120600
--
-- Source of truth: docs/DATABASE_SCHEMA.md §4
-- ============================================================================

-- ===========================================================================
-- users  (§4.1) — profile mirror of auth.users
-- ===========================================================================
create table public.users (
  id                 uuid primary key references auth.users(id) on delete cascade,
  email              text not null check (position('@' in email) > 1),
  display_name       text not null check (char_length(btrim(display_name)) between 1 and 80),
  avatar_url         text,
  timezone           text not null default 'UTC',
  default_currency   text not null default 'GBP' references public.currencies(code) on delete restrict,
  notification_prefs jsonb not null default '{"email":true,"push":false}'::jsonb
                       check (jsonb_typeof(notification_prefs) = 'object'),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create unique index users_lower_email_key on public.users (lower(email));

create trigger users_set_updated_at   before update on public.users
  for each row execute function app.tg_set_updated_at();
create trigger users_validate_timezone before insert or update of timezone on public.users
  for each row execute function app.tg_validate_timezone();

-- ===========================================================================
-- projects  (§4.2)
-- ===========================================================================
create table public.projects (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (char_length(btrim(name)) between 1 and 120),
  description   text,
  status        public.project_status not null default 'draft',
  starts_on     date,
  ends_on       date,
  timezone      text not null,
  currency      text not null references public.currencies(code) on delete restrict,
  cover_theme   text,
  health_config jsonb not null default '{}'::jsonb check (jsonb_typeof(health_config) = 'object'),
  created_by    uuid,   -- -> project_members.id ; deliberately NOT an FK (docs/DATABASE_SCHEMA.md §7.2)
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  archived_at   timestamptz,
  deleted_at    timestamptz,
  constraint chk_project_dates check (starts_on is null or ends_on is null or starts_on <= ends_on),
  constraint chk_archived_consistency check ((status = 'archived') = (archived_at is not null))
);
create index projects_status_idx      on public.projects (status) where deleted_at is null;
create index projects_created_by_idx  on public.projects (created_by);

create trigger projects_set_updated_at   before update on public.projects
  for each row execute function app.tg_set_updated_at();
create trigger projects_validate_timezone before insert or update of timezone on public.projects
  for each row execute function app.tg_validate_timezone();

-- ===========================================================================
-- project_members  (§4.3)
-- ===========================================================================
create table public.project_members (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references public.projects(id) on delete cascade,
  user_id      uuid references public.users(id) on delete set null,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
  email        text check (email is null or position('@' in email) > 1),
  role         public.member_role   not null default 'member',
  status       public.member_status not null default 'active',
  invited_at   timestamptz,
  joined_at    timestamptz default now(),
  removed_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  constraint uq_member_project_id unique (project_id, id),   -- composite-FK target
  constraint chk_member_removed_dates check ((status = 'removed') = (removed_at is not null))
);
create unique index uq_member_user on public.project_members (project_id, user_id)
  where user_id is not null;
create unique index uq_member_email_active on public.project_members (project_id, lower(email))
  where email is not null and status <> 'removed' and deleted_at is null;
create index project_members_user_idx on public.project_members (user_id) where user_id is not null;
create index project_members_active_role_idx on public.project_members (project_id, role)
  where status = 'active' and deleted_at is null;

create trigger project_members_set_updated_at before update on public.project_members
  for each row execute function app.tg_set_updated_at();
create trigger project_members_block_immutable before update on public.project_members
  for each row execute function app.tg_block_immutable_columns();
create trigger project_members_lc_email before insert or update of email on public.project_members
  for each row execute function app.tg_lowercase_email();

-- ===========================================================================
-- invitations  (§4.4)
-- ===========================================================================
create table public.invitations (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  email              text not null check (position('@' in email) > 1),
  role               public.member_role not null default 'member' check (role <> 'organizer'),
  status             public.invitation_status not null default 'pending',
  token              text not null default
                       replace(replace(encode(extensions.gen_random_bytes(24),'base64'),'+','-'),'/','_'),
  invited_by         uuid not null,
  expires_at         timestamptz not null default (now() + interval '14 days'),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  accepted_at        timestamptz,
  accepted_member_id uuid,
  constraint uq_invitation_token unique (token),
  constraint chk_invitation_accept check ((status = 'accepted') = (accepted_at is not null)),
  constraint fk_invitation_inviter
    foreign key (project_id, invited_by) references public.project_members(project_id, id) on delete cascade,
  constraint fk_invitation_accepted_member
    foreign key (project_id, accepted_member_id) references public.project_members(project_id, id) on delete set null
);
create unique index uq_invitation_pending on public.invitations (project_id, lower(email))
  where status = 'pending';
create index invitations_pending_idx on public.invitations (project_id) where status = 'pending';

create trigger invitations_set_updated_at before update on public.invitations
  for each row execute function app.tg_set_updated_at();
create trigger invitations_lc_email before insert or update of email on public.invitations
  for each row execute function app.tg_lowercase_email();

-- ===========================================================================
-- commitments  (§4.5)  — Locations are the embedded location_* columns
-- ===========================================================================
create table public.commitments (
  id                   uuid primary key default gen_random_uuid(),
  project_id           uuid not null references public.projects(id) on delete cascade,
  title                text not null check (char_length(btrim(title)) between 1 and 120),
  kind                 public.commitment_kind not null,
  status               public.commitment_status not null default 'researching',
  owner_member_id      uuid,
  estimated_cost_minor bigint check (estimated_cost_minor is null or estimated_cost_minor >= 0),
  confirmed_cost_minor bigint check (confirmed_cost_minor is null or confirmed_cost_minor >= 0),
  starts_at            timestamptz,
  ends_at              timestamptz,
  is_all_day           boolean not null default false,
  schedule_note        text,
  location_label       text,
  location_address     text,
  location_lat         numeric(9,6) check (location_lat is null or location_lat between -90 and 90),
  location_lng         numeric(9,6) check (location_lng is null or location_lng between -180 and 180),
  location_place_id    text,
  supplier_name        text,
  supplier_contact     text,
  booking_reference    text,
  booking_confirmed    boolean not null default false,
  notes                text,
  created_by           uuid,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  constraint uq_commitment_project_id unique (project_id, id),   -- composite-FK target
  constraint chk_commitment_time check (starts_at is null or ends_at is null or ends_at >= starts_at),
  constraint fk_commitment_owner
    foreign key (project_id, owner_member_id) references public.project_members(project_id, id) on delete cascade,
  constraint fk_commitment_created_by
    foreign key (project_id, created_by) references public.project_members(project_id, id) on delete set null
);
create index commitments_status_idx    on public.commitments (project_id, status) where deleted_at is null;
create index commitments_owner_idx     on public.commitments (owner_member_id) where deleted_at is null;
create index commitments_schedule_idx  on public.commitments (project_id, starts_at)
  where deleted_at is null and status <> 'cancelled';
create index commitments_kind_idx      on public.commitments (project_id, kind) where deleted_at is null;
create index commitments_inactive_idx  on public.commitments (project_id, updated_at)
  where status in ('idea','researching') and deleted_at is null;

create trigger commitments_set_updated_at before update on public.commitments
  for each row execute function app.tg_set_updated_at();
create trigger commitments_block_immutable before update on public.commitments
  for each row execute function app.tg_block_immutable_columns();

-- ===========================================================================
-- commitment_participants  (§4.6)
-- ===========================================================================
create table public.commitment_participants (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid not null references public.projects(id) on delete cascade,
  commitment_id uuid not null,
  member_id     uuid not null,
  rsvp          public.rsvp_status not null default 'unknown',
  added_by      uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint uq_participant unique (commitment_id, member_id),
  constraint fk_participant_commitment
    foreign key (project_id, commitment_id) references public.commitments(project_id, id) on delete cascade,
  constraint fk_participant_member
    foreign key (project_id, member_id) references public.project_members(project_id, id) on delete cascade,
  constraint fk_participant_added_by
    foreign key (project_id, added_by) references public.project_members(project_id, id) on delete set null
);
create index participants_member_idx     on public.commitment_participants (member_id);
create index participants_commitment_idx on public.commitment_participants (commitment_id);
create index participants_project_idx    on public.commitment_participants (project_id);

create trigger participants_set_updated_at before update on public.commitment_participants
  for each row execute function app.tg_set_updated_at();
create trigger participants_block_immutable before update on public.commitment_participants
  for each row execute function app.tg_block_immutable_columns();

-- ===========================================================================
-- cost_shares  (§4.7) — explicit overrides only; absence => equal split
-- ===========================================================================
create table public.cost_shares (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  commitment_id      uuid not null,
  member_id          uuid not null,
  basis              public.cost_share_basis not null,
  weight             numeric(12,4),
  fixed_amount_minor bigint,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint uq_cost_share unique (commitment_id, member_id),
  constraint chk_cost_share_basis check (
      (basis = 'equal'  and weight is null and fixed_amount_minor is null)
   or (basis = 'weight' and weight is not null and weight > 0 and fixed_amount_minor is null)
   or (basis = 'fixed'  and fixed_amount_minor is not null and fixed_amount_minor >= 0 and weight is null)
  ),
  constraint fk_cost_share_commitment
    foreign key (project_id, commitment_id) references public.commitments(project_id, id) on delete cascade,
  constraint fk_cost_share_member
    foreign key (project_id, member_id) references public.project_members(project_id, id) on delete cascade
);
create index cost_shares_commitment_idx on public.cost_shares (commitment_id);
create index cost_shares_member_idx     on public.cost_shares (member_id);
create index cost_shares_project_idx    on public.cost_shares (project_id);

create trigger cost_shares_set_updated_at before update on public.cost_shares
  for each row execute function app.tg_set_updated_at();
create trigger cost_shares_block_immutable before update on public.cost_shares
  for each row execute function app.tg_block_immutable_columns();

-- ===========================================================================
-- payments  (§4.8)
-- ===========================================================================
create table public.payments (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  commitment_id      uuid not null,
  type               public.payment_type not null,
  direction          public.payment_direction not null default 'outgoing',
  status             public.payment_status not null default 'scheduled',
  amount_minor       bigint not null check (amount_minor > 0),
  due_on             date,
  paid_on            date,
  ever_paid          boolean not null default false,  -- set once status='paid'; never cleared (see BACKEND_IMPLEMENTATION.md deviation D1)
  paid_by_member_id  uuid,
  method             text,
  reference          text,
  notes              text,
  created_by         uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  constraint chk_payment_refund_direction check (type <> 'refund' or direction = 'incoming'),
  constraint chk_payment_paid_on check ((status = 'paid') = (paid_on is not null)),
  constraint fk_payment_commitment
    foreign key (project_id, commitment_id) references public.commitments(project_id, id) on delete cascade,
  constraint fk_payment_paid_by
    foreign key (project_id, paid_by_member_id) references public.project_members(project_id, id) on delete set null,
  constraint fk_payment_created_by
    foreign key (project_id, created_by) references public.project_members(project_id, id) on delete set null
);
create index payments_status_idx       on public.payments (project_id, status) where deleted_at is null;
create index payments_due_idx          on public.payments (project_id, status, due_on)
  where deleted_at is null and status = 'scheduled';
create index payments_commitment_idx   on public.payments (commitment_id) where deleted_at is null;
create index payments_payer_idx        on public.payments (paid_by_member_id)
  where status = 'paid' and deleted_at is null;

create trigger payments_set_updated_at before update on public.payments
  for each row execute function app.tg_set_updated_at();
create trigger payments_block_immutable before update on public.payments
  for each row execute function app.tg_block_immutable_columns();

-- ===========================================================================
-- tasks  (§4.9)
-- ===========================================================================
create table public.tasks (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  commitment_id      uuid,
  title              text not null check (char_length(btrim(title)) between 1 and 120),
  status             public.task_status not null default 'open',
  assignee_member_id uuid,
  due_on             date,
  notes              text,
  completed_at       timestamptz,
  created_by         uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  constraint chk_task_completed check ((status = 'done') = (completed_at is not null)),
  constraint fk_task_commitment
    foreign key (project_id, commitment_id) references public.commitments(project_id, id) on delete cascade,
  constraint fk_task_assignee
    foreign key (project_id, assignee_member_id) references public.project_members(project_id, id) on delete set null,
  constraint fk_task_created_by
    foreign key (project_id, created_by) references public.project_members(project_id, id) on delete set null
);
create index tasks_status_idx     on public.tasks (project_id, status) where deleted_at is null;
create index tasks_due_idx        on public.tasks (project_id, status, due_on)
  where deleted_at is null and status in ('open','in_progress');
create index tasks_assignee_idx   on public.tasks (assignee_member_id) where deleted_at is null;
create index tasks_commitment_idx on public.tasks (commitment_id) where deleted_at is null;

create trigger tasks_set_updated_at before update on public.tasks
  for each row execute function app.tg_set_updated_at();
create trigger tasks_block_immutable before update on public.tasks
  for each row execute function app.tg_block_immutable_columns();

-- ===========================================================================
-- milestones  (§4.10)
-- ===========================================================================
create table public.milestones (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid not null references public.projects(id) on delete cascade,
  commitment_id uuid,
  title         text not null check (char_length(btrim(title)) between 1 and 120),
  on_date       date not null,
  notes         text,
  created_by    uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint fk_milestone_commitment
    foreign key (project_id, commitment_id) references public.commitments(project_id, id) on delete cascade,
  constraint fk_milestone_created_by
    foreign key (project_id, created_by) references public.project_members(project_id, id) on delete set null
);
create index milestones_date_idx       on public.milestones (project_id, on_date);
create index milestones_commitment_idx on public.milestones (commitment_id) where commitment_id is not null;

create trigger milestones_set_updated_at before update on public.milestones
  for each row execute function app.tg_set_updated_at();
create trigger milestones_block_immutable before update on public.milestones
  for each row execute function app.tg_block_immutable_columns();

-- ===========================================================================
-- budgets & budget_category_targets  (§4.11-4.12) — targets only
-- ===========================================================================
create table public.budgets (
  project_id         uuid primary key references public.projects(id) on delete cascade,
  total_target_minor bigint check (total_target_minor is null or total_target_minor >= 0),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create trigger budgets_set_updated_at before update on public.budgets
  for each row execute function app.tg_set_updated_at();

create table public.budget_category_targets (
  project_id   uuid not null references public.budgets(project_id) on delete cascade,
  kind         public.commitment_kind not null,
  amount_minor bigint not null check (amount_minor >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (project_id, kind)
);
create trigger budget_targets_set_updated_at before update on public.budget_category_targets
  for each row execute function app.tg_set_updated_at();

-- ===========================================================================
-- finding_dismissals  (§4.13) — the only persisted health data
-- ===========================================================================
create table public.finding_dismissals (
  id               uuid primary key default gen_random_uuid(),
  project_id       uuid not null references public.projects(id) on delete cascade,
  code             text not null,
  subject_type     text not null check (subject_type in
                     ('commitment','payment','task','milestone','project','commitment_pair','budget_category')),
  subject_id       uuid,
  state            public.finding_dismissal_state not null,
  snoozed_until    date,
  actor_member_id  uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint chk_dismissal_snooze check ((state = 'snoozed') = (snoozed_until is not null)),
  constraint uq_finding_dismissal unique nulls not distinct (project_id, code, subject_type, subject_id),
  constraint fk_dismissal_actor
    foreign key (project_id, actor_member_id) references public.project_members(project_id, id) on delete set null
);
create index finding_dismissals_project_idx on public.finding_dismissals (project_id);

create trigger finding_dismissals_set_updated_at before update on public.finding_dismissals
  for each row execute function app.tg_set_updated_at();

-- ===========================================================================
-- audit_log  (§4.14) — immutable, append-only. No FKs by design.
-- ===========================================================================
create table public.audit_log (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid,
  at              timestamptz not null default now(),
  actor_user_id   uuid,
  actor_member_id uuid,
  source          public.audit_source not null default 'app',
  action          public.audit_action not null,
  entity_type     text not null,
  entity_id       uuid not null,
  before          jsonb,
  after           jsonb,
  request_id      text,
  constraint chk_audit_create_image check (action <> 'create' or before is null),
  constraint chk_audit_delete_image check (action <> 'delete' or after is null)
);
create index audit_log_project_idx on public.audit_log (project_id, at desc);
create index audit_log_entity_idx  on public.audit_log (entity_type, entity_id, at desc);
create index audit_log_actor_idx   on public.audit_log (actor_user_id, at desc);
