-- TaskPula audit remediation: funded reward budgets, payout serialization, and banner viewability.
-- This migration is intentionally committed to Git only. Review and apply separately after staging tests.
begin;

-- Research and Digital Growth become campaign-funded reward programmes.
alter table public.research_studies
  add column if not exists campaign_id uuid references public.campaigns(id) on delete restrict,
  add column if not exists budget_amount numeric(12,2) not null default 0,
  add column if not exists max_submissions integer not null default 0;
alter table public.growth_projects
  add column if not exists campaign_id uuid references public.campaigns(id) on delete restrict,
  add column if not exists budget_amount numeric(12,2) not null default 0,
  add column if not exists max_submissions integer not null default 0;

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid='public.research_studies'::regclass and conname='research_studies_budget_nonnegative') then
    alter table public.research_studies add constraint research_studies_budget_nonnegative check (budget_amount >= 0 and max_submissions >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.growth_projects'::regclass and conname='growth_projects_budget_nonnegative') then
    alter table public.growth_projects add constraint growth_projects_budget_nonnegative check (budget_amount >= 0 and max_submissions >= 0);
  end if;
end $$;

create index if not exists research_studies_campaign_idx on public.research_studies(campaign_id,status);
create index if not exists growth_projects_campaign_idx on public.growth_projects(campaign_id,status);
create index if not exists research_responses_member_study_idx on public.research_responses(user_id,study_id,status);
create index if not exists growth_submissions_member_project_idx on public.growth_submissions(user_id,project_id,status);

-- Central, server-side campaign accounting. Paused and completed programmes continue
-- to reserve their budgets; changing a programme's status cannot silently free funds.
create or replace function private.taskpula_campaign_confirmed_funds(p_campaign_id uuid)
returns numeric
language sql stable security definer set search_path=''
as $$
  select coalesce(sum(case
    when f.entry_type in ('received','adjustment') then f.amount
    when f.entry_type='refund' then -f.amount
    else 0 end),0)
  from public.campaign_funding f
  where f.campaign_id=p_campaign_id and f.status='confirmed'
$$;

create or replace function private.taskpula_campaign_committed_budget(
  p_campaign_id uuid, p_exclude_table text default null, p_exclude_id uuid default null
)
returns numeric
language sql stable security definer set search_path=''
as $$
  select
    coalesce((select sum(t.budget_amount) from public.tasks t
      where t.campaign_id=p_campaign_id and t.status in ('active','paused','completed')
      and not (coalesce(p_exclude_table='tasks',false) and t.id is not distinct from p_exclude_id)),0)
    + coalesce((select sum(r.budget_amount) from public.research_studies r
      where r.campaign_id=p_campaign_id and r.status in ('active','paused','completed')
      and not (coalesce(p_exclude_table='research_studies',false) and r.id is not distinct from p_exclude_id)),0)
    + coalesce((select sum(g.budget_amount) from public.growth_projects g
      where g.campaign_id=p_campaign_id and g.status in ('active','paused','completed')
      and not (coalesce(p_exclude_table='growth_projects',false) and g.id is not distinct from p_exclude_id)),0)
$$;
revoke all on function private.taskpula_campaign_confirmed_funds(uuid) from public,anon,authenticated;
revoke all on function private.taskpula_campaign_committed_budget(uuid,text,uuid) from public,anon,authenticated;

-- Every newly published task, study, and growth project must be tied to an active,
-- confirmed-funded campaign. Existing records are not rewritten by this migration.
create or replace function private.taskpula_enforce_reward_campaign()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  v_row jsonb := to_jsonb(new);
  v_campaign_id uuid := nullif(v_row->>'campaign_id','')::uuid;
  v_id uuid := (v_row->>'id')::uuid;
  v_status text := v_row->>'status';
  v_budget numeric := coalesce(nullif(v_row->>'budget_amount','')::numeric,0);
  v_reward numeric := 0;
  v_max integer := 0;
  v_campaign public.campaigns%rowtype;
  v_funded numeric;
  v_committed numeric;
begin
  if v_status='active' and v_campaign_id is null then
    raise exception 'Link this reward opportunity to a funded campaign before publishing it';
  end if;
  if v_campaign_id is null then return new; end if;

  select * into v_campaign from public.campaigns where id=v_campaign_id for update;
  if not found then raise exception 'Campaign not found'; end if;

  if tg_table_name='tasks' then
    if (v_row->>'sponsor_id')::uuid is distinct from v_campaign.sponsor_id then
      raise exception 'Task sponsor must match its campaign sponsor';
    end if;
    v_reward := coalesce((v_row->>'reward_amount')::numeric,0);
    v_max := coalesce(nullif(v_row->>'max_submissions','')::integer,0);
  elsif tg_table_name='research_studies' then
    v_reward := coalesce((v_row->>'incentive_amount')::numeric,0);
    v_max := coalesce(nullif(v_row->>'max_submissions','')::integer,0);
  elsif tg_table_name='growth_projects' then
    v_reward := coalesce((v_row->>'reward_amount')::numeric,0);
    v_max := coalesce(nullif(v_row->>'max_submissions','')::integer,0);
  end if;

  if v_status in ('active','paused','completed') then
    if v_budget<=0 or v_reward<=0 or v_max<=0 or v_budget<(v_reward*v_max) then
      raise exception 'Set a positive reward, a maximum participant count, and a budget covering all maximum rewards';
    end if;
    if v_status='active' and v_campaign.status<>'active' then
      raise exception 'Campaign must be active before publishing its reward opportunity';
    end if;
    v_funded := private.taskpula_campaign_confirmed_funds(v_campaign_id);
    v_committed := private.taskpula_campaign_committed_budget(v_campaign_id,tg_table_name,v_id);
    if v_funded < v_committed+v_budget then
      raise exception 'Confirmed campaign funds are insufficient for this reward budget';
    end if;
  end if;
  return new;
end $$;
revoke all on function private.taskpula_enforce_reward_campaign() from public,anon,authenticated;

drop trigger if exists enforce_task_campaign_funding on public.tasks;
create trigger enforce_task_campaign_funding
before insert or update of campaign_id,budget_amount,reward_amount,max_submissions,status on public.tasks
for each row execute function private.taskpula_enforce_reward_campaign();

drop trigger if exists enforce_research_campaign_funding on public.research_studies;
create trigger enforce_research_campaign_funding
before insert or update of campaign_id,budget_amount,incentive_amount,max_submissions,status on public.research_studies
for each row execute function private.taskpula_enforce_reward_campaign();

drop trigger if exists enforce_growth_campaign_funding on public.growth_projects;
create trigger enforce_growth_campaign_funding
before insert or update of campaign_id,budget_amount,reward_amount,max_submissions,status on public.growth_projects
for each row execute function private.taskpula_enforce_reward_campaign();

-- Funding receipts/refunds are serialized on the campaign row and cannot reduce
-- confirmed funds below the combined task, research, and growth commitments.
create or replace function private.enforce_campaign_funding_entry()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  v_campaign public.campaigns%rowtype;
  v_funded numeric;
  v_delta numeric := 0;
  v_committed numeric;
begin
  select * into v_campaign from public.campaigns where id=new.campaign_id for update;
  if not found then raise exception 'Campaign not found'; end if;
  if tg_op='UPDATE' and new.campaign_id is distinct from old.campaign_id then
    raise exception 'A funding entry cannot be moved to another campaign; record a correcting entry instead';
  end if;
  if new.sponsor_id is distinct from v_campaign.sponsor_id then
    raise exception 'Funding sponsor must match campaign sponsor';
  end if;

  if new.status='confirmed' then
    v_delta := case
      when new.entry_type in ('received','adjustment') then new.amount
      when new.entry_type='refund' then -new.amount
      else 0 end;
  end if;

  select private.taskpula_campaign_confirmed_funds(new.campaign_id)
    - case when tg_op='UPDATE' and old.status='confirmed' then
      case when old.entry_type in ('received','adjustment') then old.amount
           when old.entry_type='refund' then -old.amount else 0 end
      else 0 end
    into v_funded;
  if v_funded+v_delta<0 then raise exception 'Refund exceeds confirmed campaign funds'; end if;
  if v_funded+v_delta>v_campaign.budget_cap then raise exception 'Confirmed funding cannot exceed the campaign budget cap'; end if;
  v_committed := private.taskpula_campaign_committed_budget(new.campaign_id,null,null);
  if v_funded+v_delta<v_committed then raise exception 'Confirmed funds cannot fall below committed reward budgets'; end if;
  return new;
end $$;

create or replace function private.enforce_campaign_activation()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_funded numeric; v_committed numeric;
begin
  if new.status='active' then
    v_funded := private.taskpula_campaign_confirmed_funds(new.id);
    v_committed := private.taskpula_campaign_committed_budget(new.id,null,null);
    if v_funded<=0 then raise exception 'Campaign needs confirmed funding before activation'; end if;
    if v_funded>new.budget_cap then raise exception 'Confirmed funding exceeds the campaign budget cap'; end if;
    if v_funded<v_committed then raise exception 'Confirmed funds are below all reward programme commitments'; end if;
  end if;
  new.updated_at=now();
  return new;
end $$;
revoke all on function private.enforce_campaign_funding_entry() from public,anon,authenticated;
revoke all on function private.enforce_campaign_activation() from public,anon,authenticated;

-- A campaign pause or funding shortfall stops new participation across every department.
create or replace function private.taskpula_assert_campaign_live(p_campaign_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare v_campaign public.campaigns%rowtype; v_funded numeric; v_committed numeric;
begin
  if p_campaign_id is null then raise exception 'This reward opportunity is not linked to a funded campaign'; end if;
  select * into v_campaign from public.campaigns where id=p_campaign_id for share;
  if not found or v_campaign.status<>'active' then raise exception 'The linked campaign is not active'; end if;
  v_funded := private.taskpula_campaign_confirmed_funds(p_campaign_id);
  v_committed := private.taskpula_campaign_committed_budget(p_campaign_id,null,null);
  if v_funded<v_committed then raise exception 'The linked campaign is not fully funded'; end if;
end $$;
revoke all on function private.taskpula_assert_campaign_live(uuid) from public,anon,authenticated;

-- Prevent duplicate active/pending participant entries and reserve the participant
-- slot under a row lock. Rejected entries may be resubmitted.
create or replace function private.taskpula_guard_reward_submission()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  v_project_status text;
  v_max integer;
  v_used integer;
  v_project_id uuid;
  v_campaign_id uuid;
begin
  if tg_table_name='research_responses' then
    v_project_id := new.study_id;
    select status,max_submissions,campaign_id into v_project_status,v_max,v_campaign_id
      from public.research_studies where id=v_project_id for update;
    if not found then raise exception 'Research study not found'; end if;
    if v_project_status<>'active' then raise exception 'This research study is not accepting responses'; end if;
    perform private.taskpula_assert_campaign_live(v_campaign_id);
    if exists(select 1 from public.research_responses r where r.study_id=v_project_id and r.user_id=new.user_id and r.status<>'rejected') then
      raise exception 'You already have an active or approved response for this study';
    end if;
    select count(*) into v_used from public.research_responses r
      where r.study_id=v_project_id and r.status<>'rejected';
  else
    v_project_id := new.project_id;
    select status,max_submissions,campaign_id into v_project_status,v_max,v_campaign_id
      from public.growth_projects where id=v_project_id for update;
    if not found then raise exception 'Digital Growth project not found'; end if;
    if v_project_status<>'active' then raise exception 'This Digital Growth project is not accepting submissions'; end if;
    perform private.taskpula_assert_campaign_live(v_campaign_id);
    if exists(select 1 from public.growth_submissions g where g.project_id=v_project_id and g.user_id=new.user_id and g.status<>'rejected') then
      raise exception 'You already have an active or approved submission for this project';
    end if;
    select count(*) into v_used from public.growth_submissions g
      where g.project_id=v_project_id and g.status<>'rejected';
  end if;
  if v_max is null or v_max<=0 or v_used>=v_max then
    raise exception 'This reward programme has reached its participant limit';
  end if;
  return new;
end $$;
revoke all on function private.taskpula_guard_reward_submission() from public,anon,authenticated;

drop trigger if exists taskpula_guard_research_response on public.research_responses;
create trigger taskpula_guard_research_response before insert on public.research_responses
for each row execute function private.taskpula_guard_reward_submission();
drop trigger if exists taskpula_guard_growth_submission on public.growth_submissions;
create trigger taskpula_guard_growth_submission before insert on public.growth_submissions
for each row execute function private.taskpula_guard_reward_submission();

-- Approval is atomic: serialize on the programme row, enforce its cap, and issue
-- the ledger credit once. No browser-side wallet writes are granted.
create or replace function public.review_research_response(p_response_id uuid,p_decision text)
returns boolean language plpgsql security definer set search_path=''
as $$
declare
  rec public.research_responses%rowtype;
  project public.research_studies%rowtype;
  uid uuid := (select auth.uid());
  approved_count integer;
begin
  if uid is null or not private.is_staff('admin') then raise exception 'Administrator access required'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Invalid review decision'; end if;
  select * into rec from public.research_responses where id=p_response_id;
  if not found then raise exception 'Research response not found'; end if;
  select * into project from public.research_studies where id=rec.study_id for update;
  if not found then raise exception 'Research study not found'; end if;
  select * into rec from public.research_responses where id=p_response_id for update;
  if rec.status in ('approved','rejected') then raise exception 'This response has already been reviewed'; end if;
  if p_decision='approved' then
    if project.max_submissions<=0 or project.budget_amount<project.incentive_amount then
      raise exception 'This study has no valid funded reward allocation';
    end if;
    select count(*) into approved_count from public.research_responses
      where study_id=project.id and status='approved';
    if approved_count>=project.max_submissions or (approved_count+1)*project.incentive_amount>project.budget_amount then
      raise exception 'Research incentive budget or participant limit exhausted';
    end if;
    insert into public.wallet_transactions(user_id,amount,currency,transaction_type,reference_id,idempotency_key,description)
    values(rec.user_id,project.incentive_amount,project.currency,'task_reward',rec.id,'research:'||rec.id::text,'Approved TaskPula Research incentive')
    on conflict(idempotency_key) do nothing;
  end if;
  update public.research_responses set status=p_decision,reviewed_by=uid,reviewed_at=now() where id=p_response_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,details)
  values(uid,'review_'||p_decision,'research_response',rec.id::text,jsonb_build_object('reward',case when p_decision='approved' then project.incentive_amount else 0 end,'campaign_id',project.campaign_id,'budget',project.budget_amount));
  return true;
end $$;

create or replace function public.review_growth_submission(p_submission_id uuid,p_decision text)
returns boolean language plpgsql security definer set search_path=''
as $$
declare
  rec public.growth_submissions%rowtype;
  project public.growth_projects%rowtype;
  uid uuid := (select auth.uid());
  approved_count integer;
begin
  if uid is null or not private.is_staff('admin') then raise exception 'Administrator access required'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Invalid review decision'; end if;
  select * into rec from public.growth_submissions where id=p_submission_id;
  if not found then raise exception 'Growth submission not found'; end if;
  select * into project from public.growth_projects where id=rec.project_id for update;
  if not found then raise exception 'Digital Growth project not found'; end if;
  select * into rec from public.growth_submissions where id=p_submission_id for update;
  if rec.status in ('approved','rejected') then raise exception 'This submission has already been reviewed'; end if;
  if p_decision='approved' then
    if project.max_submissions<=0 or project.budget_amount<project.reward_amount then
      raise exception 'This project has no valid funded reward allocation';
    end if;
    select count(*) into approved_count from public.growth_submissions
      where project_id=project.id and status='approved';
    if approved_count>=project.max_submissions or (approved_count+1)*project.reward_amount>project.budget_amount then
      raise exception 'Digital Growth reward budget or participant limit exhausted';
    end if;
    insert into public.wallet_transactions(user_id,amount,currency,transaction_type,reference_id,idempotency_key,description)
    values(rec.user_id,project.reward_amount,project.currency,'task_reward',rec.id,'growth:'||rec.id::text,'Approved TaskPula Digital Growth reward')
    on conflict(idempotency_key) do nothing;
  end if;
  update public.growth_submissions set status=p_decision,reviewed_by=uid,reviewed_at=now() where id=p_submission_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,details)
  values(uid,'review_'||p_decision,'growth_submission',rec.id::text,jsonb_build_object('reward',case when p_decision='approved' then project.reward_amount else 0 end,'campaign_id',project.campaign_id,'budget',project.budget_amount));
  return true;
end $$;

-- Task submissions for campaign-linked tasks also stop when the sponsor campaign is paused
-- or loses confirmed funding. Legacy unlinked active tasks are grandfathered until admin review.
create or replace function private.validate_submission()
returns trigger language plpgsql security definer set search_path=''
as $
declare v_task public.tasks%rowtype; v_count bigint; v_reserved numeric(14,2);
begin
  if (select auth.uid()) is null or new.user_id<>(select auth.uid()) then
    raise exception 'Submission user must match the signed-in account';
  end if;
  select * into v_task from public.tasks where id=new.task_id for update;
  if not found or v_task.status<>'active' or v_task.starts_at>now()
    or (v_task.ends_at is not null and v_task.ends_at<=now()) then
    raise exception 'Task is not currently available';
  end if;
  if v_task.campaign_id is not null then
    perform private.taskpula_assert_campaign_live(v_task.campaign_id);
  end if;
  select count(*),coalesce(sum(v_task.reward_amount),0) into v_count,v_reserved
    from public.task_submissions s where s.task_id=new.task_id and s.status in ('pending','approved');
  if v_task.max_submissions is not null and v_count>=v_task.max_submissions then
    raise exception 'Task submission limit has been reached';
  end if;
  if v_reserved+v_task.reward_amount>v_task.budget_amount then
    raise exception 'Task reward budget has been reached';
  end if;
  return new;
end $;
revoke all on function private.validate_submission() from public,anon,authenticated;

-- Record research/growth programme configuration changes in the admin audit trail.
drop trigger if exists audit_research_admin_changes on public.research_studies;
create trigger audit_research_admin_changes after insert or update or delete on public.research_studies
for each row execute function private.audit_admin_mutations();
drop trigger if exists audit_growth_admin_changes on public.growth_projects;
create trigger audit_growth_admin_changes after insert or update or delete on public.growth_projects
for each row execute function private.audit_admin_mutations();

-- Per-member transaction-scoped advisory locks serialize concurrent payout requests
-- and settlements, so two requests cannot reserve or pay the same available funds.
create or replace function private.taskpula_lock_wallet(p_user_id uuid)
returns void language sql volatile security definer set search_path=''
as $$ select pg_advisory_xact_lock(hashtextextended('taskpula-wallet:'||p_user_id::text,0)) $$;
revoke all on function private.taskpula_lock_wallet(uuid) from public,anon,authenticated;

create or replace function public.request_wallet_payout(p_amount numeric,payout_method text,payout_reference text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare uid uuid := (select auth.uid()); available numeric; reserved numeric; new_id uuid;
begin
  if uid is null then raise exception 'Sign in is required'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Enter a valid payout amount'; end if;
  if payout_method not in ('orange_money','bank_transfer','myzaka') then raise exception 'Unsupported payout method'; end if;
  if length(trim(coalesce(payout_reference,'')))<3 then raise exception 'Enter a valid payout reference'; end if;
  perform private.taskpula_lock_wallet(uid);
  select coalesce(sum(amount),0) into available from public.wallet_transactions where user_id=uid;
  select coalesce(sum(amount),0) into reserved from public.wallet_payout_requests
    where user_id=uid and status in ('requested','under_review','approved');
  if p_amount>available-reserved then raise exception 'Payout amount exceeds your available balance'; end if;
  insert into public.wallet_payout_requests(user_id,amount,payout_method,payout_reference)
  values(uid,p_amount,payout_method,trim(payout_reference)) returning id into new_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,details)
  values(uid,'payout_requested','wallet_payout_request',new_id::text,jsonb_build_object('amount',p_amount,'method',payout_method));
  return new_id;
end $$;

create or replace function public.process_wallet_payout(p_request_id uuid,p_decision text,p_admin_note text default null)
returns boolean language plpgsql security definer set search_path=''
as $$
declare rec public.wallet_payout_requests%rowtype; uid uuid := (select auth.uid()); available numeric; reserved numeric;
begin
  if uid is null or not private.is_staff('admin') then raise exception 'Administrator access required'; end if;
  if p_decision not in ('under_review','approved','paid','rejected') then raise exception 'Invalid payout decision'; end if;
  select * into rec from public.wallet_payout_requests where id=p_request_id for update;
  if not found then raise exception 'Payout request not found'; end if;
  perform private.taskpula_lock_wallet(rec.user_id);
  if rec.status in ('paid','rejected','cancelled') then raise exception 'This payout request is already closed'; end if;
  if p_decision='under_review' and rec.status not in ('requested','under_review') then raise exception 'Invalid payout status transition'; end if;
  if p_decision='approved' and rec.status not in ('requested','under_review','approved') then raise exception 'Invalid payout status transition'; end if;
  if p_decision in ('paid','rejected') and rec.status not in ('requested','under_review','approved') then raise exception 'Invalid payout status transition'; end if;
  if p_decision='paid' then
    select coalesce(sum(amount),0) into available from public.wallet_transactions where user_id=rec.user_id;
    select coalesce(sum(amount),0) into reserved from public.wallet_payout_requests
      where user_id=rec.user_id and status in ('requested','under_review','approved') and id<>rec.id;
    if rec.amount>available-reserved then raise exception 'Insufficient available wallet balance to settle this payout'; end if;
    insert into public.wallet_transactions(user_id,amount,currency,transaction_type,reference_id,idempotency_key,description)
    values(rec.user_id,-rec.amount,rec.currency,'adjustment',rec.id,'payout:'||rec.id::text,'Payout settled via '||rec.payout_method)
    on conflict(idempotency_key) do nothing;
  end if;
  update public.wallet_payout_requests set status=p_decision,admin_note=nullif(trim(coalesce(p_admin_note,'')),''),reviewed_by=uid,reviewed_at=now()
    where id=p_request_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,details)
  values(uid,'payout_'||p_decision,'wallet_payout_request',rec.id::text,jsonb_build_object('amount',rec.amount,'member_id',rec.user_id,'previous_status',rec.status));
  return true;
end $$;

revoke all on function public.review_research_response(uuid,text) from public,anon;
revoke all on function public.review_growth_submission(uuid,text) from public,anon;
revoke all on function public.request_wallet_payout(numeric,text,text) from public,anon;
revoke all on function public.process_wallet_payout(uuid,text,text) from public,anon;
grant execute on function public.review_research_response(uuid,text) to authenticated;
grant execute on function public.review_growth_submission(uuid,text) to authenticated;
grant execute on function public.request_wallet_payout(numeric,text,text) to authenticated;
grant execute on function public.process_wallet_payout(uuid,text,text) to authenticated;

-- A banner impression now requires a minimum viewability dwell-time attestation.
-- The browser reports >= 1 second at >= 50% visibility; the server remains the
-- authoritative deduplicator and only counts paid, scheduled, active inventory.
drop function if exists public.track_banner_ad_event(uuid,text,text);
create or replace function public.track_banner_ad_event(
  p_ad_id uuid,p_event text,p_visitor_hash text,p_viewable_ms integer default 0
)
returns void language plpgsql security definer set search_path=''
as $$
declare v_bucket timestamptz; v_inserted integer;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Not authorized'; end if;
  if p_event not in ('impression','click') or p_visitor_hash is null or length(p_visitor_hash)<>64 then
    raise exception 'Invalid event';
  end if;
  if p_event='impression' and (p_viewable_ms is null or p_viewable_ms<1000 or p_viewable_ms>60000) then
    raise exception 'Impression did not meet the minimum viewability threshold';
  end if;
  if p_event='impression' then
    v_bucket:=date_trunc('hour',now())+make_interval(mins=>(floor(extract(minute from now())/30)::int)*30);
  else
    v_bucket:=date_trunc('hour',now())+make_interval(mins=>(floor(extract(minute from now())/5)::int)*5);
  end if;
  insert into public.banner_ad_event_dedup(ad_id,visitor_hash,event_type,window_bucket)
  select p_ad_id,p_visitor_hash,p_event,v_bucket
  where exists(select 1 from public.advertisements a where a.id=p_ad_id and a.status='active'
    and a.payment_status in ('paid','waived') and (a.starts_at is null or a.starts_at<=now())
    and (a.ends_at is null or a.ends_at>now()))
  on conflict do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=1 and p_event='impression' then
    update public.advertisements set impressions=impressions+1 where id=p_ad_id;
  elsif v_inserted=1 and p_event='click' then
    update public.advertisements set clicks=clicks+1 where id=p_ad_id;
  end if;
end $$;
revoke all on function public.track_banner_ad_event(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.track_banner_ad_event(uuid,text,text,integer) to service_role;

commit;
