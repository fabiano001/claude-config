// Template: query GCP Cloud Logging for submitApp activity on a loan.
// Used by /fix-prod-submission-error step 7 (success verification).
// Copy to functions/temp/verify-<shortid>.js and fill in the two CONFIGURE blocks.
//
// Run from <repo>/functions:
//   GCLOUD_PROJECT=trident-funding node temp/<this-file>.js
//
// Why a node wrapper instead of plain `gcloud`?
//   The project's CLAUDE.md forbids `$(...)` / `${...}` substitution in Bash tool
//   calls, so we can't inline `date -u +"..."` to build the timestamp filter.
//   Computing it in JS and passing it via child_process keeps the call shell-safe.

const { execFileSync } = require('child_process');

// === CONFIGURE ===
const LOAN_ID = '<loan-id>';
const SINCE_ISO = '<ISO timestamp ~30s before the Resubmit click>'; // e.g. '2026-05-15T21:45:30Z'
// =================

const PROJECT = process.env.GCLOUD_PROJECT || 'trident-funding';

const filter = `"${LOAN_ID}" AND timestamp>="${SINCE_ISO}"`;
const args = [
  'logging',
  'read',
  filter,
  `--project=${PROJECT}`,
  '--limit=100',
  '--order=asc',
  '--format=value(timestamp,severity,resource.labels.function_name,jsonPayload.message,textPayload)',
];

console.log(`gcloud ${args.join(' ')}`);
console.log('');

let out;
try {
  out = execFileSync('gcloud', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });
} catch (e) {
  console.error('gcloud call failed:', e.message);
  process.exit(2);
}

if (!out.trim()) {
  console.log('(no log entries matched yet — GCP ingestion lag is typically 30–90s; re-run in 60s)');
  process.exit(3);
}

console.log(out);

const success = /SubmitApp:SUCCESS - \(FINISHED\)/.test(out);
const error = /SubmitApp:ERROR\b/.test(out) || /processFailure/.test(out);

console.log('---');
if (success && !error) {
  console.log('VERDICT: ✅ SubmitApp:SUCCESS observed; no errors. Resubmit succeeded.');
  process.exit(0);
}
if (error) {
  console.log('VERDICT: ❌ Failure log observed. Resubmit did NOT succeed — inspect above lines.');
  process.exit(4);
}
console.log('VERDICT: ⏳ Inconclusive — logs present but no terminal SUCCESS/ERROR marker yet. Re-run in 60s.');
process.exit(3);
