#!/bin/bash

# Simple diagnosis: Check current database state and recommend action

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
DATA_FILE="${PROJECT_DIR}/data/traffic.db"

echo "=========================================="
echo "   📋 Current Database State"
echo "=========================================="
echo ""

if [ ! -f "${DATA_FILE}" ]; then
    echo "❌ Database not found!"
    exit 1
fi

echo "Complete database content:"
echo "----------------------------------------"
cat "${DATA_FILE}"
echo "----------------------------------------"
echo ""

# Count entries
TOTAL_LINES=$(wc -l < "${DATA_FILE}")
DATA_LINES=$(grep -v "^#" "${DATA_FILE}" | grep -v "^RESET" | wc -l)
TODAY=$(date +%Y-%m-%d)
TODAY_LINES=$(grep "^${TODAY}|" "${DATA_FILE}" | wc -l)

echo "Statistics:"
echo "  Total lines: ${TOTAL_LINES}"
echo "  Data entries: ${DATA_LINES}"
echo "  Today's entries: ${TODAY_LINES}"
echo ""

# Check for data consistency
echo "=========================================="
echo "   🔍 Data Consistency Check"
echo "=========================================="
echo ""

LAST_LINE=$(grep -v "^#" "${DATA_FILE}" | grep -v "^RESET" | tail -1)
echo "Last data entry:"
echo "  ${LAST_LINE}"
echo ""

# Parse the last line
CUMULATIVE_TOTAL=$(echo "${LAST_LINE}" | cut -d'|' -f3)
CUMULATIVE_RX=$(echo "${LAST_LINE}" | cut -d'|' -f6)
CUMULATIVE_TX=$(echo "${LAST_LINE}" | cut -d'|' -f7)

echo "From last entry:"
echo "  CUMULATIVE_TOTAL: ${CUMULATIVE_TOTAL} bytes"
echo "  CUMULATIVE_RX: ${CUMULATIVE_RX} bytes"
echo "  CUMULATIVE_TX: ${CUMULATIVE_TX} bytes"
echo "  RX + TX: $((CUMULATIVE_RX + CUMULATIVE_TX)) bytes"
echo ""

# Check if consistent
if [ "$((CUMULATIVE_RX + CUMULATIVE_TX))" -ne "${CUMULATIVE_TOTAL}" ]; then
    echo "⚠️  WARNING: Inconsistency detected!"
    echo "   CUMULATIVE_TOTAL should equal RX + TX"
    echo "   ${CUMULATIVE_TOTAL} != $((CUMULATIVE_RX + CUMULATIVE_TX))"
    echo ""
    echo "   This indicates a calculation error in the script."
    echo ""
    echo "=========================================="
    echo "   💡 Recommendation"
    echo "=========================================="
    echo ""
    echo "RECOMMENDED: Reset the database"
    echo ""
    echo "  1. Reset the database: ./scripts/traffic_monitor.sh"
    echo "     Then select option 2 (Manual Reset Database)"
    echo ""
    echo "  2. Wait a few minutes for traffic to accumulate"
    echo ""
    echo "  3. Send a test report: ./scripts/traffic_monitor.sh"
    echo "     Then select option 1 (Send Daily Report)"
    echo ""
else
    echo "✅ Data consistency check PASSED!"
    echo "   CUMULATIVE_TOTAL = RX + TX"
    echo "   ${CUMULATIVE_TOTAL} = $((CUMULATIVE_RX + CUMULATIVE_TX))"
    echo ""
    echo "=========================================="
    echo "   ✅ System Status: HEALTHY"
    echo "=========================================="
    echo ""
    echo "Traffic monitoring is working correctly."
    echo "No action needed."
    echo ""
fi

echo "=========================================="
