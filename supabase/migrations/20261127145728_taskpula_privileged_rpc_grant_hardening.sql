-- Remove anonymous execution from privileged TaskPula RPCs.
-- Authenticated execution remains only where the function validates auth.uid()
-- and/or the private staff role internally. Trigger-only audit function is not
-- directly callable by API roles.
begin;
revoke execute on function public.process_wallet_payout(uuid,text,text) from public, anon;
revoke execute on function public.request_wallet_payout(numeric,text,text) from public, anon;
revoke execute on function public.review_growth_submission(uuid,text) from public, anon;
revoke execute on function public.review_research_response(uuid,text) from public, anon;
revoke execute on function public.taskpula_list_staff() from public, anon;
revoke execute on function public.taskpula_set_admin_access(uuid,boolean) from public, anon;
revoke all on function public.taskpula_audit_row() from public, anon, authenticated;

grant execute on function public.request_wallet_payout(numeric,text,text) to authenticated;
grant execute on function public.process_wallet_payout(uuid,text,text) to authenticated;
grant execute on function public.review_growth_submission(uuid,text) to authenticated;
grant execute on function public.review_research_response(uuid,text) to authenticated;
grant execute on function public.taskpula_list_staff() to authenticated;
grant execute on function public.taskpula_set_admin_access(uuid,boolean) to authenticated;

-- Prevent future public/anonymous function exposure by default.
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon;
commit;
