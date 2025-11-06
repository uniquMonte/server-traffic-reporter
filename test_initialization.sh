#!/bin/bash

# Test script for first-time initialization logic

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

test_case() {
    TEST_COUNT=$((TEST_COUNT + 1))
    echo ""
    echo "Test #${TEST_COUNT}: $1"
    echo "----------------------------------------"
}

assert_equal() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    if [ "${expected}" == "${actual}" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        echo "  Expected: ${expected}, Got: ${actual}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo "  Expected: ${expected}, Got: ${actual}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Function to calculate last reset date (same logic as in init_traffic_db)
calculate_last_reset() {
    local current_date="$1"
    local reset_day=$2

    local current_day=$(date -d "${current_date}" +%d)
    local current_month=$(date -d "${current_date}" +%Y-%m)
    local days_in_month=$(date -d "${current_month}-01 +1 month -1 day" +%d)

    # Adjust reset day if it exceeds days in current month
    local effective_reset_day=${reset_day}
    if [ "${reset_day}" -gt "${days_in_month}" ] 2>/dev/null; then
        effective_reset_day=${days_in_month}
    fi

    local last_reset_date=""

    # Determine the last reset date
    if [ "${current_day}" -lt "${effective_reset_day}" ] 2>/dev/null; then
        # Current day is before reset day - last reset was in previous month
        local prev_month=$(date -d "${current_month}-01 -1 month" +%Y-%m)
        local prev_month_days=$(date -d "${prev_month}-01 +1 month -1 day" +%d)

        # Adjust reset day for previous month if needed
        local prev_effective_reset_day=${reset_day}
        if [ "${reset_day}" -gt "${prev_month_days}" ] 2>/dev/null; then
            prev_effective_reset_day=${prev_month_days}
        fi

        last_reset_date="${prev_month}-$(printf "%02d" ${prev_effective_reset_day})"
    else
        # Current day is on or after reset day - last reset was this month
        last_reset_date="${current_month}-$(printf "%02d" ${effective_reset_day})"
    fi

    echo "${last_reset_date}"
}

echo "=========================================="
echo "  First-Time Initialization Test Suite"
echo "=========================================="

# Test 1: Initialize before reset day
test_case "First run on Nov 1, reset day is 3"
result=$(calculate_last_reset "2025-11-01" 3)
assert_equal "Last reset should be Oct 3" "2025-10-03" "${result}"

# Test 2: Initialize on reset day
test_case "First run on Nov 3 (reset day), reset day is 3"
result=$(calculate_last_reset "2025-11-03" 3)
assert_equal "Last reset should be Nov 3 (today)" "2025-11-03" "${result}"

# Test 3: Initialize after reset day
test_case "First run on Nov 6, reset day is 3"
result=$(calculate_last_reset "2025-11-06" 3)
assert_equal "Last reset should be Nov 3" "2025-11-03" "${result}"

# Test 4: Initialize in February with reset day 31
test_case "First run on Feb 15, reset day is 31"
result=$(calculate_last_reset "2025-02-15" 31)
assert_equal "Last reset should be Jan 31" "2025-01-31" "${result}"

# Test 5: Initialize in March with reset day 31 (after Feb)
test_case "First run on Mar 15, reset day is 31"
result=$(calculate_last_reset "2025-03-15" 31)
assert_equal "Last reset should be Feb 28" "2025-02-28" "${result}"

# Test 6: Initialize on Feb 28 with reset day 31
test_case "First run on Feb 28 (last day), reset day is 31"
result=$(calculate_last_reset "2025-02-28" 31)
assert_equal "Last reset should be Feb 28 (today)" "2025-02-28" "${result}"

# Test 7: Initialize on Mar 1 with reset day 31
test_case "First run on Mar 1, reset day is 31"
result=$(calculate_last_reset "2025-03-01" 31)
assert_equal "Last reset should be Feb 28" "2025-02-28" "${result}"

# Test 8: Initialize in leap year February
test_case "First run on Feb 15 2024 (leap year), reset day is 31"
result=$(calculate_last_reset "2024-02-15" 31)
assert_equal "Last reset should be Jan 31" "2024-01-31" "${result}"

# Test 9: Initialize on Feb 29 (leap year) with reset day 31
test_case "First run on Feb 29 2024 (leap year), reset day is 31"
result=$(calculate_last_reset "2024-02-29" 31)
assert_equal "Last reset should be Feb 29 (today)" "2024-02-29" "${result}"

# Test 10: Initialize on Jan 1 with reset day 15
test_case "First run on Jan 1, reset day is 15"
result=$(calculate_last_reset "2025-01-01" 15)
assert_equal "Last reset should be Dec 15 of previous year" "2024-12-15" "${result}"

# Test 11: Initialize with reset day 1
test_case "First run on Nov 1 (reset day is 1)"
result=$(calculate_last_reset "2025-11-01" 1)
assert_equal "Last reset should be Nov 1 (today)" "2025-11-01" "${result}"

# Test 12: Initialize with reset day 1, but on Nov 2
test_case "First run on Nov 2 (reset day is 1)"
result=$(calculate_last_reset "2025-11-02" 1)
assert_equal "Last reset should be Nov 1" "2025-11-01" "${result}"

# Test 13: End of month scenarios
test_case "First run on Apr 30 with reset day 31"
result=$(calculate_last_reset "2025-04-30" 31)
assert_equal "Last reset should be Apr 30 (today, effective reset day)" "2025-04-30" "${result}"

test_case "First run on May 1 with reset day 31"
result=$(calculate_last_reset "2025-05-01" 31)
assert_equal "Last reset should be Apr 30 (effective reset day of April)" "2025-04-30" "${result}"

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
