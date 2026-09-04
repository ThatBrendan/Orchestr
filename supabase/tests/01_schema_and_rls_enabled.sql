-- pgTAP: schema objects exist and RLS is enabled + forced everywhere.
-- Run: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(28);

-- enums
select has_type('public','project_status','project_status enum');
select has_type('public','commitment_status','commitment_status enum');
select has_type('public','payment_status','payment_status enum');
select has_type('public','member_role','member_role enum');

-- tables
select has_table('public','users');
select has_table('public','projects');
select has_table('public','project_members');
select has_table('public','invitations');
select has_table('public','commitments');
select has_table('public','commitment_participants');
select has_table('public','cost_shares');
select has_table('public','payments');
select has_table('public','tasks');
select has_table('public','milestones');
select has_table('public','budgets');
select has_table('public','budget_category_targets');
select has_table('public','finding_dismissals');
select has_table('public','audit_log');

-- NO derived tables
select hasnt_table('public','budget_totals',   'no stored budget actuals table');
select hasnt_table('public','timeline_events',  'no stored timeline table');
select hasnt_table('public','health_findings',  'no stored health findings table');
select hasnt_table('public','member_balances',  'no stored member balances table');

-- views
select has_view('public','v_project_financials');
select has_view('public','v_member_balances');
select has_view('public','v_timeline_events');

-- functions / RPCs
select has_function('public','get_project_health', array['uuid']);
select has_function('public','accept_invitation', array['text']);
select has_function('app','is_member', array['uuid']);

-- RLS enabled + forced on every table
select is_empty($$
  select c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and c.relname in ('users','projects','project_members','invitations','commitments',
      'commitment_participants','cost_shares','payments','tasks','milestones','budgets',
      'budget_category_targets','finding_dismissals','audit_log','currencies')
    and (c.relrowsecurity = false or c.relforcerowsecurity = false)
$$, 'RLS is ENABLED and FORCED on every public table');

select * from finish();
rollback;
