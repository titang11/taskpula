# TaskPula audit preflight CI

The workflow at `.github/workflows/taskpula-audit-tests.yml` runs on pushes to
`chore/taskpula-ci-infrastructure`, pull requests targeting `main`, and manual
dispatch. It requires no GitHub secrets and uses no production Supabase credentials.

## What the workflow checks

- JavaScript syntax for root-level application modules.
- Static safeguard contracts in the proposed audit-remediation SQL migration.
- Deno type-checking for `taskpula-banner-track`.
- Git whitespace errors.

These are preflight checks only. They do **not** prove that PostgreSQL accepts the
migration, that database objects and policies behave correctly, or that payout
concurrency and campaign-budget race conditions are safe.

## Database integration tests are a separate gate

The repository does not yet contain a complete reproducible baseline schema or a
`supabase/config.toml` for a clean local Supabase reset. The incremental migrations
depend on database objects and Supabase platform roles already present in the live
project. Running them against an empty CI database would be misleading.

The next safe step is a reviewed schema-only snapshot (no customer rows, auth users,
secrets, or storage objects), followed by an isolated disposable database fixture.
CI must never connect to production Supabase.

## Public repository warning

This repository and its branches are public. Workflow source, logs, and fixtures
must contain synthetic data only. Never add service-role keys, database passwords,
real member data, or production transaction exports.
