begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values ('00000000-0000-0000-0000-000000000000','aa280000-0000-0000-0000-000000000028','authenticated','authenticated','names-a@t.co','{}','{"display_name":"Test User"}',now(),now(),'','','','');
select pg_temp.login('aa280000-0000-0000-0000-000000000028','names-a@t.co');
create temporary table pg_temp.ctx as select public.create_project('Name sync','UTC','GBP',null,null,'team_project') as project_id;
select is((select display_name from public.v_member_directory where project_id=(select project_id from pg_temp.ctx) and status='active'),'Test User','Initial linked member name');
update public.users set display_name='Sarah Jones' where id=auth.uid();
select is((select display_name from public.v_member_directory where project_id=(select project_id from pg_temp.ctx) and status='active'),'Sarah Jones','Project directory uses current profile name');
select is((select display_name from public.v_my_people where user_id=auth.uid()),'Sarah Jones','Global people uses current profile name');
select * from finish();
rollback;