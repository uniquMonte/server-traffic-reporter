#!/bin/bash

# Test send_daily_report function with debug output
# This script mimics send_daily_report but with detailed logging

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_DIR="${PROJECT_DIR}/config"
DATA_DIR="${PROJECT_DIR}/data"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
TRAFFIC_DATA_FILE="${DATA_DIR}/traffic.db"

# Load configuration
source "${CONFIG_FILE}"

# Source all functions from traffic_monitor.sh
source "${SCRIPT_DIR}/traffic_monitor.sh" 2>/dev/null || true

echo "=========================================="
echo "   🔍 Testing send_daily_report Logic"
echo "=========================================="
echo ""

# Step 1: Call get_daily_traffic
echo "[1] Calling get_daily_traffic()..."
daily_bytes=$(get_daily_traffic)
echo "    Result: daily_bytes = ${daily_bytes} bytes"
echo "    In GB: $(awk "BEGIN {printf \"%.2f\", ${daily_bytes}/1073741824}") GB"
echo ""

# Step 2: Call get_cumulative_traffic
echo "[2] Calling get_cumulative_traffic()..."
cumulative_bytes=$(get_cumulative_traffic)
echo "    Result: cumulative_bytes = ${cumulative_bytes} bytes"
echo "    In GB: $(awk "BEGIN {printf \"%.2f\", ${cumulative_bytes}/1073741824}") GB"
echo ""

# Step 3: Get detailed traffic
echo "[3] Calling get_daily_traffic_detailed()..."
daily_detailed=$(get_daily_traffic_detailed)
daily_rx=$(echo "${daily_detailed}" | awk '{print $1}')
daily_tx=$(echo "${daily_detailed}" | awk '{print $2}')
echo "    Result: daily_rx = ${daily_rx} bytes"
echo "    Result: daily_tx = ${daily_tx} bytes"
echo "    RX in GB: $(awk "BEGIN {printf \"%.2f\", ${daily_rx}/1073741824}") GB"
echo "    TX in GB: $(awk "BEGIN {printf \"%.2f\", ${daily_tx}/1073741824}") GB"
echo ""

# Step 4: Get cumulative detailed
echo "[4] Calling get_cumulative_traffic_detailed()..."
cumulative_detailed=$(get_cumulative_traffic_detailed)
cumulative_rx=$(echo "${cumulative_detailed}" | awk '{print $1}')
cumulative_tx=$(echo "${cumulative_detailed}" | awk '{print $2}')
echo "    Result: cumulative_rx = ${cumulative_rx} bytes"
echo "    Result: cumulative_tx = ${cumulative_tx} bytes"
echo "    RX in GB: $(awk "BEGIN {printf \"%.2f\", ${cumulative_rx}/1073741824}") GB"
echo "    TX in GB: $(awk "BEGIN {printf \"%.2f\", ${cumulative_tx}/1073741824}") GB"
echo ""

# Step 5: Convert to GB (as done in send_daily_report)
echo "[5] Converting to GB..."
daily_gb=$(awk "BEGIN {printf \"%.2f\", ${daily_bytes}/1073741824}")
cumulative_gb=$(awk "BEGIN {printf \"%.2f\", ${cumulative_bytes}/1073741824}")
daily_rx_gb=$(awk "BEGIN {printf \"%.2f\", ${daily_rx}/1073741824}")
daily_tx_gb=$(awk "BEGIN {printf \"%.2f\", ${daily_tx}/1073741824}")
cumulative_rx_gb=$(awk "BEGIN {printf \"%.2f\", ${cumulative_rx}/1073741824}")
cumulative_tx_gb=$(awk "BEGIN {printf \"%.2f\", ${cumulative_tx}/1073741824}")

echo "    daily_gb = ${daily_gb}"
echo "    cumulative_gb = ${cumulative_gb}"
echo "    daily_rx_gb = ${daily_rx_gb}"
echo "    daily_tx_gb = ${daily_tx_gb}"
echo "    cumulative_rx_gb = ${cumulative_rx_gb}"
echo "    cumulative_tx_gb = ${cumulative_tx_gb}"
echo ""

# Step 6: Show what would be in the report
echo "=========================================="
echo "   📊 What the Report SHOULD Show"
echo "=========================================="
echo ""
echo "📈 Today's Usage"
echo "  ├ 💎 Used: ${daily_gb} GB"
echo "             ├ ⬇️ ${daily_rx_gb} GB"
echo "             └ ⬆️ ${daily_tx_gb} GB"
echo ""
echo "🎯 Cycle Total"
echo "  ├ 💎 Used: ${cumulative_gb} GB"
echo "             ├ ⬇️ ${cumulative_rx_gb} GB"
echo "             └ ⬆️ ${cumulative_tx_gb} GB"
echo ""

# Step 7: Check if values are zero
echo "=========================================="
echo "   ⚠️  Diagnosis"
echo "=========================================="
echo ""

if [ "${daily_bytes}" -eq 0 ]; then
    echo "❌ PROBLEM: daily_bytes is ZERO!"
    echo "   This means get_daily_traffic() returned 0"
    echo ""
    echo "   Debugging get_daily_traffic():"

    today=$(date +%Y-%m-%d)
    echo "   Today: ${today}"

    # Check for today's entries
    today_entries=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep "^${today}|" | wc -l)
    echo "   Today's entries in database: ${today_entries}"

    if [ "${today_entries}" -gt 0 ]; then
        echo "   First today entry:"
        grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep "^${today}|" | head -1

        yesterday=$(date -d "${today} -1 day" +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
        yesterday_last=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep "^${yesterday}|" | tail -1 | cut -d'|' -f3 2>/dev/null || echo "")

        echo "   Yesterday (${yesterday}) last cumulative: ${yesterday_last}"

        if [ -z "${yesterday_last}" ]; then
            today_start=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep -v "^${today}|" | grep -v "RESET" | tail -1 | cut -d'|' -f3 2>/dev/null || echo "0")
            echo "   No yesterday entry, using last non-today: ${today_start}"
        else
            today_start=${yesterday_last}
            echo "   Using yesterday's last: ${today_start}"
        fi
    fi

elif [ "${cumulative_bytes}" -eq 0 ]; then
    echo "❌ PROBLEM: cumulative_bytes is ZERO!"
    echo "   This means get_cumulative_traffic() returned 0"

else
    echo "✅ Values look correct!"
    echo "   daily_bytes: ${daily_bytes} (${daily_gb} GB)"
    echo "   cumulative_bytes: ${cumulative_bytes} (${cumulative_gb} GB)"
    echo ""
    echo "   If Telegram still shows 0.00 GB, the problem might be:"
    echo "   1. The values are being calculated correctly but not sent"
    echo "   2. The message format is incorrect"
    echo "   3. There's a race condition or timing issue"
fi

echo ""
echo "=========================================="
