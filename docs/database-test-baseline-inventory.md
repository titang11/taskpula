# TaskPula database test baseline: inventory and blockers

Checked against the `test/taskpula-staging-validation` branch and the connected Supabase project on 2026-11-27.

## Safety boundary

- This inspection used schema metadata and migration history only.
- No application rows were exported or copied.
- No production SQL, migration, Edge Function deployment, or data mutation was performed.
- Do not connect CI to the production database or add production credentials to GitHub Actions.

## Current inventory

The connected Supabase database reports:

- 26 public base tables
- 17 public functions
- 58 public RLS policies
- 66 public triggers
- 5 installed extensions (including `pgcrypto`, `uuid-ossp`, `pg_stat_statements`, and `supabase_vault`; the Supabase-managed environment also supplies platform schemas and roles)

The database migration history contains 33 applied migration records.

The repository currently contains 18 SQL migration files under `supabase/migrations`. Their version identifiers and names do not form a complete, one-to-one copy of the applied database migration history. Some live migration records are not represented by files in this branch, and the branch also contains the proposed audit-remediation migration that has not been applied to production.

## Why the empty-Postgres test is not ready

The repository has no `supabase/config.toml` and no clean baseline schema. Replaying only the 18 checked-in migration files into an empty PostgreSQL database is not a valid integration test: earlier table/function/policy definitions are missing, and Supabase platform dependencies (auth roles/schemas and extensions) are not represented by the repository.

A test that only checks SQL text is useful as a preflight, but it does not prove that the migration executes, that RLS behaves correctly, or that wallet/budget operations are safe under concurrent transactions.

## Required next step

Create a **schema-only, no-data baseline** from the current Supabase project, then review it before committing it to this public repository. The baseline must include the relevant public schema objects and dependencies needed by tests:

- table definitions, defaults, constraints, indexes, and sequences
- RLS enablement and policies
- functions and triggers
- required extensions and minimal Supabase auth roles/schema stubs for local tests

Exclude all application rows, auth users, secrets, storage objects, and production connection details.

After the baseline is reviewed, the GitHub Actions workflow can start a disposable PostgreSQL/Supabase-compatible service, load the baseline, apply the proposed migration, and run database-level assertions for authorization, budget enforcement, duplicate approvals, payout state transitions, and banner-event deduplication.

## Acceptance criteria for the next phase

1. CI runs against an isolated ephemeral database only.
2. The baseline contains schema definitions only; no production data.
3. The proposed migration applies cleanly from the baseline.
4. Database tests verify both allowed and denied operations under member, staff/admin, and service-role contexts.
5. Wallet credit and payout tests include duplicate/retry and concurrent transaction cases.
6. Production remains untouched until the user explicitly approves a separately reviewed production rollout.
