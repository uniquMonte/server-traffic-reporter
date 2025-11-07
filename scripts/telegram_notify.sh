#!/bin/bash

# Telegram Notification Script
# Sends messages to Telegram using Bot API

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_DIR="${PROJECT_DIR}/config"
CONFIG_FILE="${CONFIG_DIR}/config.conf"

# Load configuration
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Error: Configuration file not found at ${CONFIG_FILE}"
    exit 1
fi

source "${CONFIG_FILE}"

# Check if required variables are set
if [ -z "${TELEGRAM_BOT_TOKEN}" ] || [ -z "${TELEGRAM_CHAT_ID}" ]; then
    echo "Error: Telegram configuration not complete"
    echo "Please run setup.sh and configure your Telegram settings"
    exit 1
fi

# Function to send message to Telegram
send_telegram_message() {
    local title="$1"
    local message="$2"

    # Combine title and message
    local full_message="${message}"

    # URL encode the message
    local encoded_message=$(echo -ne "${full_message}" | od -An -tx1 | tr ' ' % | tr -d '\n')

    # Telegram API URL
    local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

    # Send message using curl
    local response=$(curl -s -X POST "${api_url}" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${encoded_message}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true")

    # Check if message was sent successfully
    if echo "${response}" | grep -q '"ok":true'; then
        echo "Message sent successfully"
        return 0
    else
        echo "Failed to send message"
        echo "Response: ${response}"
        return 1
    fi
}

# Main
main() {
    local title="${1:-Notification}"
    local message="${2:-No message provided}"

    send_telegram_message "${title}" "${message}"
}

# Run main function
main "$@"
