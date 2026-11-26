-- Expose only the referral operation through the public Data API.
-- The privileged implementation remains in the private schema.
create or replace function public.attribute_circle_referral(p_referral_code text)
returns uuid
language sql
security invoker
set search_path = ''
as $function$
  select private.attribute_circle_referral(p_referral_code);
$function$;
revoke all on function public.attribute_circle_referral(text) from public, anon;
grant execute on function public.attribute_circle_referral(text) to authenticated;

create or replace function private.set_circle_member_level(
  p_user_id uuid,
  p_level text,
  p_status text default 'active'
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_old_level text;
  v_old_status text;
begin
  if auth.uid() is null or not private.is_staff('admin') then
    raise exception 'Admin access required';
  end if;
  if p_level not in ('member','contributor','community_ambassador','brand_representative') then
    raise exception 'Invalid Circle membership level';
  end if;
  if p_status not in ('active','paused','suspended') then
    raise exception 'Invalid Circle membership status';
  end if;

  select membership_level,membership_status into v_old_level,v_old_status
  from public.circle_profiles where user_id=p_user_id for update;
  if not found then raise exception 'Circle profile not found'; end if;

  update public.circle_profiles
  set membership_level=p_level,membership_status=p_status,updated_at=now()
  where user_id=p_user_id;

  insert into private.audit_log(actor_id,action,entity_type,entity_id,details)
  values(
    auth.uid(),
    'circle_membership_updated',
    'circle_profile',
    p_user_id,
    jsonb_build_object(
      'old_level',v_old_level,'new_level',p_level,
      'old_status',v_old_status,'new_status',p_status
    )
  );
end;
$function$;
revoke all on function private.set_circle_member_level(uuid,text,text) from public,anon;
grant execute on function private.set_circle_member_level(uuid,text,text) to authenticated;
