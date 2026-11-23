# EarnLoop BW

EarnLoop BW is a Botswana-first task and rewards platform. Members create an account, discover sponsor tasks, complete the task, upload private photo evidence and receive a wallet-ledger credit only after staff approval.

## Connected MVP
- Supabase email/password authentication with email confirmation.
- Profile creation linked to the authenticated account.
- Live task listing from the EarnLoop BW database (no seeded or simulated offers).
- Private evidence uploads to the `task-evidence` bucket (JPEG, PNG or WebP; maximum 3 MB).
- Task submissions recorded for review.
- Submission status and wallet transactions read from the database.
- Wallet balance calculated from ledger transactions; no fake balance or local demo wallet.
- Responsive blue interface and installable web-app shell.

## Security
- Frontend uses only the Supabase publishable key.
- Evidence storage is private and controlled by Storage RLS.
- Database RLS controls profile, task, submission and wallet access.
- Rewards are credited through the protected review workflow, not from the browser.
- Never add service-role keys, passwords or payment secrets to this repository.

## Current limitations
- The task list will remain empty until an authorized staff member creates and activates a sponsor task.
- Staff review/admin screens are not yet included in this frontend.
- Wallet entries are accounting records only. Cash-out and payout-provider integration are not enabled.
- Referral attribution, sponsor self-service, fraud analytics and production monitoring remain future work.
- Keep the Supabase project on the free tier; provider limits and pricing can change, so do not enable paid services without explicit approval.

## Deploy
GitHub Pages should publish the `main` branch from the repository root over HTTPS. Update Supabase Authentication Site URL and redirect allow-list whenever the GitHub Pages repository name changes.
