#!/bin/bash
# Runs the "retired flow" (minimum tabs path) through the combined loan application.
# This flow uses Retired employment to minimize the number of tabs.
#
# Usage: retired-flow.sh <test_url> <email> <app_type> <screenshot_path>
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
  echo "Usage: retired-flow.sh <test_url> <email> <app_type> <screenshot_path>"
  exit 1
fi

echo "=== Starting retired flow ==="
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

# Tab 5: Results - No hit softpull - just click Continue
echo "--- Tab 5: Results ---"
playwright-cli run-code "async (page) => {
  const frame = page.locator('iframe[title=\"LendAPI Product Studio\"]').contentFrame();
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(4000);
}"
sleep 1

# Tab 6: Start Your Application - New Purchase
echo "--- Tab 6: Start Your Application ---"
playwright-cli run-code "async (page) => {
  const frame = page.locator('iframe[title=\"LendAPI Product Studio\"]').contentFrame();
  await frame.getByText('New Purchase').click();
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(4000);
}"
sleep 1

# Tab 7: Tell Us About You (Full App) - US citizen, address, housing
echo "--- Tab 7: Full App About You ---"
playwright-cli run-code "async (page) => {
  const frame = page.locator('iframe[title=\"LendAPI Product Studio\"]').contentFrame();
  await frame.locator('#are_you_us_citizen').selectOption(['Yes']);
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(4000);

  // Address sub-tab
  await frame.locator('#years_at_address').selectOption(['4']);
  await frame.locator('#type_of_residence').selectOption(['Own Free and Clear']);
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(4000);

  // Mailing address - Yes same address
  await frame.getByText('Yes').first().click();
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(4000);
}"
sleep 1

# Tab 8: Boat Details - sequential dropdown selection
# Each dropdown only appears after the previous one is selected
# Helper: click a react-select by its placeholder text, wait for menu, pick first option
echo "--- Tab 8: Boat Details ---"
playwright-cli run-code "async (page) => {
  const frame = page.locator('iframe[title=\"LendAPI Product Studio\"]').contentFrame();

  // Helper: select first option from a react-select identified by placeholder text
  async function selectByPlaceholder(placeholderText) {
    // Find the control element that contains this placeholder (fresh DOM query each time)
    const control = frame.locator('.react-select__control', {
      has: frame.locator('.react-select__placeholder', { hasText: placeholderText })
    }).first();
    await control.waitFor({ state: 'visible', timeout: 15000 });
    // Only scroll the parent page if the element is below the visible viewport
    const box = await control.boundingBox();
    if (box) {
      const vh = await page.evaluate(() => window.innerHeight);
      if (box.y > vh - 150) {
        await page.evaluate(({scrollAmt}) => window.scrollBy({ top: scrollAmt, behavior: 'instant' }), {scrollAmt: box.y - vh / 2});
        await page.waitForTimeout(1000);
      }
    }
    // Click with force:true to bypass stability checks (Boat Model oscillates due to description text)
    await control.click({ force: true });
    await page.waitForTimeout(1500);
    // If menu did not open (e.g. Engine Year below fold), fall back to keyboard
    const menuCheck = await frame.locator('.react-select__menu').isVisible();
    if (!menuCheck) {
      const combobox = control.locator('[role=\"combobox\"]');
      await combobox.focus();
      await page.waitForTimeout(500);
      await combobox.press('ArrowDown');
    }
    await page.waitForTimeout(1500);
    const menu = frame.locator('.react-select__menu');
    await menu.waitFor({ state: 'visible', timeout: 10000 });
    await menu.locator('.react-select__option').first().click();
    await page.waitForTimeout(3000);
  }

  // Boat dropdowns (appear sequentially - each loads options from API after previous selection)
  await selectByPlaceholder('Select Boat Year');
  await selectByPlaceholder('Select Boat Type');
  await selectByPlaceholder('Select Boat Manufacturer');
  // Wait for Boat Model options to load from API after manufacturer selection
  await page.waitForTimeout(5000);
  await selectByPlaceholder('Select Boat Model');

  // Wait for auto-populated fields to render after boat model selection
  await page.waitForTimeout(5000);

  // Engine dropdowns (appear sequentially, below the fold)
  await selectByPlaceholder('Select Engine Year');
  await selectByPlaceholder('Select Engine Manufacturer');
  await selectByPlaceholder('Select Engine Model');

  // Click Continue
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(4000);
}"
sleep 1

# Tab 9: Trade-in - No
echo "--- Tab 9: Trade-in ---"
playwright-cli run-code "async (page) => {
  const frame = page.locator('iframe[title=\"LendAPI Product Studio\"]').contentFrame();
  await frame.locator('#have_trade_in').selectOption(['No']);
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(4000);
}"
sleep 1

# Tab 10: Loan Details
echo "--- Tab 10: Loan Details ---"
playwright-cli run-code "async (page) => {
  const frame = page.locator('iframe[title=\"LendAPI Product Studio\"]').contentFrame();
  await frame.getByText('Personally').click();
  await frame.locator('#purchase_price').fill('75000');
  await frame.locator('#down_payment').fill('25000');
  await frame.locator('#desired_term').selectOption(['15']);
  await frame.getByText('Private Seller').click();
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(4000);
}"
sleep 1

# Tab 11: Income - Retired
echo "--- Tab 11: Income ---"
playwright-cli run-code "async (page) => {
  const frame = page.locator('iframe[title=\"LendAPI Product Studio\"]').contentFrame();
  await frame.locator('#employment_status').selectOption(['Retired']);
  await frame.locator('#primary_income_source').selectOption(['Salary']);
  await frame.getByRole('textbox', { name: '\$' }).fill('490000');
  await frame.locator('#add_other_income').selectOption(['No']);
  await frame.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(4000);
}"
sleep 1

# Tab 12: Credit Authorization + Submit
echo "--- Tab 12: Credit Authorization & Submit ---"
playwright-cli run-code "async (page) => {
  const frame = page.locator('iframe[title=\"LendAPI Product Studio\"]').contentFrame();
  await frame.getByRole('textbox', { name: 'Primary Borrower' }).fill('999-99-9999');
  await frame.getByRole('textbox', { name: 'MM/DD/YYYY' }).fill('01/11/1990');
  await frame.getByRole('heading', { name: 'Credit Authorization' }).click();
  await page.waitForTimeout(500);
  await frame.getByRole('checkbox').first().check();
  await frame.getByRole('button', { name: 'Submit' }).click();
  // Wait for success page to load — 'Application Submitted!' appears after processing completes
  await frame.getByText('Application Submitted!').waitFor({ state: 'visible', timeout: 120000 });
  await page.waitForTimeout(3000);
}"
sleep 1

# Take screenshot of final page
echo "--- Taking screenshot ---"
playwright-cli screenshot --filename "$SCREENSHOT_PATH" --full-page

# Take snapshot for verification
SNAPSHOT_PATH="${SCREENSHOT_PATH%.png}-snapshot.yml"
playwright-cli snapshot --filename "$SNAPSHOT_PATH"

echo "=== Flow complete ==="
echo "Screenshot saved to: $SCREENSHOT_PATH"
echo "Snapshot saved to: $SNAPSHOT_PATH"
