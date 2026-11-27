import json
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class ExperienceContractTests(unittest.TestCase):
 def test_business_intake_is_no_account_and_no_database_write(self):
  s=(ROOT/'experience.js').read_text();self.assertIn('businessEnquiryForm',s);self.assertIn('mailto:',s);self.assertNotIn("from('campaign_requests').insert",s);self.assertIn('No business account',s)
 def test_member_updates_are_read_only_derived_from_own_submissions(self):
  s=(ROOT/'experience.js').read_text();self.assertIn("from('task_submissions').select",s);self.assertIn('.eq(\'user_id\',user.id)',s);self.assertNotIn("wallet_transactions').insert",s);self.assertNotIn("wallet_payout_requests').insert",s)
 def test_profile_edit_uses_existing_fields(self):
  s=(ROOT/'experience.js').read_text();self.assertIn("from('profiles').update",s);self.assertIn('display_name',s);self.assertIn('phone',s)
 def test_fixture_is_synthetic_and_has_no_financial_data(self):
  f=json.loads((ROOT/'tests/fixtures/taskpula_demo.json').read_text());self.assertIn('SYNTHETIC',f['_notice']);self.assertNotIn('wallet_transactions',f);self.assertNotIn('wallet_payout_requests',f)
if __name__=='__main__': unittest.main()
