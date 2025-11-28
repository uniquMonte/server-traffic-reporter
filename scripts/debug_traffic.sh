#!/bin/bash

# Traffic Monitoring Debug Script
# This script helps diagnose why traffic monitoring shows zero

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "   🔍 Traffic Monitor Debug Tool"
echo "=========================================="
echo ""

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_DIR="${PROJECT_DIR}/config"
DATA_DIR="${PROJECT_DIR}/data"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
TRAFFIC_DATA_FILE="${DATA_DIR}/traffic.db"

# Check 1: Configuration file exists
echo -e "${BLUE}[1] Checking configuration file...${NC}"
if [ ! -f "${CONFIG_FILE}" ]; then
    echo -e "${RED}   ✗ Configuration file not found: ${CONFIG_FILE}${NC}"
    exit 1
else
    echo -e "${GREEN}   ✓ Configuration file exists${NC}"
fi
echo ""

# Load configuration
source "${CONFIG_FILE}"

# Check 2: Display current configuration
echo -e "${BLUE}[2] Current Configuration:${NC}"
echo "   Server Name: ${SERVER_NAME:-Not set}"
echo "   Network Interface: ${NETWORK_INTERFACE:-Not set}"
echo "   Traffic Direction: ${TRAFFIC_DIRECTION:-Not set} (1=Both, 2=Upload, 3=Download)"
echo "   Monthly Limit: ${MONTHLY_TRAFFIC_LIMIT:-Not set} GB"
echo "   Reset Day: ${TRAFFIC_RESET_DAY:-Not set}"
echo ""

# Check 3: Network interface exists
echo -e "${BLUE}[3] Checking network interface '${NETWORK_INTERFACE}'...${NC}"
if [ -z "${NETWORK_INTERFACE}" ]; then
    echo -e "${RED}   ✗ NETWORK_INTERFACE not configured!${NC}"
    echo ""
    echo -e "${YELLOW}Available network interfaces:${NC}"
    ls /sys/class/net/ | while read iface; do
        echo "   - ${iface}"
    done
    echo ""
    echo -e "${YELLOW}Please update your config file with the correct interface name.${NC}"
    exit 1
elif [ ! -d "/sys/class/net/${NETWORK_INTERFACE}" ]; then
    echo -e "${RED}   ✗ Interface '${NETWORK_INTERFACE}' does not exist!${NC}"
    echo ""
    echo -e "${YELLOW}Available network interfaces:${NC}"
    ls /sys/class/net/ | while read iface; do
        echo "   - ${iface}"
    done
    echo ""
    echo -e "${YELLOW}Please update your config file with the correct interface name.${NC}"
    exit 1
else
    echo -e "${GREEN}   ✓ Interface '${NETWORK_INTERFACE}' exists${NC}"
fi
echo ""

# Check 4: Can read traffic statistics
echo -e "${BLUE}[4] Checking traffic statistics files...${NC}"
RX_FILE="/sys/class/net/${NETWORK_INTERFACE}/statistics/rx_bytes"
TX_FILE="/sys/class/net/${NETWORK_INTERFACE}/statistics/tx_bytes"

if [ ! -r "${RX_FILE}" ]; then
    echo -e "${RED}   ✗ Cannot read ${RX_FILE}${NC}"
    echo -e "${YELLOW}   Permission issue - try running with sudo${NC}"
    exit 1
else
    echo -e "${GREEN}   ✓ Can read ${RX_FILE}${NC}"
fi

if [ ! -r "${TX_FILE}" ]; then
    echo -e "${RED}   ✗ Cannot read ${TX_FILE}${NC}"
    echo -e "${YELLOW}   Permission issue - try running with sudo${NC}"
    exit 1
else
    echo -e "${GREEN}   ✓ Can read ${TX_FILE}${NC}"
fi
echo ""

# Check 5: Read current traffic values
echo -e "${BLUE}[5] Current traffic statistics:${NC}"
RX_BYTES=$(cat "${RX_FILE}" 2>/dev/null || echo "0")
TX_BYTES=$(cat "${TX_FILE}" 2>/dev/null || echo "0")

# Convert to human readable
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

RX_HUMAN=$(bytes_to_human ${RX_BYTES})
TX_HUMAN=$(bytes_to_human ${TX_BYTES})
TOTAL_BYTES=$((RX_BYTES + TX_BYTES))
TOTAL_HUMAN=$(bytes_to_human ${TOTAL_BYTES})

echo "   RX (Download): ${RX_BYTES} bytes (${RX_HUMAN})"
echo "   TX (Upload):   ${TX_BYTES} bytes (${TX_HUMAN})"
echo "   Total:         ${TOTAL_BYTES} bytes (${TOTAL_HUMAN})"
echo ""

if [ "${TOTAL_BYTES}" -eq 0 ]; then
    echo -e "${RED}   ✗ WARNING: Total traffic is 0!${NC}"
    echo -e "${YELLOW}   This interface may not be the one carrying your traffic.${NC}"
    echo ""
    echo -e "${YELLOW}Checking all interfaces:${NC}"
    echo ""
    for iface in /sys/class/net/*; do
        iface_name=$(basename "${iface}")
        if [ "${iface_name}" != "lo" ]; then
            rx=$(cat "${iface}/statistics/rx_bytes" 2>/dev/null || echo "0")
            tx=$(cat "${iface}/statistics/tx_bytes" 2>/dev/null || echo "0")
            total=$((rx + tx))
            total_human=$(bytes_to_human ${total})
            if [ "${total}" -gt 0 ]; then
                echo -e "${GREEN}   ${iface_name}: ${total_human}${NC}"
            else
                echo "   ${iface_name}: ${total_human}"
            fi
        fi
    done
    echo ""
fi

# Check 6: Database status
echo -e "${BLUE}[6] Checking traffic database...${NC}"
if [ ! -f "${TRAFFIC_DATA_FILE}" ]; then
    echo -e "${YELLOW}   ! Database not initialized yet${NC}"
    echo -e "${YELLOW}   This is normal for first-time setup${NC}"
else
    echo -e "${GREEN}   ✓ Database exists: ${TRAFFIC_DATA_FILE}${NC}"
    echo ""
    echo "   Last 5 entries:"
    echo "   ----------------------------------------"
    tail -5 "${TRAFFIC_DATA_FILE}" | while read line; do
        if [[ "${line}" =~ ^# ]]; then
            echo -e "   ${BLUE}${line}${NC}"
        elif [[ "${line}" =~ ^RESET ]]; then
            echo -e "   ${YELLOW}${line}${NC}"
        else
            echo "   ${line}"
        fi
    done
    echo "   ----------------------------------------"
    echo ""

    # Extract baseline values
    LAST_LINE=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" 2>/dev/null | tail -1)
    BASELINE_RX=$(echo "${LAST_LINE}" | sed -n 's/.*baseline_rx=\([0-9]*\).*/\1/p' 2>/dev/null || echo "")
    BASELINE_TX=$(echo "${LAST_LINE}" | sed -n 's/.*baseline_tx=\([0-9]*\).*/\1/p' 2>/dev/null || echo "")

    if [ -n "${BASELINE_RX}" ] && [ -n "${BASELINE_TX}" ]; then
        echo "   Current Baseline:"
        echo "   RX: ${BASELINE_RX} bytes ($(bytes_to_human ${BASELINE_RX}))"
        echo "   TX: ${BASELINE_TX} bytes ($(bytes_to_human ${BASELINE_TX}))"
        echo ""

        # Calculate what the traffic should be
        DIFF_RX=$((RX_BYTES - BASELINE_RX))
        DIFF_TX=$((TX_BYTES - BASELINE_TX))

        if [ "${DIFF_RX}" -lt 0 ]; then
            DIFF_RX=0
        fi
        if [ "${DIFF_TX}" -lt 0 ]; then
            DIFF_TX=0
        fi

        DIFF_TOTAL=$((DIFF_RX + DIFF_TX))

        echo "   Traffic since last baseline:"
        echo "   RX: ${DIFF_RX} bytes ($(bytes_to_human ${DIFF_RX}))"
        echo "   TX: ${DIFF_TX} bytes ($(bytes_to_human ${DIFF_TX}))"
        echo "   Total: ${DIFF_TOTAL} bytes ($(bytes_to_human ${DIFF_TOTAL}))"
        echo ""

        if [ "${DIFF_TOTAL}" -eq 0 ]; then
            echo -e "${RED}   ✗ No traffic detected since last measurement!${NC}"
            echo -e "${YELLOW}   Possible causes:${NC}"
            echo "   1. Wrong network interface configured"
            echo "   2. Server has not received/sent any data"
            echo "   3. Baseline was just set (wait for some traffic)"
        else
            echo -e "${GREEN}   ✓ Traffic is being measured correctly${NC}"
        fi
    fi
fi
echo ""

# Check 7: Recommendations
echo -e "${BLUE}[7] Recommendations:${NC}"
echo ""

# Find the interface with most traffic
MAX_TRAFFIC=0
BEST_INTERFACE=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "${iface}")
    if [ "${iface_name}" != "lo" ]; then
        rx=$(cat "${iface}/statistics/rx_bytes" 2>/dev/null || echo "0")
        tx=$(cat "${iface}/statistics/tx_bytes" 2>/dev/null || echo "0")
        total=$((rx + tx))
        if [ "${total}" -gt "${MAX_TRAFFIC}" ]; then
            MAX_TRAFFIC=${total}
            BEST_INTERFACE=${iface_name}
        fi
    fi
done

if [ "${BEST_INTERFACE}" != "${NETWORK_INTERFACE}" ]; then
    echo -e "${YELLOW}⚠️  Recommended interface: ${BEST_INTERFACE}${NC}"
    echo "   (This interface has the most traffic)"
    echo ""
    echo "   To update your configuration:"
    echo -e "   ${BLUE}nano ${CONFIG_FILE}${NC}"
    echo "   Change: NETWORK_INTERFACE=\"${BEST_INTERFACE}\""
    echo ""
fi

if [ ! -f "${TRAFFIC_DATA_FILE}" ] || [ "${TOTAL_BYTES}" -eq 0 ]; then
    echo "💡 Next steps:"
    echo "   1. Verify the network interface is correct"
    echo "   2. Run the monitor script to initialize: ./scripts/traffic_monitor.sh"
    echo "   3. Generate some traffic (browse web, download files, etc.)"
    echo "   4. Check stats again: ./scripts/traffic_monitor.sh (option 3)"
fi

echo ""
echo "=========================================="
echo "   Debug scan complete!"
echo "=========================================="
