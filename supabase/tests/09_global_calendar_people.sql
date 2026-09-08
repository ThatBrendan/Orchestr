-- pgTAP: global calendar + people read-model isolation and grouping.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

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
 ('00000000-0000-0000-0000-000000000000','aa000000-0000-0000-0000-000000000001','authenticated','authenticated','a-global@t.co','{}','{"display_name":"A Global"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb000000-0000-0000-0000-000000000002','authenticated','authenticated','b-global@t.co','{}','{"display_name":"B Global"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','cc000000-0000-0000-0000-000000000003','authenticated','authenticated','c-global@t.co','{}','{"display_name":"C Global"}',now(),now(),'','','','');

insert into public.projects (id,name,status,timezone,currency,starts_on,ends_on) values
 ('91000000-0000-0000-0000-000000000001','Global A','active','UTC','GBP','2026-09-01','2026-09-30'),
 ('92000000-0000-0000-0000-000000000002','Global B','active','UTC','GBP',null,null),
 ('93000000-0000-0000-0000-000000000003','Global C','active','UTC','GBP',null,null);

insert into public.project_members (id,project_id,user_id,display_name,email,role,status) values
 ('91000000-0000-0000-0000-00000000000a','91000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000001','A Global','a-global@t.co','organizer','active'),
 ('91000000-0000-0000-0000-00000000000b','91000000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000002','B Global','b-global@t.co','member','active'),
 ('91000000-0000-0000-0000-000000000010','91000000-0000-0000-0000-000000000001',null,'Alex','alex-one@example.com','member','active'),
 ('92000000-0000-0000-0000-00000000000a','92000000-0000-0000-0000-000000000002','aa000000-0000-0000-0000-000000000001','A Global','a-global@t.co','member','active'),
 ('92000000-0000-0000-0000-00000000000b','92000000-0000-0000-0000-000000000002','bb000000-0000-0000-0000-000000000002','B Global','b-global@t.co','viewer','active'),
 ('92000000-0000-0000-0000-000000000020','92000000-0000-0000-0000-000000000002',null,'Alex','alex-two@example.com','viewer','active'),
 ('93000000-0000-0000-0000-00000000000c','93000000-0000-0000-0000-000000000003','cc000000-0000-0000-0000-000000000003','C Global','c-global@t.co','organizer','active');

insert into public.commitments (id,project_id,title,kind,status,starts_at,estimated_cost_minor) values
 ('91110000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001','A dated','other','researching','2026-09-10 09:00+00',1000),
 ('92220000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000002','B dated','other','researching','2026-09-12 09:00+00',2000),
 ('93330000-0000-0000-0000-000000000003','93000000-0000-0000-0000-000000000003','C private','other','researching','2026-09-14 09:00+00',3000),
 ('92220000-0000-0000-0000-000000000004','92000000-0000-0000-0000-000000000002','B unscheduled','other','researching',null,4000);

insert into public.payments (id,project_id,commitment_id,amount_minor,status,due_on) values
 ('94440000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000002','92220000-0000-0000-0000-000000000002',1200,'scheduled','2026-09-15');

select set_config('role','anon', true); select set_config('request.jwt.claims','', true);
select throws_ok($$select count(*) from public.v_my_timeline_events$$, '42501', null, 'anon: cannot select global timeline view');
select throws_ok($$select count(*) from public.v_my_people$$, '42501', null, 'anon: cannot select global people view');
select pg_temp.logout();

select pg_temp.login('aa000000-0000-0000-0000-000000000001','a-global@t.co');
select is((select count(*)::int from public.v_my_timeline_events where project_id in ('91000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000002')), 4, 'A: calendar sees events from both shared projects');
select is((select count(*)::int from public.v_my_timeline_events where project_id='93000000-0000-0000-0000-000000000003'), 0, 'A: calendar excludes inaccessible project');
select is((select count(*)::int from public.v_my_timeline_events where title='B unscheduled'), 0, 'A: calendar excludes missing dates');
select is((select amount_minor::int from public.v_my_timeline_events where event_type='payment_due' and subject_id='94440000-0000-0000-0000-000000000001'), 1200, 'A: payment amount is exposed for payment timeline event');
select is((select project_count from public.v_my_people where user_id='bb000000-0000-0000-0000-000000000002'), 2, 'A: same authenticated user is deduplicated by user_id');
select is((select count(*)::int from public.v_my_people where display_name='Alex'), 2, 'A: same-name name-only members remain distinct');
select is((select count(*)::int from public.v_my_people where user_id='cc000000-0000-0000-0000-000000000003'), 0, 'A: people excludes inaccessible project members');
select ok((select is_current_user from public.v_my_people where user_id='aa000000-0000-0000-0000-000000000001'), 'A: current user is labelled by read model');
select pg_temp.logout();

select pg_temp.login('bb000000-0000-0000-0000-000000000002','b-global@t.co');
select is((select count(*)::int from public.v_my_timeline_events where project_id='92000000-0000-0000-0000-000000000002'), 2, 'B viewer: readable project events appear');
select pg_temp.logout();

select * from finish();
rollback;
