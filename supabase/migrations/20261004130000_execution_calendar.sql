-- Phase 12 is a read projection. No tables, triggers, events or source mutations.
create function public.get_project_calendar(p_project uuid, p_range_start date, p_range_end date)
returns table (
 entry_id text, source_type text, source_id uuid, project_id uuid, title text,
 start_at timestamptz, end_at timestamptz, start_date date, end_date date,
 all_day boolean, status text, activity_id uuid, activity_title text,
 activity_type text, category_name text, assigned_member text,
 amount_minor bigint, currency_code text, occurrence_date date
)
language plpgsql stable security invoker set search_path='' as $$
begin
 if p_range_start is null or p_range_end is null or not isfinite(p_range_start) or not isfinite(p_range_end)
 or p_range_end <= p_range_start or p_range_end-p_range_start > 62 then
  raise exception 'Calendar range must be between 1 and 62 days.' using errcode='22023';
 end if;
 return query
 with project as (
  select p.id,p.timezone,p.currency,
   p_range_start::timestamp at time zone p.timezone lo,
   p_range_end::timestamp at time zone p.timezone hi
  from public.projects p where p.id=p_project and p.deleted_at is null and app.is_member(p.id)
 ), activities as (
  select c.*,a.title category,m.display_name assignee,p.timezone,p.currency,p.lo,p.hi
  from public.commitments c join project p on p.id=c.project_id
  left join public.project_areas a on a.id=c.area_id
  left join public.project_members m on m.id=c.owner_member_id
  where c.deleted_at is null and c.status<>'cancelled'
 )
 select 'activity:'||c.id,'activity',c.id,c.project_id,c.title,
  case when not c.is_all_day then c.starts_at end,case when not c.is_all_day then c.ends_at end,
  case when c.is_all_day then (c.starts_at at time zone c.timezone)::date end,
  case when c.is_all_day then (c.ends_at at time zone c.timezone)::date end,
  c.is_all_day,c.status::text,c.id,c.title,c.activity_type::text,c.category,c.assignee,
  null::bigint,null::text,null::date
 from activities c where c.recurrence_frequency is null and c.starts_at<c.hi
 and (c.starts_at>=c.lo or case when c.is_all_day then (c.ends_at at time zone c.timezone)::date>=p_range_start else c.ends_at>c.lo end)
 union all
 select 'occurrence:'||c.id||':'||rd.occurrence_date,'activity_occurrence',c.id,c.project_id,c.title,
  null::timestamptz,null::timestamptz,rd.occurrence_date,null::date,true,
  coalesce(co.status::text,case when rd.occurrence_date<(statement_timestamp() at time zone c.timezone)::date then 'overdue' else 'upcoming' end),
  c.id,c.title,c.activity_type::text,c.category,c.assignee,null::bigint,null::text,rd.occurrence_date
 from activities c
 cross join lateral app.recurrence_dates(c.recurrence_frequency,c.recurrence_interval,c.recurrence_start_date,c.recurrence_end_date,p_range_start,p_range_end-1) rd
 left join public.commitment_occurrences co on co.commitment_id=c.id and co.occurrence_date=rd.occurrence_date
 where c.recurrence_frequency is not null
 union all
 select 'decision:'||d.id,'decision',d.id,d.project_id,d.title,d.voting_deadline,null::timestamptz,
  null::date,null::date,false,
  case when d.status='resolved' then 'resolved' when d.voting_deadline<=statement_timestamp() then 'voting_closed' else 'open' end,
  null::uuid,null::text,null::text,null::text,null::text,null::bigint,null::text,null::date
 from public.decisions d join project p on p.id=d.project_id
 where d.deleted_at is null and d.voting_deadline>=p.lo and d.voting_deadline<p.hi
 union all
 select 'payment_schedule:'||s.payment_schedule_id,'payment_schedule',s.payment_schedule_id,s.project_id,s.title,
  null::timestamptz,null::timestamptz,s.due_on,null::date,true,
  case when s.outstanding_minor=0 then 'paid' when s.net_paid_minor>0 then 'part_paid'
   when s.due_on<(statement_timestamp() at time zone c.timezone)::date then 'overdue' else 'upcoming' end,
  c.id,c.title,c.activity_type::text,c.category,c.assignee,s.scheduled_amount_minor,c.currency,null::date
 from public.v_activity_payment_schedule_financials s join activities c on c.id=s.commitment_id
 where s.due_on>=p_range_start and s.due_on<p_range_end;
end $$;
revoke all on function public.get_project_calendar(uuid,date,date) from public,anon,service_role;
grant execute on function public.get_project_calendar(uuid,date,date) to authenticated;
comment on function public.get_project_calendar(uuid,date,date) is 'Read-only execution dates from RLS-protected authorities; [start,end) project-local date range, at most 62 days.';
