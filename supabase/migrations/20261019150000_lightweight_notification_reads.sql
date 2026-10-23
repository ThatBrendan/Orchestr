-- Render notification history without loading full target financial read models.
-- Source authorization and lifecycle visibility remain enforced for every call.
create function app.notification_visible(p_notification uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare n public.notifications%rowtype; r public.reimbursement_requests%rowtype; a public.reimbursement_payment_acknowledgements%rowtype;
begin
 select * into n from public.notifications where id=p_notification and recipient_user_id=auth.uid();
 if not found or not exists(select 1 from public.projects where id=n.project_id and deleted_at is null) then return false;end if;
 if not app.is_member(n.project_id) then return false;end if;
 case n.kind
 when 'activity_created' then
  return exists(select 1 from public.commitments where id=n.commitment_id and project_id=n.project_id and deleted_at is null);
 when 'activity_due_soon' then
  return exists(select 1 from public.commitments where id=n.activity_reminder_id and project_id=n.project_id and deleted_at is null and status<>'cancelled');
 when 'project_join_requested' then return app.is_organizer(n.project_id);
 when 'project_member_approved' then return true;
 when 'decision_deadline_reached','decision_resolved' then
  return exists(select 1 from public.decisions d where d.id=n.decision_id and d.project_id=n.project_id and d.deleted_at is null and (n.kind='decision_resolved' or d.created_by=auth.uid() or app.is_organizer(n.project_id)));
 when 'payment_due_soon' then
  return exists(select 1 from public.activity_payment_schedules s join public.commitments c on c.id=s.commitment_id where s.id=n.payment_schedule_id and s.project_id=n.project_id and s.deleted_at is null and c.deleted_at is null);
 when 'reimbursement_created','reimbursement_payment_acknowledged','reimbursement_payment_acknowledgement_withdrawn','reimbursement_receipt_confirmed' then
  if not app.can_read_reimbursement(n.reimbursement_id) then return false;end if;
  select * into r from public.reimbursement_requests where id=n.reimbursement_id and project_id=n.project_id;
  if not found then return false;end if;
  if n.kind='reimbursement_receipt_confirmed' then return true;end if;
  if r.status<>'open' then return false;end if;
  if n.kind='reimbursement_created' then return not exists(select 1 from public.reimbursement_payment_acknowledgements where reimbursement_request_id=r.id and withdrawn_at is null);end if;
  select * into a from public.reimbursement_payment_acknowledgements where id=n.payment_acknowledgement_id and reimbursement_request_id=r.id;
  if not found then return false;end if;
  if n.kind='reimbursement_payment_acknowledged' then return a.withdrawn_at is null;end if;
  return a.withdrawn_at is not null and not exists(select 1 from public.reimbursement_payment_acknowledgements newer where newer.reimbursement_request_id=r.id and (newer.acknowledged_at,newer.id)>(a.acknowledged_at,a.id));
 else return false;
 end case;
end $$;
revoke all on function app.notification_visible(uuid) from public,anon,service_role;
grant execute on function app.notification_visible(uuid) to authenticated;

create function app.notification_summary(p_notification uuid)
returns table(category text,resource_type text,resource_id uuid,section text,title text,body text)
language plpgsql stable security definer set search_path='' rows 1 as $$
declare n public.notifications%rowtype; p public.projects%rowtype; c public.commitments%rowtype; r public.reimbursement_requests%rowtype; d public.decisions%rowtype; s public.activity_payment_schedules%rowtype; person text; selected_title text;
begin
 if not app.notification_visible(p_notification) then return;end if;
 select * into strict n from public.notifications where id=p_notification and recipient_user_id=auth.uid();
 select * into strict p from public.projects where id=n.project_id;
 case n.kind
 when 'activity_created','activity_due_soon' then
  select * into strict c from public.commitments where id=coalesce(n.commitment_id,n.activity_reminder_id);
  category:='activities';resource_type:='activity';resource_id:=c.id;
  if n.kind='activity_created' then title:='New activity';body:=c.title||' was added to '||p.name||'.';
  else title:='Activity coming up';body:=c.title||' — '||to_char(c.starts_at at time zone p.timezone,'FMDD Month YYYY');end if;
 when 'project_join_requested','project_member_approved' then
  category:='project_access';resource_type:='project';resource_id:=p.id;body:=p.name;
  if n.kind='project_join_requested' then section:='people';title:='New project access request';else title:='Your access was approved';end if;
 when 'decision_deadline_reached','decision_resolved' then
  select * into strict d from public.decisions where id=n.decision_id;
  category:='decisions';resource_type:='decision';resource_id:=d.id;
  if n.kind='decision_resolved' then
   select o.title into selected_title from public.decision_options o where o.id=d.resolved_option_id;
   title:='Decision resolved';body:=d.title||' — '||coalesce(selected_title,'An option')||' was selected.';
  else title:='Voting closed';body:=d.title||' — Ready to resolve.';end if;
 when 'payment_due_soon' then
  select * into strict s from public.activity_payment_schedules where id=n.payment_schedule_id;
  category:='payments';resource_type:='activity';resource_id:=s.commitment_id;section:='payments';
  title:='Payment reminder';body:=s.title||' — Due '||to_char(s.due_on,'FMDD Month YYYY');
 when 'reimbursement_created','reimbursement_payment_acknowledged','reimbursement_payment_acknowledgement_withdrawn','reimbursement_receipt_confirmed' then
  select * into strict r from public.reimbursement_requests where id=n.reimbursement_id;
  select * into strict c from public.commitments where id=r.commitment_id;
  category:='reimbursements';resource_type:='activity';resource_id:=r.commitment_id;section:='reimbursements';
  select coalesce(u.display_name,m.display_name) into person from public.project_members m left join public.users u on u.id=m.user_id where m.id=case when n.kind in('reimbursement_payment_acknowledged','reimbursement_payment_acknowledgement_withdrawn') then r.debtor_member_id else r.creditor_member_id end;
  body:=c.title||' — '||person;
  case n.kind
   when 'reimbursement_created' then title:='Reimbursement requested';
   when 'reimbursement_payment_acknowledged' then title:='Payment marked as sent';
   when 'reimbursement_payment_acknowledgement_withdrawn' then title:='Payment claim withdrawn';
   else
    if exists(select 1 from public.reimbursement_receipt_confirmations f join public.payments pay on pay.settlement_group_id=f.settlement_group_id where f.reimbursement_request_id=r.id and pay.status='cancelled') then title:='Settlement reversed';else title:='Reimbursement settled';end if;
  end case;
 else return;
 end case;
 return next;
end $$;
revoke all on function app.notification_summary(uuid) from public,anon,service_role;
grant execute on function app.notification_summary(uuid) to authenticated;

create or replace view public.v_my_notification_inbox with(security_invoker=true) as
 select n.id,n.project_id,n.created_at,n.read_at,n.kind,s.category,s.resource_type,s.resource_id,s.section,s.title,s.body
 from public.notifications n cross join lateral app.notification_summary(n.id) s
 where n.recipient_user_id=(select auth.uid());

create function public.get_my_notification_unread_state() returns boolean
-- Zero arguments: the caller cannot select another identity. The same visibility
-- guard as the inbox enforces recipient, membership and live-source authorization.
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.notifications n where n.recipient_user_id=(select auth.uid()) and n.read_at is null and app.notification_visible(n.id));
$$;
revoke all on function public.get_my_notification_unread_state() from public,anon,service_role;
grant execute on function public.get_my_notification_unread_state() to authenticated;
