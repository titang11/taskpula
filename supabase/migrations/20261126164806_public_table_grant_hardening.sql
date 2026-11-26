-- Remove unnecessary anonymous access from all public application tables.
-- TaskPula requires an authenticated member/client account for app data access.
revoke all privileges on all tables in schema public from anon;

-- Keep member-facing tables on least-privilege grants.
revoke all privileges on table public.profiles from authenticated;
grant select, insert, update on table public.profiles to authenticated;

revoke all privileges on table public.tasks from authenticated;
grant select, insert, update on table public.tasks to authenticated;

revoke all privileges on table public.task_submissions from authenticated;
grant select, insert on table public.task_submissions to authenticated;

revoke all privileges on table public.wallet_transactions from authenticated;
grant select on table public.wallet_transactions to authenticated;
