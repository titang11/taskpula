-- Tighten anonymous banner access to the exact columns needed by the public landing page.
begin;
revoke select, trigger on table public.advertisements from anon;
grant select (id, advertiser_name, title, image_path, destination_url, status,
  starts_at, ends_at, display_order, created_at, payment_status)
on table public.advertisements to anon;
commit;