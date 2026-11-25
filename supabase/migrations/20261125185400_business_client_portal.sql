-- TaskPula business customer portal: tenant-scoped sponsor access and campaign requests.
-- Clients can create their own sponsor profile, submit campaign briefs, and read only
-- their sponsor's campaigns, funding status, and campaign task summaries.
-- Actual funding entries, campaign activation, and task publishing remain staff-controlled.

create table if not exists public.sponsor_memberships (
  id uuid primary key default gen_random_uuid(),
  sponsor_id uuid not null references public.sponsors(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner','member')),
  invited_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (sponsor_id, user_id)
);

create index if not exists sponsor_memberships_user_idx
  on public.sponsor_memberships(user_id, sponsor_id);

create table if not exists public.campaign_requests (
  id uuid primary key default gen_random_uuid(),
  sponsor_id uuid not null references public.sponsors(id) on delete restrict,
  requested_by uuid not null references auth.users(id) on delete restrict,
  campaign_name text not null check (char_length(btrim(campaign_name)) between 3 and 140),
  objective text not null default '',
  target_audience text not null default '',
  deliverables text not null default '',
  proposed_budget numeric(12,2) not null check (proposed_budget > 0),
  preferred_start date,
  preferred_end date,
  status text not null default 'submitted'
    check (status in ('submitted','under_review','needs_information','approved','declined','converted')),
  admin_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  converted_campaign_id uuid references public.campaigns(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (preferred_end is null or preferred_start is null or preferred_end >= preferred_start)
);

create index if not exists campaign_requests_sponsor_created_idx
  on public.campaign_requests(sponsor_id, created_at desc);

alter table public.sponsor_memberships enable row level security;
alter table public.campaign_requests enable row level security;

grant select, insert on public.sponsor_memberships to authenticated;
grant select, insert on public.campaign_requests to authenticated;
grant select, insert on public.sponsors to authenticated;
grant select on public.campaigns, public.campaign_funding, public.tasks to authenticated;

drop policy if exists "client read own sponsor memberships" on public.sponsor_memberships;
create policy "client read own sponsor memberships"
on public.sponsor_memberships for select to authenticated
using (user_id = (select auth.uid()) or private.is_staff());

drop policy if exists "client create own sponsor owner membership" on public.sponsor_memberships;
create policy "client create own sponsor owner membership"
on public.sponsor_memberships for insert to authenticated
with check (
  user_id = (select auth.uid())
  and role = 'owner'
  and exists (
    select 1 from public.sponsors s
    where s.id = sponsor_id and s.created_by = (select auth.uid())
  )
);

drop policy if exists "staff manage sponsor memberships" on public.sponsor_memberships;
create policy "staff manage sponsor memberships"
on public.sponsor_memberships for all to authenticated
using (private.is_staff('admin'))
with check (private.is_staff('admin'));

drop policy if exists "client create own sponsor profile" on public.sponsors;
create policy "client create own sponsor profile"
on public.sponsors for insert to authenticated
with check (created_by = (select auth.uid()) and status = 'active');

drop policy if exists "client read own sponsor profile" on public.sponsors;
create policy "client read own sponsor profile"
on public.sponsors for select to authenticated
using (
  exists (
    select 1 from public.sponsor_memberships sm
    where sm.sponsor_id = sponsors.id and sm.user_id = (select auth.uid())
  )
);

drop policy if exists "client read own sponsor campaigns" on public.campaigns;
create policy "client read own sponsor campaigns"
on public.campaigns for select to authenticated
using (
  exists (
    select 1 from public.sponsor_memberships sm
    where sm.sponsor_id = campaigns.sponsor_id and sm.user_id = (select auth.uid())
  )
);

drop policy if exists "client read own campaign funding" on public.campaign_funding;
create policy "client read own campaign funding"
on public.campaign_funding for select to authenticated
using (
  exists (
    select 1 from public.sponsor_memberships sm
    where sm.sponsor_id = campaign_funding.sponsor_id and sm.user_id = (select auth.uid())
  )
);

drop policy if exists "client read own campaign tasks" on public.tasks;
create policy "client read own campaign tasks"
on public.tasks for select to authenticated
using (
  campaign_id is not null
  and exists (
    select 1
    from public.campaigns c
    join public.sponsor_memberships sm on sm.sponsor_id = c.sponsor_id
    where c.id = tasks.campaign_id and sm.user_id = (select auth.uid())
  )
);

drop policy if exists "client read own campaign requests" on public.campaign_requests;
create policy "client read own campaign requests"
on public.campaign_requests for select to authenticated
using (
  exists (
    select 1 from public.sponsor_memberships sm
    where sm.sponsor_id = campaign_requests.sponsor_id
      and sm.user_id = (select auth.uid())
  )
);

drop policy if exists "client submit campaign request" on public.campaign_requests;
create policy "client submit campaign request"
on public.campaign_requests for insert to authenticated
with check (
  requested_by = (select auth.uid())
  and status = 'submitted'
  and reviewed_by is null
  and reviewed_at is null
  and admin_note is null
  and converted_campaign_id is null
  and exists (
    select 1 from public.sponsor_memberships sm
    where sm.sponsor_id = campaign_requests.sponsor_id
      and sm.user_id = (select auth.uid())
  )
);

drop policy if exists "staff manage campaign requests" on public.campaign_requests;
create policy "staff manage campaign requests"
on public.campaign_requests for all to authenticated
using (private.is_staff('admin'))
with check (private.is_staff('admin'));
