# TaskPula

TaskPula is a Botswana-first task and rewards platform. Members create an account, discover sponsor tasks, complete the task, upload private photo evidence and receive a wallet-ledger credit only after staff approval.

## Connected MVP
- Supabase email/password authentication with email confirmation.
- Profile creation linked to the authenticated account.
- Live task listing from the TaskPula database (no seeded or simulated offers).
- Private evidence uploads to the `task-evidence` bucket (JPEG, PNG or WebP; maximum 3 MB).
- Task submissions recorded for review.
- Admin-managed sponsor directory with company, contact and industry details.
- Campaign records linked to sponsors, with BWP budget caps and start/end dates.
- Campaign funding ledger separates pledged funds from confirmed receipts and refunds.
- Tasks can be linked to campaigns; activation is blocked unless campaign funds are confirmed and sufficient.
- Admin-managed service-provider directory for local campaign fulfilment.
- Submission status and wallet transactions read from the database.
- Wallet balance calculated from ledger transactions; no fake balance or local demo wallet.
- Responsive blue interface and installable web-app shell.

## Security
- Frontend uses only the Supabase publishable key.
- Evidence storage is private and controlled by Storage RLS.
- Database RLS controls profile, task, submission, wallet, sponsor, campaign, funding and provider access.
- Sponsor, campaign, funding and service-provider records are restricted to staff; management writes are admin-only.
- Campaign funding and activation checks run in database triggers; unconfirmed pledges are not spendable.
- Rewards are credited through the protected review workflow, not from the browser.
- Never add service-role keys, passwords or payment secrets to this repository.

## Current limitations
- The task list will remain empty until an authorized staff member creates and activates a sponsor task.
- Admin dashboard includes sponsor registration, campaign creation, funding records and service-provider management.
- Wallet entries are accounting records only. Cash-out and payout-provider integration are not enabled.
- Sponsor self-service portal, provider self-registration, automated payment reconciliation, referral attribution, fraud analytics and production monitoring remain future work.
- Keep the Supabase project on the free tier; provider limits and pricing can change, so do not enable paid services without explicit approval.

## Deploy
GitHub Pages should publish the `main` branch from the repository root over HTTPS. Update Supabase Authentication Site URL and redirect allow-list whenever the GitHub Pages repository name changes.
