begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.login(n int) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',json_build_object('sub',('aa000000-0000-0000-0000-'||lpad(n::text,12,'0')),'role','authenticated')::text,true);
end $$;
create function pg_temp.logout() returns void language plpgsql as $$
begin perform set_config('role','postgres',true); perform set_config('request.jwt.claims','',true); end $$;
insert into auth.users(id,email,raw_user_meta_data) select
 ('aa000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid, 'invite-test-'||n||'@example.com', '{"display_name":"Test"}'::jsonb
 from generate_series(1,5) n;
insert into public.projects(id,name,timezone,currency) values('ab000000-0000-0000-0000-000000000001','Invitation test','UTC','GBP');
insert into public.project_members(project_id,user_id,display_name,email,role) select
 'ab000000-0000-0000-0000-000000000001',id,display_name,email,
 case when email='invite-test-1@example.com' then 'organizer'::public.member_role else 'viewer'::public.member_role end
 from public.users where email in ('invite-test-1@example.com','invite-test-3@example.com');
update public.users set platform_role='admin' where email='invite-test-4@example.com';
select pg_temp.login(1);
select lives_ok($$select public.create_invitation('ab000000-0000-0000-0000-000000000001',' Invite-Test-2@example.com ','member')$$,'Organizer creates Member invitation');
select lives_ok($$select public.create_invitation('ab000000-0000-0000-0000-000000000001','future@example.com','viewer')$$,'Organizer creates Viewer invitation for future signup');
select throws_ok($$select public.create_invitation('ab000000-0000-0000-0000-000000000001','invite-test-2@example.com','member')$$,'P0001',null,'Duplicate normalized pending email rejected');
select throws_ok($$select public.create_invitation('ab000000-0000-0000-0000-000000000001','invite-test-3@example.com','member')$$,'P0001',null,'Existing membership detected');
select throws_ok($$select public.create_invitation('ab000000-0000-0000-0000-000000000001','x@example.com','organizer')$$,'P0001',null,'Cannot invite organizer');
select pg_temp.login(3);
select throws_ok($$select public.create_invitation('ab000000-0000-0000-0000-000000000001','x@example.com','member')$$,'42501',null,'Viewer cannot invite');
select pg_temp.login(5);
select throws_ok($$select public.create_invitation('ab000000-0000-0000-0000-000000000001','x@example.com','member')$$,'42501',null,'Nonmember cannot invite');
select pg_temp.login(4);
select throws_ok($$select public.create_invitation('ab000000-0000-0000-0000-000000000001','x@example.com','member')$$,'42501',null,'Platform admin cannot bypass project membership');
select is((select count(*)::int from public.list_my_invitations()),0,'Other emails see no pending notifications');
select pg_temp.logout();
create temporary table invitation_tokens as select email,token from public.invitations where project_id='ab000000-0000-0000-0000-000000000001';
grant select on invitation_tokens to authenticated;
select pg_temp.login(5);
select throws_ok($$select public.accept_invitation((select token from invitation_tokens where email='invite-test-2@example.com'))$$,'P0001',null,'Wrong email cannot accept');
select pg_temp.login(2);
select is((select count(*)::int from public.list_my_invitations()),1,'Existing account discovers invitation');
select lives_ok($$select public.decline_invitation((select token from invitation_tokens where email='invite-test-2@example.com'))$$,'Correct email declines');
select is((select count(*)::int from public.list_my_invitations()),0,'Decline resolves notification');
select pg_temp.logout();
select is((select count(*)::int from public.project_members where user_id='aa000000-0000-0000-0000-000000000002'),0,'Decline creates no membership');
select pg_temp.login(1);
select lives_ok($$select public.create_invitation('ab000000-0000-0000-0000-000000000001','invite-test-2@example.com','member')$$,'Organizer can reinvite after decline');
select pg_temp.logout();
update invitation_tokens set token=(select token from public.invitations where email='invite-test-2@example.com' and status='pending') where email='invite-test-2@example.com';
select pg_temp.login(2);
select lives_ok($$select public.accept_invitation((select token from invitation_tokens where email='invite-test-2@example.com'))$$,'Correct email accepts');
select throws_ok($$select public.accept_invitation((select token from invitation_tokens where email='invite-test-2@example.com'))$$,'P0001',null,'Accepted invitation cannot be accepted twice');
select is((select role::text from public.project_members where user_id=auth.uid() and project_id='ab000000-0000-0000-0000-000000000001'),'member','Accept uses invited Member role');
select throws_ok($$select public.create_invitation('ab000000-0000-0000-0000-000000000001','x@example.com','member')$$,'42501',null,'Member cannot invite');
select pg_temp.logout();
insert into auth.users(id,email,raw_user_meta_data) values('aa000000-0000-0000-0000-000000000006','future@example.com','{"display_name":"Future"}');
select pg_temp.login(6);
select is((select count(*)::int from public.list_my_invitations()),1,'Future signup discovers email invitation');
select lives_ok($$select public.accept_invitation((select token from public.list_my_invitations() limit 1))$$,'Future account accepts Viewer invitation');
select is((select role::text from public.project_members where user_id=auth.uid() and project_id='ab000000-0000-0000-0000-000000000001'),'viewer','Accept uses invited Viewer role');
select throws_ok($$insert into public.tasks(project_id,title) values('ab000000-0000-0000-0000-000000000001','Forbidden')$$,'42501',null,'Viewer cannot create task');
select pg_temp.logout();
set local role anon;
select throws_ok($$select public.create_invitation('ab000000-0000-0000-0000-000000000001','x@example.com','member')$$,'42501',null,'Anonymous cannot invite');
select pg_temp.logout();
select * from finish();
rollback;
