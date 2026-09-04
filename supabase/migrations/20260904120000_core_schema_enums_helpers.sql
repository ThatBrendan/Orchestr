-- ============================================================================
-- 20260904120000_core_schema_enums_helpers
-- Objects that can exist BEFORE the application tables:
--   schemas, extensions, enumerated types, the currencies reference table,
--   and generic trigger functions that reference no application table.
--
-- The SECURITY DEFINER membership helpers (app.is_member / has_role / is_organizer
-- / current_member_id / is_writable_project) and app.tg_enforce_project_writable()
-- reference public.project_members / public.projects, so they are created in
-- 20260904120150_security_helpers.sql — which runs AFTER 20260904120100_tables.sql.
--
-- Source of truth: docs/DATABASE_SCHEMA.md §1-3, §8.1-8.2 ; docs/SECURITY_RLS.md §4
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Schemas
-- ---------------------------------------------------------------------------
create schema if not exists app;      -- RLS internals + trigger fns; NOT exposed to PostgREST
comment on schema app is 'Orchestr internal: RLS helper functions and trigger functions. Not exposed via PostgREST.';

-- `public` and `extensions` already exist in Supabase.
create extension if not exists pgcrypto with schema extensions;   -- gen_random_bytes for invitation tokens

-- ---------------------------------------------------------------------------
-- Enumerated types  (docs/DATABASE_SCHEMA.md §2)
-- ---------------------------------------------------------------------------
create type public.project_status        as enum ('draft','active','completed','archived');
create type public.member_role           as enum ('organizer','member','viewer');
create type public.member_status         as enum ('invited','active','removed');
create type public.invitation_status     as enum ('pending','accepted','expired','revoked');
create type public.commitment_kind       as enum ('accommodation','transport','food','experience','services','other');
create type public.commitment_status     as enum ('idea','researching','confirmed','booked','completed','cancelled');
create type public.payment_type          as enum ('deposit','balance','installment','full','refund');
create type public.payment_direction     as enum ('outgoing','incoming');
create type public.payment_status        as enum ('scheduled','paid','waived','cancelled');
create type public.task_status           as enum ('open','in_progress','done','cancelled');
create type public.cost_share_basis      as enum ('equal','weight','fixed');
create type public.rsvp_status           as enum ('going','maybe','not_going','unknown');
create type public.finding_dismissal_state as enum ('dismissed','snoozed');
create type public.audit_action          as enum ('create','update','soft_delete','restore','delete');
create type public.audit_source          as enum ('app','rpc','edge','system');

-- ---------------------------------------------------------------------------
-- Reference data: currencies  (docs/DATABASE_SCHEMA.md §3.1)
-- ---------------------------------------------------------------------------
create table public.currencies (
  code        text primary key check (code ~ '^[A-Z]{3}$'),
  name        text not null,
  minor_unit  smallint not null check (minor_unit between 0 and 4),
  symbol      text
);
comment on table public.currencies is 'ISO-4217 currency metadata for minor-unit arithmetic and formatting. Seed/migration writes only.';

insert into public.currencies (code, name, minor_unit, symbol) values
  ('GBP','Pound Sterling',2,'£'),
  ('EUR','Euro',2,'€'),
  ('USD','US Dollar',2,'$'),
  ('AUD','Australian Dollar',2,'A$'),
  ('CAD','Canadian Dollar',2,'C$'),
  ('NZD','New Zealand Dollar',2,'NZ$'),
  ('CHF','Swiss Franc',2,'CHF'),
  ('SEK','Swedish Krona',2,'kr'),
  ('NOK','Norwegian Krone',2,'kr'),
  ('DKK','Danish Krone',2,'kr'),
  ('PLN','Polish Zloty',2,'zł'),
  ('CZK','Czech Koruna',2,'Kč'),
  ('JPY','Japanese Yen',0,'¥'),
  ('KRW','South Korean Won',0,'₩'),
  ('KWD','Kuwaiti Dinar',3,'KD'),
  ('BHD','Bahraini Dinar',3,'BD'),
  ('ZAR','South African Rand',2,'R'),
  ('AED','UAE Dirham',2,'AED'),
  ('SGD','Singapore Dollar',2,'S$'),
  ('HKD','Hong Kong Dollar',2,'HK$'),
  ('INR','Indian Rupee',2,'₹'),
  ('MXN','Mexican Peso',2,'$'),
  ('BRL','Brazilian Real',2,'R$'),
  ('THB','Thai Baht',2,'฿'),
  ('TRY','Turkish Lira',2,'₺');

-- ---------------------------------------------------------------------------
-- Generic trigger functions  (docs/DATABASE_SCHEMA.md §8.1)
-- These are SECURITY INVOKER (no elevation needed).
-- ---------------------------------------------------------------------------

create or replace function app.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Freezes project_id / created_at / created_by after insert. (docs/DATABASE_SCHEMA.md §7.13)
create or replace function app.tg_block_immutable_columns()
returns trigger language plpgsql as $$
begin
  if new.project_id is distinct from old.project_id then
    raise exception 'orchestr:immutable_column:project_id cannot be changed' using errcode = 'P0001';
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'orchestr:immutable_column:created_at cannot be changed' using errcode = 'P0001';
  end if;
  if to_jsonb(new) ? 'created_by'
     and (to_jsonb(new)->>'created_by') is distinct from (to_jsonb(old)->>'created_by') then
    raise exception 'orchestr:immutable_column:created_by cannot be changed' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

-- IANA timezone validity. Trigger (not CHECK) because pg_timezone_names is not IMMUTABLE.
-- (docs/DATABASE_SCHEMA.md §7.9)
create or replace function app.tg_validate_timezone()
returns trigger language plpgsql as $$
begin
  if new.timezone is null
     or not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise exception 'orchestr:bad_timezone:% is not a valid IANA timezone', coalesce(new.timezone,'<null>')
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create or replace function app.tg_lowercase_email()
returns trigger language plpgsql as $$
begin
  if new.email is not null then
    new.email := lower(btrim(new.email));
  end if;
  return new;
end;
$$;

-- app.tg_enforce_project_writable() references public.projects — created in
-- 20260904120150_security_helpers.sql (after the tables).

-- Static dismissibility map: blockers cannot be dismissed. (docs/BUSINESS_RULES §9 HLT-F)
create or replace function app.finding_is_dismissible(p_code text)
returns boolean language sql immutable as $$
  select p_code <> all (array['payment_overdue']);
$$;

-- ---------------------------------------------------------------------------
-- Schema + generic-helper grants. `app` is not PostgREST-exposed.
-- The membership helpers' grants live in 20260904120150_security_helpers.sql
-- alongside their definitions.
-- ---------------------------------------------------------------------------
revoke all on schema app from public;
grant usage on schema app to authenticated, service_role;

revoke execute on function app.finding_is_dismissible(text) from public;
grant  execute on function app.finding_is_dismissible(text) to authenticated, service_role;

grant select on public.currencies to anon, authenticated;
