-- First-stage cross-department fraud signal collection.
-- Signals are review prompts, never automatic member penalties.
begin;

create table if not exists public.fraud_risk_events (
 id uuid primary key default gen_random_uuid(),
 source text not null check (source in ('task','research','digital_growth','watch_earn')),
 event_type text not null,
 severity text not null check (severity in ('low','medium','high')),
 user_id uuid references auth.users(id) on delete set null,
 entity_id uuid,
 details jsonb not null default '{}'::jsonb,
 review_status text not null default 'open' check (review_status in ('open','under_review','cleared','actioned')),
 admin_note text,
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists fraud_risk_events_open_idx
 on public.fraud_risk_events(review_status,severity,created_at desc);
create index if not exists fraud_risk_events_user_idx
 on public.fraud_risk_events(user_id,created_at desc);

alter table public.fraud_risk_events enable row level security;
revoke all on public.fraud_risk_events from anon, authenticated;
grant select on public.fraud_risk_events to authenticated;
grant update (review_status,admin_note,reviewed_by,reviewed_at)
 on public.fraud_risk_events to authenticated;
drop policy if exists fraud_risk_events_admin_read on public.fraud_risk_events;
create policy fraud_risk_events_admin_read on public.fraud_risk_events
 for select to authenticated using (public.is_earnloop_admin());
drop policy if exists fraud_risk_events_admin_update on public.fraud_risk_events;
create policy fraud_risk_events_admin_update on public.fraud_risk_events
 for update to authenticated
 using (public.is_earnloop_admin())
 with check (public.is_earnloop_admin());

create or replace function private.record_fraud_risk_signal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare v_count bigint;
begin
 if tg_table_name = 'task_submissions' and tg_op = 'INSERT' then
  select count(*) into v_count from public.task_submissions
  where user_id = new.user_id and created_at >= now() - interval '10 minutes';
  if v_count >= 6 then
   insert into public.fraud_risk_events(source,event_type,severity,user_id,entity_id,details)
   values('task','rapid_task_submissions','medium',new.user_id,new.id,jsonb_build_object('submissions_in_10_minutes',v_count));
  end if;
  if new.evidence_path is not null and exists (
   select 1 from public.task_submissions where evidence_path = new.evidence_path and id <> new.id
  ) then
   insert into public.fraud_risk_events(source,event_type,severity,user_id,entity_id,details)
   values('task','reused_evidence_path','high',new.user_id,new.id,jsonb_build_object('evidence_path',new.evidence_path));
  end if;
  select count(*) into v_count from public.task_submissions
  where user_id = new.user_id and status = 'rejected' and created_at >= now() - interval '30 days';
  if v_count >= 3 then
   insert into public.fraud_risk_events(source,event_type,severity,user_id,entity_id,details)
   values('task','repeated_rejected_task_attempts','medium',new.user_id,new.id,jsonb_build_object('rejected_attempts_in_30_days',v_count));
  end if;
 elsif tg_table_name = 'research_responses' and tg_op = 'INSERT' then
  select count(*) into v_count from public.research_responses
  where user_id = new.user_id and study_id = new.study_id;
  if v_count > 1 then
   insert into public.fraud_risk_events(source,event_type,severity,user_id,entity_id,details)
   values('research','duplicate_study_response','high',new.user_id,new.id,jsonb_build_object('responses_for_study',v_count,'study_id',new.study_id));
  end if;
  select count(*) into v_count from public.research_responses
  where user_id = new.user_id and created_at >= now() - interval '10 minutes';
  if v_count >= 6 then
   insert into public.fraud_risk_events(source,event_type,severity,user_id,entity_id,details)
   values('research','rapid_research_responses','medium',new.user_id,new.id,jsonb_build_object('responses_in_10_minutes',v_count));
  end if;
 elsif tg_table_name = 'growth_submissions' and tg_op = 'INSERT' then
  select count(*) into v_count from public.growth_submissions
  where user_id = new.user_id and project_id = new.project_id;
  if v_count > 1 then
   insert into public.fraud_risk_events(source,event_type,severity,user_id,entity_id,details)
   values('digital_growth','duplicate_project_submission','high',new.user_id,new.id,jsonb_build_object('submissions_for_project',v_count,'project_id',new.project_id));
  end if;
  select count(*) into v_count from public.growth_submissions
  where user_id = new.user_id and created_at >= now() - interval '10 minutes';
  if v_count >= 6 then
   insert into public.fraud_risk_events(source,event_type,severity,user_id,entity_id,details)
   values('digital_growth','rapid_growth_submissions','medium',new.user_id,new.id,jsonb_build_object('submissions_in_10_minutes',v_count));
  end if;
 elsif tg_table_name = 'watch_sessions' and tg_op = 'UPDATE'
   and new.status in ('expired','rejected') and old.status not in ('expired','rejected') then
  select count(*) into v_count from public.watch_sessions
  where user_id = new.user_id and status in ('expired','rejected')
   and started_at >= now() - interval '24 hours';
  if v_count >= 3 then
   insert into public.fraud_risk_events(source,event_type,severity,user_id,entity_id,details)
   values('watch_earn','repeated_failed_viewing_sessions','medium',new.user_id,new.id,jsonb_build_object('failed_sessions_in_24_hours',v_count,'campaign_id',new.campaign_id));
  end if;
 end if;
 return coalesce(new,old);
end;
$function$;
revoke all on function private.record_fraud_risk_signal() from public,anon,authenticated;

drop trigger if exists taskpula_fraud_task_submission on public.task_submissions;
create trigger taskpula_fraud_task_submission after insert on public.task_submissions
 for each row execute function private.record_fraud_risk_signal();
drop trigger if exists taskpula_fraud_research_response on public.research_responses;
create trigger taskpula_fraud_research_response after insert on public.research_responses
 for each row execute function private.record_fraud_risk_signal();
drop trigger if exists taskpula_fraud_growth_submission on public.growth_submissions;
create trigger taskpula_fraud_growth_submission after insert on public.growth_submissions
 for each row execute function private.record_fraud_risk_signal();
drop trigger if exists taskpula_fraud_watch_session on public.watch_sessions;
create trigger taskpula_fraud_watch_session after update of status on public.watch_sessions
 for each row execute function private.record_fraud_risk_signal();
commit;
