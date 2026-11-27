# TaskPula audit preflight CI

The workflow at `.github/workflows/taskpula-audit-tests.yml` runs on pushes to
`test/taskpula-staging-validation`, pull requests targeting `main`, and manual
dispatch. It requires no GitHub secrets and uses no production Supabase credentials.

## What the workflow checks

- JavaScript syntax for the root-level application modules.
- Static safeguard contracts in the audit-remediation SQL migration.
- Deno type-checking for `taskpula-banner-track`.
- Git whitespace errors.

These are preflight checks only. They do **not** prove that PostgreSQL accepts the
migration, that database objects and policies behave correctly, or that payout
concurrency and campaign-budget race conditions are safe.

## Why database integration tests are not enabled yet

The repository currently contains incremental Supabase migrations that depend on
tables, schemas, functions, roles, and policies already present in the live Supabase
project. It does not contain a complete reproducible baseline schema or a
`supabase/config.toml` for a clean local Supabase reset. Running the incremental
migrations against an empty CI database would therefore be misleading and may fail
before reaching the remediation migration.

The next safe step is to obtain and review a schema-only snapshot (no customer rows,
auth users, secrets, or storage objects), then build a disposable local Supabase
test fixture from that reviewed baseline. Only then should CI apply the complete
migration chain and run SQL integration tests for:

- concurrent wallet payout reservations and settlement;
- campaign funding and combined department budget caps;
- duplicate submissions and participant limits;
- atomic reward approval and ledger idempotency;
- RLS and role-boundary checks;
- banner event validation and deduplication.

No workflow in this branch connects to or writes to production Supabase.

## Public repository warning

This repository and its branches are public. Workflow source, logs, and test
fixtures must contain synthetic data only. Never add service-role keys, database
passwords, real member data, or production transaction exports.
