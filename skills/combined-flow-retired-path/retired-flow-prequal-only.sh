#!/bin/bash
# Runs the "retired flow" prequal-only path through the combined loan application.
# Stops after the mandatory login on the Results page (does NOT continue into full app).
#
# Usage: retired-flow-prequal-only.sh <test_url> <email> <app_type> <screenshot_path>
#   test_url        - The combined funnel URL with test params
#   email           - Pre-generated unique email (e.g., fabiano.test.48291573@boats.com)
#   app_type        - "Individual" or "Joint"
#   screenshot_path - Full path for the final screenshot (e.g., /path/to/screenshot.png)

set -e

TEST_URL="$1"
EMAIL="$2"
APP_TYPE="$3"
SCREENSHOT_PATH="$4"

if [ -z "$TEST_URL" ] || [ -z "$EMAIL" ] || [ -z "$APP_TYPE" ] || [ -z "$SCREENSHOT_PATH" ]; then
  echo "ERROR: Missing required arguments"
  echo "Usage: retired-flow-prequal-only.sh <test_url> <email> <app_type> <screenshot_path>"
  exit 1
fi

echo "=== Starting retired flow (prequal only) ==="
echo "URL: $TEST_URL"
echo "Email: $EMAIL"
echo "App Type: $APP_TYPE"
echo "Screenshot: $SCREENSHOT_PATH"

# Ensure screenshot directory exists
mkdir -p "$(dirname "$SCREENSHOT_PATH")"

# Open browser and navigate
playwright-cli open --headed "$TEST_URL"
sleep 5

# Tab 1: Lets Get Started - select timeframe and app type
echo "--- Tab 1: Lets Get Started ---"
playwright-cli run-code "async (page) => {
  const frame = page.locator('iframe[title=\"LendAPI Product Studio\"]').contentFrame();
  await frame.getByText('0-30 days').click();
  await frame.getByText('$APP_TYPE', { exact: true }).click();
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(4000);
}"
sleep 1

# Tab 2: Tell Us About Your Boat
echo "--- Tab 2: Tell Us About Your Boat ---"
playwright-cli run-code "async (page) => {
  const frame = page.locator('iframe[title=\"LendAPI Product Studio\"]').contentFrame();
  await frame.locator('#make_year').fill('2026');
  await frame.locator('select').filter({ hasText: 'Select an option' }).selectOption('Boat');
  await page.waitForTimeout(1000);
  await frame.getByText('Pleasure').click();
  await frame.locator('#purchase_price').fill('75000');
  await frame.locator('#estimated_down_payment').fill('25000');
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(4000);
}"
sleep 1

# Tab 3: Tell Us About You (Prequal)
echo "--- Tab 3: Tell Us About You ---"
playwright-cli run-code "async (page) => {
  const frame = page.locator('iframe[title=\"LendAPI Product Studio\"]').contentFrame();
  await frame.locator('#first_name').fill('John');
  await frame.locator('#last_name').fill('TestSmith');
  await frame.locator('#email').fill('$EMAIL');
  await frame.locator('#mobile').fill('5551234567');
  await frame.getByRole('textbox', { name: 'Address Line 1' }).fill('123 Main Street');
  await frame.getByRole('textbox', { name: 'City' }).fill('Miami');
  await frame.getByRole('combobox').first().selectOption(['Florida (FL)']);
  await frame.getByRole('textbox', { name: 'Zip Code' }).fill('33101');
  await frame.locator('#type_of_residence').selectOption(['Own Free and Clear']);
  await frame.locator('#annual_income').fill('100000');
  await frame.getByRole('checkbox').first().check();
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(6000);
}"
sleep 1

# Tab 4: SSN Verification
echo "--- Tab 4: SSN Verification ---"
playwright-cli run-code "async (page) => {
  const frame = page.locator('iframe[title=\"LendAPI Product Studio\"]').contentFrame();
  await frame.getByRole('textbox', { name: 'Primary Borrower' }).fill('999-99-9999');
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(10000);
}"
sleep 1

# Tab 5: Results - Mandatory Login (NO Continue — stop here)
# After softpull, a login modal appears in the main page (not in iframe).
# We create an account via email, then take a screenshot of the Results page.
echo "--- Tab 5: Results + Mandatory Login ---"
playwright-cli run-code "async (page) => {
  // Wait for the login modal to appear (it's in the main page, not the iframe)
  const modal = page.getByRole('dialog');
  await modal.waitFor({ state: 'visible', timeout: 15000 });
  await page.waitForTimeout(2000);

  // Click 'Sign in with email'
  const emailBtn = modal.locator('button').filter({ hasText: 'Sign in with email' });
  await emailBtn.click();
  await page.waitForTimeout(2000);

  // Fill email (reuse the same test email)
  const emailInput = modal.locator('input').first();
  await emailInput.fill('$EMAIL');
  await page.waitForTimeout(500);

  // Click Next
  const nextBtn = modal.locator('button').filter({ hasText: 'Next' });
  await nextBtn.click();
  await page.waitForTimeout(3000);

  // Create account: fill name and password
  const nameInput = modal.locator('input[type=\"text\"]');
  await nameInput.fill('John TestSmith');
  await page.waitForTimeout(500);

  const passwordInput = modal.locator('input[type=\"password\"]');
  await passwordInput.fill('TestPass123!');
  await page.waitForTimeout(500);

  // Click Save to create the account
  const saveBtn = modal.locator('button').filter({ hasText: 'Save' });
  await saveBtn.click();
  await page.waitForTimeout(5000);
}"
sleep 1

# Take screenshot of the Results page (prequal complete, before full app)
echo "--- Taking screenshot ---"
playwright-cli screenshot --filename "$SCREENSHOT_PATH" --full-page

# Take snapshot for verification
SNAPSHOT_PATH="${SCREENSHOT_PATH%.png}-snapshot.yml"
playwright-cli snapshot --filename "$SNAPSHOT_PATH"

echo "=== Prequal flow complete ==="
echo "Screenshot saved to: $SCREENSHOT_PATH"
echo "Snapshot saved to: $SNAPSHOT_PATH"
