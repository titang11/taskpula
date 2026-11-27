# TaskPula audit remediation — staging verification plan

This branch contains code and a database migration proposal only. It has not changed the production Supabase database and the Edge Function has not been deployed.

## Architecture changes
- Research studies and Digital Growth projects now carry a campaign link, a dedicated BWP reward budget, and a maximum paid-participant count.
- Campaign commitment calculations include tasks, research studies, and Digital Growth projects. Active, paused, and completed programmes retain their budget reservation.
- New submissions are rejected when a programme is not active, is not linked to a live funded campaign, has already accepted the maximum number of non-rejected entries, or already has an active/approved entry for that member.
- Research and Growth approval functions lock their parent programme, enforce the funded reward cap, and credit the wallet ledger once per submission.
- Wallet payout request and settlement functions serialize by member using transaction-scoped advisory locks.
- Banner impressions are counted only after the page reports at least 50% visibility for one second. The Edge Function signs visitor identifiers with HMAC before sending them to the deduplication RPC.

## Staging test checklist

### Campaign funding and department budgets
1. Create a campaign with a BWP budget cap and no confirmed funding. Activation must fail.
2. Record a pledge. It must not count as spendable funding.
3. Record a confirmed receipt. Activation must succeed only when the campaign has enough confirmed funding.
4. Create a task, Research study, and Digital Growth project with a combined budget larger than confirmed funds. The last activation must fail.
5. Confirm that a project cannot be published with no campaign, zero budget, zero reward, zero participant cap, or a budget below reward × maximum participants.
6. Confirm that a refund or funding reduction cannot take confirmed funding below committed programme budgets.
7. Pause a campaign and confirm that new submissions across its linked programmes are rejected.
8. Confirm that an existing legacy task without a campaign is not rewritten by the migration. Admins must decide whether to link it to a funded campaign or retire it before it is republished.

### Submission and reward controls
1. Submit twice to the same active Research study or Digital Growth project as one member. The second active/approved entry must be rejected.
2. Reject the first entry and confirm a new attempt is allowed while the programme still has capacity.
3. Submit concurrently from multiple sessions and confirm the programme row lock prevents exceeding its maximum participant count.
4. Approve concurrent responses whose combined rewards would exceed the programme budget. Only affordable approvals may succeed.
5. Retry an approval and confirm the ledger idempotency key prevents a second credit.
6. Verify that consumers cannot call admin review functions or write directly to wallet_transactions.

### Wallet payouts
1. Use a staging member with a known positive ledger balance.
2. Submit two payout requests concurrently whose combined amount exceeds the balance. At most one request may reserve the overlapping funds.
3. Process two payout requests for the same member concurrently. The resulting debits must not make the member balance negative.
4. Confirm invalid payout status transitions are rejected and every request/decision is audit logged.

### Paid banner impressions
1. Keep a paid banner below the viewport: no impression should be counted.
2. Scroll until at least 50% of the banner is visible and keep it visible for one second: one impression should be recorded.
3. Hide the browser tab before one second: no impression should be recorded.
4. Send an impression event with viewable_ms below 1000: the Edge Function and database RPC must reject it.
5. Repeat within the same deduplication window: the count must not increase.
6. Confirm unpaid, paused, not-yet-started, and expired ads do not increment impressions or clicks.

### UI and device checks
1. On Android-width screens, confirm the admin tabs remain horizontally scrollable and forms do not overflow.
2. Confirm the member and admin navigation remain separate after sign-in and refresh.
3. Confirm the shared landing page and paid banner visibility are unchanged for guests and members.

## Production rollout gates
- Apply the migration to a staging Supabase project first.
- Run the Supabase Security and Performance Advisors after the migration.
- Deploy the updated `taskpula-banner-track` Edge Function with the new RPC signature at the same time as the migration.
- Complete the checklist above before applying the migration or deploying the function to production.
