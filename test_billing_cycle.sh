#!/bin/bash

# Test script for billing cycle logic
# Tests various scenarios to ensure correct reset behavior

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Test helper functions
test_case() {
    TEST_COUNT=$((TEST_COUNT + 1))
    echo ""
    echo "Test #${TEST_COUNT}: $1"
    echo "----------------------------------------"
}

assert_true() {
    local description="$1"
    local result=$2

    if [ $result -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_false() {
    local description="$1"
    local result=$2

    if [ $result -ne 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Mock the need_reset function with test data
test_need_reset() {
    local current_date="$1"
    local reset_day=$2
    local last_reset_month="$3"

    # Extract date components
    local current_day=$(date -d "${current_date}" +%d)
    local current_month=$(date -d "${current_date}" +%Y-%m)

    # Calculate effective reset day for current month
    local days_in_month=$(date -d "${current_month}-01 +1 month -1 day" +%d)
    local effective_reset_day=${reset_day}
    if [ "${reset_day}" -gt "${days_in_month}" ] 2>/dev/null; then
        effective_reset_day=${days_in_month}
    fi

    # If no reset record exists, we need to reset
    if [ -z "${last_reset_month}" ]; then
        return 0  # Need reset
    fi

    # Check if we already reset this month
    if [ "${last_reset_month}" == "${current_month}" ]; then
        return 1  # Already reset this month, no need to reset
    fi

    # Check if we have crossed the reset day in this month
    local reset_date_this_month="${current_month}-$(printf "%02d" ${effective_reset_day})"

    # If current date >= reset date of this month, we need to reset
    if [[ "${current_date}" > "${reset_date_this_month}" ]] || [[ "${current_date}" == "${reset_date_this_month}" ]]; then
        return 0  # Need reset
    fi

    # Additional check: if last reset was in a previous month and we're past the reset day
    if [ "${current_day}" -ge "${effective_reset_day}" ] 2>/dev/null; then
        if [ "${last_reset_month}" != "${current_month}" ]; then
            return 0  # Need reset
        fi
    fi

    return 1  # No reset needed
}

echo "=========================================="
echo "  Billing Cycle Reset Logic Test Suite"
echo "=========================================="

# Test 1: First time initialization (no previous reset)
test_case "First time initialization - should need reset"
test_need_reset "2025-11-06" 3 ""
assert_true "Should need reset on first run" $?

# Test 2: Already reset this month
test_case "Already reset this month - should NOT need reset"
test_need_reset "2025-11-06" 3 "2025-11"
assert_false "Should not reset again in same month" $?

# Test 3: Reset day is today
test_case "Today is the reset day"
test_need_reset "2025-11-03" 3 "2025-10"
assert_true "Should reset on reset day" $?

# Test 4: Current day before reset day (same month as last reset)
test_case "Before reset day in month after last reset"
test_need_reset "2025-11-01" 3 "2025-10"
assert_false "Should not reset before reset day" $?

# Test 5: Current day after reset day (different month from last reset)
test_case "After reset day in month after last reset"
test_need_reset "2025-11-06" 3 "2025-10"
assert_true "Should reset after reset day" $?

# Test 6: Missed reset day (script didn't run on reset day)
test_case "Missed reset day - running days later"
test_need_reset "2025-11-10" 3 "2025-10"
assert_true "Should reset even if reset day was missed" $?

# Test 7: Script stopped for a month
test_case "Script didn't run for a full month"
test_need_reset "2025-12-06" 3 "2025-10"
assert_true "Should reset after missing a full month" $?

# Test 8: February with reset day 31 - before effective reset day
test_case "Reset day 31 in February (28 days) - before reset"
current_date="2025-02-15"
reset_day=31
last_reset="2025-01"

current_month=$(date -d "${current_date}" +%Y-%m)
days_in_month=$(date -d "${current_month}-01 +1 month -1 day" +%d)
effective_reset_day=${days_in_month}  # Should be 28

echo "Current: ${current_date}, Effective reset day: ${effective_reset_day}"
test_need_reset "${current_date}" ${reset_day} "${last_reset}"
assert_false "Should not reset before effective reset day (Feb 28)" $?

# Test 8b: On the effective reset day
current_date="2025-02-28"
echo "Current: ${current_date}, Effective reset day: ${effective_reset_day}"
test_need_reset "${current_date}" ${reset_day} "${last_reset}"
assert_true "Should reset on effective reset day (Feb 28)" $?

# Test 9: Year boundary (December to January)
test_case "Year boundary - December to January"
test_need_reset "2025-01-05" 3 "2024-12"
assert_true "Should reset in new year" $?

# Test 10: Running on last day before reset
test_case "Running on last day before reset day"
test_need_reset "2025-11-02" 3 "2025-10"
assert_false "Should not reset the day before reset day" $?

# Test 11: Multiple months missed, reset day already passed
test_case "Multiple months missed, currently past reset day"
test_need_reset "2026-01-15" 3 "2025-10"
assert_true "Should reset after missing multiple months" $?

# Test 12: Running on reset day when already reset
test_case "Running again on reset day after already resetting"
test_need_reset "2025-11-03" 3 "2025-11"
assert_false "Should not reset twice in same month" $?

# Test 13: Leap year February with day 29
test_case "Leap year February with reset day 30"
current_month="2024-02"
days_in_month=$(date -d "${current_month}-01 +1 month -1 day" +%d)
echo "Days in February 2024 (leap year): ${days_in_month} (effective reset: ${days_in_month})"

echo "Testing Feb 20 (before reset day 29):"
test_need_reset "2024-02-20" 30 "2024-01"
result=$?
echo "  Result: need_reset=$result"
assert_false "Should not reset before effective reset day (Feb 29)" $result

echo "Testing Feb 29 (on reset day):"
test_need_reset "2024-02-29" 30 "2024-01"
assert_true "Should reset on Feb 29 (leap year)" $?

# Test 14: April (30 days) with reset day 31
test_case "April (30 days) with reset day 31"
test_need_reset "2025-04-30" 31 "2025-03"
assert_true "Should reset on April 30 (last day)" $?

# Test 15: Edge case - reset day is 1st of month
test_case "Reset day is 1st of month"
test_need_reset "2025-11-01" 1 "2025-10"
assert_true "Should reset on 1st day of month" $?

test_need_reset "2025-11-02" 1 "2025-11"
assert_false "Should not reset again after 1st" $?

# Print summary
echo ""
echo "=========================================="
echo "  Test Summary"
echo "=========================================="
echo "Total Tests: ${TEST_COUNT}"
echo -e "${GREEN}Passed: ${PASS_COUNT}${NC}"
echo -e "${RED}Failed: ${FAIL_COUNT}${NC}"
echo ""

if [ ${FAIL_COUNT} -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
