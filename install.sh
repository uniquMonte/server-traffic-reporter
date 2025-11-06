#!/bin/bash

# VPS Traffic Reporter - One-Click Installer
# Usage: sudo bash <(curl -Ls https://raw.githubusercontent.com/uniquMonte/server-traffic-reporter/main/install.sh)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# GitHub repository
GITHUB_REPO="uniquMonte/server-traffic-reporter"
GITHUB_BRANCH="main"

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

print_header() {
    clear
    echo "======================================"
    echo "  VPS Traffic Reporter Installer"
    echo "======================================"
    echo ""
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check system requirements
check_requirements() {
    print_info "Checking system requirements..."

    local missing_deps=()

    # Check for required commands
    if ! command_exists curl; then
        missing_deps+=("curl")
    fi

    if ! command_exists git; then
        missing_deps+=("git")
    fi

    if ! command_exists bc; then
        missing_deps+=("bc")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        print_info "Please install them using your package manager:"

        if command_exists apt-get; then
            echo "  sudo apt-get update"
            echo "  sudo apt-get install -y ${missing_deps[*]}"
        elif command_exists yum; then
            echo "  sudo yum install -y ${missing_deps[*]}"
        elif command_exists dnf; then
            echo "  sudo dnf install -y ${missing_deps[*]}"
        elif command_exists pacman; then
            echo "  sudo pacman -S ${missing_deps[*]}"
        else
            echo "  Install: ${missing_deps[*]}"
        fi
        echo ""
        read -p "Would you like to attempt automatic installation? (Y/n, press Enter for yes): " auto_install < /dev/tty

        # Default to yes if empty
        auto_install=${auto_install:-y}

        if [[ "${auto_install}" =~ ^[Yy]$ ]]; then
            if command_exists apt-get; then
                sudo apt-get update && sudo apt-get install -y ${missing_deps[*]}
            elif command_exists yum; then
                sudo yum install -y ${missing_deps[*]}
            elif command_exists dnf; then
                sudo dnf install -y ${missing_deps[*]}
            elif command_exists pacman; then
                sudo pacman -S --noconfirm ${missing_deps[*]}
            else
                print_error "Automatic installation not supported for your system"
                exit 1
            fi
            print_success "Dependencies installed successfully!"
        else
            exit 1
        fi
    fi

    # Check for cron
    if ! command_exists crontab; then
        print_warning "crontab not found. Automatic scheduling will not be available."
        print_info "You can install it later if needed."
    fi

    print_success "All requirements satisfied!"
    echo ""
}

# Function to determine installation directory
determine_install_dir() {
    local default_dir=""

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        default_dir="/opt/vps-traffic-reporter"
    else
        default_dir="${HOME}/vps-traffic-reporter"
    fi

    echo ""
    print_info "Installation directory [${default_dir}]"
    read -p "Press Enter for default, or enter custom path: " custom_dir < /dev/tty

    if [ -n "${custom_dir}" ]; then
        INSTALL_DIR="${custom_dir}"
    else
        INSTALL_DIR="${default_dir}"
    fi

    print_info "Installing to: ${INSTALL_DIR}"

    # Check if directory already exists
    if [ -d "${INSTALL_DIR}" ]; then
        echo ""
        print_warning "Directory ${INSTALL_DIR} already exists!"
        read -p "Remove it and reinstall? (Y/n, press Enter for yes): " remove_existing < /dev/tty

        # Default to yes if empty
        remove_existing=${remove_existing:-y}

        if [[ "${remove_existing}" =~ ^[Yy]$ ]]; then
            print_info "Removing existing installation..."
            rm -rf "${INSTALL_DIR}"
            print_success "Removed existing installation"
        else
            print_error "Installation cancelled"
            exit 1
        fi
    fi

    echo ""
}

# Function to download and install
download_and_install() {
    print_info "Downloading VPS Traffic Reporter from GitHub..."
    echo ""

    # Create parent directory if it doesn't exist
    local parent_dir=$(dirname "${INSTALL_DIR}")
    if [ ! -d "${parent_dir}" ]; then
        mkdir -p "${parent_dir}"
    fi

    # Clone the repository
    if git clone --branch "${GITHUB_BRANCH}" "https://github.com/${GITHUB_REPO}.git" "${INSTALL_DIR}"; then
        print_success "Repository cloned successfully!"
    else
        print_error "Failed to clone repository"
        print_info "Trying alternative method..."

        # Alternative: download as zip
        local temp_dir=$(mktemp -d)
        if curl -Ls "https://github.com/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.zip" -o "${temp_dir}/repo.zip"; then
            if command_exists unzip; then
                unzip -q "${temp_dir}/repo.zip" -d "${temp_dir}"
                mv "${temp_dir}/server-traffic-reporter-${GITHUB_BRANCH}" "${INSTALL_DIR}"
                rm -rf "${temp_dir}"
                print_success "Repository downloaded successfully!"
            else
                print_error "unzip command not found. Please install it and try again."
                rm -rf "${temp_dir}"
                exit 1
            fi
        else
            print_error "Failed to download repository"
            rm -rf "${temp_dir}"
            exit 1
        fi
    fi

    echo ""
}

# Function to set permissions
set_permissions() {
    print_info "Setting up permissions..."

    # Make scripts executable
    chmod +x "${INSTALL_DIR}/setup.sh"
    chmod +x "${INSTALL_DIR}/scripts/"*.sh

    # Adjust ownership if needed
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER}" ]; then
        chown -R "${SUDO_USER}:${SUDO_USER}" "${INSTALL_DIR}"
        print_info "Changed ownership to ${SUDO_USER}"
    fi

    print_success "Permissions set successfully!"
    echo ""
}

# Function to create symlink
create_symlink() {
    print_info "Creating command shortcut..."

    local symlink_path="/usr/local/bin/vps-traffic-reporter"

    if [ "$EUID" -eq 0 ]; then
        # Running as root, create symlink
        ln -sf "${INSTALL_DIR}/setup.sh" "${symlink_path}"
        print_success "Command 'vps-traffic-reporter' is now available system-wide"
    else
        # Not root, try to create in user's local bin
        local user_bin="${HOME}/.local/bin"
        mkdir -p "${user_bin}"

        if echo "${PATH}" | grep -q "${user_bin}"; then
            ln -sf "${INSTALL_DIR}/setup.sh" "${user_bin}/vps-traffic-reporter"
            print_success "Command 'vps-traffic-reporter' is now available"
        else
            print_warning "Cannot create system-wide command without root privileges"
            print_info "You can run the script directly: ${INSTALL_DIR}/setup.sh"
        fi
    fi

    echo ""
}

# Function to display next steps
show_next_steps() {
    print_header
    print_success "Installation completed successfully!"
    echo ""
    echo "======================================"
    echo "  Next Steps"
    echo "======================================"
    echo ""
    echo "1. Run the setup script:"

    if [ -L "/usr/local/bin/vps-traffic-reporter" ]; then
        echo "   vps-traffic-reporter"
    else
        echo "   cd ${INSTALL_DIR}"
        echo "   ./setup.sh"
    fi

    echo ""
    echo "2. In the menu, select option 2 to configure:"
    echo "   - Server name"
    echo "   - Telegram Bot Token (get from @BotFather)"
    echo "   - Telegram Chat ID (get from @userinfobot)"
    echo "   - Traffic reset day (e.g., 3 for monthly reset on 3rd)"
    echo "   - Monthly traffic limit in GB (e.g., 500)"
    echo "   - Daily report time (e.g., 09:00)"
    echo ""
    echo "3. Test the notification (option 4)"
    echo ""
    echo "4. Install cron job for automatic daily reports"
    echo ""
    echo "======================================"
    echo ""
    print_info "For more information, visit:"
    echo "https://github.com/${GITHUB_REPO}"
    echo ""
    print_success "Thank you for using VPS Traffic Reporter!"
    echo ""
}

# Function to check if already installed
check_existing_installation() {
    local default_dir=""

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        default_dir="/opt/vps-traffic-reporter"
    else
        default_dir="${HOME}/vps-traffic-reporter"
    fi

    # Check if installation exists
    if [ -d "${default_dir}" ] && [ -f "${default_dir}/setup.sh" ]; then
        clear
        echo "======================================"
        echo "  VPS Traffic Reporter"
        echo "======================================"
        echo ""
        print_success "VPS Traffic Reporter is already installed!"
        echo ""
        print_info "Installation directory: ${default_dir}"

        # Check if config exists
        if [ -f "${default_dir}/config/config.conf" ]; then
            print_success "Configuration found"
        else
            print_warning "No configuration found"
        fi

        echo ""
        print_info "Starting VPS Traffic Reporter..."
        sleep 1
        cd "${default_dir}"
        exec ./setup.sh
    fi
}

# Main installation function
main() {
    print_header

    print_info "This script will install VPS Traffic Reporter on your system"
    echo ""

    # Check if already installed
    check_existing_installation

    # Check requirements
    check_requirements

    # Determine installation directory
    determine_install_dir

    # Download and install
    download_and_install

    # Set permissions
    set_permissions

    # Create symlink
    create_symlink

    # Show next steps
    show_next_steps

    # Ask if user wants to run setup now
    read -p "Would you like to run the setup now? (Y/n, press Enter for yes): " run_setup < /dev/tty

    # Default to yes if empty
    run_setup=${run_setup:-y}

    if [[ "${run_setup}" =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Starting setup..."
        sleep 2
        cd "${INSTALL_DIR}"
        exec ./setup.sh
    else
        echo ""
        print_info "You can run the setup later with: vps-traffic-reporter"
        echo ""
    fi
}

# Run main function
main
