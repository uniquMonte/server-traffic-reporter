#!/bin/bash

# Comprehensive test for traffic tracking logic
# Tests the complete flow of daily and cumulative traffic tracking

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Test directories
TEST_DIR="/tmp/traffic_test_$$"
TEST_DATA_DIR="${TEST_DIR}/data"
TEST_DB="${TEST_DATA_DIR}/traffic.db"

# Mock configuration
NETWORK_INTERFACE="eth0"
TRAFFIC_RESET_DAY=17
MONTHLY_TRAFFIC_LIMIT=330000
TRAFFIC_DIRECTION=1

# Create test environment
setup_test_env() {
    rm -rf "${TEST_DIR}"
    mkdir -p "${TEST_DATA_DIR}"
}

# Cleanup
cleanup() {
    rm -rf "${TEST_DIR}"
}

# Test helper functions
test_case() {
    TEST_COUNT=$((TEST_COUNT + 1))
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Test #${TEST_COUNT}: $1${NC}"
    echo -e "${BLUE}========================================${NC}"
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

assert_in_range() {
    local description="$1"
    local expected=$2
    local actual=$3
    local tolerance=$4

    local diff=$(echo "${actual} - ${expected}" | bc | sed 's/-//')

    if (( $(echo "${diff} <= ${tolerance}" | bc -l) )); then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        echo "  Expected: ~${expected}, Got: ${actual} (tolerance: ±${tolerance})"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo "  Expected: ~${expected}, Got: ${actual} (diff: ${diff}, tolerance: ±${tolerance})"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Mock function to get current traffic (simulates system traffic counter)
mock_system_traffic_counter=0

get_current_traffic() {
    echo "${mock_system_traffic_counter}"
}

# Function to get baseline
get_baseline() {
    local baseline=$(grep -v "^#" "${TEST_DB}" 2>/dev/null | grep "baseline=" | tail -1 | sed 's/.*baseline=//' 2>/dev/null || echo "0")
    if ! [[ "${baseline}" =~ ^[0-9]+$ ]]; then
        baseline=0
    fi
    echo "${baseline}"
}

# Function to get cumulative traffic
get_cumulative_traffic() {
    local baseline=$(get_baseline)
    local current=$(get_current_traffic)
    local last_cumulative=$(grep -v "^#" "${TEST_DB}" | grep -v "RESET" | tail -1 | cut -d'|' -f3 || echo "0")
    local cumulative=0

    if [ "${current}" -lt "${baseline}" ] 2>/dev/null; then
        cumulative=$((last_cumulative + current))
    else
        local diff=$((current - baseline))
        cumulative=$((last_cumulative + diff))
    fi

    echo "${cumulative}"
}

# Function to get daily traffic
get_daily_traffic() {
    local today="$1"
    local current_cumulative=$(get_cumulative_traffic)

    local today_start_cumulative=0
    local today_first_entry=$(grep -v "^#" "${TEST_DB}" | grep "^${today}|" | head -1 | cut -d'|' -f3 2>/dev/null || echo "")

    if [ -n "${today_first_entry}" ]; then
        local yesterday=$(date -d "${today} -1 day" +%Y-%m-%d 2>/dev/null)
        local yesterday_last=$(grep -v "^#" "${TEST_DB}" | grep "^${yesterday}|" | tail -1 | cut -d'|' -f3 2>/dev/null || echo "")

        if [ -n "${yesterday_last}" ]; then
            today_start_cumulative=${yesterday_last}
        else
            today_start_cumulative=$(grep -v "^#" "${TEST_DB}" | grep -v "^${today}|" | grep -v "RESET" | tail -1 | cut -d'|' -f3 2>/dev/null || echo "0")
        fi
    else
        today_start_cumulative=$(grep -v "^#" "${TEST_DB}" | grep -v "RESET" | tail -1 | cut -d'|' -f3 2>/dev/null || echo "0")
    fi

    local daily=$((current_cumulative - today_start_cumulative))

    if [ "${daily}" -lt 0 ] 2>/dev/null; then
        daily=0
    fi

    echo "${daily}"
}

# Function to initialize database
init_traffic_db() {
    local init_date="$1"
    local reset_day=${TRAFFIC_RESET_DAY}

    echo "# Traffic Database" > "${TEST_DB}"
    echo "# Format: DATE|DAILY_BYTES|CUMULATIVE_BYTES|RESET_PERIOD" >> "${TEST_DB}"

    local current_day=$(date -d "${init_date}" +%d)
    local current_month=$(date -d "${init_date}" +%Y-%m)
    local days_in_month=$(date -d "${current_month}-01 +1 month -1 day" +%d)

    local effective_reset_day=${reset_day}
    if [ "${reset_day}" -gt "${days_in_month}" ] 2>/dev/null; then
        effective_reset_day=${days_in_month}
    fi

    local last_reset_date=""
    if [ "${current_day}" -lt "${effective_reset_day}" ] 2>/dev/null; then
        local prev_month=$(date -d "${current_month}-01 -1 month" +%Y-%m)
        local prev_month_days=$(date -d "${prev_month}-01 +1 month -1 day" +%d)
        local prev_effective_reset_day=${reset_day}
        if [ "${reset_day}" -gt "${prev_month_days}" ] 2>/dev/null; then
            prev_effective_reset_day=${prev_month_days}
        fi
        last_reset_date="${prev_month}-$(printf "%02d" ${prev_effective_reset_day})"
    else
        last_reset_date="${current_month}-$(printf "%02d" ${effective_reset_day})"
    fi

    echo "RESET|${last_reset_date}|0|${current_month}" >> "${TEST_DB}"

    local current_traffic=$(get_current_traffic)
    echo "${init_date}|0|0|baseline=${current_traffic}" >> "${TEST_DB}"
}

# Function to record daily data
record_daily_data() {
    local date="$1"
    local daily_bytes=$(get_daily_traffic "${date}")
    local cumulative_bytes=$(get_cumulative_traffic)
    local baseline=$(get_current_traffic)

    echo "${date}|${daily_bytes}|${cumulative_bytes}|baseline=${baseline}" >> "${TEST_DB}"
}

# Function to reset traffic
reset_traffic() {
    local reset_date="$1"

    if [ -f "${TEST_DB}" ]; then
        cp "${TEST_DB}" "${TEST_DB}.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    echo "# Traffic Database - Reset on ${reset_date}" > "${TEST_DB}"
    echo "# Format: DATE|DAILY_BYTES|CUMULATIVE_BYTES|RESET_PERIOD" >> "${TEST_DB}"
    echo "RESET|${reset_date}|0|$(date -d "${reset_date}" +%Y-%m)" >> "${TEST_DB}"

    local current_traffic=$(get_current_traffic)
    echo "${reset_date}|0|0|baseline=${current_traffic}" >> "${TEST_DB}"
}

# Convert bytes to GB
bytes_to_gb() {
    local bytes=$1
    echo "$(echo "scale=2; ${bytes}/1073741824" | bc)"
}

echo "=========================================="
echo "  Traffic Tracking Logic Test Suite"
echo "=========================================="
echo ""

# Setup
setup_test_env

##############################################################################
# Test 1: Initial setup and first day tracking
##############################################################################
test_case "初始化后第一天的流量统计"

# Simulate system starting with 1000GB already used (historical traffic)
mock_system_traffic_counter=1073741824000  # 1000 GB in bytes

# Initialize on Nov 6 (reset day is 17, so last reset was Oct 17)
init_traffic_db "2025-11-06"

echo "Database after init:"
cat "${TEST_DB}"
echo ""

# Simulate 5GB used during the day
mock_system_traffic_counter=$((mock_system_traffic_counter + 5368709120))  # +5GB

# Get traffic stats
cumulative=$(get_cumulative_traffic)
daily=$(get_daily_traffic "2025-11-06")

echo "System counter: ${mock_system_traffic_counter} bytes"
echo "Cumulative: ${cumulative} bytes ($(bytes_to_gb ${cumulative}) GB)"
echo "Daily: ${daily} bytes ($(bytes_to_gb ${daily}) GB)"

# Record the data
record_daily_data "2025-11-06"

echo ""
echo "Database after recording:"
cat "${TEST_DB}"

# Check results
assert_equal "首日累积流量应为5GB" "5368709120" "${cumulative}"
assert_equal "首日今日流量应为5GB" "5368709120" "${daily}"

##############################################################################
# Test 2: Second day tracking
##############################################################################
test_case "第二天的流量统计"

# Simulate another 6GB used on second day
mock_system_traffic_counter=$((mock_system_traffic_counter + 6442450944))  # +6GB

cumulative=$(get_cumulative_traffic)
daily=$(get_daily_traffic "2025-11-07")

echo "System counter: ${mock_system_traffic_counter} bytes"
echo "Cumulative: ${cumulative} bytes ($(bytes_to_gb ${cumulative}) GB)"
echo "Daily: ${daily} bytes ($(bytes_to_gb ${daily}) GB)"

record_daily_data "2025-11-07"

echo ""
echo "Database:"
cat "${TEST_DB}"

# Check results: cumulative should be 11GB, daily should be 6GB
expected_cumulative=$((5368709120 + 6442450944))
assert_equal "第二日累积流量应为11GB" "${expected_cumulative}" "${cumulative}"
assert_equal "第二日今日流量应为6GB" "6442450944" "${daily}"

##############################################################################
# Test 3: Multiple runs on same day
##############################################################################
test_case "同一天多次运行脚本"

# Add more traffic on same day (Nov 7)
mock_system_traffic_counter=$((mock_system_traffic_counter + 2147483648))  # +2GB

cumulative=$(get_cumulative_traffic)
daily=$(get_daily_traffic "2025-11-07")

echo "System counter: ${mock_system_traffic_counter} bytes"
echo "Cumulative: ${cumulative} bytes ($(bytes_to_gb ${cumulative}) GB)"
echo "Daily: ${daily} bytes ($(bytes_to_gb ${daily}) GB)"

record_daily_data "2025-11-07"

echo ""
echo "Database (with duplicate entry for same day):"
cat "${TEST_DB}"

# Check: cumulative should be 13GB, daily should be 8GB (6+2)
expected_cumulative=$((5368709120 + 6442450944 + 2147483648))
expected_daily=$((6442450944 + 2147483648))
assert_equal "同日第二次运行累积流量应为13GB" "${expected_cumulative}" "${cumulative}"
assert_equal "同日第二次运行今日流量应为8GB" "${expected_daily}" "${daily}"

##############################################################################
# Test 4: Server reboot (traffic counter reset)
##############################################################################
test_case "服务器重启导致系统流量计数器归零"

# Simulate server reboot - system counter resets to 0
old_counter=${mock_system_traffic_counter}
mock_system_traffic_counter=0

# Some new traffic after reboot
mock_system_traffic_counter=$((mock_system_traffic_counter + 1073741824))  # 1GB

cumulative=$(get_cumulative_traffic)
daily=$(get_daily_traffic "2025-11-08")

echo "Old system counter: ${old_counter} bytes"
echo "New system counter (after reboot): ${mock_system_traffic_counter} bytes"
echo "Cumulative: ${cumulative} bytes ($(bytes_to_gb ${cumulative}) GB)"
echo "Daily: ${daily} bytes ($(bytes_to_gb ${daily}) GB)"

record_daily_data "2025-11-08"

# Check: cumulative should be 13GB (previous) + 1GB (new) = 14GB
expected_cumulative=$((5368709120 + 6442450944 + 2147483648 + 1073741824))
assert_equal "服务器重启后累积流量应正确累加" "${expected_cumulative}" "${cumulative}"

##############################################################################
# Test 5: Billing cycle reset on reset day
##############################################################################
test_case "计费周期重置日的流量统计"

# Fast forward to reset day (Nov 17)
# Add some more traffic before reset
mock_system_traffic_counter=$((mock_system_traffic_counter + 5368709120))  # +5GB

# Record traffic for a few days leading up to reset
for day in $(seq 9 16); do
    date_str="2025-11-$(printf "%02d" ${day})"
    mock_system_traffic_counter=$((mock_system_traffic_counter + 1073741824))  # +1GB per day
    record_daily_data "${date_str}"
done

echo "Before reset - Database:"
tail -5 "${TEST_DB}"
echo ""

cumulative_before_reset=$(get_cumulative_traffic)
echo "Cumulative before reset: $(bytes_to_gb ${cumulative_before_reset}) GB"

# Now simulate reset on Nov 17
reset_traffic "2025-11-17"

echo ""
echo "After reset - New database:"
cat "${TEST_DB}"
echo ""

# Add some traffic on reset day
mock_system_traffic_counter=$((mock_system_traffic_counter + 2147483648))  # +2GB

cumulative_after_reset=$(get_cumulative_traffic)
daily_after_reset=$(get_daily_traffic "2025-11-17")

echo "Cumulative after reset: ${cumulative_after_reset} bytes ($(bytes_to_gb ${cumulative_after_reset}) GB)"
echo "Daily after reset: ${daily_after_reset} bytes ($(bytes_to_gb ${daily_after_reset}) GB)"

record_daily_data "2025-11-17"

# Check: cumulative should be 2GB (reset to 0, then +2GB)
assert_equal "重置后累积流量应重新从0开始" "2147483648" "${cumulative_after_reset}"
assert_equal "重置日的今日流量应为2GB" "2147483648" "${daily_after_reset}"

##############################################################################
# Test 6: Next day after reset
##############################################################################
test_case "重置后第二天的流量统计"

# Add traffic on Nov 18
mock_system_traffic_counter=$((mock_system_traffic_counter + 3221225472))  # +3GB

cumulative=$(get_cumulative_traffic)
daily=$(get_daily_traffic "2025-11-18")

echo "Cumulative: ${cumulative} bytes ($(bytes_to_gb ${cumulative}) GB)"
echo "Daily: ${daily} bytes ($(bytes_to_gb ${daily}) GB)"

record_daily_data "2025-11-18"

echo ""
echo "Database:"
tail -5 "${TEST_DB}"

# Check: cumulative should be 5GB (2+3), daily should be 3GB
expected_cumulative=$((2147483648 + 3221225472))
assert_equal "重置后第二天累积应为5GB" "${expected_cumulative}" "${cumulative}"
assert_equal "重置后第二天今日流量应为3GB" "3221225472" "${daily}"

##############################################################################
# Test 7: Simulating the user's scenario
##############################################################################
test_case "模拟用户的实际场景：首次运行脚本"

# Reset everything
setup_test_env

# Scenario: User installs script on Nov 6, reset day is 17
# System has been running for a while with 995GB used
mock_system_traffic_counter=1068264079360  # 995GB

echo "Initial system counter: $(bytes_to_gb ${mock_system_traffic_counter}) GB"

# Initialize on Nov 6
init_traffic_db "2025-11-06"

echo ""
echo "Initial database:"
cat "${TEST_DB}"
echo ""

# During the day, 5.48GB is used
mock_system_traffic_counter=$((mock_system_traffic_counter + 5884901376))  # +5.48GB

cumulative=$(get_cumulative_traffic)
daily=$(get_daily_traffic "2025-11-06")

echo "After 5.48GB usage:"
echo "System counter: $(bytes_to_gb ${mock_system_traffic_counter}) GB"
echo "Cumulative: $(bytes_to_gb ${cumulative}) GB"
echo "Daily: $(bytes_to_gb ${daily}) GB"

# This should match user's output: Today's Usage = 5.48GB, Cycle Used = 5.48GB
expected_daily=5884901376
expected_cumulative=5884901376

cumulative_gb=$(bytes_to_gb ${cumulative})
daily_gb=$(bytes_to_gb ${daily})

assert_in_range "用户场景-今日流量应约为5.48GB" "5.48" "${daily_gb}" "0.01"
assert_in_range "用户场景-周期累积应约为5.48GB" "5.48" "${cumulative_gb}" "0.01"

# Cleanup
cleanup

# Print summary
echo ""
echo "=========================================="
echo "  测试总结 / Test Summary"
echo "=========================================="
echo "总测试数 / Total Tests: ${TEST_COUNT}"
echo -e "${GREEN}通过 / Passed: ${PASS_COUNT}${NC}"
echo -e "${RED}失败 / Failed: ${FAIL_COUNT}${NC}"
echo ""

if [ ${FAIL_COUNT} -eq 0 ]; then
    echo -e "${GREEN}✓ 所有测试通过! / All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ 部分测试失败! / Some tests failed!${NC}"
    exit 1
fi
