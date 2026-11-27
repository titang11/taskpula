-- Shared TaskPula landing page: public banner inventory is visible only when paid and live.
-- Visitors and authenticated members use the same public landing page.
begin;

alter table public.advertisements enable row level security;

drop policy if exists "Public can view active advertisements" on public.advertisements;
drop policy if exists "Public can view paid active advertisements" on public.advertisements;
create policy "Public can view paid active advertisements"
on public.advertisements
for select
to anon, authenticated
using (
  status = 'active'
  and payment_status in ('paid', 'waived')
  and (starts_at is null or starts_at <= now())
  and (ends_at is null or ends_at > now())
);

-- Anonymous visitors may read only the fields needed to render a paid banner.
-- Remove the legacy anonymous write/metadata privileges on this advertising table.
revoke insert, update, delete, truncate, references
on table public.advertisements from anon;

revoke select (id, advertiser_name, title, image_path, destination_url, status,
  starts_at, ends_at, display_order, created_by, created_at, updated_at,
  slot_fee_bwp, amount_paid_bwp, payment_status, impressions, clicks),
  insert (id, advertiser_name, title, image_path, destination_url, status,
  starts_at, ends_at, display_order, created_by, created_at, updated_at,
  slot_fee_bwp, amount_paid_bwp, payment_status, impressions, clicks),
  update (id, advertiser_name, title, image_path, destination_url, status,
  starts_at, ends_at, display_order, created_by, created_at, updated_at,
  slot_fee_bwp, amount_paid_bwp, payment_status, impressions, clicks),
  references (id, advertiser_name, title, image_path, destination_url, status,
  starts_at, ends_at, display_order, created_by, created_at, updated_at,
  slot_fee_bwp, amount_paid_bwp, payment_status, impressions, clicks)
on table public.advertisements from anon;

grant select (id, advertiser_name, title, image_path, destination_url, status,
  starts_at, ends_at, display_order, created_at, payment_status)
on table public.advertisements to anon;

commit;