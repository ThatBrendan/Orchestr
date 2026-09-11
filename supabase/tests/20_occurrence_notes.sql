begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;
create function pg_temp.wc(sql text) returns int language plpgsql as $$
declare n int; begin execute sql; get diagnostics n = row_count; return n; end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','aa120000-0000-0000-0000-000000000012','authenticated','authenticated','notes-a@t.co','{}','{"display_name":"Notes A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb120000-0000-0000-0000-000000000012','authenticated','authenticated','notes-b@t.co','{}','{"display_name":"Notes B"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','cc120000-0000-0000-0000-000000000012','authenticated','authenticated','notes-c@t.co','{}','{"display_name":"Notes C"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','dd120000-0000-0000-0000-000000000012','authenticated','authenticated','notes-d@t.co','{}','{"display_name":"Notes D"}',now(),now(),'','','','');

select pg_temp.login('aa120000-0000-0000-0000-000000000012','notes-a@t.co');
create temporary table pg_temp.ctx as
select public.create_project('Project notes','UTC','GBP',null,null,'team_project') as project_id;

insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'bb120000-0000-0000-0000-000000000012', 'Notes B', 'member' from pg_temp.ctx;
insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'cc120000-0000-0000-0000-000000000012', 'Notes C', 'viewer' from pg_temp.ctx;

create temporary table pg_temp.series as
with added as (
 insert into public.commitments(project_id,title,kind,activity_type,notes,recurrence_frequency,recurrence_interval,recurrence_start_date)
 select project_id,'Outreach','other','task','Contact 20 creators.','weekly',1,current_date-14 from pg_temp.ctx returning id
) select id from added;
select lives_ok($$select public.save_commitment_occurrence_note((select id from pg_temp.series),current_date-14,'Messaged 18.')$$,'Organizer saves occurrence note');
select is((select count(*)::int from app._recurring_health_findings((select project_id from pg_temp.ctx))),2,'Note alone does not resolve an overdue occurrence');
select lives_ok($$select public.complete_commitment_occurrence((select id from pg_temp.series),current_date-14)$$,'Complete without changing note');
select pg_temp.login('bb120000-0000-0000-0000-000000000012','notes-b@t.co');
select lives_ok($$select public.save_commitment_occurrence_note((select id from pg_temp.series),current_date-7,'Only 10.')$$,'Member saves distinct note');
select lives_ok($$select public.skip_commitment_occurrence((select id from pg_temp.series),current_date-7,'Waiting for shortlist')$$,'Member skips exactly one date');
select is((select note from public.commitment_occurrences where commitment_id=(select id from pg_temp.series) and occurrence_date=current_date-14),'Messaged 18.','First note preserved after completion');
select is((select note from public.commitment_occurrences where commitment_id=(select id from pg_temp.series) and occurrence_date=current_date-7),'Only 10.','Second note distinct after skip');
select is((select notes from public.commitments where id=(select id from pg_temp.series)),'Contact 20 creators.','Series instructions unchanged');
select is((select skip_reason from public.commitment_occurrences where commitment_id=(select id from pg_temp.series) and occurrence_date=current_date-7),'Waiting for shortlist','Skip reason persisted');
select is((select status from public.get_commitment_occurrences((select id from pg_temp.series),current_date,current_date)),'upcoming','Next occurrence stays upcoming');
select is((select count(*)::int from app._recurring_health_findings((select project_id from pg_temp.ctx))),0,'Completed and skipped dates are not overdue findings');
select is((select status from public.get_project_timeline_events((select project_id from pg_temp.ctx),(current_date-7)::timestamptz,(current_date-6)::timestamptz) where occurrence_date=current_date-7),'skipped','Timeline retains skipped state');
select is((select status from public.get_my_timeline_events((current_date-7)::timestamptz,(current_date-6)::timestamptz) where subject_id=(select id from pg_temp.series) and occurrence_date=current_date-7),'skipped','Calendar retains skipped state');
select throws_ok($$select public.skip_commitment_occurrence((select id from pg_temp.series),current_date,' ')$$,'23514',null,'Blank reason rejected');
select throws_ok($$select public.skip_commitment_occurrence((select id from pg_temp.series),current_date,repeat('x',501))$$,'23514',null,'Long reason rejected');
select throws_ok($$select public.save_commitment_occurrence_note((select id from pg_temp.series),current_date,repeat('x',10001))$$,'23514',null,'Long note rejected');
select lives_ok($$select public.save_commitment_occurrence_note((select id from pg_temp.series),current_date,'Upcoming note')$$,'Note-only upcoming row supported');
select lives_ok($$select public.save_commitment_occurrence_note((select id from pg_temp.series),current_date,null)$$,'Clear note');
select ok((select note is null and status is null from public.commitment_occurrences where commitment_id=(select id from pg_temp.series) and occurrence_date=current_date),'Clear preserves upcoming state');
select throws_ok($$select public.save_commitment_occurrence_note((select id from pg_temp.series),current_date+1,'Invalid')$$,'22023',null,'Nonoccurrence date rejected');
select is((select count(*)::int from public.commitment_occurrences where commitment_id=(select id from pg_temp.series) and occurrence_date=current_date),1,'Upsert keeps one logical state row');
select pg_temp.login('cc120000-0000-0000-0000-000000000012','notes-c@t.co');
select throws_ok($$select public.save_commitment_occurrence_note((select id from pg_temp.series),current_date,'Viewer')$$,'42501',null,'Viewer cannot edit note');
select throws_ok($$select public.skip_commitment_occurrence((select id from pg_temp.series),current_date,'Waiting for shortlist')$$,'42501',null,'Viewer cannot skip');
select throws_ok($$select public.complete_commitment_occurrence((select id from pg_temp.series),current_date)$$,'42501',null,'Viewer cannot complete');
select pg_temp.login('dd120000-0000-0000-0000-000000000012','notes-d@t.co');
select throws_ok($$select public.save_commitment_occurrence_note((select id from pg_temp.series),current_date,'Outside')$$,'42501',null,'Nonmember cannot mutate');
select is((select count(*)::int from public.get_commitment_occurrences((select id from pg_temp.series),current_date-14,current_date)),0,'Project isolation for occurrence reads');
select pg_temp.login('aa120000-0000-0000-0000-000000000012','notes-a@t.co');
select lives_ok($$select public.save_commitment_occurrence_note((select id from pg_temp.series),current_date+7,'Future context')$$,'Future note stored lazily');
select lives_ok($$select public.stop_commitment_recurrence((select id from pg_temp.series),current_date)$$,'Stop recurrence');
select is((select count(*)::int from public.get_commitment_occurrences((select id from pg_temp.series),current_date+1,current_date+30)),0,'No future derived dates after stop');
select is((select note from public.commitment_occurrences where commitment_id=(select id from pg_temp.series) and occurrence_date=current_date-14),'Messaged 18.','Stop preserves historical note');
select is((select skip_reason from public.commitment_occurrences where commitment_id=(select id from pg_temp.series) and occurrence_date=current_date-7),'Waiting for shortlist','Stop preserves historical reason');
select is((select note from public.commitment_occurrences where commitment_id=(select id from pg_temp.series) and occurrence_date=current_date+7),'Future context','Stop does not delete stored notes');
update public.projects set status='archived' where id=(select project_id from pg_temp.ctx);
select throws_ok($$select public.save_commitment_occurrence_note((select id from pg_temp.series),current_date,'Archived')$$,'42501',null,'Archived note writes rejected');
select * from finish();
rollback;
