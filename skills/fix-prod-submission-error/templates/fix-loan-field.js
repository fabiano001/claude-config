// Template: patch one field on a Firestore loan doc.
// Used by /fix-prod-submission-error. Copy to functions/temp/fix-<shortid>-<fieldname>.js
// and fill in the four CONFIGURE blocks below.
//
// Run from <repo>/functions:
//   GCLOUD_PROJECT=trident-funding node temp/<this-file>.js
//
// Safety properties:
//   - Reads the doc first; aborts if missing.
//   - Logs the BEFORE state.
//   - Skips the write if the current value !== EXPECTED_BAD (idempotent re-run).
//   - Reads the doc back after writing and logs the AFTER state.

const admin = require('firebase-admin');

// === CONFIGURE ===
const LOAN_ID = '<loan-id>';                         // e.g. 'lendapi-d678e292-...'
const FIELD_PATH = '<dot.path.to.field>';            // e.g. 'borrower.dateOfBirth'
const EXPECTED_BAD = '<exact current bad value>';    // e.g. '02/16/1'
const NEW_VALUE = '<corrected value>';               // e.g. '02/16/1965'
// =================

admin.initializeApp();
const db = admin.firestore();

const getNested = (obj, path) =>
  path.split('.').reduce((cur, key) => (cur == null ? cur : cur[key]), obj);

(async () => {
  const ref = db.collection('loans').doc(LOAN_ID);
  const snap = await ref.get();
  if (!snap.exists) {
    console.error(`Loan ${LOAN_ID} not found in project ${process.env.GCLOUD_PROJECT}.`);
    process.exit(1);
  }
  const data = snap.data();
  const currentValue = getNested(data, FIELD_PATH);

  console.log('--- BEFORE ---');
  console.log(`Loan ID:    ${LOAN_ID}`);
  console.log(`Field:      ${FIELD_PATH}`);
  console.log(`Current:    ${JSON.stringify(currentValue)}`);
  console.log(`Workflow:   ${data.workflow}`);

  if (currentValue !== EXPECTED_BAD) {
    console.log('');
    console.log(`Current value does not match EXPECTED_BAD (${JSON.stringify(EXPECTED_BAD)}).`);
    console.log('No update performed (assumed already fixed or wrong loan id).');
    process.exit(0);
  }

  await ref.update({ [FIELD_PATH]: NEW_VALUE });

  const afterSnap = await ref.get();
  const afterValue = getNested(afterSnap.data(), FIELD_PATH);
  console.log('');
  console.log('--- AFTER ---');
  console.log(`New value:  ${JSON.stringify(afterValue)}`);
  console.log('Update complete.');
  process.exit(0);
})().catch((err) => {
  console.error('Script failed:', err);
  process.exit(1);
});
