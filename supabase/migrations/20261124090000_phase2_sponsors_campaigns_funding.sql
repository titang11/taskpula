-- EarnLoop BW Phase 2: sponsor, campaign, funding and service-provider foundations.
alter table public.sponsors add column if not exists contact_name text, add column if not exists phone text, add column if not exists website text, add column if not exists industry text, add column if not exists location text, add column if not exists notes text, add column if not exists created_by uuid references auth.users(id);
create table if not exists public.campaigns (
 id uuid primary key default gen_random_uuid(), sponsor_id uuid not null references public.sponsors(id) on delete restrict,
 name text not null check(char_length(name) between 3 and 140), objective text not null default '', target_audience text not null default '',
 budget_cap numeric(12,2) not null check(budget_cap>0), currency text not null default 'BWP' check(currency='BWP'),
 starts_at timestamptz, ends_at timestamptz, status text not null default 'draft' check(status in ('draft','active','paused','completed','cancelled')),
 created_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(ends_at is null or starts_at is null or ends_at>starts_at));
create table if not exists public.campaign_funding (
 id uuid primary key default gen_random_uuid(), campaign_id uuid not null references public.campaigns(id) on delete restrict,
 sponsor_id uuid not null references public.sponsors(id) on delete restrict, amount numeric(12,2) not null check(amount>0),
 entry_type text not null check(entry_type in ('pledged','received','refund','adjustment')),
 status text not null default 'pending' check(status in ('pending','confirmed','cancelled')), reference_note text not null default '',
 received_at timestamptz, recorded_by uuid references auth.users(id), created_at timestamptz not null default now());
create table if not exists public.service_providers (
 id uuid primary key default gen_random_uuid(), business_name text not null check(char_length(business_name) between 2 and 140),
 contact_name text, email text, phone text, service_categories text[] not null default '{}', coverage_area text, notes text,
 status text not null default 'pending' check(status in ('pending','approved','paused','rejected')),
 created_by uuid references auth.users(id), created_at timestamptz not null default now());
alter table public.tasks add column if not exists campaign_id uuid references public.campaigns(id) on delete restrict;
create index if not exists campaigns_sponsor_created_idx on public.campaigns(sponsor_id,created_at desc);
create index if not exists campaign_funding_campaign_status_idx on public.campaign_funding(campaign_id,status,entry_type);
create index if not exists tasks_campaign_idx on public.tasks(campaign_id);
alter table public.campaigns enable row level security; alter table public.campaign_funding enable row level security; alter table public.service_providers enable row level security;
drop policy if exists "campaigns staff read" on public.campaigns;
create policy "campaigns staff read" on public.campaigns for select to authenticated using(private.is_staff());
drop policy if exists "campaigns admin manage" on public.campaigns;
create policy "campaigns admin manage" on public.campaigns for all to authenticated using(private.is_staff('admin')) with check(private.is_staff('admin'));
drop policy if exists "campaign funding staff read" on public.campaign_funding;
create policy "campaign funding staff read" on public.campaign_funding for select to authenticated using(private.is_staff());
drop policy if exists "campaign funding admin manage" on public.campaign_funding;
create policy "campaign funding admin manage" on public.campaign_funding for all to authenticated using(private.is_staff('admin')) with check(private.is_staff('admin'));
drop policy if exists "service providers staff read" on public.service_providers;
create policy "service providers staff read" on public.service_providers for select to authenticated using(private.is_staff());
drop policy if exists "service providers admin manage" on public.service_providers;
create policy "service providers admin manage" on public.service_providers for all to authenticated using(private.is_staff('admin')) with check(private.is_staff('admin'));

create or replace function private.enforce_campaign_funding()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_campaign public.campaigns%rowtype; v_confirmed numeric(12,2); v_committed numeric(12,2);
begin
 if new.campaign_id is null then return new; end if;
 select * into v_campaign from public.campaigns where id=new.campaign_id for update;
 if not found then raise exception 'Campaign not found'; end if;
 if new.sponsor_id is distinct from v_campaign.sponsor_id then raise exception 'Task sponsor must match its campaign sponsor'; end if;
 select coalesce(sum(case when entry_type in ('received','adjustment') then amount when entry_type='refund' then -amount else 0 end),0)
 into v_confirmed from public.campaign_funding where campaign_id=new.campaign_id and status='confirmed';
 select coalesce(sum(budget_amount),0) into v_committed from public.tasks where campaign_id=new.campaign_id and status='active' and id<>new.id;
 if new.status='active' and v_campaign.status<>'active' then raise exception 'Campaign must be active before activating its tasks'; end if;
 if new.status='active' and v_confirmed<v_committed+new.budget_amount then raise exception 'Confirmed campaign funds are insufficient for this task budget'; end if;
 return new;
end; $function$;
drop trigger if exists enforce_task_campaign_funding on public.tasks;
create trigger enforce_task_campaign_funding before insert or update of campaign_id,sponsor_id,budget_amount,status on public.tasks for each row execute function private.enforce_campaign_funding();

create or replace function private.enforce_campaign_funding_entry()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_campaign public.campaigns%rowtype; v_net numeric(12,2); v_delta numeric(12,2); v_committed numeric(12,2);
begin
 select * into v_campaign from public.campaigns where id=new.campaign_id for update;
 if not found then raise exception 'Campaign not found'; end if;
 if new.sponsor_id is distinct from v_campaign.sponsor_id then raise exception 'Funding sponsor must match campaign sponsor'; end if;
 if new.status='confirmed' then
  v_delta:=case when new.entry_type in ('received','adjustment') then new.amount when new.entry_type='refund' then -new.amount else 0 end;
  select coalesce(sum(case when entry_type in ('received','adjustment') then amount when entry_type='refund' then -amount else 0 end),0) into v_net
   from public.campaign_funding where campaign_id=new.campaign_id and status='confirmed' and id<>new.id;
  if v_net+v_delta<0 then raise exception 'Refund exceeds confirmed campaign funds'; end if;
  if v_net+v_delta>v_campaign.budget_cap then raise exception 'Confirmed funding cannot exceed the campaign budget cap'; end if;
  select coalesce(sum(budget_amount),0) into v_committed from public.tasks where campaign_id=new.campaign_id and status='active';
  if v_net+v_delta<v_committed then raise exception 'Confirmed funds cannot fall below active task budget commitments'; end if;
 end if;
 return new;
end; $function$;
drop trigger if exists enforce_campaign_funding_entry on public.campaign_funding;
create trigger enforce_campaign_funding_entry before insert or update of campaign_id,sponsor_id,amount,entry_type,status on public.campaign_funding for each row execute function private.enforce_campaign_funding_entry();

create or replace function private.enforce_campaign_activation()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_funded numeric(12,2); v_committed numeric(12,2);
begin
 if new.status='active' then
  select coalesce(sum(case when entry_type in ('received','adjustment') then amount when entry_type='refund' then -amount else 0 end),0) into v_funded
   from public.campaign_funding where campaign_id=new.id and status='confirmed';
  select coalesce(sum(budget_amount),0) into v_committed from public.tasks where campaign_id=new.id and status='active';
  if v_funded<=0 then raise exception 'Campaign needs confirmed funding before activation'; end if;
  if v_funded<v_committed then raise exception 'Confirmed funds are below active task commitments'; end if;
 end if;
 new.updated_at=now(); return new;
end; $function$;
drop trigger if exists enforce_campaign_activation on public.campaigns;
create trigger enforce_campaign_activation before insert or update on public.campaigns for each row execute function private.enforce_campaign_activation();

drop trigger if exists audit_campaign_admin_changes on public.campaigns;
create trigger audit_campaign_admin_changes after insert or update or delete on public.campaigns for each row execute function private.audit_admin_mutations();
drop trigger if exists audit_campaign_funding_admin_changes on public.campaign_funding;
create trigger audit_campaign_funding_admin_changes after insert or update or delete on public.campaign_funding for each row execute function private.audit_admin_mutations();
drop trigger if exists audit_service_provider_admin_changes on public.service_providers;
create trigger audit_service_provider_admin_changes after insert or update or delete on public.service_providers for each row execute function private.audit_admin_mutations();
revoke execute on function private.enforce_campaign_funding() from public,anon,authenticated;
revoke execute on function private.enforce_campaign_funding_entry() from public,anon,authenticated;
revoke execute on function private.enforce_campaign_activation() from public,anon,authenticated;
revoke all on public.campaigns,public.campaign_funding,public.service_providers from anon;
grant select,insert,update,delete on public.campaigns,public.campaign_funding,public.service_providers to authenticated;
