-- Admin-only Circle membership and referral review controls.
-- Privileged operations remain in private schema; public wrappers are SECURITY INVOKER.

create or replace function private.set_circle_referral_status(
  p_referral_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_referrer uuid;
  v_referred uuid;
  v_old_status text;
begin
  if auth.uid() is null or not private.is_staff('admin') then
    raise exception 'Admin access required';
  end if;
  if p_status not in ('registered','verified','qualified','rejected') then
    raise exception 'Invalid referral status';
  end if;

  select referrer_user_id,referred_user_id,status
    into v_referrer,v_referred,v_old_status
  from public.circle_referrals
  where id=p_referral_id
  for update;
  if not found then raise exception 'Referral record not found'; end if;

  update public.circle_referrals
  set status=p_status,
      qualified_at=case when p_status='qualified' then coalesce(qualified_at,now()) else null end
  where id=p_referral_id;

  insert into private.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'circle_referral_status_updated','circle_referral',p_referral_id,
    jsonb_build_object('referrer_user_id',v_referrer,'referred_user_id',v_referred,
      'old_status',v_old_status,'new_status',p_status));
end;
$function$;
revoke all on function private.set_circle_referral_status(uuid,text) from public,anon;
grant execute on function private.set_circle_referral_status(uuid,text) to authenticated;

create or replace function public.set_circle_member_level(
  p_user_id uuid,
  p_level text,
  p_status text default 'active'
)
returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.set_circle_member_level(p_user_id,p_level,p_status);
$function$;
revoke all on function public.set_circle_member_level(uuid,text,text) from public,anon;
grant execute on function public.set_circle_member_level(uuid,text,text) to authenticated;

create or replace function public.set_circle_referral_status(
  p_referral_id uuid,
  p_status text
)
returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.set_circle_referral_status(p_referral_id,p_status);
$function$;
revoke all on function public.set_circle_referral_status(uuid,text) from public,anon;
grant execute on function public.set_circle_referral_status(uuid,text) to authenticated;
