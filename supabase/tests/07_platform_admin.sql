-- pgTAP: platform admin role is global, read-only, and backend-authoritative.
begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

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

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','aa000000-0000-0000-0000-00000000000a','authenticated','authenticated','admin@t.co','{}','{"display_name":"Admin"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb000000-0000-0000-0000-00000000000b','authenticated','authenticated','normal@t.co','{}','{"display_name":"Normal"}',now(),now(),'','','','');

update public.users
set platform_role = 'admin'
where id = 'aa000000-0000-0000-0000-00000000000a';

insert into public.projects (id,name,status,timezone,currency,archived_at) values
 ('77110000-0000-0000-0000-000000000001','Admin visible project','active','UTC','GBP',null),
 ('77220000-0000-0000-0000-000000000002','Archived project','archived','UTC','GBP',now());

insert into public.project_members (id,project_id,user_id,display_name,email,role,status) values
 ('77110000-0000-0000-0000-00000000000a','77110000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-00000000000a','Admin','admin@t.co','organizer','active'),
 ('77110000-0000-0000-0000-00000000000b','77110000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-00000000000b','Normal','normal@t.co','member','active');

update public.projects set created_by = '77110000-0000-0000-0000-00000000000a'
where id = '77110000-0000-0000-0000-000000000001';

insert into public.invitations (project_id,email,role,invited_by)
values ('77110000-0000-0000-0000-000000000001','invitee@t.co','member','77110000-0000-0000-0000-00000000000a');

insert into public.commitments (project_id,title,kind,status,confirmed_cost_minor)
values ('77110000-0000-0000-0000-000000000001','Confirmed booking','services','confirmed',1000);

-- ===== anon =====
select set_config('role','anon', true);
select set_config('request.jwt.claims','', true);
select throws_ok($$select count(*) from public.v_admin_users$$, '42501', null, 'anon: cannot read admin users view');
select throws_ok($$select count(*) from public.v_admin_projects$$, '42501', null, 'anon: cannot read admin projects view');
select throws_ok($$select count(*) from public.v_admin_audit_log$$, '42501', null, 'anon: cannot read admin audit view');
select pg_temp.logout();

-- ===== normal authenticated user =====
select pg_temp.login('bb000000-0000-0000-0000-00000000000b','normal@t.co');
select is(app.is_platform_admin(), false, 'normal: app.is_platform_admin() is false');
select is((select platform_role::text from public.users where id = 'bb000000-0000-0000-0000-00000000000b'), 'user', 'normal: can read own user role only');
select is((select count(*)::int from public.v_admin_users), 0, 'normal: cannot read admin user list');
select is((select count(*)::int from public.v_admin_projects), 0, 'normal: cannot read platform project list');
select is((select count(*)::int from public.v_admin_audit_log), 0, 'normal: cannot read global audit');
select throws_ok($$update public.users set platform_role = 'admin' where id = 'bb000000-0000-0000-0000-00000000000b'$$,
  'P0001', null, 'normal: cannot update own platform role');
select throws_ok($$select * from public.get_admin_overview()$$,
  'P0001', null, 'normal: cannot invoke admin-only overview RPC');
select throws_ok($$select * from public.get_admin_project_health_summary('77110000-0000-0000-0000-000000000001')$$,
  'P0001', null, 'normal: cannot invoke admin-only health RPC');
select pg_temp.logout();

-- ===== platform admin =====
select pg_temp.login('aa000000-0000-0000-0000-00000000000a','admin@t.co');
select is(app.is_platform_admin(), true, 'admin: app.is_platform_admin() is true');
select is((select count(*)::int from public.v_admin_users), 2, 'admin: can read approved user list');
select is((select count(*)::int from public.v_admin_projects), 2, 'admin: can read approved project list');
select is((select count(*)::int from public.v_admin_invitations), 1, 'admin: can inspect invitations');
select ok((select count(*)::int from public.v_admin_audit_log) > 0, 'admin: can inspect audit activity');
select is((select total_users from public.get_admin_overview()), 2, 'admin: can invoke admin overview RPC');
select is((select active_projects from public.get_admin_overview()), 1, 'admin: overview includes active projects');
select is((select archived_projects from public.get_admin_overview()), 1, 'admin: overview includes archived projects');
select is((select count(*)::int from public.get_admin_project_health_summary('77110000-0000-0000-0000-000000000001')),
  1, 'admin: can inspect project health summary');
select pg_temp.logout();

select * from finish();
rollback;
