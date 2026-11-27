-- Lock down browser-inaccessible reward RPCs and deduplicate public banner analytics.
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
 select p_ad_id,p_visitor_hash,p_event,v_bucket where exists(select 1 from public.advertisements where id=p_ad_id and status='active' and payment_status in ('paid','waived')) on conflict do nothing;
 get diagnostics v_inserted=row_count;
 if v_inserted=1 and p_event='impression' then update public.advertisements set impressions=impressions+1 where id=p_ad_id;
 elsif v_inserted=1 and p_event='click' then update public.advertisements set clicks=clicks+1 where id=p_ad_id; end if;
end $$;
revoke all on function public.track_banner_ad_event(uuid,text,text) from public,anon,authenticated;
grant execute on function public.track_banner_ad_event(uuid,text,text) to service_role;

drop function if exists public.watch_begin_session(uuid,text);
drop function if exists public.watch_heartbeat(uuid,uuid,numeric,boolean);
drop function if exists public.watch_complete_session(uuid,uuid);
create or replace function public.watch_begin_session(p_user_id uuid,p_campaign_id uuid,p_client_nonce text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_campaign public.watch_campaigns%rowtype; v_session public.watch_sessions%rowtype; v_today integer;
begin
 if coalesce(auth.role(),'')<>'service_role' or p_user_id is null then raise exception 'Not authorized.'; end if;
 if p_client_nonce is null or length(p_client_nonce)<16 or length(p_client_nonce)>128 then raise exception 'Invalid viewing session request.'; end if;
 select * into v_campaign from public.watch_campaigns where id=p_campaign_id for update;
 if not found or v_campaign.status<>'active' or v_campaign.funding_status<>'confirmed' or (v_campaign.starts_at is not null and v_campaign.starts_at>now()) or (v_campaign.ends_at is not null and v_campaign.ends_at<=now()) then raise exception 'This video campaign is not available or its funding is not confirmed.'; end if;
 select count(*) into v_today from public.watch_views where campaign_id=p_campaign_id and user_id=p_user_id and verified_at>=date_trunc('day',now());
 if v_today>=v_campaign.daily_limit_per_user then raise exception 'You have reached today’s viewing limit for this campaign.'; end if;
 if v_campaign.views_count>=v_campaign.max_views or v_campaign.spent_amount+v_campaign.reward_amount>v_campaign.funded_budget then raise exception 'This campaign has reached its reward limit.'; end if;
 insert into public.watch_sessions(campaign_id,user_id,expires_at,client_nonce) values(p_campaign_id,p_user_id,now()+make_interval(secs=>v_campaign.duration_seconds+600),p_client_nonce) returning * into v_session;
 return jsonb_build_object('session_id',v_session.id,'session_token',v_session.session_token,'duration_seconds',v_campaign.duration_seconds,'started_at',v_session.started_at);
end $$;
create or replace function public.watch_heartbeat(p_user_id uuid,p_session_id uuid,p_session_token uuid,p_video_time numeric,p_page_visible boolean)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_session public.watch_sessions%rowtype; v_delta numeric; v_elapsed numeric;
begin
 if coalesce(auth.role(),'')<>'service_role' or p_user_id is null then raise exception 'Not authorized.'; end if;
 select * into v_session from public.watch_sessions where id=p_session_id and user_id=p_user_id for update;
 if not found or v_session.session_token<>p_session_token or v_session.status<>'started' then raise exception 'Viewing session is invalid.'; end if;
 if now()>v_session.expires_at then update public.watch_sessions set status='expired' where id=p_session_id; raise exception 'Viewing session expired.'; end if;
 if p_video_time is null or p_video_time<0 or p_video_time>36000 then raise exception 'Invalid playback position.'; end if;
 if v_session.last_heartbeat_at is null then update public.watch_sessions set last_heartbeat_at=now(),last_video_time=p_video_time where id=p_session_id; return jsonb_build_object('watched_seconds',0,'required_seconds',(select duration_seconds from public.watch_campaigns where id=v_session.campaign_id)); end if;
 v_elapsed:=extract(epoch from (now()-v_session.last_heartbeat_at));
 if v_elapsed<2 then return jsonb_build_object('watched_seconds',v_session.watched_seconds,'ignored',true); end if;
 if p_page_visible and p_video_time>v_session.last_video_time and p_video_time-v_session.last_video_time<=12 and v_elapsed<=15 then v_delta:=least(10,floor(v_elapsed),floor(p_video_time-v_session.last_video_time)); else v_delta:=0; end if;
 update public.watch_sessions set watched_seconds=watched_seconds+v_delta::integer,last_heartbeat_at=now(),last_video_time=greatest(last_video_time,p_video_time) where id=p_session_id;
 return jsonb_build_object('watched_seconds',v_session.watched_seconds+v_delta::integer,'required_seconds',(select duration_seconds from public.watch_campaigns where id=v_session.campaign_id));
end $$;
create or replace function public.watch_complete_session(p_user_id uuid,p_session_id uuid,p_session_token uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_session public.watch_sessions%rowtype; v_campaign public.watch_campaigns%rowtype; v_view public.watch_views%rowtype; v_today integer;
begin
 if coalesce(auth.role(),'')<>'service_role' or p_user_id is null then raise exception 'Not authorized.'; end if;
 select * into v_session from public.watch_sessions where id=p_session_id and user_id=p_user_id for update;
 if not found or v_session.session_token<>p_session_token then raise exception 'Viewing session could not be verified.'; end if;
 if v_session.status<>'started' then raise exception 'This viewing session has already been used.'; end if;
 select * into v_campaign from public.watch_campaigns where id=v_session.campaign_id;
 if now()<v_session.started_at+make_interval(secs=>v_campaign.duration_seconds) or v_session.watched_seconds<v_campaign.duration_seconds then raise exception 'The video has not met its verified playback requirement yet.'; end if;
 if now()>v_session.expires_at then update public.watch_sessions set status='expired' where id=p_session_id; raise exception 'Viewing session expired. Please start again.'; end if;
 select * into v_campaign from public.watch_campaigns where id=v_session.campaign_id for update;
 if not found or v_campaign.status<>'active' or v_campaign.funding_status<>'confirmed' then raise exception 'Campaign is no longer eligible for rewards.'; end if;
 select count(*) into v_today from public.watch_views where campaign_id=v_campaign.id and user_id=p_user_id and verified_at>=date_trunc('day',now());
 if v_today>=v_campaign.daily_limit_per_user then raise exception 'You have reached today’s viewing limit for this campaign.'; end if;
 if v_campaign.views_count>=v_campaign.max_views or v_campaign.spent_amount+v_campaign.reward_amount>v_campaign.funded_budget then raise exception 'Campaign reward budget is exhausted.'; end if;
 insert into public.watch_views(campaign_id,session_id,user_id,reward_amount) values(v_campaign.id,v_session.id,p_user_id,v_campaign.reward_amount) returning * into v_view;
 update public.watch_campaigns set views_count=views_count+1,spent_amount=spent_amount+v_campaign.reward_amount,status=case when views_count+1>=max_views or spent_amount+v_campaign.reward_amount>=funded_budget then 'completed' else status end,updated_at=now() where id=v_campaign.id;
 update public.watch_sessions set status='completed',completed_at=now() where id=v_session.id;
 insert into public.wallet_transactions(user_id,amount,currency,transaction_type,reference_id,idempotency_key,description) values(p_user_id,v_campaign.reward_amount,'BWP','watch_reward',v_view.id,'watch-view:'||v_view.id::text,'Verified Watch & Earn: '||v_campaign.title);
 insert into public.audit_events(actor_id,action,entity_type,entity_id,details) values(p_user_id,'watch_reward_issued','watch_view',v_view.id::text,jsonb_build_object('campaign_id',v_campaign.id,'amount',v_campaign.reward_amount,'session_id',v_session.id));
 return jsonb_build_object('success',true,'reward_amount',v_campaign.reward_amount,'currency','BWP','view_id',v_view.id);
end $$;
revoke all on function public.watch_begin_session(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.watch_heartbeat(uuid,uuid,uuid,numeric,boolean) from public,anon,authenticated;
revoke all on function public.watch_complete_session(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.watch_begin_session(uuid,uuid,text) to service_role;
grant execute on function public.watch_heartbeat(uuid,uuid,uuid,numeric,boolean) to service_role;
grant execute on function public.watch_complete_session(uuid,uuid,uuid) to service_role;
