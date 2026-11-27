# Member experience and managed business intake

## Business operating model
TaskPula is the service provider. Businesses do not create accounts, sign in, manage campaigns, or access dashboards by default. They contact TaskPula by the official business phone/email, provide a brief, and the TaskPula administrator manages sponsor records, campaign setup, delivery and reporting. Requested reports can be prepared and delivered manually as Excel or another agreed format.

## Public business enquiry
The landing page displays the official business telephone number (+267 71725678) and location (Block 3, Gaborone, Botswana). The no-account enquiry form validates the submitted details and opens the visitor's SMS app with a prepared message to the business phone number. No email address is published or required. SMS availability depends on the visitor's device and mobile network. Enquiry content is not stored in Supabase or in the website.

## Member experience
- Profile editing uses existing profiles.display_name and profiles.phone fields.
- Search filters existing live task, research, campaign and growth cards; it does not create or alter opportunity records.
- Activity updates are derived from the member's own task_submissions rows. There is no dedicated notifications table in the current public schema, so these are an in-app activity view, not durable notifications or push messages.
- No wallet ledger, payout request, financial approval, campaign funding, reward credit or production security workflow is modified.

## Synthetic test data
The tests/fixtures/taskpula_demo.json file contains invented IDs and clearly labelled demo records. It is for local/CI tests only. Never seed it into production Supabase.

## Manual validation
1. Open the landing page signed out and confirm business enquiry is visible without login.
2. Submit the form with missing fields, malformed email and too-short project details; browser validation should block it.
3. Configure the official contact email before testing email preparation.
4. Sign in as a member; test profile edits and refresh to confirm persistence.
5. Search each department and confirm non-matching cards are hidden; clear the query to restore all cards.
6. Open Progress and confirm activity is built from the signed-in member's task submission rows only.
7. Sign in as authorized admin and confirm existing controls still work with refreshed visual treatment.
8. Confirm no demo fixture data appears in Supabase and no wallet/payout records were changed.
