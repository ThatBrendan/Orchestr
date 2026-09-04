-- ============================================================================
-- seed.sql  — development / staging fixtures (NEVER run against production)
-- Ports the prototype's "Barcelona Stag Weekend" + "Sarah & John's Wedding".
-- Applied automatically by `supabase db reset`.
--
-- Runs as `postgres` (BYPASSRLS) but all triggers still fire. Because there is
-- no JWT during seed, auth.uid() is null and app.tg_after_project_insert_create_member
-- skips; the founding organizer membership is inserted explicitly below.
-- Password for every seeded user: "password123".
--
-- Fixed UUIDs (all hex):
--   users     : 11.. James | 22.. Mike | 33.. Sarah | 44.. Chris
--   projects  : aaaaaaaa-0000-… Barcelona | bbbbbbbb-0000-… Wedding
--   members   : a11a0000-…-00000000000N Barcelona (1 James .. 6 Ed)
--               b22b0000-…-00000000000N Wedding   (1 Sarah, 2 John)
--   commits   : c0000000-…-0000000000b1 boat | e1 restaurant | d1 transfer | a1 hotel | f1 golf
--               d0000000-…-0000000000c1 wedding venue
-- ============================================================================

insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
   confirmation_token, email_change, email_change_token_new, recovery_token)
values
  ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated',
   'james@example.com', extensions.crypt('password123', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}',
   '{"display_name":"James Dawson","timezone":"Europe/London","default_currency":"GBP"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222','authenticated','authenticated',
   'mike@example.com', extensions.crypt('password123', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}','{"display_name":"Mike"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000','33333333-3333-3333-3333-333333333333','authenticated','authenticated',
   'sarah@example.com', extensions.crypt('password123', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}','{"display_name":"Sarah"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000','44444444-4444-4444-4444-444444444444','authenticated','authenticated',
   'chris@example.com', extensions.crypt('password123', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}','{"display_name":"Chris"}', now(), now(), '', '', '', '');

insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
values
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111',
   '{"sub":"11111111-1111-1111-1111-111111111111","email":"james@example.com"}','email', now(), now(), now()),
  (gen_random_uuid(),'22222222-2222-2222-2222-222222222222','22222222-2222-2222-2222-222222222222',
   '{"sub":"22222222-2222-2222-2222-222222222222","email":"mike@example.com"}','email', now(), now(), now()),
  (gen_random_uuid(),'33333333-3333-3333-3333-333333333333','33333333-3333-3333-3333-333333333333',
   '{"sub":"33333333-3333-3333-3333-333333333333","email":"sarah@example.com"}','email', now(), now(), now()),
  (gen_random_uuid(),'44444444-4444-4444-4444-444444444444','44444444-4444-4444-4444-444444444444',
   '{"sub":"44444444-4444-4444-4444-444444444444","email":"chris@example.com"}','email', now(), now(), now());
-- public.users rows are created by the on_auth_user_created trigger.

-- =========================================================================
-- Project: Barcelona Stag Weekend
-- =========================================================================
insert into public.projects (id, name, status, starts_on, ends_on, timezone, currency, created_at)
values ('aaaaaaaa-0000-0000-0000-0000000000aa','Barcelona Stag Weekend','active',
        date '2027-05-16', date '2027-05-18','Europe/Madrid','GBP', now());

insert into public.project_members (id, project_id, user_id, display_name, email, role, status, joined_at) values
  ('a11a0000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-0000000000aa','11111111-1111-1111-1111-111111111111','James','james@example.com','organizer','active', now()),
  ('a11a0000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-0000000000aa','22222222-2222-2222-2222-222222222222','Mike','mike@example.com','member','active', now()),
  ('a11a0000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-0000000000aa','33333333-3333-3333-3333-333333333333','Sarah','sarah@example.com','member','active', now()),
  ('a11a0000-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-0000000000aa','44444444-4444-4444-4444-444444444444','Chris','chris@example.com','member','active', now()),
  ('a11a0000-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-0000000000aa', null,'Tom','tom@example.com','member','active', now()),
  ('a11a0000-0000-0000-0000-000000000006','aaaaaaaa-0000-0000-0000-0000000000aa', null,'Ed', 'ed@example.com', 'member','active', now());

update public.projects set created_by = 'a11a0000-0000-0000-0000-000000000001'
where id = 'aaaaaaaa-0000-0000-0000-0000000000aa';

insert into public.budgets (project_id, total_target_minor) values
  ('aaaaaaaa-0000-0000-0000-0000000000aa', 500000);
insert into public.budget_category_targets (project_id, kind, amount_minor) values
  ('aaaaaaaa-0000-0000-0000-0000000000aa','accommodation',180000),
  ('aaaaaaaa-0000-0000-0000-0000000000aa','experience',    120000),
  ('aaaaaaaa-0000-0000-0000-0000000000aa','food',           90000),
  ('aaaaaaaa-0000-0000-0000-0000000000aa','transport',      48000),
  ('aaaaaaaa-0000-0000-0000-0000000000aa','other',          30000);

insert into public.commitments
  (id, project_id, title, kind, status, owner_member_id, confirmed_cost_minor,
   starts_at, ends_at, location_label, supplier_name, booking_reference, booking_confirmed, notes)
values
  ('c0000000-0000-0000-0000-0000000000b1','aaaaaaaa-0000-0000-0000-0000000000aa','Boat Party','experience','confirmed',
   'a11a0000-0000-0000-0000-000000000002', 120000,
   timestamptz '2027-05-16 11:00+02', timestamptz '2027-05-16 15:00+02',
   'Port Olimpic, Barcelona','Barcelona Boats','ABC123', true,'Balance due before boarding.'),
  ('c0000000-0000-0000-0000-0000000000e1','aaaaaaaa-0000-0000-0000-0000000000aa','Restaurant','food','confirmed',
   'a11a0000-0000-0000-0000-000000000004', 60000,
   timestamptz '2027-05-16 19:30+02', timestamptz '2027-05-16 22:00+02',
   'El Xampanyet, Barcelona','El Xampanyet', null, false,'Confirmation number still missing.'),
  ('c0000000-0000-0000-0000-0000000000d1','aaaaaaaa-0000-0000-0000-0000000000aa','Airport Transfer','transport','researching',
   null, 24000,
   timestamptz '2027-05-15 14:00+02', null,
   'BCN Airport to Hotel Praktik', null, null, false,'Need someone to own this.'),
  ('c0000000-0000-0000-0000-0000000000a1','aaaaaaaa-0000-0000-0000-0000000000aa','Hotel','accommodation','booked',
   'a11a0000-0000-0000-0000-000000000001', 180000,
   timestamptz '2027-05-15 15:00+02', timestamptz '2027-05-18 11:00+02',
   'Hotel Praktik Rambla','Hotel Praktik Rambla','HPR-2245', true,'Two twins and two doubles.'),
  ('c0000000-0000-0000-0000-0000000000f1','aaaaaaaa-0000-0000-0000-0000000000aa','Crazy Golf','experience','confirmed',
   'a11a0000-0000-0000-0000-000000000003', 18000,
   timestamptz '2027-05-15 16:30+02', timestamptz '2027-05-15 18:00+02',
   'Adventure Golf, Poble Espanyol','Adventure Golf','AG-9081', true,'Pay on arrival.');

insert into public.commitment_participants (project_id, commitment_id, member_id)
select 'aaaaaaaa-0000-0000-0000-0000000000aa', c.id, m.id
from public.commitments c
cross join public.project_members m
where c.project_id = 'aaaaaaaa-0000-0000-0000-0000000000aa'
  and m.project_id = 'aaaaaaaa-0000-0000-0000-0000000000aa';

insert into public.payments
  (project_id, commitment_id, type, direction, status, amount_minor, due_on, paid_on, paid_by_member_id)
values
  ('aaaaaaaa-0000-0000-0000-0000000000aa','c0000000-0000-0000-0000-0000000000b1','deposit','outgoing','paid',
   40000, null, date '2026-08-20','a11a0000-0000-0000-0000-000000000002'),
  ('aaaaaaaa-0000-0000-0000-0000000000aa','c0000000-0000-0000-0000-0000000000b1','balance','outgoing','scheduled',
   80000, date '2027-05-12', null, null),
  ('aaaaaaaa-0000-0000-0000-0000000000aa','c0000000-0000-0000-0000-0000000000e1','full','outgoing','paid',
   60000, null, date '2026-08-25','a11a0000-0000-0000-0000-000000000004'),
  ('aaaaaaaa-0000-0000-0000-0000000000aa','c0000000-0000-0000-0000-0000000000a1','full','outgoing','paid',
   180000, null, date '2026-08-10','a11a0000-0000-0000-0000-000000000001'),
  ('aaaaaaaa-0000-0000-0000-0000000000aa','c0000000-0000-0000-0000-0000000000f1','full','outgoing','scheduled',
   18000, null, null, null);

insert into public.tasks (project_id, commitment_id, title, status, assignee_member_id, due_on) values
  ('aaaaaaaa-0000-0000-0000-0000000000aa','c0000000-0000-0000-0000-0000000000e1',
   'Chase the restaurant for a confirmation number','open','a11a0000-0000-0000-0000-000000000004', date '2027-04-01'),
  ('aaaaaaaa-0000-0000-0000-0000000000aa','c0000000-0000-0000-0000-0000000000d1',
   'Compare minibus companies and book','open', null, date '2027-04-15');

insert into public.milestones (project_id, title, on_date) values
  ('aaaaaaaa-0000-0000-0000-0000000000aa','Final headcount to all venues', date '2027-05-01');

-- =========================================================================
-- Project: Sarah & John's Wedding
-- =========================================================================
insert into public.projects (id, name, status, ends_on, timezone, currency, created_at)
values ('bbbbbbbb-0000-0000-0000-0000000000bb','Sarah & John''s Wedding','active',
        date '2027-07-24','Europe/London','GBP', now());

insert into public.project_members (id, project_id, user_id, display_name, email, role, status, joined_at) values
  ('b22b0000-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-0000000000bb','33333333-3333-3333-3333-333333333333','Sarah','sarah@example.com','organizer','active', now()),
  ('b22b0000-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-0000000000bb', null,'John','john@example.com','member','active', now());

update public.projects set created_by = 'b22b0000-0000-0000-0000-000000000001'
where id = 'bbbbbbbb-0000-0000-0000-0000000000bb';

insert into public.budgets (project_id, total_target_minor) values
  ('bbbbbbbb-0000-0000-0000-0000000000bb', 1200000);

insert into public.commitments (id, project_id, title, kind, status, owner_member_id, estimated_cost_minor)
values
  ('d0000000-0000-0000-0000-0000000000c1','bbbbbbbb-0000-0000-0000-0000000000bb','Reception venue','services','researching',
   'b22b0000-0000-0000-0000-000000000001', 600000);
insert into public.commitment_participants (project_id, commitment_id, member_id)
select 'bbbbbbbb-0000-0000-0000-0000000000bb','d0000000-0000-0000-0000-0000000000c1', m.id
from public.project_members m where m.project_id = 'bbbbbbbb-0000-0000-0000-0000000000bb';

-- Pending invitation for the Barcelona project
insert into public.invitations (project_id, email, role, invited_by, token)
values ('aaaaaaaa-0000-0000-0000-0000000000aa','newperson@example.com','member',
        'a11a0000-0000-0000-0000-000000000001','seed-invite-token-newperson');
