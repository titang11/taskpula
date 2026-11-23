-- Phase 1: explicitly reject non-staff calls at the public review RPC entry point.
-- SECURITY DEFINER is intentional: the admin UI uses this RPC, but the function guards both authentication and staff membership.
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
