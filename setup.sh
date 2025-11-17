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
    echo ""
    echo "======================================"
    echo "  Current Configuration"
    echo "======================================"
    echo ""

    if load_config; then
        # Determine traffic mode name
        local traffic_mode="Bidirectional"
        case "${TRAFFIC_DIRECTION:-1}" in
            1) traffic_mode="Bidirectional (both directions)" ;;
            2) traffic_mode="Outbound only (server to client)" ;;
            3) traffic_mode="Inbound only (client to server)" ;;
        esac

        # Determine report interval description
        local interval_desc
        case "${REPORT_INTERVAL:-24}" in
            1)  interval_desc="Every 1 hour (at :00 of each hour)" ;;
            2)  interval_desc="Every 2 hours (00:00, 02:00, 04:00...)" ;;
            3)  interval_desc="Every 3 hours (00:00, 03:00, 06:00...)" ;;
            4)  interval_desc="Every 4 hours (00:00, 04:00, 08:00...)" ;;
            6)  interval_desc="Every 6 hours (00:00, 06:00, 12:00, 18:00)" ;;
            8)  interval_desc="Every 8 hours (00:00, 08:00, 16:00)" ;;
            12) interval_desc="Every 12 hours (00:00, 12:00)" ;;
            24) interval_desc="Once per day at ${REPORT_TIME:-09:00}" ;;
            *)  interval_desc="Unknown interval" ;;
        esac

        echo "Server Name: ${SERVER_NAME:-Not set}"
        echo "Telegram Bot Token: ${TELEGRAM_BOT_TOKEN:0:10}...${TELEGRAM_BOT_TOKEN: -5}"
        echo "Telegram Chat ID: ${TELEGRAM_CHAT_ID:-Not set}"
        echo "Traffic Reset Day: ${TRAFFIC_RESET_DAY:-Not set} (Day of month)"
        echo "Monthly Traffic Limit: ${MONTHLY_TRAFFIC_LIMIT:-Not set} GB"
        echo "Report Interval: ${interval_desc}"
        echo "Network Interface: ${NETWORK_INTERFACE:-Not set}"
        echo "Traffic Mode: ${traffic_mode}"
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
    sleep 1
}

# Function to detect network interface
detect_network_interface() {
    local interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | head -1)
    echo "${interfaces}"
}

# Function to update configuration
update_configuration() {
    echo ""
    echo "======================================"
    echo "  Update Configuration"
    echo "======================================"
    echo ""

    # Load existing config if available
    load_config 2>/dev/null || true

    # Server Name
    # Use existing SERVER_NAME if available, otherwise use system hostname
    DEFAULT_SERVER_NAME="${SERVER_NAME:-$(hostname)}"
    read -p "Enter server name [${DEFAULT_SERVER_NAME}]: " input < /dev/tty
    SERVER_NAME="${input:-${DEFAULT_SERVER_NAME}}"

    # Telegram Bot Token
    echo ""
    print_info "To create a Telegram bot, talk to @BotFather on Telegram"
    read -p "Enter Telegram Bot Token [${TELEGRAM_BOT_TOKEN}]: " input < /dev/tty
    TELEGRAM_BOT_TOKEN="${input:-${TELEGRAM_BOT_TOKEN}}"

    # Telegram Chat ID
    echo ""
    print_info "To get your Chat ID, talk to @userinfobot on Telegram"
    read -p "Enter Telegram Chat ID [${TELEGRAM_CHAT_ID}]: " input < /dev/tty
    TELEGRAM_CHAT_ID="${input:-${TELEGRAM_CHAT_ID}}"

    # Traffic Reset Day
    echo ""
    read -p "Enter traffic reset day (1-31) [${TRAFFIC_RESET_DAY:-3}]: " input < /dev/tty
    TRAFFIC_RESET_DAY="${input:-${TRAFFIC_RESET_DAY:-3}}"

    # Monthly Traffic Limit
    echo ""
    read -p "Enter monthly traffic limit in GB [${MONTHLY_TRAFFIC_LIMIT:-500}]: " input < /dev/tty
    MONTHLY_TRAFFIC_LIMIT="${input:-${MONTHLY_TRAFFIC_LIMIT:-500}}"

    # Report Interval
    echo ""
    print_info "Select report sending interval:"
    echo "  1) Every 1 hour (at :00 of each hour)"
    echo "  2) Every 2 hours (00:00, 02:00, 04:00...)"
    echo "  3) Every 3 hours (00:00, 03:00, 06:00...)"
    echo "  4) Every 4 hours (00:00, 04:00, 08:00...)"
    echo "  6) Every 6 hours (00:00, 06:00, 12:00, 18:00)"
    echo "  8) Every 8 hours (00:00, 08:00, 16:00)"
    echo "  12) Every 12 hours (00:00, 12:00)"
    echo "  24) Once per day (at specific time)"
    read -p "Enter interval in hours (1/2/3/4/6/8/12/24) [${REPORT_INTERVAL:-24}]: " input < /dev/tty
    REPORT_INTERVAL="${input:-${REPORT_INTERVAL:-24}}"

    # Validate report interval
    if [[ ! "${REPORT_INTERVAL}" =~ ^(1|2|3|4|6|8|12|24)$ ]]; then
        print_warning "Invalid interval, using default (24 hours)"
        REPORT_INTERVAL=24
    fi

    # Report Time (only for 24-hour interval)
    if [ "${REPORT_INTERVAL}" = "24" ]; then
        echo ""
        read -p "Enter daily report time (HH:MM format, 24h) [${REPORT_TIME:-09:00}]: " input < /dev/tty
        REPORT_TIME="${input:-${REPORT_TIME:-09:00}}"
    else
        # For other intervals, set time to 00:00 (will use interval-based cron)
        REPORT_TIME="00:00"
        print_info "Reports will be sent every ${REPORT_INTERVAL} hour(s) at the top of the hour"
    fi

    # Network Interface
    echo ""
    local default_interface=$(detect_network_interface)
    read -p "Enter network interface [${NETWORK_INTERFACE:-${default_interface}}]: " input < /dev/tty
    NETWORK_INTERFACE="${input:-${NETWORK_INTERFACE:-${default_interface}}}"

    # Traffic Direction
    echo ""
    print_info "Traffic counting mode:"
    echo "  1) Bidirectional (both directions, RECOMMENDED)"
    echo "  2) Outbound only (server to client, download)"
    echo "  3) Inbound only (client to server, upload)"
    read -p "Select traffic mode (1/2/3) [1]: " input < /dev/tty
    TRAFFIC_DIRECTION="${input:-${TRAFFIC_DIRECTION:-1}}"

    # Validate traffic direction
    if [[ ! "${TRAFFIC_DIRECTION}" =~ ^[123]$ ]]; then
        print_warning "Invalid selection, using default (bidirectional)"
        TRAFFIC_DIRECTION=1
    fi

    # Save configuration
    cat > "${CONFIG_FILE}" << EOF
# VPS Traffic Reporter Configuration
# Generated on $(date)

SERVER_NAME="${SERVER_NAME}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
TRAFFIC_RESET_DAY=${TRAFFIC_RESET_DAY}
MONTHLY_TRAFFIC_LIMIT=${MONTHLY_TRAFFIC_LIMIT}
REPORT_INTERVAL=${REPORT_INTERVAL}
REPORT_TIME="${REPORT_TIME}"
NETWORK_INTERFACE="${NETWORK_INTERFACE}"
TRAFFIC_DIRECTION=${TRAFFIC_DIRECTION}
CRON_INSTALLED="no"
EOF

    print_success "Configuration saved successfully!"
    echo ""

    # Ask to install cron job
    read -p "Install cron job for automatic daily reports? (Y/n, press Enter for yes): " install_cron < /dev/tty

    # Default to yes if empty
    install_cron=${install_cron:-y}

    if [[ "${install_cron}" =~ ^[Yy]$ ]]; then
        install_cron_job
    fi

    echo ""
    sleep 1
}

# Function to install cron job
install_cron_job() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        print_error "Configuration not found. Please update configuration first."
        return 1
    fi

    load_config

    # Default interval to 24 hours if not set (for backward compatibility)
    REPORT_INTERVAL="${REPORT_INTERVAL:-24}"

    local cron_schedule
    local description

    # Generate cron schedule based on interval
    case "${REPORT_INTERVAL}" in
        1)
            cron_schedule="0 * * * *"
            description="every hour at :00"
            ;;
        2)
            cron_schedule="0 */2 * * *"
            description="every 2 hours at :00"
            ;;
        3)
            cron_schedule="0 */3 * * *"
            description="every 3 hours at :00"
            ;;
        4)
            cron_schedule="0 */4 * * *"
            description="every 4 hours at :00"
            ;;
        6)
            cron_schedule="0 */6 * * *"
            description="every 6 hours at :00"
            ;;
        8)
            cron_schedule="0 */8 * * *"
            description="every 8 hours at :00"
            ;;
        12)
            cron_schedule="0 */12 * * *"
            description="every 12 hours at :00"
            ;;
        24)
            # Extract hour and minute from REPORT_TIME
            local hour=$(echo "${REPORT_TIME}" | cut -d':' -f1)
            local minute=$(echo "${REPORT_TIME}" | cut -d':' -f2)
            cron_schedule="${minute} ${hour} * * *"
            description="daily at ${REPORT_TIME}"
            ;;
        *)
            print_error "Invalid report interval: ${REPORT_INTERVAL}"
            return 1
            ;;
    esac

    # Remove old cron job if exists
    (crontab -l 2>/dev/null | grep -v "traffic_monitor.sh") | crontab - 2>/dev/null || true

    # Add new cron job
    (crontab -l 2>/dev/null; echo "${cron_schedule} ${SCRIPTS_DIR}/traffic_monitor.sh daily >> ${DATA_DIR}/cron.log 2>&1") | crontab -

    # Update config to mark cron as installed
    sed -i 's/CRON_INSTALLED="no"/CRON_INSTALLED="yes"/' "${CONFIG_FILE}"

    print_success "Cron job installed! Reports will be sent ${description}"
}

# Function to uninstall cron job
uninstall_cron_job() {
    (crontab -l 2>/dev/null | grep -v "traffic_monitor.sh") | crontab - 2>/dev/null || true
    print_success "Cron job removed"
}

# Function to update scripts
update_scripts() {
    echo ""
    echo "======================================"
    echo "  Update Scripts"
    echo "======================================"
    echo ""

    print_info "Checking for updates..."

    if [ -d "${SCRIPT_DIR}/.git" ]; then
        cd "${SCRIPT_DIR}"

        # Check for local modifications
        if ! git diff-index --quiet HEAD 2>/dev/null; then
            print_warning "You have local modifications. Creating backup..."
            git stash save "Auto-backup before update $(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        fi

        git fetch origin

        local CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
        local LOCAL=$(git rev-parse @)
        local REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")

        if [ -z "${REMOTE}" ]; then
            print_warning "Cannot check for updates. No upstream branch set."
        elif [ "${LOCAL}" = "${REMOTE}" ]; then
            print_success "Already up to date!"
        else
            print_info "Updates available. Pulling changes..."

            # Try to pull with rebase first
            if git pull --rebase origin "${CURRENT_BRANCH}" 2>/dev/null; then
                print_success "Scripts updated successfully!"
            else
                print_warning "Rebase failed. Attempting reset to remote..."
                git rebase --abort 2>/dev/null || true

                # Force reset to remote (safe for monitoring scripts)
                if git reset --hard origin/"${CURRENT_BRANCH}" 2>/dev/null; then
                    print_success "Scripts force-updated to latest version!"
                    print_info "Local changes were discarded. Check git stash if needed."
                else
                    print_error "Update failed. Please update manually."
                fi
            fi
        fi
    else
        print_warning "Not a git repository. Cannot auto-update."
        print_info "Please download the latest version manually from GitHub."
    fi

    echo ""
    sleep 1
}

# Function to test notification
test_notification() {
    echo ""
    echo "======================================"
    echo "  Test Telegram Notification"
    echo "======================================"
    echo ""

    if [ ! -f "${CONFIG_FILE}" ]; then
        print_error "Configuration not found. Please update configuration first."
        read -p "Press Enter to continue..." < /dev/tty
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
    sleep 1
}

# Function to run traffic report now
run_report_now() {
    echo ""
    echo "======================================"
    echo "  Run Traffic Report"
    echo "======================================"
    echo ""

    if [ ! -f "${CONFIG_FILE}" ]; then
        print_error "Configuration not found. Please update configuration first."
        read -p "Press Enter to continue..." < /dev/tty
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
    sleep 1
}

# Function to reset database
reset_database() {
    echo ""
    echo "======================================"
    echo "  Reset Traffic Database"
    echo "======================================"
    echo ""

    if [ ! -f "${CONFIG_FILE}" ]; then
        print_error "Configuration not found. Please update configuration first."
        read -p "Press Enter to continue..." < /dev/tty
        return 1
    fi

    # Load configuration to get data file location
    load_config

    print_warning "This will:"
    echo "  • Backup current database"
    echo "  • Delete all traffic history"
    echo "  • Reset cumulative traffic to 0"
    echo "  • Initialize new database with detailed format"
    echo ""

    if [ -f "${TRAFFIC_DATA_FILE}" ]; then
        echo "Current database info:"
        echo "  File: ${TRAFFIC_DATA_FILE}"
        echo "  Size: $(ls -lh ${TRAFFIC_DATA_FILE} 2>/dev/null | awk '{print $5}' || echo 'N/A')"
        echo "  Lines: $(wc -l < ${TRAFFIC_DATA_FILE} 2>/dev/null || echo '0')"
        echo ""
    else
        print_info "No existing database found."
        echo ""
    fi

    read -p "Type 'yes' to confirm, or press Enter to cancel: " confirm < /dev/tty

    if [ "${confirm}" != "yes" ]; then
        print_info "Reset cancelled."
        echo ""
        sleep 1
        return 0
    fi

    echo ""
    print_info "Resetting database..."

    # Backup old database if it exists
    if [ -f "${TRAFFIC_DATA_FILE}" ]; then
        local backup_file="${TRAFFIC_DATA_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "${TRAFFIC_DATA_FILE}" "${backup_file}"
        print_success "Backup created: ${backup_file}"
    fi

    # Delete old database
    rm -f "${TRAFFIC_DATA_FILE}"
    print_success "Old database deleted"

    # Initialize new database by running the script
    print_info "Initializing new database..."
    "${SCRIPTS_DIR}/traffic_monitor.sh" daily > /dev/null 2>&1

    if [ -f "${TRAFFIC_DATA_FILE}" ]; then
        print_success "New database initialized with detailed format"
        echo ""
        echo "New database content:"
        echo "--------------------------------------"
        cat "${TRAFFIC_DATA_FILE}"
        echo "--------------------------------------"
    else
        print_error "Failed to initialize database"
    fi

    echo ""
    print_success "Database reset complete!"
    echo ""
    sleep 1
}

# Function to uninstall
uninstall() {
    echo ""
    echo "======================================"
    echo "  Uninstall VPS Traffic Reporter"
    echo "======================================"
    echo ""

    print_warning "This will remove all cron jobs and data files."
    read -p "Type 'yes' to confirm, or press Enter to cancel: " confirm < /dev/tty

    if [ "${confirm}" != "yes" ]; then
        print_info "Uninstall cancelled."
        echo ""
        sleep 1
        return 0
    fi

    # Remove cron job
    uninstall_cron_job

    # Ask if user wants to delete data
    read -p "Delete all data files? (Y/n, press Enter for yes): " delete_data < /dev/tty

    # Default to yes if empty
    delete_data=${delete_data:-y}

    if [[ "${delete_data}" =~ ^[Yy]$ ]]; then
        rm -rf "${CONFIG_DIR}" "${DATA_DIR}"
        print_success "Data files removed"
    fi

    print_success "Uninstall completed!"
    echo ""
    print_info "To completely remove the program, delete this directory:"
    echo "  rm -rf ${SCRIPT_DIR}"
    echo ""
    read -p "Press Enter to exit..." < /dev/tty
    exit 0
}

# Function to display main menu
show_menu() {
    echo "======================================"
    echo "  VPS Traffic Reporter"
    echo "======================================"
    echo ""
    print_info "Installation: ${SCRIPT_DIR}"
    echo ""
    print_info "💡 Tip: Run option 3 first to update to the latest version from GitHub"
    echo ""
    echo "1) View current configuration"
    echo "2) Update configuration"
    echo "3) Update scripts to latest version"
    echo "4) Test notification"
    echo "5) Run traffic report now"
    echo "6) Reset traffic database"
    echo "7) Uninstall"
    echo "0) Exit (or just press Enter)"
    echo ""
    read -p "Select an option: " choice < /dev/tty
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

    # Check if this is first run (no configuration exists)
    if [ ! -f "${CONFIG_FILE}" ]; then
        clear
        echo "======================================"
        echo "  Welcome to VPS Traffic Reporter"
        echo "======================================"
        echo ""
        print_info "First time setup detected!"
        echo ""
        print_info "Let's configure your VPS traffic monitoring system."
        print_info "You will need:"
        echo "  - Telegram Bot Token (from @BotFather)"
        echo "  - Telegram Chat ID (from @userinfobot)"
        echo "  - Your VPS traffic limits and reset schedule"
        echo ""
        read -p "Press Enter to start configuration..." < /dev/tty

        # Run initial configuration
        update_configuration

        echo ""
        print_success "Initial configuration completed!"
        echo ""
        print_info "You can now:"
        echo "  - Test notification (option 4)"
        echo "  - Run a test report (option 5)"
        echo "  - Or just press Enter to exit and let cron do its job"
        echo ""
        read -p "Press Enter to continue to main menu..." < /dev/tty
    fi

    clear
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
                reset_database
                ;;
            7)
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
