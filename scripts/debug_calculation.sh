#!/bin/bash

# Detailed Traffic Calculation Debug Script
# This script shows step-by-step how traffic is calculated

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================="
echo "   🔍 Traffic Calculation Debug"
echo "=========================================="
echo ""

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_DIR="${PROJECT_DIR}/config"
DATA_DIR="${PROJECT_DIR}/data"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
TRAFFIC_DATA_FILE="${DATA_DIR}/traffic.db"

# Load configuration
source "${CONFIG_FILE}"

echo -e "${BLUE}Configuration:${NC}"
echo "  Interface: ${NETWORK_INTERFACE}"
echo "  Traffic Direction: ${TRAFFIC_DIRECTION} (1=Both, 2=Upload, 3=Download)"
echo ""

# Read current values from interface
RX_CURRENT=$(cat /sys/class/net/${NETWORK_INTERFACE}/statistics/rx_bytes)
TX_CURRENT=$(cat /sys/class/net/${NETWORK_INTERFACE}/statistics/tx_bytes)

echo -e "${BLUE}Step 1: Current Interface Values${NC}"
echo "  RX_CURRENT: ${RX_CURRENT} bytes"
echo "  TX_CURRENT: ${TX_CURRENT} bytes"
echo ""

# Calculate current traffic based on direction
CURRENT_TOTAL=0
case "${TRAFFIC_DIRECTION:-1}" in
    1)
        CURRENT_TOTAL=$((RX_CURRENT + TX_CURRENT))
        echo -e "${CYAN}  Direction = 1 (Bidirectional)${NC}"
        echo "  CURRENT_TOTAL = RX + TX = ${RX_CURRENT} + ${TX_CURRENT} = ${CURRENT_TOTAL}"
        ;;
    2)
        CURRENT_TOTAL=${TX_CURRENT}
        echo -e "${CYAN}  Direction = 2 (Upload only)${NC}"
        echo "  CURRENT_TOTAL = TX = ${TX_CURRENT}"
        ;;
    3)
        CURRENT_TOTAL=${RX_CURRENT}
        echo -e "${CYAN}  Direction = 3 (Download only)${NC}"
        echo "  CURRENT_TOTAL = RX = ${RX_CURRENT}"
        ;;
esac
echo ""

# Read baseline from database
LAST_LINE=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | tail -1)
echo -e "${BLUE}Step 2: Last Database Entry${NC}"
echo "  ${LAST_LINE}"
echo ""

# Extract baseline values
BASELINE_RX=$(echo "${LAST_LINE}" | sed -n 's/.*baseline_rx=\([0-9]*\).*/\1/p')
BASELINE_TX=$(echo "${LAST_LINE}" | sed -n 's/.*baseline_tx=\([0-9]*\).*/\1/p')

echo -e "${BLUE}Step 3: Baseline Values from Database${NC}"
echo "  BASELINE_RX: ${BASELINE_RX} bytes"
echo "  BASELINE_TX: ${BASELINE_TX} bytes"
echo ""

# Calculate baseline based on direction
BASELINE_TOTAL=0
case "${TRAFFIC_DIRECTION:-1}" in
    1)
        BASELINE_TOTAL=$((BASELINE_RX + BASELINE_TX))
        echo -e "${CYAN}  Direction = 1 (Bidirectional)${NC}"
        echo "  BASELINE_TOTAL = BASELINE_RX + BASELINE_TX = ${BASELINE_RX} + ${BASELINE_TX} = ${BASELINE_TOTAL}"
        ;;
    2)
        BASELINE_TOTAL=${BASELINE_TX}
        echo -e "${CYAN}  Direction = 2 (Upload only)${NC}"
        echo "  BASELINE_TOTAL = BASELINE_TX = ${BASELINE_TX}"
        ;;
    3)
        BASELINE_TOTAL=${BASELINE_RX}
        echo -e "${CYAN}  Direction = 3 (Download only)${NC}"
        echo "  BASELINE_TOTAL = BASELINE_RX = ${BASELINE_RX}"
        ;;
esac
echo ""

# Extract last cumulative from database
LAST_CUMULATIVE=$(echo "${LAST_LINE}" | cut -d'|' -f3)
LAST_CUMULATIVE_RX=$(echo "${LAST_LINE}" | cut -d'|' -f6)
LAST_CUMULATIVE_TX=$(echo "${LAST_LINE}" | cut -d'|' -f7)

echo -e "${BLUE}Step 4: Last Cumulative Values from Database${NC}"
echo "  LAST_CUMULATIVE (total): ${LAST_CUMULATIVE} bytes"
echo "  LAST_CUMULATIVE_RX: ${LAST_CUMULATIVE_RX} bytes"
echo "  LAST_CUMULATIVE_TX: ${LAST_CUMULATIVE_TX} bytes"
echo ""

# Calculate difference
echo -e "${BLUE}Step 5: Calculate Traffic Since Last Baseline${NC}"

if [ "${CURRENT_TOTAL}" -lt "${BASELINE_TOTAL}" ]; then
    echo -e "${YELLOW}  WARNING: CURRENT < BASELINE (server might have rebooted)${NC}"
    echo "  CURRENT_TOTAL (${CURRENT_TOTAL}) < BASELINE_TOTAL (${BASELINE_TOTAL})"
    echo "  Using reboot logic: CUMULATIVE = LAST_CUMULATIVE + CURRENT_TOTAL"
    CUMULATIVE_TOTAL=$((LAST_CUMULATIVE + CURRENT_TOTAL))
    echo "  CUMULATIVE_TOTAL = ${LAST_CUMULATIVE} + ${CURRENT_TOTAL} = ${CUMULATIVE_TOTAL}"
else
    DIFF=$((CURRENT_TOTAL - BASELINE_TOTAL))
    echo "  DIFF = CURRENT_TOTAL - BASELINE_TOTAL"
    echo "  DIFF = ${CURRENT_TOTAL} - ${BASELINE_TOTAL} = ${DIFF}"
    CUMULATIVE_TOTAL=$((LAST_CUMULATIVE + DIFF))
    echo "  CUMULATIVE_TOTAL = LAST_CUMULATIVE + DIFF"
    echo "  CUMULATIVE_TOTAL = ${LAST_CUMULATIVE} + ${DIFF} = ${CUMULATIVE_TOTAL}"
fi
echo ""

# Detailed RX/TX calculation
echo -e "${BLUE}Step 6: Calculate Detailed RX/TX Traffic${NC}"

DIFF_RX=$((RX_CURRENT - BASELINE_RX))
DIFF_TX=$((TX_CURRENT - BASELINE_TX))

if [ "${DIFF_RX}" -lt 0 ]; then
    echo -e "${YELLOW}  RX: Negative diff detected, using reboot logic${NC}"
    CUMULATIVE_RX=$((LAST_CUMULATIVE_RX + RX_CURRENT))
    echo "  CUMULATIVE_RX = ${LAST_CUMULATIVE_RX} + ${RX_CURRENT} = ${CUMULATIVE_RX}"
else
    CUMULATIVE_RX=$((LAST_CUMULATIVE_RX + DIFF_RX))
    echo "  DIFF_RX = ${RX_CURRENT} - ${BASELINE_RX} = ${DIFF_RX}"
    echo "  CUMULATIVE_RX = ${LAST_CUMULATIVE_RX} + ${DIFF_RX} = ${CUMULATIVE_RX}"
fi

if [ "${DIFF_TX}" -lt 0 ]; then
    echo -e "${YELLOW}  TX: Negative diff detected, using reboot logic${NC}"
    CUMULATIVE_TX=$((LAST_CUMULATIVE_TX + TX_CURRENT))
    echo "  CUMULATIVE_TX = ${LAST_CUMULATIVE_TX} + ${TX_CURRENT} = ${CUMULATIVE_TX}"
else
    CUMULATIVE_TX=$((LAST_CUMULATIVE_TX + DIFF_TX))
    echo "  DIFF_TX = ${TX_CURRENT} - ${BASELINE_TX} = ${DIFF_TX}"
    echo "  CUMULATIVE_TX = ${LAST_CUMULATIVE_TX} + ${DIFF_TX} = ${CUMULATIVE_TX}"
fi
echo ""

# Calculate today's traffic
echo -e "${BLUE}Step 7: Calculate Today's Traffic${NC}"
TODAY=$(date +%Y-%m-%d)
echo "  Today: ${TODAY}"

# Find yesterday's cumulative or start of today
YESTERDAY=$(date -d "${TODAY} -1 day" +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
YESTERDAY_LAST=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep "^${YESTERDAY}|" | tail -1 | cut -d'|' -f3 2>/dev/null || echo "")

if [ -n "${YESTERDAY_LAST}" ]; then
    TODAY_START=${YESTERDAY_LAST}
    echo "  Yesterday's last cumulative: ${TODAY_START}"
else
    # Check if there's a non-today entry
    TODAY_START=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep -v "^${TODAY}|" | grep -v "RESET" | tail -1 | cut -d'|' -f3 2>/dev/null || echo "0")
    echo "  No yesterday entry, using last non-today cumulative: ${TODAY_START}"
fi

DAILY_TOTAL=$((CUMULATIVE_TOTAL - TODAY_START))
if [ "${DAILY_TOTAL}" -lt 0 ]; then
    echo -e "${YELLOW}  Negative daily traffic, setting to 0${NC}"
    DAILY_TOTAL=0
fi

echo "  DAILY_TOTAL = CUMULATIVE_TOTAL - TODAY_START"
echo "  DAILY_TOTAL = ${CUMULATIVE_TOTAL} - ${TODAY_START} = ${DAILY_TOTAL}"
echo ""

# Convert to human readable
bytes_to_gb() {
    local bytes=$1
    echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1073741824}")"
}

bytes_to_human() {
    local bytes=$1
    if [ "${bytes}" -lt 1024 ]; then
        echo "${bytes} B"
    elif [ "${bytes}" -lt 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1024}") KB"
    elif [ "${bytes}" -lt 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1048576}") MB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1073741824}") GB"
    fi
}

echo -e "${GREEN}=========================================="
echo "   📊 FINAL RESULTS"
echo "==========================================${NC}"
echo ""
echo -e "${CYAN}Today's Traffic:${NC}"
echo "  Total: $(bytes_to_human ${DAILY_TOTAL}) ($(bytes_to_gb ${DAILY_TOTAL}) GB)"
echo ""
echo -e "${CYAN}Cycle Total:${NC}"
echo "  Total: $(bytes_to_human ${CUMULATIVE_TOTAL}) ($(bytes_to_gb ${CUMULATIVE_TOTAL}) GB)"
echo "  RX: $(bytes_to_human ${CUMULATIVE_RX}) ($(bytes_to_gb ${CUMULATIVE_RX}) GB)"
echo "  TX: $(bytes_to_human ${CUMULATIVE_TX}) ($(bytes_to_gb ${CUMULATIVE_TX}) GB)"
echo ""

# Check if values are reasonable
if [ "${CUMULATIVE_TOTAL}" -eq 0 ] && [ "${CURRENT_TOTAL}" -gt 1000000 ]; then
    echo -e "${RED}=========================================="
    echo "   ⚠️  PROBLEM DETECTED!"
    echo "==========================================${NC}"
    echo ""
    echo -e "${YELLOW}Current interface has traffic ($(bytes_to_human ${CURRENT_TOTAL})),"
    echo "but calculated cumulative is 0!${NC}"
    echo ""
    echo "Possible causes:"
    echo "  1. Database was just reset with current interface values as baseline"
    echo "  2. Baseline values are incorrect"
    echo "  3. Calculation logic error"
    echo ""
    echo "Recommended action:"
    echo "  Wait a few minutes and run traffic_monitor.sh again"
    echo "  OR reset database: ./scripts/traffic_monitor.sh (option 2)"
    echo ""
fi

echo "=========================================="
