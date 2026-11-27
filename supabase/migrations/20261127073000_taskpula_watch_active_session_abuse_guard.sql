create unique index if not exists watch_sessions_one_active_per_user_campaign
 on public.watch_sessions(campaign_id,user_id) where status='started';
create or replace function public.watch_begin_session(p_user_id uuid,p_campaign_id uuid,p_client_nonce text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_campaign public.watch_campaigns%rowtype; v_session public.watch_sessions%rowtype; v_today integer; v_active integer;
begin
 if coalesce(auth.role(),'')<>'service_role' or p_user_id is null then raise exception 'Not authorized.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
 if p_client_nonce is null or length(p_client_nonce)<16 or length(p_client_nonce)>128 then raise exception 'Invalid viewing session request.'; end if;
 update public.watch_sessions set status='expired' where user_id=p_user_id and campaign_id=p_campaign_id and status='started' and expires_at<=now();
 select count(*) into v_active from public.watch_sessions where user_id=p_user_id and status='started' and expires_at>now();
 if v_active>=3 then raise exception 'You already have several active viewing sessions. Finish or allow one to expire before starting another.'; end if;
 if exists(select 1 from public.watch_sessions where user_id=p_user_id and campaign_id=p_campaign_id and status='started' and expires_at>now()) then raise exception 'You already have an active session for this video.'; end if;
 select * into v_campaign from public.watch_campaigns where id=p_campaign_id for update;
 if not found or v_campaign.status<>'active' or v_campaign.funding_status<>'confirmed' or (v_campaign.starts_at is not null and v_campaign.starts_at>now()) or (v_campaign.ends_at is not null and v_campaign.ends_at<=now()) then raise exception 'This video campaign is not available or its funding is not confirmed.'; end if;
 select count(*) into v_today from public.watch_views where campaign_id=p_campaign_id and user_id=p_user_id and verified_at>=date_trunc('day',now());
 if v_today>=v_campaign.daily_limit_per_user then raise exception 'You have reached today’s viewing limit for this campaign.'; end if;
 if v_campaign.views_count>=v_campaign.max_views or v_campaign.spent_amount+v_campaign.reward_amount>v_campaign.funded_budget then raise exception 'This campaign has reached its reward limit.'; end if;
 insert into public.watch_sessions(campaign_id,user_id,expires_at,client_nonce) values(p_campaign_id,p_user_id,now()+make_interval(secs=>v_campaign.duration_seconds+600),p_client_nonce) returning * into v_session;
 return jsonb_build_object('session_id',v_session.id,'session_token',v_session.session_token,'duration_seconds',v_campaign.duration_seconds,'started_at',v_session.started_at);
end $$;