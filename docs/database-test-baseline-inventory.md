# TaskPula database test baseline: inventory and blockers

Checked against the connected Supabase project on 2026-11-27 using schema metadata and migration history only.

## Safety boundary

- No application rows were exported or copied.
- No production SQL, migration, Edge Function deployment, or data mutation was performed.
- Do not connect CI to production or add production credentials to GitHub Actions.

## Current inventory

The connected database reports 26 public base tables, 17 public functions, 58 public RLS policies, and 66 public triggers. The migration history contains 33 applied records. The repository contains 18 SQL migration files; their identifiers and names do not form a complete one-to-one copy of the applied history.

## Why an empty-Postgres test is not ready

The repository has no `supabase/config.toml` and no clean baseline schema. Replaying only the checked-in incremental migrations into an empty PostgreSQL database is not a valid integration test: earlier definitions and Supabase platform dependencies are missing.

A schema-only baseline must include table definitions, defaults, constraints, indexes, sequences, RLS policies, functions, triggers, required extensions, and minimal auth-role/schema stubs. It must exclude application rows, auth users, secrets, storage objects, and production connection details.

## Acceptance criteria

1. CI uses an isolated ephemeral database only.
2. The baseline contains schema definitions only.
3. The proposed migration applies cleanly from that baseline.
4. Tests verify allowed and denied operations under member, staff/admin, and service-role contexts.
5. Wallet credit and payout tests include retry and concurrency cases.
6. Production remains untouched until separately approved.
