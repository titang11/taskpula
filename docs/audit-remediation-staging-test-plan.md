# TaskPula audit remediation — staging verification plan

The security migration and Edge Function changes are proposals only. They have not
changed the production Supabase database and the Edge Function has not been deployed.

## Required database tests

### Campaign funding and department budgets
1. An unfunded campaign cannot activate.
2. A pledge does not count as spendable funding; a confirmed receipt does.
3. Combined Tasks, Research, and Digital Growth commitments cannot exceed confirmed funds.
4. Programmes cannot publish with missing campaign, invalid reward/budget, or zero participant cap.
5. Funding reductions cannot undercut committed programme budgets.
6. Paused campaigns reject new submissions.
7. Legacy tasks without campaign links are not silently rewritten.

### Submission and reward controls
1. Duplicate active/approved submissions by one member are rejected.
2. A rejected submission can be retried if capacity remains.
3. Concurrent submissions cannot exceed the participant cap.
4. Concurrent approvals cannot exceed the reward budget.
5. Retried approvals cannot credit the wallet twice.
6. Members cannot invoke admin review functions or write directly to the wallet ledger.

### Wallet payouts
1. Concurrent payout requests cannot reserve more than the available balance.
2. Concurrent settlement cannot drive a member balance negative.
3. Invalid payout state transitions are rejected and decisions are audit logged.

### Banner events
1. Below-viewport or less-than-one-second impressions are rejected.
2. Valid viewability events are deduplicated.
3. Unpaid, paused, future, and expired ads do not accrue impressions or clicks.

### Device checks
1. Android-width admin forms and navigation do not overflow.
2. Member and admin navigation remain separate after sign-in and refresh.
3. Landing page and banner behavior remain correct for guests and members.

## Production rollout gates

- Apply the migration to an isolated staging database first.
- Run Supabase Security and Performance Advisors.
- Deploy the updated `taskpula-banner-track` Edge Function with the matching RPC signature.
- Complete the checklist before production rollout.
- Production migration and Edge Function deployment require separate explicit approval.
