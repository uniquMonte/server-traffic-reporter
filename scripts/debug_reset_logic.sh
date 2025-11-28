#!/bin/bash

# Debug need_reset() function logic

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${PROJECT_DIR}/config/config.conf"
TRAFFIC_DATA_FILE="${PROJECT_DIR}/data/traffic.db"

# Load configuration
source "${CONFIG_FILE}"

echo "=========================================="
echo "   🔍 Debug need_reset() Logic"
echo "=========================================="
echo ""

# Current values
CURRENT_MONTH=$(date +%Y-%m)
CURRENT_DATE=$(date +%Y-%m-%d)
RESET_DAY=${TRAFFIC_RESET_DAY}

echo "Current values:"
echo "  CURRENT_DATE: ${CURRENT_DATE}"
echo "  CURRENT_MONTH: ${CURRENT_MONTH}"
echo "  RESET_DAY: ${RESET_DAY}"
echo ""

# Calculate reset date for this month
DAYS_IN_MONTH=$(date -d "${CURRENT_MONTH}-01 +1 month -1 day" +%d)
EFFECTIVE_RESET_DAY=${RESET_DAY}
if [ "$((10#${RESET_DAY}))" -gt "$((10#${DAYS_IN_MONTH}))" ]; then
    EFFECTIVE_RESET_DAY=${DAYS_IN_MONTH}
fi

RESET_DATE_THIS_MONTH="${CURRENT_MONTH}-$(printf "%02d" ${EFFECTIVE_RESET_DAY})"

echo "Calculated reset date for this month:"
echo "  DAYS_IN_MONTH: ${DAYS_IN_MONTH}"
echo "  EFFECTIVE_RESET_DAY: ${EFFECTIVE_RESET_DAY}"
echo "  RESET_DATE_THIS_MONTH: ${RESET_DATE_THIS_MONTH}"
echo ""

# Get last reset from database
LAST_RESET_LINE=$(grep "RESET|" "${TRAFFIC_DATA_FILE}" 2>/dev/null | tail -1)
LAST_RESET_DATE=$(echo "${LAST_RESET_LINE}" | cut -d'|' -f2 || echo "")

echo "Database info:"
echo "  LAST_RESET_LINE: ${LAST_RESET_LINE}"
echo "  LAST_RESET_DATE: ${LAST_RESET_DATE}"
echo ""

# Check logic
echo "=========================================="
echo "   Logic Checks"
echo "=========================================="
echo ""

echo "Check 1: Did we already reset on the configured reset day this month?"
echo "  LAST_RESET_DATE == RESET_DATE_THIS_MONTH?"
echo "  ${LAST_RESET_DATE} == ${RESET_DATE_THIS_MONTH}?"
if [ "${LAST_RESET_DATE}" == "${RESET_DATE_THIS_MONTH}" ]; then
    echo "  YES - Already reset on configured day, should NOT reset again"
else
    echo "  NO - Not reset on configured day yet"
fi
echo ""

echo "Check 2: Has the reset day arrived this month?"
echo "  CURRENT_DATE < RESET_DATE_THIS_MONTH?"
echo "  ${CURRENT_DATE} < ${RESET_DATE_THIS_MONTH}?"
if [[ "${CURRENT_DATE}" < "${RESET_DATE_THIS_MONTH}" ]]; then
    echo "  YES - Reset day hasn't arrived, should NOT reset"
else
    echo "  NO - Reset day has passed or is today"
fi
echo ""

echo "=========================================="
echo "   Current need_reset() Logic Result"
echo "=========================================="
echo ""

if [ "${LAST_RESET_DATE}" == "${RESET_DATE_THIS_MONTH}" ]; then
    echo "Result: Do NOT reset (already reset on configured day)"
elif [[ "${CURRENT_DATE}" < "${RESET_DATE_THIS_MONTH}" ]]; then
    echo "Result: Do NOT reset (reset day not arrived)"
else
    echo "Result: RESET (reset day arrived and not reset on configured day)"
fi
echo ""

echo "=========================================="
echo "   ⚠️  PROBLEM ANALYSIS"
echo "=========================================="
echo ""

echo "The issue is:"
echo "  Today is ${CURRENT_DATE} (the 28th)"
echo "  Reset day is configured as the ${RESET_DAY}th (2025-11-04)"
echo "  Last reset was on ${LAST_RESET_DATE} (today, manually reset)"
echo ""
echo "The current logic says:"
echo "  - Is last_reset_date (${LAST_RESET_DATE}) == reset_date_this_month (${RESET_DATE_THIS_MONTH})? NO"
echo "  - Is current_date (${CURRENT_DATE}) < reset_date_this_month (${RESET_DATE_THIS_MONTH})? NO"
echo "  - Therefore: RESET!"
echo ""
echo "This is WRONG because:"
echo "  1. We already reset today (${LAST_RESET_DATE})"
echo "  2. The reset day (4th) was already passed this month"
echo "  3. The script should NOT reset again until next month's 4th"
echo ""
echo "The fix:"
echo "  The logic should check if last_reset_date is in the SAME MONTH"
echo "  as current_date, and if so, don't reset again."
echo "  OR: Check if last_reset_date >= reset_date_this_month"
echo ""

echo "=========================================="
