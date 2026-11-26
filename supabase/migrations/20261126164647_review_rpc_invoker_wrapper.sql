-- Keep the exposed review RPC as SECURITY INVOKER.
-- The private implementation remains SECURITY DEFINER and enforces staff authorization.
grant execute on function private.review_submission(uuid,text,text) to authenticated;

create or replace function public.review_earnloop_submission(
  p_submission_id uuid,
  p_decision text,
  p_rejection_reason text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.review_submission(p_submission_id,p_decision,p_rejection_reason);
$function$;

revoke all on function public.review_earnloop_submission(uuid,text,text) from public,anon;
grant execute on function public.review_earnloop_submission(uuid,text,text) to authenticated;
