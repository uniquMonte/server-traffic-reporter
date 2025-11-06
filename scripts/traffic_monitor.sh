#!/bin/bash

# VPS Traffic Monitor Script
# Monitors network traffic and sends daily reports

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_DIR="${PROJECT_DIR}/config"
DATA_DIR="${PROJECT_DIR}/data"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
TRAFFIC_DATA_FILE="${DATA_DIR}/traffic.db"
LAST_RUN_FILE="${DATA_DIR}/last_run"

# Load configuration
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Error: Configuration file not found at ${CONFIG_FILE}"
    exit 1
fi

source "${CONFIG_FILE}"

# Function to get current traffic in bytes
get_current_traffic() {
    local interface="$1"

    # Get received and transmitted bytes
    local rx_bytes=$(cat /sys/class/net/${interface}/statistics/rx_bytes 2>/dev/null || echo 0)
    local tx_bytes=$(cat /sys/class/net/${interface}/statistics/tx_bytes 2>/dev/null || echo 0)

    # Calculate traffic based on direction setting
    local total_bytes=0
    case "${TRAFFIC_DIRECTION:-1}" in
        1)
            # Bidirectional (both directions)
            total_bytes=$((rx_bytes + tx_bytes))
            ;;
        2)
            # Outbound only (server to client, tx = transmitted)
            total_bytes=${tx_bytes}
            ;;
        3)
            # Inbound only (client to server, rx = received)
            total_bytes=${rx_bytes}
            ;;
        *)
            # Default to bidirectional
            total_bytes=$((rx_bytes + tx_bytes))
            ;;
    esac

    echo "${total_bytes}"
}

# Function to convert bytes to human readable format
bytes_to_human() {
    local bytes=$1

    if [ "${bytes}" -lt 1024 ] 2>/dev/null; then
        echo "${bytes} B"
    elif [ "${bytes}" -lt 1048576 ] 2>/dev/null; then
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1024}") KB"
    elif [ "${bytes}" -lt 1073741824 ] 2>/dev/null; then
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1048576}") MB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1073741824}") GB"
    fi
}

# Function to convert bytes to GB
bytes_to_gb() {
    local bytes=$1
    echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1073741824}")"
}

# Function to initialize traffic database
init_traffic_db() {
    if [ ! -f "${TRAFFIC_DATA_FILE}" ]; then
        echo "# Traffic Database" > "${TRAFFIC_DATA_FILE}"
        echo "# Format: DATE|DAILY_BYTES|CUMULATIVE_BYTES|RESET_PERIOD" >> "${TRAFFIC_DATA_FILE}"
    fi
}

# Function to check if we need to reset (new billing cycle)
need_reset() {
    local current_day=$(date +%d)
    local current_month=$(date +%Y-%m)
    local reset_day=${TRAFFIC_RESET_DAY}

    # Get the number of days in current month
    local days_in_month=$(date -d "${current_month}-01 +1 month -1 day" +%d)

    # If reset day exceeds days in month, use last day of month
    # Example: reset_day=31 in February (28/29 days) → use 28/29
    local effective_reset_day=${reset_day}
    if [ "${reset_day}" -gt "${days_in_month}" ] 2>/dev/null; then
        effective_reset_day=${days_in_month}
    fi

    # Get last reset month from database
    local last_reset=$(grep "RESET|" "${TRAFFIC_DATA_FILE}" 2>/dev/null | tail -1 | cut -d'|' -f4 || echo "")

    # Check if current day matches effective reset day
    if [ "${current_day}" == "${effective_reset_day}" ] 2>/dev/null; then
        # Check if we already reset this month
        if [ "${last_reset}" != "${current_month}" ]; then
            return 0  # Need reset
        fi
    fi

    return 1  # No reset needed
}

# Function to reset traffic counter
reset_traffic() {
    local reset_date=$(date +%Y-%m-%d)

    # Backup old data
    if [ -f "${TRAFFIC_DATA_FILE}" ]; then
        cp "${TRAFFIC_DATA_FILE}" "${TRAFFIC_DATA_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Create new database with reset marker
    echo "# Traffic Database - Reset on ${reset_date}" > "${TRAFFIC_DATA_FILE}"
    echo "# Format: DATE|DAILY_BYTES|CUMULATIVE_BYTES|RESET_PERIOD" >> "${TRAFFIC_DATA_FILE}"
    echo "RESET|${reset_date}|0|$(date +%Y-%m)" >> "${TRAFFIC_DATA_FILE}"

    # Record the baseline traffic
    local current_traffic=$(get_current_traffic "${NETWORK_INTERFACE}")
    echo "$(date +%Y-%m-%d)|0|0|baseline=${current_traffic}" >> "${TRAFFIC_DATA_FILE}"

    echo "Traffic counter reset for new billing cycle starting ${reset_date}"
}

# Function to get baseline traffic (traffic at last measurement)
get_baseline() {
    local baseline=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" 2>/dev/null | grep "baseline=" | tail -1 | sed 's/.*baseline=//' 2>/dev/null || echo "0")

    # Validate that baseline is a valid number
    if ! [[ "${baseline}" =~ ^[0-9]+$ ]]; then
        baseline=0
    fi

    echo "${baseline}"
}

# Function to get cumulative traffic for current period
get_cumulative_traffic() {
    local baseline=$(get_baseline)
    local current=$(get_current_traffic "${NETWORK_INTERFACE}")

    # If current is less than baseline, interface was reset (server reboot)
    # In this case, get the last known cumulative and add current
    if [ "${current}" -lt "${baseline}" ] 2>/dev/null; then
        local last_cumulative=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep -v "RESET" | tail -1 | cut -d'|' -f3 || echo "0")
        local cumulative=$((last_cumulative + current))
    else
        local last_cumulative=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep -v "RESET" | tail -1 | cut -d'|' -f3 || echo "0")
        local diff=$((current - baseline))
        local cumulative=$((last_cumulative + diff))
    fi

    echo "${cumulative}"
}

# Function to get today's traffic
get_daily_traffic() {
    local today=$(date +%Y-%m-%d)
    local current_cumulative=$(get_cumulative_traffic)

    # Find today's starting cumulative (first entry of today, or last entry of yesterday)
    local today_start_cumulative=0

    # Check if there's any entry for today already
    local today_first_entry=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep "^${today}|" | head -1 | cut -d'|' -f3 2>/dev/null || echo "")

    if [ -n "${today_first_entry}" ]; then
        # Today has entries, get the cumulative from yesterday's last entry
        local yesterday=$(date -d "${today} -1 day" +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
        local yesterday_last=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep "^${yesterday}|" | tail -1 | cut -d'|' -f3 2>/dev/null || echo "")

        if [ -n "${yesterday_last}" ]; then
            today_start_cumulative=${yesterday_last}
        else
            # No yesterday entry, use the last non-today entry
            today_start_cumulative=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep -v "^${today}|" | grep -v "RESET" | tail -1 | cut -d'|' -f3 2>/dev/null || echo "0")
        fi
    else
        # No entry for today yet, use last entry's cumulative as starting point
        today_start_cumulative=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep -v "RESET" | tail -1 | cut -d'|' -f3 2>/dev/null || echo "0")
    fi

    # Calculate today's usage
    local daily=$((current_cumulative - today_start_cumulative))

    # If daily is negative, something is wrong (reset, etc.)
    if [ "${daily}" -lt 0 ] 2>/dev/null; then
        daily=0
    fi

    echo "${daily}"
}

# Function to calculate percentage
calculate_percentage() {
    local used_gb=$1
    local limit_gb=$2

    local percentage=$(awk "BEGIN {printf \"%.2f\", (${used_gb}/${limit_gb})*100}")
    echo "${percentage}"
}

# Function to get progress bar
get_progress_bar() {
    local percentage=$1
    local bar_length=12
    local filled=$(awk "BEGIN {printf \"%d\", (${percentage}/100)*${bar_length}}")
    local empty=$((bar_length - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do
        bar="${bar}▓"
    done
    for ((i=0; i<empty; i++)); do
        bar="${bar}░"
    done

    echo "${bar}"
}

# Function to send daily report
send_daily_report() {
    local daily_bytes=$(get_daily_traffic)
    local cumulative_bytes=$(get_cumulative_traffic)

    # Convert to GB
    local daily_gb=$(bytes_to_gb ${daily_bytes})
    local cumulative_gb=$(bytes_to_gb ${cumulative_bytes})
    local limit_gb=${MONTHLY_TRAFFIC_LIMIT}

    # Calculate percentage
    local percentage=$(calculate_percentage ${cumulative_gb} ${limit_gb})

    # Get progress bar
    local progress_bar=$(get_progress_bar ${percentage})

    # Get billing cycle info
    local current_day=$(date +%d)
    local reset_day=$(printf "%02d" ${TRAFFIC_RESET_DAY})
    local current_month=$(date +%Y-%m)

    # Calculate days until reset
    local days_in_month=$(date -d "${current_month}-01 +1 month -1 day" +%d)
    local days_until_reset=0

    if [ "${current_day}" -lt "${TRAFFIC_RESET_DAY}" ] 2>/dev/null; then
        days_until_reset=$((TRAFFIC_RESET_DAY - current_day))
    else
        local next_month=$(date -d "${current_month}-01 +1 month" +%Y-%m)
        local next_reset_date="${next_month}-${reset_day}"
        days_until_reset=$(( ($(date -d "${next_reset_date}" +%s) - $(date +%s)) / 86400 ))
    fi

    # Determine status emoji
    local status_emoji="✅"
    if (( $(echo "${percentage} >= 90" | bc -l) )); then
        status_emoji="🔴"
    elif (( $(echo "${percentage} >= 75" | bc -l) )); then
        status_emoji="🟡"
    elif (( $(echo "${percentage} >= 50" | bc -l) )); then
        status_emoji="🟠"
    fi

    # Build message
    local message="📊 *Daily Traffic Report - ${SERVER_NAME}*\n\n"
    message="${message}📈 *Today's Usage:* ${daily_gb} GB\n\n"
    message="${message}📊 *Billing Cycle Stats:*\n"
    message="${message}├ Used: ${cumulative_gb} GB\n"
    message="${message}├ Limit: ${limit_gb} GB\n"
    message="${message}└ Remaining: $(awk "BEGIN {printf \"%.2f\", ${limit_gb}-${cumulative_gb}}") GB\n"
    message="${message}${progress_bar} ${percentage}%\n\n"
    message="${message}🔄 *Cycle Info:*\n"
    message="${message}├ Reset Day: ${reset_day} of each month\n"
    message="${message}└ Days until reset: ${days_until_reset}"

    # Add warning if usage is high
    if (( $(echo "${percentage} >= 90" | bc -l) )); then
        message="${message}⚠️ *WARNING:* High usage detected!\n"
    fi

    # Send notification
    "${SCRIPT_DIR}/telegram_notify.sh" "📊 Daily Traffic Report" "${message}"

    # Record today's data
    local today=$(date +%Y-%m-%d)
    local baseline=$(get_current_traffic "${NETWORK_INTERFACE}")
    echo "${today}|${daily_bytes}|${cumulative_bytes}|baseline=${baseline}" >> "${TRAFFIC_DATA_FILE}"
}

# Main function
main() {
    local mode="${1:-daily}"

    # Initialize database if needed
    init_traffic_db

    # Check if we need to reset for new billing cycle
    if need_reset; then
        echo "New billing cycle detected. Resetting traffic counter..."
        reset_traffic

        # Send reset notification
        local message="🔄 *Traffic Counter Reset*\n\n"
        message="${message}New billing cycle started on $(date +%Y-%m-%d)\n\n"
        message="${message}Monthly limit: ${MONTHLY_TRAFFIC_LIMIT} GB\n"
        message="${message}Reset day: ${TRAFFIC_RESET_DAY} of each month"

        "${SCRIPT_DIR}/telegram_notify.sh" "🔄 Billing Cycle Reset" "${message}"
    fi

    # Send daily report
    send_daily_report

    # Update last run time
    date +%s > "${LAST_RUN_FILE}"

    echo "Traffic report sent successfully at $(date)"
}

# Run main function
main "$@"
