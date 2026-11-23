-- EarnLoop BW Phase 1: budget enforcement, wallet protection, admin audit
-- Apply through Supabase migrations; approval transaction serializes per-task via FOR UPDATE.
create or replace function private.review_submission(p_submission_id uuid, p_decision text, p_rejection_reason text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare
  v_submission public.task_submissions%rowtype;
  v_task public.tasks%rowtype;
  v_spent numeric := 0;
  v_approved_count integer := 0;
begin
  if not private.is_staff() then raise exception 'Not authorized'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
  if p_decision = 'rejected' and nullif(trim(coalesce(p_rejection_reason,'')),'') is null then
    raise exception 'Rejection reason is required';
  end if;
  select * into v_submission from public.task_submissions where id=p_submission_id;
  if not found then raise exception 'Submission not found'; end if;
  select * into v_task from public.tasks where id=v_submission.task_id for update;
  if not found then raise exception 'Task not found'; end if;
  select * into v_submission from public.task_submissions where id=p_submission_id for update;
  if v_submission.status <> 'pending' then raise exception 'Submission has already been reviewed'; end if;
  if p_decision='approved' then
    select coalesce(sum(wt.amount),0) into v_spent
    from public.wallet_transactions wt
    join public.task_submissions ts on ts.id=wt.reference_id
    where ts.task_id=v_task.id and wt.transaction_type='task_reward';
    select count(*) into v_approved_count from public.task_submissions where task_id=v_task.id and status='approved';
    if v_task.max_submissions is not null and v_approved_count>=v_task.max_submissions then
      raise exception 'Task maximum approved submissions reached';
    end if;
    if v_spent+v_task.reward_amount>v_task.budget_amount then raise exception 'Task reward budget exhausted'; end if;
    insert into public.wallet_transactions(user_id,amount,transaction_type,reference_id,idempotency_key,description,currency)
    values(v_submission.user_id,v_task.reward_amount,'task_reward',v_submission.id,
      'task-reward:'||v_submission.id::text,'Approved task reward: '||v_task.title,v_task.currency)
    on conflict(idempotency_key) do nothing;
  end if;
  update public.task_submissions set status=p_decision,reviewer_id=(select auth.uid()),reviewed_at=now(),
    rejection_reason=case when p_decision='rejected' then nullif(trim(p_rejection_reason),'') else null end
  where id=p_submission_id;
  insert into private.audit_log(actor_id,action,entity_type,entity_id,details)
  values((select auth.uid()),'submission_'||p_decision,'task_submission',p_submission_id,
    jsonb_build_object('task_id',v_submission.task_id,'reward',case when p_decision='approved' then v_task.reward_amount else 0 end));
  return jsonb_build_object('submission_id',p_submission_id,'status',p_decision);
end;
$function$;

-- Protect ledger from browser-side writes.
revoke insert, update, delete on public.wallet_transactions from anon, authenticated;
grant select on public.wallet_transactions to authenticated;
revoke execute on function private.review_submission(uuid,text,text) from public,anon,authenticated;
-- The exposed RPC validates the logged-in identity; the private function enforces staff authorization.
create or replace function public.review_earnloop_submission(p_submission_id uuid,p_decision text,p_rejection_reason text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
 if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
 if not private.is_staff() then raise exception 'Not authorized'; end if;
 return private.review_submission(p_submission_id,p_decision,p_rejection_reason);
end;
$function$;
revoke execute on function public.review_earnloop_submission(uuid,text,text) from public,anon;
grant execute on function public.review_earnloop_submission(uuid,text,text) to authenticated;

-- Private audit logs remain inaccessible through client APIs.
alter table private.audit_log enable row level security;
create or replace function private.audit_admin_mutations()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_action text;
  v_entity uuid;
  v_details jsonb;
begin
  if not private.is_staff('admin') then raise exception 'Admin authorization required'; end if;
  v_action:=lower(tg_op);
  if tg_op='DELETE' then v_entity:=old.id; v_details:=jsonb_build_object('old',to_jsonb(old));
  elsif tg_op='INSERT' then v_entity:=new.id; v_details:=jsonb_build_object('new',to_jsonb(new));
  else v_entity:=new.id; v_details:=jsonb_build_object('old',to_jsonb(old),'new',to_jsonb(new)); end if;
  insert into private.audit_log(actor_id,action,entity_type,entity_id,details)
  values(v_actor,'admin_'||v_action,tg_table_name,v_entity,v_details);
  if tg_op='DELETE' then return old; else return new; end if;
end;
$function$;
revoke execute on function private.audit_admin_mutations() from public,anon,authenticated;
drop trigger if exists audit_task_admin_changes on public.tasks;
create trigger audit_task_admin_changes after insert or update or delete on public.tasks for each row execute function private.audit_admin_mutations();
drop trigger if exists audit_sponsor_admin_changes on public.sponsors;
create trigger audit_sponsor_admin_changes after insert or update or delete on public.sponsors for each row execute function private.audit_admin_mutations();
