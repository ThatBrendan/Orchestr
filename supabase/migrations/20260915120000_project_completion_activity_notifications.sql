-- Project completion retains the existing status graph, RLS and writable semantics.
-- Historical project health stays available through project-specific RPCs.
-- Activity insert + fan-out is atomic: an error rolls back both, never partial delivery.

create or replace view public.v_my_projects
with (security_invoker = true) as
select
  pr.id as project_id,
  pr.name, pr.status, pr.starts_on, pr.ends_on, pr.timezone, pr.currency,
  me.role as my_role,
  fin.total_cost_minor, fin.committed_spend_minor, fin.net_actual_spend_minor,
  fin.outstanding_minor, fin.remaining_budget_minor, fin.progress_pct,
  h.status as health_status, coalesce(h.attention_count, 0)::integer as attention_count,
  (select min(occurs_at) from public.v_timeline_events te
    where te.project_id = pr.id and te.occurs_at >= now()) as next_event_at,
  fin.total_target_minor,
  pr.profile,
  pr.module_visibility
from public.projects pr
join public.project_members me
  on me.project_id = pr.id and me.user_id = auth.uid()
 and me.status = 'active' and me.deleted_at is null
left join public.v_project_financials fin on fin.project_id = pr.id
left join lateral public.get_project_health_summary(pr.id) h on pr.status in ('draft', 'active')
where pr.deleted_at is null;

grant select on public.v_my_projects to authenticated;


create or replace function public.get_my_attention()
returns table (
  project_id uuid,
  project_name text,
  code text,
  severity text,
  subject_type text,
  subject_id uuid,
  subject_label text,
  params jsonb,
  message text,
  resolution text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    p.id            as project_id,
    p.name          as project_name,
    f.code, f.severity, f.subject_type, f.subject_id, f.subject_label,
    f.params, f.message, f.resolution
  from public.projects p
  join public.project_members m
    on m.project_id = p.id
   and m.user_id = auth.uid()
   and m.status = 'active'
   and m.deleted_at is null
  cross join lateral app._health_findings(p.id) f
  left join public.finding_dismissals d
    on d.project_id = p.id
   and d.code = f.code
   and d.subject_type = f.subject_type
   and d.subject_id is not distinct from f.subject_id
  where p.deleted_at is null
    and p.status in ('draft', 'active')
    and f.severity in ('blocker', 'warning')
    and case
          when not f.dismissible then false
          when d.state = 'dismissed' then true
          when d.state = 'snoozed'
            and d.snoozed_until >= (now() at time zone p.timezone)::date then true
          else false
        end = false
  order by
    case f.severity when 'blocker' then 0 else 1 end,
    p.name,
    f.subject_label;
$$;

revoke execute on function public.get_my_attention() from public;
grant execute on function public.get_my_attention() to authenticated;

create or replace function app.tg_audit_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project   uuid;
  v_action    public.audit_action;
  v_before    jsonb;
  v_after     jsonb;
  v_old_del   text;
  v_new_del   text;
  v_member    uuid;
begin
  if tg_op = 'INSERT' then
    v_after  := to_jsonb(new);
    v_before := null;
    v_action := 'create';
    v_project := nullif(v_after->>'project_id','')::uuid;
  elsif tg_op = 'DELETE' then
    v_before := to_jsonb(old);
    v_after  := null;
    v_action := 'delete';
    v_project := nullif(v_before->>'project_id','')::uuid;
  else
    v_before := to_jsonb(old);
    v_after  := to_jsonb(new);
    v_project := nullif(v_after->>'project_id','')::uuid;
    v_old_del := v_before->>'deleted_at';
    v_new_del := v_after->>'deleted_at';
    if v_before ? 'deleted_at' and v_old_del is null and v_new_del is not null then
      v_action := 'soft_delete';
    elsif v_before ? 'deleted_at' and v_old_del is not null and v_new_del is null then
      v_action := 'restore';
    else
      v_action := 'update';
    end if;
  end if;

  -- Project rows carry their own ID rather than a project_id column.
  if tg_table_name = 'projects' then
    v_project := coalesce(v_after->>'id', v_before->>'id')::uuid;
  end if;

  if v_project is not null then
    begin
      v_member := app.current_member_id(v_project);
    exception when others then
      v_member := null;
    end;
  end if;

  insert into public.audit_log
    (project_id, actor_user_id, actor_member_id, source, action, entity_type, entity_id, before, after)
  values
    (v_project, auth.uid(), v_member, 'app', v_action, tg_table_name,
     coalesce((v_after->>'id'), (v_before->>'id'),
              (v_after->>'project_id'), (v_before->>'project_id'))::uuid,   -- budgets/targets have no `id`
     v_before, v_after);

  return coalesce(new, old);
end;
$$;

revoke execute on function app.tg_audit_row() from public;


-- Extend the existing in-app bell. No email, webhooks, or assignment fan-out.
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  commitment_id uuid not null,
  recipient_user_id uuid not null references public.users(id) on delete cascade,
  kind text not null default 'activity_created' check (kind = 'activity_created'),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint notifications_activity_fk foreign key (project_id, commitment_id)
    references public.commitments(project_id, id) on delete cascade,
  constraint notifications_recipient_activity_kind_key unique (recipient_user_id, commitment_id, kind)
);
create index notifications_unread_recipient_idx
  on public.notifications(recipient_user_id, created_at desc) where read_at is null;
create index notifications_project_activity_idx on public.notifications(project_id, commitment_id);
alter table public.notifications enable row level security;
revoke all on public.notifications from public, anon, authenticated;
grant select, update(read_at) on public.notifications to authenticated;
grant all on public.notifications to service_role;

-- Removing membership or deleting an Activity/project revokes inbox visibility too.
create policy notifications_read_own on public.notifications for select to authenticated
using (
  recipient_user_id = (select auth.uid()) and app.is_member(project_id)
  and exists (select 1 from public.projects p where p.id = project_id and p.deleted_at is null)
  and exists (select 1 from public.commitments c where c.id = commitment_id and c.deleted_at is null)
);
create policy notifications_mark_own on public.notifications for update to authenticated
using (recipient_user_id = (select auth.uid()) and app.is_member(project_id))
with check (recipient_user_id = (select auth.uid()) and app.is_member(project_id));

create or replace function app.tg_activity_created_notifications()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_creator uuid;
begin
  if new.deleted_at is not null then return new; end if;
  -- The actual authenticated creator wins over caller-supplied created_by.
  v_creator := coalesce(auth.uid(), (select m.user_id from public.project_members m
    where m.project_id = new.project_id and m.id = new.created_by));
  insert into public.notifications(project_id, commitment_id, recipient_user_id)
  select new.project_id, new.id, m.user_id
  from public.project_members m
  where m.project_id = new.project_id and m.status = 'active'
    and m.deleted_at is null and m.user_id is not null
    and m.user_id is distinct from v_creator
  on conflict (recipient_user_id, commitment_id, kind) do nothing;
  return new;
end;
$$;
revoke all on function app.tg_activity_created_notifications() from public, anon, authenticated;
create trigger activity_created_notifications after insert on public.commitments
for each row execute function app.tg_activity_created_notifications();

-- Uses the same project/Activity authorization as normal deep links.
create view public.v_my_activity_notifications with (security_invoker = true) as
select n.id, n.project_id, n.commitment_id, n.created_at, n.read_at,
       c.title as activity_title, p.name as project_name
from public.notifications n
join public.commitments c on c.id = n.commitment_id and c.project_id = n.project_id
join public.projects p on p.id = n.project_id
where n.recipient_user_id = auth.uid() and app.is_member(n.project_id)
  and c.deleted_at is null and p.deleted_at is null;
revoke all on public.v_my_activity_notifications from public, anon, authenticated;
grant select on public.v_my_activity_notifications to authenticated;

create function public.mark_notification_read(p_notification uuid)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_id uuid;
begin
  update public.notifications set read_at = coalesce(read_at, now())
  where id = p_notification and recipient_user_id = auth.uid()
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.mark_notification_read(uuid) from public, anon;
grant execute on function public.mark_notification_read(uuid) to authenticated;
