"""Static contract checks for the TaskPula audit-remediation migration.

These checks catch accidental removal of critical safeguards. They do not replace
running the migration against PostgreSQL or exercising concurrent transactions.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"
MIGRATION = MIGRATIONS / "20261127190000_taskpula_audit_financial_integrity_and_viewability.sql"
EDGE_FUNCTION = ROOT / "supabase" / "functions" / "taskpula-banner-track" / "index.ts"


class MigrationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.edge = EDGE_FUNCTION.read_text(encoding="utf-8").lower()

    def test_migration_is_transactional(self):
        self.assertRegex(self.sql, r"(?m)^begin;")
        self.assertRegex(self.sql, r"(?m)^commit;")

    def test_wallet_operations_use_member_scoped_transaction_lock(self):
        self.assertIn("pg_advisory_xact_lock", self.sql)
        self.assertIn("taskpula-wallet:", self.sql)
        self.assertIn("perform private.taskpula_lock_wallet(uid)", self.sql)
        self.assertIn("perform private.taskpula_lock_wallet(rec.user_id)", self.sql)

    def test_wallet_credits_and_payouts_are_idempotent(self):
        self.assertGreaterEqual(self.sql.count("on conflict(idempotency_key) do nothing"), 3)
        self.assertIn("'payout:'||rec.id::text", self.sql)

    def test_reward_programmes_enforce_participant_and_budget_limits(self):
        self.assertIn("max_submissions", self.sql)
        self.assertIn("participant limit", self.sql)
        self.assertIn("budget exhausted", self.sql)
        self.assertIn("for update", self.sql)

    def test_browser_cannot_write_wallet_ledger(self):
        self.assertRegex(
            self.sql,
            r"revoke\s+insert\s*,\s*update\s*,\s*delete\s+on\s+public\.wallet_transactions\s+from\s+anon\s*,\s*authenticated",
        )

    def test_banner_rpc_requires_service_role_and_viewability(self):
        self.assertIn("auth.jwt()->>'role'", self.sql)
        self.assertIn("service_role", self.sql)
        self.assertIn("p_viewable_ms<1000", self.sql)
        self.assertIn("banner_ad_event_dedup", self.sql)

    def test_edge_function_validates_viewability_and_uses_hmac(self):
        self.assertIn('hash: "sha-256"', self.edge)
        self.assertIn("crypto.subtle.sign", self.edge)
        self.assertIn("viewable_ms", self.edge)
        self.assertIn("viewablems<1000", self.edge)
        self.assertIn('db.rpc("track_banner_ad_event"', self.edge)


if __name__ == "__main__":
    unittest.main()
