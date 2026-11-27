# TaskPula

TaskPula is a Botswana-first digital marketing, market research and consumer engagement company powered by one technology platform. It connects business clients with a verified participant community and delivers measurable research, campaign, field-task and digital-growth outcomes.

## Business structure

- **TaskPula Research** — surveys, consumer insights and market studies.
- **TaskPula Campaigns** — brand activations, promotions and customer engagement.
- **TaskPula Tasks** — verified assignments, product trials and field activities.
- **TaskPula Digital Growth** — application marketing, software testing and user acquisition.
- **TaskPula Circle** — a distinct community identity and participant experience on the shared TaskPula platform.

## TaskPula Circle — hybrid model

Circle has its own member-facing identity and community experience while sharing TaskPula's authentication, profiles, campaign opportunities, wallet ledger, administration and Supabase backend. It is not a separate company, account system or wallet.

Membership framework:
1. Member
2. Contributor
3. Community Ambassador
4. Brand Representative

Membership levels and status are controlled by authorized administrators. Progression should reflect verified participation quality, suitability and reliability—not referral volume alone. Referral attribution is recorded through authenticated database functions; self-referrals are blocked. Referral activity does not automatically create a reward or membership upgrade.

Circle profiles contain member-selected display name, town, bio, interests, skills and an explicit opportunity-update consent preference.

## Connected platform

- Supabase email/password authentication with email confirmation.
- Profiles linked to authenticated accounts.
- Live task listing from Supabase; no seeded or simulated offers.
- Private evidence uploads to the `task-evidence` bucket (JPEG, PNG or WebP; maximum 3 MB).
- Task submissions recorded for review.
- Admin-managed sponsor directory.
- Campaign records linked to sponsors, with BWP budget caps and start/end dates.
- Campaign funding ledger separates pledged funds from confirmed receipts and refunds.
- Tasks can be linked to campaigns; activation requires sufficient confirmed sponsor funding.
- Admin-managed service-provider directory.
- Circle member profiles, referral codes, referral attribution and admin membership controls.
- Submission status and wallet transactions read from the database.
- Wallet balance calculated from the transaction ledger; no fake balance or local demo wallet.
- White-and-silver glassmorphism interface with blue accents, transparent vector branding, round floating menu control and responsive web-app shell.
- Distinct member and administrator workspaces. The administrator navigation entry is hidden until the server confirms staff authorization.
- Banner advertisement upload includes a creative preview, secure HTTPS destination validation, schedule validation, payment confirmation and approval controls.
- Administrator Fraud & Trust view summarizes verified Watch & Earn session controls and highlights repeated task-submission or failed-session patterns for human review.

## Security and financial controls

- Frontend uses only the Supabase publishable key.
- Never commit service-role keys, database connection strings, passwords or payment secrets.
- Row-level security is enabled on application tables.
- Anonymous access to public application tables is revoked; member and business data requires authentication.
- Circle profile writes are limited to member-editable columns. Membership level, membership status and referral status are controlled through guarded admin functions.
- Admin membership and referral decisions are written to the private audit log.
- Evidence storage is private and controlled by Storage RLS. Members can upload to their own folder and read their own evidence; authorized staff can review evidence.
- Members can read their own submissions and wallet ledger. Browser-side wallet writes are not granted.
- Rewards are credited through the protected submission-review workflow, not directly from the browser.
- Campaign funding and activation checks run in database controls; unconfirmed pledges are not spendable.
- Client data is tenant-scoped through sponsor membership policies.

## Commercial operating rule

Client campaign funding must be received and confirmed before TaskPula publishes funded opportunities or commits participant rewards. TaskPula does not finance client reward commitments from its own operating cash.

## Current limitations and launch checks

- The task list remains empty until an authorized staff member creates and activates a funded task.
- Wallet entries are accounting records only. Cash-out and payout-provider integration are not enabled.
- Live account registration, email confirmation, member submissions, staff reviews and wallet credits still require end-to-end testing with authorized test accounts.
- Supabase leaked-password protection should be enabled in Authentication password security settings.
- The private audit log intentionally has no client-facing RLS policy; it remains in the non-exposed private schema.
- Sponsor self-service workflows, payment reconciliation, cross-department automated fraud scoring, device/IP risk correlation, and production monitoring still require further work. The Fraud & Trust screen provides operational indicators; it is not a complete automated fraud decision engine.
- Supabase leaked-password protection must be enabled in Authentication password security settings before public launch.
- Keep the Supabase project on the free tier unless the owner explicitly approves a paid service.

## Deploy

GitHub Pages is configured to publish the `main` branch from the repository root over HTTPS. Verify the live site after each deployment. Keep the Supabase Authentication Site URL and redirect allow-list aligned with the GitHub Pages URL.
