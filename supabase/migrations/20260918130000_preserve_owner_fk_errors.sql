-- Preserve the existing composite-FK error for cross-project owners while
-- retaining the IA migration's active-member validation for same-project rows.
create or replace function app.tg_commitment_owner_role_check()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.owner_member_id is not null
    and exists(select 1 from public.project_members where id=new.owner_member_id and project_id=new.project_id)
    and not exists(select 1 from public.project_members where id=new.owner_member_id and project_id=new.project_id and status='active' and deleted_at is null) then
   raise exception 'orchestr:invalid_owner:Select an active project member.';
 end if;
 return new;
end $$;
revoke execute on function app.tg_commitment_owner_role_check() from public;
