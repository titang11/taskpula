-- Restrict reward mutations to the authenticated Edge Function service role.
create table if not exists public.banner_ad_event_dedup (
 ad_id uuid not null references public.advertisements(id) on delete cascade,
 visitor_hash text not null,
 event_type text not null check (event_type in ('impression','click')),
 window_bucket timestamptz not null,
 created_at timestamptz not null default now(),
 primary key(ad_id,visitor_hash,event_type,window_bucket)
);
alter table public.banner_ad_event_dedup enable row level security;
revoke all on public.banner_ad_event_dedup from anon,authenticated;
drop function if exists public.track_banner_ad_event(uuid,text);
create or replace function public.track_banner_ad_event(p_ad_id uuid,p_event text,p_visitor_hash text)
returns void language plpgsql security definer set search_path=public as $$
declare v_bucket timestamptz; v_inserted integer;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Not authorized.'; end if;
 if p_event not in ('impression','click') or p_visitor_hash is null or length(p_visitor_hash)<>64 then raise exception 'Invalid event.'; end if;
 if p_event='impression' then v_bucket=date_trunc('hour',now())+make_interval(mins=>(floor(extract(minute from now())/30)::int)*30);
 else v_bucket=date_trunc('hour',now())+make_interval(mins=>(floor(extract(minute from now())/5)::int)*5); end if;
 insert into public.banner_ad_event_dedup(ad_id,visitor_hash,event_type,window_bucket)
 select p_ad_id,p_visitor_hash,p_event,v_bucket
 where exists(select 1 from public.advertisements where id=p_ad_id and status='active' and payment_status in ('paid','waived'))
 on conflict do nothing;
 get diagnostics v_inserted=row_count;
 if v_inserted=1 and p_event='impression' then update public.advertisements set impressions=impressions+1 where id=p_ad_id;
 elsif v_inserted=1 and p_event='click' then update public.advertisements set clicks=clicks+1 where id=p_ad_id; end if;
end $$;
revoke all on function public.track_banner_ad_event(uuid,text,text) from public,anon,authenticated;
grant execute on function public.track_banner_ad_event(uuid,text,text) to service_role;

drop function if exists public.watch_begin_session(uuid,text);
drop function if exists public.watch_heartbeat(uuid,uuid,numeric,boolean);
drop function if exists public.watch_complete_session(uuid,uuid);
-- The final definitions are in the previous Watch & Earn migration, but now take a user id
-- only from the authenticated Edge Function, never directly from browser RPC calls.
-- (Definitions and service_role-only grants are maintained in the deployed migration.)
