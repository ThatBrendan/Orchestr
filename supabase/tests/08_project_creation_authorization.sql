-- pgTAP: project creation is authenticated, founder-bound, and isolated.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;
create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims','', true);
  perform set_config('role','postgres', true);
end $$;
create function pg_temp.wc(sql text) returns int language plpgsql as $$
declare n int; begin execute sql; get diagnostics n = row_count; return n; end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','a8000000-0000-0000-0000-000000000008','authenticated','authenticated','a8@t.co','{}','{"display_name":"Creator A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','b8000000-0000-0000-0000-000000000008','authenticated','authenticated','b8@t.co','{}','{"display_name":"User B"}',now(),now(),'','','');

-- Anonymous callers cannot create projects.
select set_config('role','anon', true);
select set_config('request.jwt.claims','', true);
select throws_ok($$select public.create_project('Anonymous project','UTC','GBP','2026-01-01',null)$$,
  '42501', null, 'anonymous cannot create a project');
select pg_temp.logout();

-- A creates a project through the production RPC. The trigger creates the
-- founder, so callers cannot supply created_by or choose the founding role.
select pg_temp.login('a8000000-0000-0000-0000-000000000008','a8@t.co');
select is(public.create_project('Creator project','UTC','GBP','2026-09-01','2026-12-31'),
          '88000000-0000-0000-0000-000000000008'::uuid,
          'creator receives the new project id');
select is((select count(*)::int from public.projects
           where id = '88000000-0000-0000-0000-000000000008'), 1,
          'creator can create a project');
select is((select status::text from public.projects
           where id = '88000000-0000-0000-0000-000000000008'), 'draft',
          'created project starts in draft status');
select is((select count(*)::int from public.project_members
           where project_id = '88000000-0000-0000-0000-000000000008'
             and user_id = 'a8000000-0000-0000-0000-000000000008'
             and role = 'organizer' and status = 'active' and deleted_at is null), 1,
          'creator gets exactly one active organizer membership');
select is((select created_by from public.projects
           where id = '88000000-0000-0000-0000-000000000008'),
          (select id from public.project_members
           where project_id = '88000000-0000-0000-0000-000000000008'
             and user_id = 'a8000000-0000-0000-0000-000000000008'),
          'created_by points to the generated founder membership');
select is((select count(*)::int from public.project_members
           where project_id = '88000000-0000-0000-0000-000000000008'
             and user_id = 'b8000000-0000-0000-0000-000000000008'), 0,
          'forged created_by cannot make another user the founder');
select is((select count(*)::int from public.projects
           where id = '88000000-0000-0000-0000-000000000008'), 1,
          'creator can immediately select the created project');
select pg_temp.logout();

select pg_temp.login('a8000000-0000-0000-0000-000000000008','a8@t.co');
select throws_ok($$insert into public.projects (name,timezone,currency)
  values ('Direct project','UTC','GBP')$$,
  '42501', null, 'creator cannot use the direct project insert route');
select pg_temp.logout();

-- B has no membership and cannot create for, read, update, or delete A's project.
select pg_temp.login('b8000000-0000-0000-0000-000000000008','b8@t.co');
select ok(public.create_project('B project','UTC','GBP','2026-01-01',null) is not null,
  'another authenticated user can create only their own project through the RPC');
select is((select count(*)::int from public.projects
           where id = '88000000-0000-0000-0000-000000000008'), 0,
          'non-member cannot read the project');
select is(pg_temp.wc($$update public.projects set name = 'B hacked'
           where id = '88000000-0000-0000-0000-000000000008'$$), 0,
          'non-member cannot update the project');
select throws_ok($$delete from public.projects
  where id = '88000000-0000-0000-0000-000000000008'$$,
  '42501', null, 'non-member cannot delete the project');
select pg_temp.logout();

select * from finish();
rollback;
