-- TaskPula Circle member foundation: opt-in community profiles and attributed referrals.
-- Member-editable fields are column-granted; membership level/status and referral codes are server-managed.

create table if not exists public.circle_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 80),
  town text not null default '' check (char_length(town) <= 100),
  bio text not null default '' check (char_length(bio) <= 500),
  interests text[] not null default '{}',
  skills text[] not null default '{}',
  marketing_opt_in boolean not null default false,
  membership_level text not null default 'member'
    check (membership_level in ('member','contributor','community_ambassador','brand_representative')),
  membership_status text not null default 'active'
    check (membership_status in ('active','paused','suspended')),
  referral_code text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists circle_profiles_level_status_idx on public.circle_profiles(membership_level,membership_status);
create table if not exists public.circle_referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_user_id uuid not null references auth.users(id) on delete restrict,
  referred_user_id uuid not null unique references auth.users(id) on delete restrict,
  referral_code text not null,
  status text not null default 'registered' check (status in ('registered','verified','qualified','rejected')),
  attributed_at timestamptz not null default now(),
  qualified_at timestamptz,
  check (referrer_user_id <> referred_user_id)
);
create index if not exists circle_referrals_referrer_status_idx on public.circle_referrals(referrer_user_id,status,attributed_at desc);
alter table public.circle_profiles enable row level security;
alter table public.circle_referrals enable row level security;
revoke all on public.circle_profiles from anon,authenticated;
revoke all on public.circle_referrals from anon,authenticated;
grant select on public.circle_profiles to authenticated;
grant insert (user_id,display_name,town,bio,interests,skills,marketing_opt_in) on public.circle_profiles to authenticated;
grant update (display_name,town,bio,interests,skills,marketing_opt_in,updated_at) on public.circle_profiles to authenticated;
grant select on public.circle_referrals to authenticated;
drop policy if exists "circle member reads own profile" on public.circle_profiles;
create policy "circle member reads own profile" on public.circle_profiles for select to authenticated using (user_id=(select auth.uid()) or private.is_staff('admin'));
drop policy if exists "circle member creates own profile" on public.circle_profiles;
create policy "circle member creates own profile" on public.circle_profiles for insert to authenticated with check (user_id=(select auth.uid()));
drop policy if exists "circle member updates own profile" on public.circle_profiles;
create policy "circle member updates own profile" on public.circle_profiles for update to authenticated using (user_id=(select auth.uid()) or private.is_staff('admin')) with check (user_id=(select auth.uid()) or private.is_staff('admin'));
drop policy if exists "circle member reads own referral activity" on public.circle_referrals;
create policy "circle member reads own referral activity" on public.circle_referrals for select to authenticated using (referrer_user_id=(select auth.uid()) or referred_user_id=(select auth.uid()) or private.is_staff('admin'));
create or replace function private.attribute_circle_referral(p_referral_code text)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_referrer uuid; v_referred uuid:=auth.uid(); v_id uuid;
begin
 if v_referred is null then raise exception 'Authentication required'; end if;
 if p_referral_code is null or length(trim(p_referral_code))<6 then raise exception 'Invalid referral code'; end if;
 select cp.user_id into v_referrer from public.circle_profiles cp
 where cp.referral_code=upper(trim(p_referral_code)) and cp.membership_status='active';
 if v_referrer is null then raise exception 'Referral code not found'; end if;
 if v_referrer=v_referred then raise exception 'Self-referrals are not allowed'; end if;
 insert into public.circle_referrals(referrer_user_id,referred_user_id,referral_code)
 values(v_referrer,v_referred,upper(trim(p_referral_code))) on conflict(referred_user_id) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.circle_referrals where referred_user_id=v_referred; end if;
 return v_id;
end;
$function$;
revoke all on function private.attribute_circle_referral(text) from public,anon;
grant execute on function private.attribute_circle_referral(text) to authenticated;
create or replace function private.set_circle_profile_updated_at()
returns trigger language plpgsql set search_path=''
as $function$ begin new.updated_at:=now(); return new; end; $function$;
drop trigger if exists circle_profiles_updated_at on public.circle_profiles;
create trigger circle_profiles_updated_at before update on public.circle_profiles for each row execute function private.set_circle_profile_updated_at();
