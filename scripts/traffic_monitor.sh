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

# Function to get detailed traffic (returns rx and tx separately)
# Output format: "rx_bytes tx_bytes"
get_current_traffic_detailed() {
    local interface="$1"

    # Get received and transmitted bytes
    local rx_bytes=$(cat /sys/class/net/${interface}/statistics/rx_bytes 2>/dev/null || echo 0)
    local tx_bytes=$(cat /sys/class/net/${interface}/statistics/tx_bytes 2>/dev/null || echo 0)

    echo "${rx_bytes} ${tx_bytes}"
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
        echo "# Format: DATE|DAILY_BYTES|CUMULATIVE_BYTES|DAILY_RX|DAILY_TX|CUMULATIVE_RX|CUMULATIVE_TX|baseline_rx=RX|baseline_tx=TX" >> "${TRAFFIC_DATA_FILE}"

        # For first-time initialization, use TODAY as the reset date
        # This is more intuitive for new VPS deployments
        # The cycle will auto-reset on the configured reset day going forward
        local today=$(date +%Y-%m-%d)
        local current_month=$(date +%Y-%m)

        # Write today as the reset date
        echo "RESET|${today}|0|${current_month}" >> "${TRAFFIC_DATA_FILE}"

        # Record baseline for current traffic measurement
        local current_traffic=$(get_current_traffic_detailed "${NETWORK_INTERFACE}")
        local rx_bytes=$(echo "${current_traffic}" | awk '{print $1}')
        local tx_bytes=$(echo "${current_traffic}" | awk '{print $2}')
        echo "${today}|0|0|0|0|0|0|baseline_rx=${rx_bytes}|baseline_tx=${tx_bytes}" >> "${TRAFFIC_DATA_FILE}"

        echo "Initialized traffic database with reset date: ${today} (first run)"
        echo "Future resets will occur on day ${TRAFFIC_RESET_DAY} of each month"
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
    if [ "$((10#${reset_day}))" -gt "$((10#${days_in_month}))" ] 2>/dev/null; then
        effective_reset_day=${days_in_month}
    fi

    # Get last reset date and month from database
    local last_reset_line=$(grep "RESET|" "${TRAFFIC_DATA_FILE}" 2>/dev/null | tail -1)
    local last_reset_month=$(echo "${last_reset_line}" | cut -d'|' -f4 || echo "")
    local last_reset_date=$(echo "${last_reset_line}" | cut -d'|' -f2 || echo "")

    # If no reset record exists, we need to reset
    if [ -z "${last_reset_month}" ]; then
        return 0  # Need reset
    fi

    # Check if we already reset this month
    if [ "${last_reset_month}" == "${current_month}" ]; then
        return 1  # Already reset this month, no need to reset
    fi

    # Check if we have crossed the reset day in this month
    # Compare: current_date >= reset_date_of_this_month
    local reset_date_this_month="${current_month}-$(printf "%02d" ${effective_reset_day})"
    local current_date=$(date +%Y-%m-%d)

    # If current date >= reset date of this month, we need to reset
    if [[ "${current_date}" > "${reset_date_this_month}" ]] || [[ "${current_date}" == "${reset_date_this_month}" ]]; then
        return 0  # Need reset
    fi

    # Additional check: if last reset was in a previous month and we're past the reset day
    # Handle year boundary (e.g., last reset was 2024-12, current is 2025-01)
    if [ "$((10#${current_day}))" -ge "$((10#${effective_reset_day}))" ] 2>/dev/null; then
        if [ "${last_reset_month}" != "${current_month}" ]; then
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
    echo "# Format: DATE|DAILY_BYTES|CUMULATIVE_BYTES|DAILY_RX|DAILY_TX|CUMULATIVE_RX|CUMULATIVE_TX|baseline_rx=RX|baseline_tx=TX" >> "${TRAFFIC_DATA_FILE}"
    echo "RESET|${reset_date}|0|$(date +%Y-%m)" >> "${TRAFFIC_DATA_FILE}"

    # Record the baseline traffic
    local current_traffic=$(get_current_traffic_detailed "${NETWORK_INTERFACE}")
    local rx_bytes=$(echo "${current_traffic}" | awk '{print $1}')
    local tx_bytes=$(echo "${current_traffic}" | awk '{print $2}')
    echo "$(date +%Y-%m-%d)|0|0|0|0|0|0|baseline_rx=${rx_bytes}|baseline_tx=${tx_bytes}" >> "${TRAFFIC_DATA_FILE}"

    echo "Traffic counter reset for new billing cycle starting ${reset_date}"
}

# Function to get baseline traffic (traffic at last measurement)
get_baseline() {
    local last_line=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" 2>/dev/null | tail -1)

    # Try to extract baseline_rx and baseline_tx from new format
    local rx_baseline=$(echo "${last_line}" | sed -n 's/.*baseline_rx=\([0-9]*\).*/\1/p' 2>/dev/null || echo "")
    local tx_baseline=$(echo "${last_line}" | sed -n 's/.*baseline_tx=\([0-9]*\).*/\1/p' 2>/dev/null || echo "")

    # If new format exists, calculate baseline based on TRAFFIC_DIRECTION
    if [ -n "${rx_baseline}" ] && [ -n "${tx_baseline}" ]; then
        # Validate that baselines are valid numbers
        if ! [[ "${rx_baseline}" =~ ^[0-9]+$ ]]; then
            rx_baseline=0
        fi
        if ! [[ "${tx_baseline}" =~ ^[0-9]+$ ]]; then
            tx_baseline=0
        fi

        local baseline=0
        case "${TRAFFIC_DIRECTION:-1}" in
            1)
                # Bidirectional
                baseline=$((rx_baseline + tx_baseline))
                ;;
            2)
                # Outbound only (tx)
                baseline=${tx_baseline}
                ;;
            3)
                # Inbound only (rx)
                baseline=${rx_baseline}
                ;;
            *)
                # Default to bidirectional
                baseline=$((rx_baseline + tx_baseline))
                ;;
        esac
        echo "${baseline}"
    else
        # Fall back to old format (baseline=)
        local baseline=$(echo "${last_line}" | sed 's/.*baseline=//' 2>/dev/null || echo "0")

        # Validate that baseline is a valid number
        if ! [[ "${baseline}" =~ ^[0-9]+$ ]]; then
            baseline=0
        fi

        echo "${baseline}"
    fi
}

# Function to get detailed baseline traffic (returns rx and tx separately)
# Output format: "rx_baseline tx_baseline"
get_baseline_detailed() {
    local last_line=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" 2>/dev/null | tail -1)

    # Try to extract baseline_rx and baseline_tx from new format
    local rx_baseline=$(echo "${last_line}" | sed -n 's/.*baseline_rx=\([0-9]*\).*/\1/p' 2>/dev/null || echo "")
    local tx_baseline=$(echo "${last_line}" | sed -n 's/.*baseline_tx=\([0-9]*\).*/\1/p' 2>/dev/null || echo "")

    # If new format doesn't exist, fall back to old format (baseline= is total)
    if [ -z "${rx_baseline}" ] || [ -z "${tx_baseline}" ]; then
        local old_baseline=$(echo "${last_line}" | sed 's/.*baseline=//' 2>/dev/null || echo "0")
        # For old format, we can't distinguish rx/tx, so return 0 0
        rx_baseline="0"
        tx_baseline="0"
    fi

    # Validate that baselines are valid numbers
    if ! [[ "${rx_baseline}" =~ ^[0-9]+$ ]]; then
        rx_baseline=0
    fi
    if ! [[ "${tx_baseline}" =~ ^[0-9]+$ ]]; then
        tx_baseline=0
    fi

    echo "${rx_baseline} ${tx_baseline}"
}

# Function to get cumulative traffic for current period
get_cumulative_traffic() {
    local baseline=$(get_baseline)
    local current=$(get_current_traffic "${NETWORK_INTERFACE}")
    local last_cumulative=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep -v "RESET" | tail -1 | cut -d'|' -f3 || echo "0")
    local cumulative=0

    # If current is less than baseline, interface was reset (server reboot)
    # In this case, get the last known cumulative and add current
    if [ "${current}" -lt "${baseline}" ] 2>/dev/null; then
        cumulative=$((last_cumulative + current))
    else
        local diff=$((current - baseline))
        cumulative=$((last_cumulative + diff))
    fi

    echo "${cumulative}"
}

# Function to get cumulative traffic with detailed rx/tx breakdown
# Output format: "cumulative_rx cumulative_tx"
get_cumulative_traffic_detailed() {
    local baselines=$(get_baseline_detailed)
    local rx_baseline=$(echo "${baselines}" | awk '{print $1}')
    local tx_baseline=$(echo "${baselines}" | awk '{print $2}')

    local current=$(get_current_traffic_detailed "${NETWORK_INTERFACE}")
    local rx_current=$(echo "${current}" | awk '{print $1}')
    local tx_current=$(echo "${current}" | awk '{print $2}')

    # Get last cumulative values from database
    local last_line=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep -v "RESET" | tail -1)
    local last_cumulative_rx=$(echo "${last_line}" | cut -d'|' -f6 2>/dev/null || echo "0")
    local last_cumulative_tx=$(echo "${last_line}" | cut -d'|' -f7 2>/dev/null || echo "0")

    # Validate numbers
    if ! [[ "${last_cumulative_rx}" =~ ^[0-9]+$ ]]; then
        last_cumulative_rx=0
    fi
    if ! [[ "${last_cumulative_tx}" =~ ^[0-9]+$ ]]; then
        last_cumulative_tx=0
    fi

    local cumulative_rx=0
    local cumulative_tx=0

    # If current < baseline, interface was reset (server reboot)
    # Calculate for rx
    if [ "${rx_current}" -lt "${rx_baseline}" ] 2>/dev/null; then
        cumulative_rx=$((last_cumulative_rx + rx_current))
    else
        local diff_rx=$((rx_current - rx_baseline))
        cumulative_rx=$((last_cumulative_rx + diff_rx))
    fi

    # Calculate for tx
    if [ "${tx_current}" -lt "${tx_baseline}" ] 2>/dev/null; then
        cumulative_tx=$((last_cumulative_tx + tx_current))
    else
        local diff_tx=$((tx_current - tx_baseline))
        cumulative_tx=$((last_cumulative_tx + diff_tx))
    fi

    echo "${cumulative_rx} ${cumulative_tx}"
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

# Function to get today's traffic with detailed rx/tx breakdown
# Output format: "daily_rx daily_tx"
get_daily_traffic_detailed() {
    local today=$(date +%Y-%m-%d)
    local current_cumulative=$(get_cumulative_traffic_detailed)
    local current_cumulative_rx=$(echo "${current_cumulative}" | awk '{print $1}')
    local current_cumulative_tx=$(echo "${current_cumulative}" | awk '{print $2}')

    # Find today's starting cumulative (first entry of today, or last entry of yesterday)
    local today_start_cumulative_rx=0
    local today_start_cumulative_tx=0

    # Check if there's any entry for today already
    local today_first_entry=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep "^${today}|" | head -1)

    if [ -n "${today_first_entry}" ]; then
        # Today has entries, get the cumulative from yesterday's last entry
        local yesterday=$(date -d "${today} -1 day" +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
        local yesterday_last=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep "^${yesterday}|" | tail -1)

        if [ -n "${yesterday_last}" ]; then
            today_start_cumulative_rx=$(echo "${yesterday_last}" | cut -d'|' -f6 2>/dev/null || echo "0")
            today_start_cumulative_tx=$(echo "${yesterday_last}" | cut -d'|' -f7 2>/dev/null || echo "0")
        else
            # No yesterday entry, use the last non-today entry
            local last_non_today=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep -v "^${today}|" | grep -v "RESET" | tail -1)
            today_start_cumulative_rx=$(echo "${last_non_today}" | cut -d'|' -f6 2>/dev/null || echo "0")
            today_start_cumulative_tx=$(echo "${last_non_today}" | cut -d'|' -f7 2>/dev/null || echo "0")
        fi
    else
        # No entry for today yet, use last entry's cumulative as starting point
        local last_entry=$(grep -v "^#" "${TRAFFIC_DATA_FILE}" | grep -v "RESET" | tail -1)
        today_start_cumulative_rx=$(echo "${last_entry}" | cut -d'|' -f6 2>/dev/null || echo "0")
        today_start_cumulative_tx=$(echo "${last_entry}" | cut -d'|' -f7 2>/dev/null || echo "0")
    fi

    # Validate numbers
    if ! [[ "${today_start_cumulative_rx}" =~ ^[0-9]+$ ]]; then
        today_start_cumulative_rx=0
    fi
    if ! [[ "${today_start_cumulative_tx}" =~ ^[0-9]+$ ]]; then
        today_start_cumulative_tx=0
    fi

    # Calculate today's usage
    local daily_rx=$((current_cumulative_rx - today_start_cumulative_rx))
    local daily_tx=$((current_cumulative_tx - today_start_cumulative_tx))

    # If daily is negative, something is wrong (reset, etc.)
    if [ "${daily_rx}" -lt 0 ] 2>/dev/null; then
        daily_rx=0
    fi
    if [ "${daily_tx}" -lt 0 ] 2>/dev/null; then
        daily_tx=0
    fi

    echo "${daily_rx} ${daily_tx}"
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
    local bar_length=8
    local filled=$(awk "BEGIN {printf \"%.0f\", (${percentage}/100)*${bar_length}}")
    local empty=$((bar_length - filled))

    local bar=""
    # Filled squares with green color
    for ((i=0; i<filled; i++)); do
        bar="${bar}🟩"
    done
    # Empty squares with white color
    for ((i=0; i<empty; i++)); do
        bar="${bar}⬜"
    done

    echo "${bar}"
}

# Function to get days since reset
get_days_since_reset() {
    # Get the reset date from database
    local reset_date=$(grep "RESET|" "${TRAFFIC_DATA_FILE}" 2>/dev/null | tail -1 | cut -d'|' -f2 || echo "")

    if [ -z "${reset_date}" ]; then
        echo "1"  # Default to 1 if no reset date found
        return
    fi

    # Calculate days between reset date and today
    local today=$(date +%Y-%m-%d)
    local reset_timestamp=$(date -d "${reset_date}" +%s 2>/dev/null || echo "0")
    local today_timestamp=$(date -d "${today}" +%s 2>/dev/null || echo "0")

    if [ "${reset_timestamp}" -eq 0 ] || [ "${today_timestamp}" -eq 0 ]; then
        echo "1"
        return
    fi

    local days_diff=$(( (today_timestamp - reset_timestamp) / 86400 ))

    # Add 1 to convert from "days elapsed" to "day number"
    # Reset day = Day 1, next day = Day 2, etc.
    local day_number=$((days_diff + 1))

    # Return at least 1
    if [ "${day_number}" -lt 1 ]; then
        echo "1"
    else
        echo "${day_number}"
    fi
}

# Function to get daily average traffic in bytes
get_daily_average() {
    local cumulative_bytes=$1
    local days_since_reset=$(get_days_since_reset)

    # Calculate average (avoid division by zero)
    if [ "${days_since_reset}" -lt 1 ]; then
        days_since_reset=1
    fi

    local average=$(awk "BEGIN {printf \"%.0f\", ${cumulative_bytes}/${days_since_reset}}")
    echo "${average}"
}

# Function to determine traffic status
# Returns: status_code|status_text|status_emoji
get_traffic_status() {
    local daily_bytes=$1
    local average_bytes=$2

    # Avoid division by zero
    if [ "${average_bytes}" -eq 0 ] || [ "${daily_bytes}" -eq 0 ]; then
        echo "normal|Normal|✅"
        return
    fi

    # Calculate ratio: daily / average
    local ratio=$(awk "BEGIN {printf \"%.2f\", ${daily_bytes}/${average_bytes}}")

    # Determine status based on ratio
    if (( $(echo "${ratio} >= 3.0" | bc -l) )); then
        echo "critical|Critical|🔴"
    elif (( $(echo "${ratio} >= 2.0" | bc -l) )); then
        echo "high|High|⚠️"
    elif (( $(echo "${ratio} < 0.5" | bc -l) )); then
        echo "low|Low|🟢"
    else
        echo "normal|Normal|✅"
    fi
}

# Function to send daily report
send_daily_report() {
    local daily_bytes=$(get_daily_traffic)
    local cumulative_bytes=$(get_cumulative_traffic)

    # Get detailed traffic data (rx/tx breakdown)
    local daily_detailed=$(get_daily_traffic_detailed)
    local daily_rx=$(echo "${daily_detailed}" | awk '{print $1}')
    local daily_tx=$(echo "${daily_detailed}" | awk '{print $2}')

    local cumulative_detailed=$(get_cumulative_traffic_detailed)
    local cumulative_rx=$(echo "${cumulative_detailed}" | awk '{print $1}')
    local cumulative_tx=$(echo "${cumulative_detailed}" | awk '{print $2}')

    # Convert to GB
    local daily_gb=$(bytes_to_gb ${daily_bytes})
    local cumulative_gb=$(bytes_to_gb ${cumulative_bytes})
    local daily_rx_gb=$(bytes_to_gb ${daily_rx})
    local daily_tx_gb=$(bytes_to_gb ${daily_tx})
    local cumulative_rx_gb=$(bytes_to_gb ${cumulative_rx})
    local cumulative_tx_gb=$(bytes_to_gb ${cumulative_tx})
    local limit_gb=${MONTHLY_TRAFFIC_LIMIT}

    # Calculate percentage
    local percentage=$(calculate_percentage ${cumulative_gb} ${limit_gb})

    # Get progress bar
    local progress_bar=$(get_progress_bar ${percentage})

    # Calculate daily average and traffic status
    local average_bytes=$(get_daily_average ${cumulative_bytes})
    local average_gb=$(bytes_to_gb ${average_bytes})
    local days_since_reset=$(get_days_since_reset)

    # Get traffic status (format: status_code|status_text|status_emoji)
    local status_info=$(get_traffic_status ${daily_bytes} ${average_bytes})
    local status_code=$(echo "${status_info}" | cut -d'|' -f1)
    local status_text=$(echo "${status_info}" | cut -d'|' -f2)
    local status_emoji=$(echo "${status_info}" | cut -d'|' -f3)

    # Calculate ratio for display
    local ratio="N/A"
    local comparison_text="N/A"
    if [ "${average_bytes}" -gt 0 ] 2>/dev/null; then
        ratio=$(awk "BEGIN {printf \"%.2f\", ${daily_bytes}/${average_bytes}}")

        # Generate user-friendly comparison text
        if (( $(echo "${ratio} >= 1.5" | bc -l) )); then
            local percent=$(awk "BEGIN {printf \"%.0f\", (${ratio}-1)*100}")
            comparison_text="${percent}% above average"
        elif (( $(echo "${ratio} >= 1.1" | bc -l) )); then
            comparison_text="slightly above average"
        elif (( $(echo "${ratio} <= 0.5" | bc -l) )); then
            local percent=$(awk "BEGIN {printf \"%.0f\", (1-${ratio})*100}")
            comparison_text="${percent}% below average"
        elif (( $(echo "${ratio} <= 0.9" | bc -l) )); then
            comparison_text="slightly below average"
        else
            comparison_text="normal"
        fi
    fi

    # Get billing cycle info
    local current_day=$(date +%d)
    local reset_day=$(printf "%02d" ${TRAFFIC_RESET_DAY})
    local current_month=$(date +%Y-%m)

    # Calculate days until reset
    local days_in_month=$(date -d "${current_month}-01 +1 month -1 day" +%d)
    local days_until_reset=0

    if [ "$((10#${current_day}))" -lt "$((10#${TRAFFIC_RESET_DAY}))" ] 2>/dev/null; then
        # Days remaining = reset_day - current_day - 1
        # The -1 is because the reset day itself is not included in current cycle
        # Example: today is 8th, reset on 15th → remaining days = 15 - 8 - 1 = 6 (9th to 14th)
        days_until_reset=$((10#${TRAFFIC_RESET_DAY} - 10#${current_day} - 1))
    else
        # Calculate days until next month's reset date
        local next_month=$(date -d "${current_month}-01 +1 month" +%Y-%m)
        local next_reset_date="${next_month}-${reset_day}"
        local today_date=$(date +%Y-%m-%d)

        # Use today's 00:00 timestamp for stable calculation
        # Subtract 1 because reset day is not included in current cycle
        days_until_reset=$(( ($(date -d "${next_reset_date}" +%s) - $(date -d "${today_date}" +%s)) / 86400 - 1 ))
    fi

    # Determine cycle status emoji
    local cycle_status_emoji="✅"
    if (( $(echo "${percentage} >= 90" | bc -l) )); then
        cycle_status_emoji="🔴"
    elif (( $(echo "${percentage} >= 75" | bc -l) )); then
        cycle_status_emoji="🟡"
    elif (( $(echo "${percentage} >= 50" | bc -l) )); then
        cycle_status_emoji="🟠"
    fi

    # Build message
    local message="📊 *Daily Traffic Report*\n🖥️ ${SERVER_NAME}\n\n"
    message="${message}📈 *Today's Usage*\n"
    message="${message}Used: ${daily_gb} GB\n"

    # Add detailed upload/download breakdown based on TRAFFIC_DIRECTION
    case "${TRAFFIC_DIRECTION:-1}" in
        1)
            # Bidirectional - show both upload and download
            message="${message}  ⬇️ ${daily_rx_gb} GB\n"
            message="${message}  ⬆️ ${daily_tx_gb} GB\n"
            ;;
        2)
            # Outbound only (upload/tx)
            message="${message}  ⬆️ ${daily_tx_gb} GB\n"
            ;;
        3)
            # Inbound only (download/rx)
            message="${message}  ⬇️ ${daily_rx_gb} GB\n"
            ;;
    esac

    message="${message}Average: ${average_gb} GB\n"
    message="${message}Status: ${ratio}x avg ${status_emoji} ${status_text}\n\n"
    message="${message}📅 *Cycle Total*\n"
    message="${message}Used: ${cumulative_gb} GB\n"

    # Add detailed upload/download breakdown for billing cycle
    case "${TRAFFIC_DIRECTION:-1}" in
        1)
            # Bidirectional - show both upload and download
            message="${message}  ⬇️ ${cumulative_rx_gb} GB\n"
            message="${message}  ⬆️ ${cumulative_tx_gb} GB\n"
            ;;
        2)
            # Outbound only (upload/tx)
            message="${message}  ⬆️ ${cumulative_tx_gb} GB\n"
            ;;
        3)
            # Inbound only (download/rx)
            message="${message}  ⬇️ ${cumulative_rx_gb} GB\n"
            ;;
    esac

    message="${message}Limit: ${limit_gb} GB\n"
    message="${message}${progress_bar} ${percentage}%\n\n"
    message="${message}🔄 *Cycle Info*\n"
    message="${message}Days: ${days_since_reset} / $((days_since_reset + days_until_reset)) (${days_until_reset} remaining)\n"
    message="${message}Resets: ${reset_day}th of each month"

    # Add warning if daily usage is critical
    if [ "${status_code}" == "critical" ]; then
        message="${message}\n\n⚠️ *WARNING:* Today's traffic is abnormally high!"
    elif [ "${status_code}" == "high" ]; then
        message="${message}\n\n💡 *NOTICE:* Today's traffic is higher than usual."
    fi

    # Add warning if cycle usage is high
    if (( $(echo "${percentage} >= 90" | bc -l) )); then
        message="${message}\n⚠️ *WARNING:* Monthly traffic approaching limit!"
    fi

    # Send notification
    "${SCRIPT_DIR}/telegram_notify.sh" "📊 Daily Traffic Report" "${message}"

    # Record today's data
    local today=$(date +%Y-%m-%d)
    local current_traffic=$(get_current_traffic_detailed "${NETWORK_INTERFACE}")
    local baseline_rx=$(echo "${current_traffic}" | awk '{print $1}')
    local baseline_tx=$(echo "${current_traffic}" | awk '{print $2}')
    echo "${today}|${daily_bytes}|${cumulative_bytes}|${daily_rx}|${daily_tx}|${cumulative_rx}|${cumulative_tx}|baseline_rx=${baseline_rx}|baseline_tx=${baseline_tx}" >> "${TRAFFIC_DATA_FILE}"
}

# Function to show interactive menu
show_menu() {
    echo ""
    echo "=========================================="
    echo "   📊 Traffic Monitor - Control Panel"
    echo "=========================================="
    echo ""
    echo "1) 📈 Send Daily Report (Normal Run)"
    echo "2) 🔄 Manual Reset Database"
    echo "3) 📊 View Current Statistics"
    echo "4) 📁 Show Database Content"
    echo "5) 🔍 Test Configuration"
    echo "0) ❌ Exit"
    echo ""
    echo "=========================================="
    echo -n "Please select an option [0-5]: "
}

# Function to view current statistics
view_statistics() {
    echo ""
    echo "=========================================="
    echo "   📊 Current Traffic Statistics"
    echo "=========================================="
    echo ""

    # Initialize database if needed
    init_traffic_db

    local daily_bytes=$(get_daily_traffic)
    local cumulative_bytes=$(get_cumulative_traffic)

    local daily_detailed=$(get_daily_traffic_detailed)
    local daily_rx=$(echo "${daily_detailed}" | awk '{print $1}')
    local daily_tx=$(echo "${daily_detailed}" | awk '{print $2}')

    local cumulative_detailed=$(get_cumulative_traffic_detailed)
    local cumulative_rx=$(echo "${cumulative_detailed}" | awk '{print $1}')
    local cumulative_tx=$(echo "${cumulative_detailed}" | awk '{print $2}')

    local daily_gb=$(bytes_to_gb ${daily_bytes})
    local cumulative_gb=$(bytes_to_gb ${cumulative_bytes})
    local daily_rx_gb=$(bytes_to_gb ${daily_rx})
    local daily_tx_gb=$(bytes_to_gb ${daily_tx})
    local cumulative_rx_gb=$(bytes_to_gb ${cumulative_rx})
    local cumulative_tx_gb=$(bytes_to_gb ${cumulative_tx})

    local percentage=$(calculate_percentage ${cumulative_gb} ${MONTHLY_TRAFFIC_LIMIT})
    local progress_bar=$(get_progress_bar ${percentage})

    echo "📈 Today's Usage:"
    echo "   Total: ${daily_gb} GB"
    echo "   ⬇️ ${daily_rx_gb} GB"
    echo "   ⬆️ ${daily_tx_gb} GB"
    echo ""
    echo "📅 Cycle Total:"
    echo "   Used: ${cumulative_gb} GB (${percentage}%)"
    echo "   ⬇️ ${cumulative_rx_gb} GB"
    echo "   ⬆️ ${cumulative_tx_gb} GB"
    echo "   Limit: ${MONTHLY_TRAFFIC_LIMIT} GB"
    echo "   ${progress_bar}"
    echo ""
    echo "=========================================="
    echo ""
}

# Function to show database content
show_database() {
    echo ""
    echo "=========================================="
    echo "   📁 Database Content"
    echo "=========================================="
    echo ""

    if [ -f "${TRAFFIC_DATA_FILE}" ]; then
        echo "File: ${TRAFFIC_DATA_FILE}"
        echo "Size: $(ls -lh ${TRAFFIC_DATA_FILE} | awk '{print $5}')"
        echo ""
        echo "Content (last 10 lines):"
        echo "------------------------------------------"
        tail -10 "${TRAFFIC_DATA_FILE}"
        echo "------------------------------------------"
    else
        echo "❌ Database file not found: ${TRAFFIC_DATA_FILE}"
    fi
    echo ""
    echo "=========================================="
    echo ""
}

# Function to test configuration
test_configuration() {
    echo ""
    echo "=========================================="
    echo "   🔍 Configuration Test"
    echo "=========================================="
    echo ""

    echo "✓ Checking configuration..."
    echo "  Server Name: ${SERVER_NAME}"
    echo "  Network Interface: ${NETWORK_INTERFACE}"
    echo "  Traffic Direction: ${TRAFFIC_DIRECTION} (1=Both, 2=Upload, 3=Download)"
    echo "  Monthly Limit: ${MONTHLY_TRAFFIC_LIMIT} GB"
    echo "  Reset Day: ${TRAFFIC_RESET_DAY}"
    echo ""

    echo "✓ Checking network interface..."
    if [ -d "/sys/class/net/${NETWORK_INTERFACE}" ]; then
        echo "  ✅ Interface ${NETWORK_INTERFACE} exists"
        local current=$(get_current_traffic_detailed "${NETWORK_INTERFACE}")
        local rx=$(echo "${current}" | awk '{print $1}')
        local tx=$(echo "${current}" | awk '{print $2}')
        echo "  Current RX: $(bytes_to_gb ${rx}) GB"
        echo "  Current TX: $(bytes_to_gb ${tx}) GB"
    else
        echo "  ❌ Interface ${NETWORK_INTERFACE} not found!"
        echo "  Available interfaces:"
        ls /sys/class/net/ | sed 's/^/    - /'
    fi
    echo ""

    echo "✓ Checking Telegram configuration..."
    if [ -n "${BOT_TOKEN}" ] && [ -n "${CHAT_ID}" ]; then
        echo "  ✅ Bot Token: ${BOT_TOKEN:0:10}...${BOT_TOKEN: -5}"
        echo "  ✅ Chat ID: ${CHAT_ID}"
    else
        echo "  ❌ Telegram Bot Token or Chat ID not configured!"
    fi
    echo ""

    echo "✓ Checking database..."
    if [ -f "${TRAFFIC_DATA_FILE}" ]; then
        echo "  ✅ Database exists: ${TRAFFIC_DATA_FILE}"
        local last_line=$(tail -1 "${TRAFFIC_DATA_FILE}")
        if echo "${last_line}" | grep -q "baseline_rx="; then
            echo "  ✅ Using new detailed format (with RX/TX breakdown)"
        else
            echo "  ⚠️  Using old format (consider resetting for detailed stats)"
        fi
    else
        echo "  ⚠️  Database not initialized (will be created on first run)"
    fi
    echo ""

    echo "=========================================="
    echo ""
}

# Function to manually reset database with confirmation
manual_reset_database() {
    echo ""
    echo "=========================================="
    echo "   🔄 Manual Database Reset"
    echo "=========================================="
    echo ""
    echo "⚠️  WARNING: This will:"
    echo "   • Backup current database"
    echo "   • Delete all traffic history"
    echo "   • Reset cumulative traffic to 0"
    echo "   • Initialize new database with detailed format"
    echo ""

    if [ -f "${TRAFFIC_DATA_FILE}" ]; then
        echo "Current database info:"
        echo "  File: ${TRAFFIC_DATA_FILE}"
        echo "  Size: $(ls -lh ${TRAFFIC_DATA_FILE} | awk '{print $5}')"
        echo "  Lines: $(wc -l < ${TRAFFIC_DATA_FILE})"
        echo ""
    fi

    echo -n "Are you sure you want to reset? (yes/no): "
    read confirmation

    if [ "${confirmation}" != "yes" ]; then
        echo ""
        echo "❌ Reset cancelled."
        echo ""
        return
    fi

    echo ""
    echo "🔄 Resetting database..."

    # Backup old database
    if [ -f "${TRAFFIC_DATA_FILE}" ]; then
        local backup_file="${TRAFFIC_DATA_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "${TRAFFIC_DATA_FILE}" "${backup_file}"
        echo "✓ Backup created: ${backup_file}"
    fi

    # Delete old database
    rm -f "${TRAFFIC_DATA_FILE}"
    echo "✓ Old database deleted"

    # Initialize new database
    init_traffic_db
    echo "✓ New database initialized with detailed format"

    echo ""
    echo "✅ Database reset complete!"
    echo ""
    echo "New database content:"
    echo "------------------------------------------"
    cat "${TRAFFIC_DATA_FILE}"
    echo "------------------------------------------"
    echo ""

    # Send notification
    local message="🔄 *Manual Database Reset*\n\n"
    message="${message}Database has been manually reset by administrator.\n\n"
    message="${message}Reset date: $(date +%Y-%m-%d)\n"
    message="${message}Monthly limit: ${MONTHLY_TRAFFIC_LIMIT} GB\n"
    message="${message}Format: Detailed with RX/TX breakdown"

    "${SCRIPT_DIR}/telegram_notify.sh" "🔄 Database Reset" "${message}"
    echo "✓ Notification sent to Telegram"
    echo ""
}

# Main function
main() {
    local mode="${1:-menu}"

    # If running from cron (with "daily" argument), skip menu
    if [ "${mode}" = "daily" ] || [ "${mode}" = "auto" ]; then
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
        return
    fi

    # Interactive menu mode
    while true; do
        show_menu
        read choice

        case "${choice}" in
            1)
                echo ""
                echo "📈 Sending daily report..."
                init_traffic_db

                if need_reset; then
                    echo "⚠️  New billing cycle detected. Resetting traffic counter..."
                    reset_traffic

                    local message="🔄 *Traffic Counter Reset*\n\n"
                    message="${message}New billing cycle started on $(date +%Y-%m-%d)\n\n"
                    message="${message}Monthly limit: ${MONTHLY_TRAFFIC_LIMIT} GB\n"
                    message="${message}Reset day: ${TRAFFIC_RESET_DAY} of each month"

                    "${SCRIPT_DIR}/telegram_notify.sh" "🔄 Billing Cycle Reset" "${message}"
                fi

                send_daily_report
                date +%s > "${LAST_RUN_FILE}"

                echo ""
                echo "✅ Daily report sent successfully!"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                manual_reset_database
                read -p "Press Enter to continue..."
                ;;
            3)
                view_statistics
                read -p "Press Enter to continue..."
                ;;
            4)
                show_database
                read -p "Press Enter to continue..."
                ;;
            5)
                test_configuration
                read -p "Press Enter to continue..."
                ;;
            0)
                echo ""
                echo "👋 Goodbye!"
                echo ""
                exit 0
                ;;
            *)
                echo ""
                echo "❌ Invalid option. Please select 0-5."
                echo ""
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Run main function
main "$@"
