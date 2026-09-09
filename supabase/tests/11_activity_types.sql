-- pgTAP: activity types persist separately from category and drive non-booking transitions.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','aa110000-0000-0000-0000-000000000011','authenticated','authenticated','activity-a@t.co','{}','{"display_name":"Activity A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb110000-0000-0000-0000-000000000011','authenticated','authenticated','activity-b@t.co','{}','{"display_name":"Activity B"}',now(),now(),'','','','');

select pg_temp.login('aa110000-0000-0000-0000-000000000011','activity-a@t.co');
create temporary table pg_temp.ctx as
select public.create_project('Activity types','UTC','GBP',null,null,'team_project') as project_id;

insert into public.commitments (project_id, title, kind, activity_type, status)
select project_id, 'Set up social media pages', 'other', 'task', 'idea' from pg_temp.ctx;

insert into public.commitments (project_id, title, kind, activity_type, status, supplier_name, booking_reference, booking_confirmed)
select project_id, 'Book hotel', 'accommodation', 'booking', 'researching', 'Hotel Ltd', 'HOTEL-1', true from pg_temp.ctx;

insert into public.commitments (project_id, title, kind, activity_type, status, supplier_name, estimated_cost_minor)
select project_id, 'Buy microphones', 'services', 'purchase', 'researching', 'Audio Shop', 30000 from pg_temp.ctx;

insert into public.commitments (project_id, title, kind, activity_type, status, starts_at, ends_at, location_label)
select project_id, 'Launch party', 'experience', 'event', 'researching', now(), now() + interval '2 hours', 'Manchester' from pg_temp.ctx;

insert into public.commitments (project_id, title, kind, status)
select project_id, 'Legacy-style activity', 'other', 'researching' from pg_temp.ctx;

select set_eq(
  $$select activity_type::text from public.commitments where title in ('Set up social media pages','Book hotel','Buy microphones','Launch party')$$,
  $$values ('task'), ('booking'), ('purchase'), ('event')$$,
  'activity types persist separately from category'
);

select is(
  (select activity_type::text from public.commitments where title = 'Legacy-style activity'),
  'other',
  'omitted activity type defaults to other'
);

select is(
  (select kind::text from public.commitments where title = 'Buy microphones'),
  'services',
  'category remains the existing kind field'
);

update public.commitments
set status = 'completed'
where title = 'Set up social media pages';

select is(
  (select status::text from public.commitments where title = 'Set up social media pages'),
  'completed',
  'task can complete without booked status'
);

update public.commitments
set status = 'researching'
where title = 'Set up social media pages';

select is(
  (select status::text from public.commitments where title = 'Set up social media pages'),
  'researching',
  'task can reopen to in-progress state'
);

select throws_ok(
  $$update public.commitments set status = 'completed' where title = 'Book hotel'$$,
  'P0001',
  null,
  'booking still follows booking lifecycle and cannot skip booked'
);

select is(
  (select count(*)::int from public.get_project_health((select project_id from pg_temp.ctx))
   where code = 'missing_booking_reference' and subject_label = 'Set up social media pages'),
  0,
  'non-booking activity does not receive missing booking reference warning'
);

select pg_temp.login('bb110000-0000-0000-0000-000000000011','activity-b@t.co');
select is(
  (select count(*)::int from public.commitments where project_id = (select project_id from pg_temp.ctx)),
  0,
  'non-member cannot read activity types'
);

select * from finish();
rollback;
