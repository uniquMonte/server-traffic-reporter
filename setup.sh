#!/bin/bash

# VPS Traffic Reporter - Setup and Management Script
# Author: GitHub @uniquMonte
# Description: Daily VPS traffic monitoring and reporting via Telegram

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
DATA_DIR="${SCRIPT_DIR}/data"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
TRAFFIC_DATA_FILE="${DATA_DIR}/traffic.db"

# Create necessary directories
mkdir -p "${CONFIG_DIR}" "${DATA_DIR}" "${SCRIPTS_DIR}"

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to load configuration
load_config() {
    if [ -f "${CONFIG_FILE}" ]; then
        source "${CONFIG_FILE}"
        return 0
    else
        return 1
    fi
}

# Function to display current configuration
view_configuration() {
    clear
    echo "======================================"
    echo "  Current Configuration"
    echo "======================================"
    echo ""

    if load_config; then
        echo "Server Name: ${SERVER_NAME:-Not set}"
        echo "Telegram Bot Token: ${TELEGRAM_BOT_TOKEN:0:10}...${TELEGRAM_BOT_TOKEN: -5}"
        echo "Telegram Chat ID: ${TELEGRAM_CHAT_ID:-Not set}"
        echo "Traffic Reset Day: ${TRAFFIC_RESET_DAY:-Not set} (Day of month)"
        echo "Monthly Traffic Limit: ${MONTHLY_TRAFFIC_LIMIT:-Not set} GB"
        echo "Report Time: ${REPORT_TIME:-Not set} (HH:MM format)"
        echo "Network Interface: ${NETWORK_INTERFACE:-Not set}"
        echo ""

        if [ -n "${CRON_INSTALLED}" ] && [ "${CRON_INSTALLED}" == "yes" ]; then
            print_success "Cron job is installed and active"
        else
            print_warning "Cron job is not installed"
        fi
    else
        print_warning "No configuration found. Please update configuration first."
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Function to detect network interface
detect_network_interface() {
    local interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | head -1)
    echo "${interfaces}"
}

# Function to update configuration
update_configuration() {
    clear
    echo "======================================"
    echo "  Update Configuration"
    echo "======================================"
    echo ""

    # Load existing config if available
    load_config 2>/dev/null || true

    # Server Name
    read -p "Enter server name [${SERVER_NAME:-MyVPS}]: " input
    SERVER_NAME="${input:-${SERVER_NAME:-MyVPS}}"

    # Telegram Bot Token
    echo ""
    print_info "To create a Telegram bot, talk to @BotFather on Telegram"
    read -p "Enter Telegram Bot Token [${TELEGRAM_BOT_TOKEN}]: " input
    TELEGRAM_BOT_TOKEN="${input:-${TELEGRAM_BOT_TOKEN}}"

    # Telegram Chat ID
    echo ""
    print_info "To get your Chat ID, talk to @userinfobot on Telegram"
    read -p "Enter Telegram Chat ID [${TELEGRAM_CHAT_ID}]: " input
    TELEGRAM_CHAT_ID="${input:-${TELEGRAM_CHAT_ID}}"

    # Traffic Reset Day
    echo ""
    read -p "Enter traffic reset day (1-31) [${TRAFFIC_RESET_DAY:-3}]: " input
    TRAFFIC_RESET_DAY="${input:-${TRAFFIC_RESET_DAY:-3}}"

    # Monthly Traffic Limit
    echo ""
    read -p "Enter monthly traffic limit in GB [${MONTHLY_TRAFFIC_LIMIT:-500}]: " input
    MONTHLY_TRAFFIC_LIMIT="${input:-${MONTHLY_TRAFFIC_LIMIT:-500}}"

    # Report Time
    echo ""
    read -p "Enter daily report time (HH:MM format, 24h) [${REPORT_TIME:-09:00}]: " input
    REPORT_TIME="${input:-${REPORT_TIME:-09:00}}"

    # Network Interface
    echo ""
    local default_interface=$(detect_network_interface)
    read -p "Enter network interface [${NETWORK_INTERFACE:-${default_interface}}]: " input
    NETWORK_INTERFACE="${input:-${NETWORK_INTERFACE:-${default_interface}}}"

    # Save configuration
    cat > "${CONFIG_FILE}" << EOF
# VPS Traffic Reporter Configuration
# Generated on $(date)

SERVER_NAME="${SERVER_NAME}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
TRAFFIC_RESET_DAY=${TRAFFIC_RESET_DAY}
MONTHLY_TRAFFIC_LIMIT=${MONTHLY_TRAFFIC_LIMIT}
REPORT_TIME="${REPORT_TIME}"
NETWORK_INTERFACE="${NETWORK_INTERFACE}"
CRON_INSTALLED="no"
EOF

    print_success "Configuration saved successfully!"
    echo ""

    # Ask to install cron job
    read -p "Do you want to install the cron job for automatic daily reports? (y/n): " install_cron
    if [[ "${install_cron}" =~ ^[Yy]$ ]]; then
        install_cron_job
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Function to install cron job
install_cron_job() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        print_error "Configuration not found. Please update configuration first."
        return 1
    fi

    load_config

    # Extract hour and minute from REPORT_TIME
    local hour=$(echo "${REPORT_TIME}" | cut -d':' -f1)
    local minute=$(echo "${REPORT_TIME}" | cut -d':' -f2)

    # Remove old cron job if exists
    (crontab -l 2>/dev/null | grep -v "traffic_monitor.sh") | crontab - 2>/dev/null || true

    # Add new cron job
    (crontab -l 2>/dev/null; echo "${minute} ${hour} * * * ${SCRIPTS_DIR}/traffic_monitor.sh daily >> ${DATA_DIR}/cron.log 2>&1") | crontab -

    # Update config to mark cron as installed
    sed -i 's/CRON_INSTALLED="no"/CRON_INSTALLED="yes"/' "${CONFIG_FILE}"

    print_success "Cron job installed! Daily report will run at ${REPORT_TIME}"
}

# Function to uninstall cron job
uninstall_cron_job() {
    (crontab -l 2>/dev/null | grep -v "traffic_monitor.sh") | crontab - 2>/dev/null || true
    print_success "Cron job removed"
}

# Function to update scripts
update_scripts() {
    clear
    echo "======================================"
    echo "  Update Scripts"
    echo "======================================"
    echo ""

    print_info "Checking for updates..."

    if [ -d "${SCRIPT_DIR}/.git" ]; then
        cd "${SCRIPT_DIR}"
        git fetch origin

        local LOCAL=$(git rev-parse @)
        local REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")

        if [ -z "${REMOTE}" ]; then
            print_warning "Cannot check for updates. No upstream branch set."
        elif [ "${LOCAL}" = "${REMOTE}" ]; then
            print_success "Already up to date!"
        else
            print_info "Updates available. Pulling changes..."
            git pull origin $(git rev-parse --abbrev-ref HEAD)
            print_success "Scripts updated successfully!"
        fi
    else
        print_warning "Not a git repository. Cannot auto-update."
        print_info "Please download the latest version manually from GitHub."
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Function to test notification
test_notification() {
    clear
    echo "======================================"
    echo "  Test Telegram Notification"
    echo "======================================"
    echo ""

    if [ ! -f "${CONFIG_FILE}" ]; then
        print_error "Configuration not found. Please update configuration first."
        read -p "Press Enter to continue..."
        return 1
    fi

    load_config

    print_info "Sending test notification to Telegram..."

    "${SCRIPTS_DIR}/telegram_notify.sh" "🧪 Test Notification" "This is a test message from VPS Traffic Reporter on *${SERVER_NAME}*.\n\nIf you see this message, your configuration is working correctly! ✅"

    if [ $? -eq 0 ]; then
        print_success "Test notification sent successfully!"
    else
        print_error "Failed to send test notification. Please check your configuration."
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Function to run traffic report now
run_report_now() {
    clear
    echo "======================================"
    echo "  Run Traffic Report"
    echo "======================================"
    echo ""

    if [ ! -f "${CONFIG_FILE}" ]; then
        print_error "Configuration not found. Please update configuration first."
        read -p "Press Enter to continue..."
        return 1
    fi

    print_info "Generating traffic report..."

    "${SCRIPTS_DIR}/traffic_monitor.sh" daily

    if [ $? -eq 0 ]; then
        print_success "Report generated and sent successfully!"
    else
        print_error "Failed to generate report. Check logs for details."
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Function to uninstall
uninstall() {
    clear
    echo "======================================"
    echo "  Uninstall VPS Traffic Reporter"
    echo "======================================"
    echo ""

    print_warning "This will remove all cron jobs and data files."
    read -p "Are you sure you want to uninstall? (yes/no): " confirm

    if [ "${confirm}" != "yes" ]; then
        print_info "Uninstall cancelled."
        read -p "Press Enter to continue..."
        return 0
    fi

    # Remove cron job
    uninstall_cron_job

    # Ask if user wants to delete data
    read -p "Do you want to delete all data files? (y/n): " delete_data
    if [[ "${delete_data}" =~ ^[Yy]$ ]]; then
        rm -rf "${CONFIG_DIR}" "${DATA_DIR}"
        print_success "Data files removed"
    fi

    print_success "Uninstall completed!"
    echo ""
    print_info "To completely remove the program, delete this directory:"
    echo "  rm -rf ${SCRIPT_DIR}"
    echo ""
    read -p "Press Enter to exit..."
    exit 0
}

# Function to display main menu
show_menu() {
    clear
    echo "======================================"
    echo "  VPS Traffic Reporter"
    echo "======================================"
    echo ""
    echo "1) View current configuration"
    echo "2) Update configuration"
    echo "3) Update scripts to latest version"
    echo "4) Test notification"
    echo "5) Run traffic report now"
    echo "6) Uninstall"
    echo "0) Exit (or just press Enter)"
    echo ""
    read -p "Select an option: " choice
    echo ""
}

# Main loop
main() {
    # Check if scripts exist, if not, this is first run
    if [ ! -f "${SCRIPTS_DIR}/traffic_monitor.sh" ]; then
        clear
        echo "======================================"
        echo "  Welcome to VPS Traffic Reporter"
        echo "======================================"
        echo ""
        print_info "First time setup detected."
        print_info "Initializing..."
        echo ""

        # The actual script files should exist in the repository
        if [ ! -f "${SCRIPTS_DIR}/traffic_monitor.sh" ]; then
            print_error "Required script files not found!"
            print_error "Please ensure all files are properly installed."
            exit 1
        fi
    fi

    while true; do
        show_menu

        case "${choice}" in
            1)
                view_configuration
                ;;
            2)
                update_configuration
                ;;
            3)
                update_scripts
                ;;
            4)
                test_notification
                ;;
            5)
                run_report_now
                ;;
            6)
                uninstall
                ;;
            0|"")
                clear
                print_success "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# Make sure we're not running as root is preferred, but allow it
if [ "$EUID" -eq 0 ]; then
    print_warning "Running as root. This is not recommended but will continue."
fi

# Run main function
main
