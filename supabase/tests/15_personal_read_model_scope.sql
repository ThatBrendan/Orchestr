-- pgTAP: platform-admin table visibility must not expand personal /app models.
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','aa150000-0000-0000-0000-000000000015','authenticated','authenticated','scope-admin@t.co','{}','{"display_name":"Scope Admin"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb150000-0000-0000-0000-000000000015','authenticated','authenticated','scope-member@t.co','{}','{"display_name":"Scope Member"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','cc150000-0000-0000-0000-000000000015','authenticated','authenticated','scope-outsider@t.co','{}','{"display_name":"Scope Outsider"}',now(),now(),'','','','');

update public.users
set platform_role = 'admin'
where id = 'aa150000-0000-0000-0000-000000000015';

insert into public.projects (id,name,status,timezone,currency,starts_on,ends_on)
values ('95100000-0000-0000-0000-000000000001','Private Scope Project','active','UTC','GBP','2026-09-01','2026-09-30');

insert into public.project_members (id,project_id,user_id,display_name,email,role,status)
values ('95100000-0000-0000-0000-00000000000b','95100000-0000-0000-0000-000000000001','bb150000-0000-0000-0000-000000000015','Scope Member','scope-member@t.co','organizer','active');

insert into public.commitments (id,project_id,title,kind,status,starts_at,activity_type)
values ('95110000-0000-0000-0000-000000000001','95100000-0000-0000-0000-000000000001','Private activity','other','researching','2026-09-10 09:00+00','task');

select pg_temp.login('aa150000-0000-0000-0000-000000000015','scope-admin@t.co');
select is(app.is_platform_admin(), true, 'admin fixture is a platform admin');
select is((select count(*)::int from public.get_my_timeline_events('2026-09-01','2026-09-30')), 0,
  'admin non-member sees no personal timeline events');
select is((select count(*)::int from public.v_my_timeline_events where project_id = '95100000-0000-0000-0000-000000000001'), 0,
  'admin non-member sees no personal view events');
select is((select count(*)::int from public.v_my_projects), 0,
  'admin non-member sees no personal projects');
select is((select count(*)::int from public.get_my_attention()), 0,
  'admin non-member sees no personal attention items');
select is((select count(*)::int from public.v_my_people), 0,
  'admin non-member sees no personal people');
select is((select count(*)::int from public.v_admin_projects where id = '95100000-0000-0000-0000-000000000001'), 1,
  'admin portal still sees the unrelated project');

insert into public.project_members (id,project_id,user_id,display_name,email,role,status)
values ('95100000-0000-0000-0000-00000000000a','95100000-0000-0000-0000-000000000001','aa150000-0000-0000-0000-000000000015','Scope Admin','scope-admin@t.co','member','active');

select is((select count(*)::int from public.get_my_timeline_events('2026-09-01','2026-09-30')
  where project_id = '95100000-0000-0000-0000-000000000001'), 1,
  'admin member sees personal timeline events');
select is((select count(*)::int from public.v_my_projects where project_id = '95100000-0000-0000-0000-000000000001'), 1,
  'admin member sees the personal project');
select is((select count(*)::int
  from public.v_my_people people
  where exists (
    select 1
    from jsonb_array_elements(people.projects) project
    where project->>'project_id' = '95100000-0000-0000-0000-000000000001'
  )), 2,
  'admin member sees project people');

select pg_temp.login('cc150000-0000-0000-0000-000000000015','scope-outsider@t.co');
select is((select count(*)::int from public.get_my_timeline_events('2026-09-01','2026-09-30')), 0,
  'unrelated normal user sees no personal timeline events');
select is((select count(*)::int from public.v_my_projects), 0,
  'unrelated normal user sees no personal projects');

select set_config('role','anon', true);
select set_config('request.jwt.claims','', true);
select throws_ok($$select count(*) from public.v_my_timeline_events$$, '42501', null,
  'anonymous cannot read personal timeline view');

select * from finish();
rollback;