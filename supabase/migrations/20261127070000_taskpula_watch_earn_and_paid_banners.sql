-- TaskPula Watch & Earn + paid banner inventory.
-- This file records the production migrations already applied to the linked Supabase project.

create table if not exists public.watch_campaigns (
 id uuid primary key default gen_random_uuid(),
 title text not null check (char_length(btrim(title)) between 3 and 140),
 description text not null default '',
 advertiser_name text not null,
 video_url text not null check (video_url ~* '^https://'),
 duration_seconds integer not null check (duration_seconds between 5 and 600),
 reward_amount numeric(12,2) not null check (reward_amount>0),
 funded_budget numeric(12,2) not null check (funded_budget>0),
 spent_amount numeric(12,2) not null default 0 check (spent_amount>=0),
 max_views integer not null check (max_views>0),
 views_count integer not null default 0 check (views_count>=0),
 daily_limit_per_user integer not null default 5 check (daily_limit_per_user between 1 and 100),
 status text not null default 'draft' check (status in ('draft','active','paused','completed')),
 starts_at timestamptz, ends_at timestamptz,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint watch_campaign_budget_not_overdrawn check (spent_amount<=funded_budget)
);
alter table public.watch_campaigns add column if not exists funding_status text not null default 'pending' check (funding_status in ('pending','confirmed','refunded'));
create index if not exists watch_campaigns_live_idx on public.watch_campaigns(status,starts_at,ends_at);

create table if not exists public.watch_sessions (
 id uuid primary key default gen_random_uuid(),
 campaign_id uuid not null references public.watch_campaigns(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 session_token uuid not null default gen_random_uuid(),
 started_at timestamptz not null default now(),
 expires_at timestamptz not null,
 completed_at timestamptz,
 status text not null default 'started' check (status in ('started','completed','expired','rejected')),
 client_nonce text not null,
 watched_seconds integer not null default 0 check (watched_seconds>=0),
 last_heartbeat_at timestamptz,
 last_video_time numeric(10,2) not null default 0,
 created_at timestamptz not null default now()
);
alter table public.watch_sessions add column if not exists watched_seconds integer not null default 0;
alter table public.watch_sessions add column if not exists last_heartbeat_at timestamptz;
alter table public.watch_sessions add column if not exists last_video_time numeric(10,2) not null default 0;
create index if not exists watch_sessions_user_idx on public.watch_sessions(user_id,created_at desc);

create table if not exists public.watch_views (
 id uuid primary key default gen_random_uuid(),
 campaign_id uuid not null references public.watch_campaigns(id),
 session_id uuid not null unique references public.watch_sessions(id),
 user_id uuid not null references auth.users(id),
 reward_amount numeric(12,2) not null check (reward_amount>0),
 verified_at timestamptz not null default now(),
 verification_method text not null default 'server_elapsed_session',
 unique(campaign_id,user_id)
);
create index if not exists watch_views_user_idx on public.watch_views(user_id,verified_at desc);

alter table public.wallet_transactions drop constraint if exists wallet_transactions_transaction_type_check;
alter table public.wallet_transactions add constraint wallet_transactions_transaction_type_check
 check (transaction_type in ('task_reward','adjustment','reversal','watch_reward'));

alter table public.watch_campaigns enable row level security;
alter table public.watch_sessions enable row level security;
alter table public.watch_views enable row level security;
drop policy if exists watch_campaigns_public_active on public.watch_campaigns;
create policy watch_campaigns_public_active on public.watch_campaigns for select to authenticated using (
 status='active' and funding_status='confirmed' and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now())
);
drop policy if exists watch_campaigns_admin_all on public.watch_campaigns;
create policy watch_campaigns_admin_all on public.watch_campaigns for all to authenticated using (public.is_earnloop_admin()) with check (public.is_earnloop_admin());
drop policy if exists watch_sessions_owner_read on public.watch_sessions;
create policy watch_sessions_owner_read on public.watch_sessions for select to authenticated using (user_id=auth.uid() or public.is_earnloop_admin());
drop policy if exists watch_views_owner_read on public.watch_views;
create policy watch_views_owner_read on public.watch_views for select to authenticated using (user_id=auth.uid() or public.is_earnloop_admin());
revoke insert,update,delete on public.watch_sessions from anon,authenticated;
revoke insert,update,delete on public.watch_views from anon,authenticated;
revoke insert,update,delete on public.wallet_transactions from anon,authenticated;
grant select on public.watch_campaigns,public.watch_sessions,public.watch_views to authenticated;

create or replace function public.watch_begin_session(p_campaign_id uuid,p_client_nonce text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid:=auth.uid(); v_campaign public.watch_campaigns%rowtype; v_session public.watch_sessions%rowtype; v_today integer;
begin
 if v_user is null then raise exception 'Sign in to watch sponsored videos.'; end if;
 if p_client_nonce is null or length(p_client_nonce)<16 or length(p_client_nonce)>128 then raise exception 'Invalid viewing session request.'; end if;
 select * into v_campaign from public.watch_campaigns where id=p_campaign_id for update;
 if not found or v_campaign.status<>'active' or v_campaign.funding_status<>'confirmed' or (v_campaign.starts_at is not null and v_campaign.starts_at>now()) or (v_campaign.ends_at is not null and v_campaign.ends_at<=now()) then raise exception 'This video campaign is not available or its funding is not confirmed.'; end if;
 if exists(select 1 from public.watch_views where campaign_id=p_campaign_id and user_id=v_user) then raise exception 'You have already earned a reward for this video.'; end if;
 select count(*) into v_today from public.watch_views where user_id=v_user and verified_at>=date_trunc('day',now());
 if v_today>=v_campaign.daily_limit_per_user then raise exception 'You have reached today’s Watch & Earn limit.'; end if;
 if v_campaign.views_count>=v_campaign.max_views or v_campaign.spent_amount+v_campaign.reward_amount>v_campaign.funded_budget then raise exception 'This campaign has reached its reward limit.'; end if;
 insert into public.watch_sessions(campaign_id,user_id,expires_at,client_nonce)
 values(p_campaign_id,v_user,now()+make_interval(secs=>v_campaign.duration_seconds+600),p_client_nonce) returning * into v_session;
 return jsonb_build_object('session_id',v_session.id,'session_token',v_session.session_token,'duration_seconds',v_campaign.duration_seconds,'started_at',v_session.started_at);
end $$;

create or replace function public.watch_heartbeat(p_session_id uuid,p_session_token uuid,p_video_time numeric,p_page_visible boolean)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid:=auth.uid(); v_session public.watch_sessions%rowtype; v_delta numeric; v_elapsed numeric;
begin
 if v_user is null then raise exception 'Sign in required.'; end if;
 select * into v_session from public.watch_sessions where id=p_session_id and user_id=v_user for update;
 if not found or v_session.session_token<>p_session_token or v_session.status<>'started' then raise exception 'Viewing session is invalid.'; end if;
 if now()>v_session.expires_at then update public.watch_sessions set status='expired' where id=p_session_id; raise exception 'Viewing session expired.'; end if;
 if p_video_time is null or p_video_time<0 or p_video_time>36000 then raise exception 'Invalid playback position.'; end if;
 if v_session.last_heartbeat_at is null then
  update public.watch_sessions set last_heartbeat_at=now(),last_video_time=p_video_time where id=p_session_id;
  return jsonb_build_object('watched_seconds',0,'required_seconds',(select duration_seconds from public.watch_campaigns where id=v_session.campaign_id));
 end if;
 v_elapsed:=extract(epoch from (now()-v_session.last_heartbeat_at));
 if v_elapsed<2 then return jsonb_build_object('watched_seconds',v_session.watched_seconds,'ignored',true); end if;
 if p_page_visible and p_video_time>v_session.last_video_time and p_video_time-v_session.last_video_time<=12 and v_elapsed<=15 then
  v_delta:=least(10,floor(v_elapsed),floor(p_video_time-v_session.last_video_time));
 else v_delta:=0; end if;
 update public.watch_sessions set watched_seconds=watched_seconds+v_delta::integer,last_heartbeat_at=now(),last_video_time=greatest(last_video_time,p_video_time) where id=p_session_id;
 return jsonb_build_object('watched_seconds',v_session.watched_seconds+v_delta::integer,'required_seconds',(select duration_seconds from public.watch_campaigns where id=v_session.campaign_id));
end $$;

create or replace function public.watch_complete_session(p_session_id uuid,p_session_token uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid:=auth.uid(); v_session public.watch_sessions%rowtype; v_campaign public.watch_campaigns%rowtype; v_view public.watch_views%rowtype;
begin
 if v_user is null then raise exception 'Sign in to claim a reward.'; end if;
 select * into v_session from public.watch_sessions where id=p_session_id and user_id=v_user for update;
 if not found or v_session.session_token<>p_session_token then raise exception 'Viewing session could not be verified.'; end if;
 if v_session.status<>'started' then raise exception 'This viewing session has already been used.'; end if;
 select * into v_campaign from public.watch_campaigns where id=v_session.campaign_id;
 if now()<v_session.started_at+make_interval(secs=>v_campaign.duration_seconds) or v_session.watched_seconds<v_campaign.duration_seconds then raise exception 'The video has not met its verified playback requirement yet.'; end if;
 if now()>v_session.expires_at then update public.watch_sessions set status='expired' where id=p_session_id; raise exception 'Viewing session expired. Please start again.'; end if;
 select * into v_campaign from public.watch_campaigns where id=v_session.campaign_id for update;
 if not found or v_campaign.status<>'active' or v_campaign.funding_status<>'confirmed' then raise exception 'Campaign is no longer eligible for rewards.'; end if;
 if exists(select 1 from public.watch_views where campaign_id=v_campaign.id and user_id=v_user) then raise exception 'A reward has already been issued for this campaign.'; end if;
 if v_campaign.views_count>=v_campaign.max_views or v_campaign.spent_amount+v_campaign.reward_amount>v_campaign.funded_budget then raise exception 'Campaign reward budget is exhausted.'; end if;
 insert into public.watch_views(campaign_id,session_id,user_id,reward_amount) values(v_campaign.id,v_session.id,v_user,v_campaign.reward_amount) returning * into v_view;
 update public.watch_campaigns set views_count=views_count+1,spent_amount=spent_amount+v_campaign.reward_amount,status=case when views_count+1>=max_views or spent_amount+v_campaign.reward_amount>=funded_budget then 'completed' else status end,updated_at=now() where id=v_campaign.id;
 update public.watch_sessions set status='completed',completed_at=now() where id=v_session.id;
 insert into public.wallet_transactions(user_id,amount,currency,transaction_type,reference_id,idempotency_key,description)
 values(v_user,v_campaign.reward_amount,'BWP','watch_reward',v_view.id,'watch-view:'||v_view.id::text,'Verified Watch & Earn: '||v_campaign.title);
 insert into public.audit_events(actor_id,action,entity_type,entity_id,details)
 values(v_user,'watch_reward_issued','watch_view',v_view.id::text,jsonb_build_object('campaign_id',v_campaign.id,'amount',v_campaign.reward_amount,'session_id',v_session.id));
 return jsonb_build_object('success',true,'reward_amount',v_campaign.reward_amount,'currency','BWP','view_id',v_view.id);
end $$;

revoke all on function public.watch_begin_session(uuid,text) from public,anon;
revoke all on function public.watch_heartbeat(uuid,uuid,numeric,boolean) from public,anon;
revoke all on function public.watch_complete_session(uuid,uuid) from public,anon;
grant execute on function public.watch_begin_session(uuid,text) to authenticated;
grant execute on function public.watch_heartbeat(uuid,uuid,numeric,boolean) to authenticated;
grant execute on function public.watch_complete_session(uuid,uuid) to authenticated;

alter table public.advertisements add column if not exists slot_fee_bwp numeric(12,2) not null default 0 check (slot_fee_bwp>=0);
alter table public.advertisements add column if not exists amount_paid_bwp numeric(12,2) not null default 0 check (amount_paid_bwp>=0);
alter table public.advertisements add column if not exists payment_status text not null default 'pending' check (payment_status in ('pending','paid','waived','refunded'));
alter table public.advertisements add column if not exists impressions bigint not null default 0;
alter table public.advertisements add column if not exists clicks bigint not null default 0;
create or replace function public.track_banner_ad_event(p_ad_id uuid,p_event text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if p_event='impression' then update public.advertisements set impressions=impressions+1 where id=p_ad_id and status='active' and payment_status in ('paid','waived');
 elsif p_event='click' then update public.advertisements set clicks=clicks+1 where id=p_ad_id and status='active' and payment_status in ('paid','waived');
 else raise exception 'Invalid ad event.'; end if;
end $$;
revoke all on function public.track_banner_ad_event(uuid,text) from public;
grant execute on function public.track_banner_ad_event(uuid,text) to anon,authenticated;
