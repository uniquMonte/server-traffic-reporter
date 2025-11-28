#!/bin/bash

# Traffic Accuracy Test Module
# This module provides functions to test traffic monitoring accuracy

# Colors for output (will use parent's if available, otherwise define here)
if [ -z "$RED" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
fi

# Function to get current traffic statistics
get_current_stats() {
    local interface="$1"
    local rx=$(cat /sys/class/net/${interface}/statistics/rx_bytes 2>/dev/null || echo 0)
    local tx=$(cat /sys/class/net/${interface}/statistics/tx_bytes 2>/dev/null || echo 0)
    echo "${rx}:${tx}"
}

# Function to calculate traffic difference in GB
calculate_diff_gb() {
    local before="$1"
    local after="$2"

    local rx_before=$(echo "$before" | cut -d':' -f1)
    local tx_before=$(echo "$before" | cut -d':' -f2)
    local rx_after=$(echo "$after" | cut -d':' -f1)
    local tx_after=$(echo "$after" | cut -d':' -f2)

    local rx_diff=$((rx_after - rx_before))
    local tx_diff=$((tx_after - tx_before))

    local rx_gb=$(awk "BEGIN {printf \"%.3f\", ${rx_diff}/1073741824}")
    local tx_gb=$(awk "BEGIN {printf \"%.3f\", ${tx_diff}/1073741824}")
    local total_gb=$(awk "BEGIN {printf \"%.3f\", (${rx_diff}+${tx_diff})/1073741824}")

    echo "${rx_gb}:${tx_gb}:${total_gb}:${rx_diff}:${tx_diff}"
}

# Function to get file size in bytes
get_file_size_bytes() {
    local file="$1"
    if [ -f "$file" ]; then
        stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# Function to convert bytes to human readable
bytes_to_human() {
    local bytes=$1
    if [ "${bytes}" -lt 1024 ]; then
        echo "${bytes} B"
    elif [ "${bytes}" -lt 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1024}") KB"
    elif [ "${bytes}" -lt 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1048576}") MB"
    else
        echo "$(awk "BEGIN {printf \"%.3f\", ${bytes}/1073741824}") GB"
    fi
}

# Function to send current traffic report
send_traffic_snapshot() {
    local prefix="$1"
    "${SCRIPTS_DIR}/traffic_monitor.sh" daily > /dev/null 2>&1
}

# Function to check if rclone is installed and configured
check_rclone() {
    if ! command -v rclone &> /dev/null; then
        return 1
    fi

    local remotes=$(rclone listremotes 2>/dev/null)
    if [ -z "$remotes" ]; then
        return 2
    fi

    return 0
}

# Function to list rclone remotes and let user choose
select_rclone_remote() {
    local remotes=$(rclone listremotes 2>/dev/null | sed 's/:$//')

    if [ -z "$remotes" ]; then
        echo "" >&2
        return 1
    fi

    # Output to terminal (not captured by command substitution)
    echo "" >&2
    echo -e "${BOLD}${CYAN}======================================" >&2
    echo -e "  📦 Available Rclone Remotes" >&2
    echo -e "======================================${NC}" >&2
    echo "" >&2

    local i=1
    local remote_array=()
    while IFS= read -r remote; do
        echo -e "  ${GREEN}${i})${NC} ${BOLD}${remote}${NC}" >&2
        remote_array+=("$remote")
        ((i++))
    done <<< "$remotes"

    echo -e "  ${RED}0)${NC} ${BOLD}Cancel${NC}" >&2
    echo "" >&2

    read -p "$(echo -e ${CYAN}Select remote [1-${#remote_array[@]}]: ${NC})" choice < /dev/tty

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#remote_array[@]}" ]; then
        echo "${remote_array[$((choice-1))]}"
        return 0
    else
        echo "" >&2
        return 1
    fi
}

# Function to test download
test_download() {
    echo "======================================"
    echo "  📥 Download Test"
    echo "======================================"
    echo ""

    load_config
    local interface="${NETWORK_INTERFACE}"

    print_info "Network Interface: ${interface}"
    echo ""

    # Ask user for download URL
    echo "Download URL options:"
    echo "  1) Default: http://speedtest.tele2.net/100MB.zip (100MB)"
    echo "  2) Custom URL"
    echo ""
    read -p "Select option (1-2) [1]: " url_choice < /dev/tty
    url_choice=${url_choice:-1}

    local download_url
    case "$url_choice" in
        2)
            echo ""
            read -p "Enter custom download URL: " download_url < /dev/tty
            if [ -z "$download_url" ]; then
                print_error "No URL provided"
                read -p "Press Enter to continue..." < /dev/tty
                return 1
            fi
            ;;
        *)
            download_url="http://speedtest.tele2.net/100MB.zip"
            ;;
    esac

    print_info "Download URL: ${download_url}"
    echo ""

    # Step 1: Send pre-test snapshot
    print_info "Step 1/5: Sending pre-test traffic snapshot to Telegram..."
    send_traffic_snapshot "Before Download Test"
    print_success "Pre-test snapshot sent"
    echo ""

    # Step 2: Get baseline
    print_info "Step 2/5: Recording baseline traffic..."
    local stats_before=$(get_current_stats "${interface}")
    print_success "Baseline recorded"
    echo ""

    # Step 3: Download test file
    print_info "Step 3/5: Downloading test file..."
    echo ""
    local test_file="/tmp/test_download_$(date +%s).tmp"

    # Download with progress bar
    if wget --progress=bar:force -O "${test_file}" "${download_url}" 2>&1 | tee /tmp/wget_output.log; then
        echo ""
        print_success "Download completed"
    else
        echo ""
        print_error "Download failed"
        rm -f "${test_file}" /tmp/wget_output.log
        read -p "Press Enter to continue..." < /dev/tty
        return 1
    fi
    echo ""

    # Get actual file size
    local file_size_bytes=$(get_file_size_bytes "${test_file}")
    local file_size_gb=$(awk "BEGIN {printf \"%.3f\", ${file_size_bytes}/1073741824}")
    local file_size_human=$(bytes_to_human ${file_size_bytes})

    print_info "Downloaded file size: ${file_size_human} (${file_size_gb} GB)"
    echo ""

    # Step 4: Measure traffic
    print_info "Step 4/5: Measuring traffic difference..."
    local stats_after=$(get_current_stats "${interface}")
    local diff=$(calculate_diff_gb "${stats_before}" "${stats_after}")

    local rx_gb=$(echo "$diff" | cut -d':' -f1)
    local tx_gb=$(echo "$diff" | cut -d':' -f2)
    local total_gb=$(echo "$diff" | cut -d':' -f3)
    local rx_bytes=$(echo "$diff" | cut -d':' -f4)
    local tx_bytes=$(echo "$diff" | cut -d':' -f5)

    echo ""
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════╗"
    echo -e "║       📊 Test Results              ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}📁 File Size:${NC}"
    echo -e "   ${GREEN}${file_size_gb} GB${NC} ${CYAN}(${file_size_human})${NC}"
    echo ""
    echo -e "${BOLD}📊 Traffic Measured:${NC}"
    echo -e "   ⬇️  Download: ${CYAN}${rx_gb} GB${NC}"
    echo -e "   ⬆️  Upload:   ${CYAN}${tx_gb} GB${NC}"
    echo -e "   📦 Total:    ${BOLD}${CYAN}${total_gb} GB${NC}"
    echo ""

    # Accuracy check - compare download traffic to file size
    if [ "${file_size_bytes}" -gt 0 ]; then
        local accuracy=$(awk "BEGIN {printf \"%.1f\", (${rx_bytes}/${file_size_bytes})*100}")
        # Calculate absolute difference using awk conditional
        local diff_percent=$(awk "BEGIN {d=100-${accuracy}; printf \"%.1f\", (d<0?-d:d)}")

        echo -e "${BOLD}🎯 Download Accuracy Analysis:${NC}"
        echo -e "   Expected:  ${GREEN}${file_size_gb} GB${NC}"
        echo -e "   Measured:  ${CYAN}${rx_gb} GB${NC}"
        echo -e "   Accuracy:  ${YELLOW}${accuracy}%${NC}"
        echo -e "   Diff:      ${MAGENTA}${diff_percent}%${NC}"
        echo ""

        # Network overhead explanation
        local overhead_percent=$(awk "BEGIN {printf \"%.1f\", ((${rx_bytes}-${file_size_bytes})/${file_size_bytes})*100}")
        echo -e "${BOLD}📡 Network Overhead:${NC} ${YELLOW}${overhead_percent}%${NC}"
        echo -e "   ${CYAN}(Includes TCP/IP headers, retransmissions, etc.)${NC}"
        echo ""

        # Accuracy assessment - use awk for safer comparison
        local is_accurate=$(awk "BEGIN {print (${diff_percent} <= 5 ? 1 : 0)}")
        local is_acceptable=$(awk "BEGIN {print (${diff_percent} <= 10 ? 1 : 0)}")
        local is_fair=$(awk "BEGIN {print (${diff_percent} <= 15 ? 1 : 0)}")

        if [ "${is_accurate}" -eq 1 ]; then
            echo -e "${BOLD}${GREEN}✅ Download measurement is ACCURATE (±5%)${NC}"
        elif [ "${is_acceptable}" -eq 1 ]; then
            echo -e "${BOLD}${YELLOW}⚠️  Download measurement is acceptable (±10%)${NC}"
        elif [ "${is_fair}" -eq 1 ]; then
            echo -e "${BOLD}${YELLOW}⚠️  Download measurement has expected network overhead (±15%)${NC}"
        else
            echo -e "${BOLD}${RED}❌ Download measurement may be INACCURATE (>${diff_percent}%)${NC}"
        fi
    else
        print_error "Cannot calculate accuracy: file size is 0"
    fi
    echo ""

    # Clean up
    rm -f "${test_file}" /tmp/wget_output.log

    # Step 5: Send post-test snapshot
    print_info "Step 5/5: Sending post-test traffic snapshot to Telegram..."
    sleep 2  # Brief pause to let system update stats
    send_traffic_snapshot "After Download Test"
    print_success "Post-test snapshot sent"
    echo ""

    print_info "Check your Telegram bot for before/after traffic comparison"
    echo ""
    read -p "Press Enter to continue..." < /dev/tty
}

# Function to test upload
test_upload() {
    echo "======================================"
    echo "  📤 Upload Test"
    echo "======================================"
    echo ""

    # Check rclone
    check_rclone
    local rclone_status=$?

    if [ $rclone_status -eq 1 ]; then
        print_error "rclone is not installed!"
        echo ""
        print_info "Please install rclone first:"
        echo "  curl https://rclone.org/install.sh | sudo bash"
        echo ""
        read -p "Press Enter to continue..." < /dev/tty
        return 1
    elif [ $rclone_status -eq 2 ]; then
        print_error "rclone is not configured!"
        echo ""
        print_info "Please configure rclone first:"
        echo "  rclone config"
        echo ""
        read -p "Press Enter to continue..." < /dev/tty
        return 1
    fi

    # Select remote
    print_info "Selecting rclone remote..."
    local remote=$(select_rclone_remote)

    if [ -z "$remote" ]; then
        print_error "No remote selected"
        echo ""
        read -p "Press Enter to continue..." < /dev/tty
        return 1
    fi

    print_success "Selected remote: ${remote}"
    echo ""

    # Ask for file size
    echo "Upload file size options:"
    echo "  1) 10 MB"
    echo "  2) 50 MB"
    echo "  3) 100 MB (Default)"
    echo "  4) 200 MB"
    echo "  5) Custom size"
    echo ""
    read -p "Select option (1-5) [3]: " size_choice < /dev/tty
    size_choice=${size_choice:-3}

    local file_size_mb
    case "$size_choice" in
        1) file_size_mb=10 ;;
        2) file_size_mb=50 ;;
        3) file_size_mb=100 ;;
        4) file_size_mb=200 ;;
        5)
            read -p "Enter custom size in MB: " file_size_mb < /dev/tty
            if ! [[ "$file_size_mb" =~ ^[0-9]+$ ]] || [ "$file_size_mb" -le 0 ]; then
                print_error "Invalid size"
                read -p "Press Enter to continue..." < /dev/tty
                return 1
            fi
            ;;
        *)
            file_size_mb=100
            ;;
    esac

    print_info "Upload file size: ${file_size_mb} MB"
    echo ""

    load_config
    local interface="${NETWORK_INTERFACE}"

    print_info "Network Interface: ${interface}"
    echo ""

    # Step 1: Send pre-test snapshot
    print_info "Step 1/6: Sending pre-test traffic snapshot to Telegram..."
    send_traffic_snapshot "Before Upload Test"
    print_success "Pre-test snapshot sent"
    echo ""

    # Step 2: Create test file
    print_info "Step 2/6: Creating ${file_size_mb}MB test file..."
    echo ""
    local test_file="/tmp/test_upload_$(date +%s).dat"
    dd if=/dev/zero of="${test_file}" bs=1M count=${file_size_mb} status=progress 2>&1 | tail -1

    # Get actual file size
    local file_size_bytes=$(get_file_size_bytes "${test_file}")
    local file_size_gb=$(awk "BEGIN {printf \"%.3f\", ${file_size_bytes}/1073741824}")
    local file_size_human=$(bytes_to_human ${file_size_bytes})

    echo ""
    print_success "Test file created: ${file_size_human}"
    echo ""

    # Step 3: Get baseline
    print_info "Step 3/6: Recording baseline traffic..."
    local stats_before=$(get_current_stats "${interface}")
    print_success "Baseline recorded"
    echo ""

    # Step 4: Upload test file
    print_info "Step 4/6: Uploading ${file_size_human} to ${remote}..."
    echo ""
    local remote_path="${remote}:vps-traffic-test/test_upload_$(date +%Y%m%d_%H%M%S).dat"

    # Upload with progress display
    if rclone copy "${test_file}" "${remote_path%/*}" --progress --stats-one-line 2>&1 | tee /tmp/rclone_output.log; then
        echo ""
        print_success "Upload completed"
    else
        echo ""
        print_error "Upload failed"
        rm -f "${test_file}" /tmp/rclone_output.log
        read -p "Press Enter to continue..." < /dev/tty
        return 1
    fi
    echo ""

    # Step 5: Measure traffic
    print_info "Step 5/6: Measuring traffic difference..."
    local stats_after=$(get_current_stats "${interface}")
    local diff=$(calculate_diff_gb "${stats_before}" "${stats_after}")

    local rx_gb=$(echo "$diff" | cut -d':' -f1)
    local tx_gb=$(echo "$diff" | cut -d':' -f2)
    local total_gb=$(echo "$diff" | cut -d':' -f3)
    local rx_bytes=$(echo "$diff" | cut -d':' -f4)
    local tx_bytes=$(echo "$diff" | cut -d':' -f5)

    echo ""
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════╗"
    echo -e "║       📊 Test Results              ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}📁 File Size:${NC}"
    echo -e "   ${GREEN}${file_size_gb} GB${NC} ${CYAN}(${file_size_human})${NC}"
    echo ""
    echo -e "${BOLD}📊 Traffic Measured:${NC}"
    echo -e "   ⬇️  Download: ${CYAN}${rx_gb} GB${NC}"
    echo -e "   ⬆️  Upload:   ${CYAN}${tx_gb} GB${NC}"
    echo -e "   📦 Total:    ${BOLD}${CYAN}${total_gb} GB${NC}"
    echo ""

    # Accuracy check - compare upload traffic to file size
    if [ "${file_size_bytes}" -gt 0 ]; then
        local accuracy=$(awk "BEGIN {printf \"%.1f\", (${tx_bytes}/${file_size_bytes})*100}")
        # Calculate absolute difference using awk conditional
        local diff_percent=$(awk "BEGIN {d=100-${accuracy}; printf \"%.1f\", (d<0?-d:d)}")

        echo -e "${BOLD}🎯 Upload Accuracy Analysis:${NC}"
        echo -e "   Expected:  ${GREEN}${file_size_gb} GB${NC}"
        echo -e "   Measured:  ${CYAN}${tx_gb} GB${NC}"
        echo -e "   Accuracy:  ${YELLOW}${accuracy}%${NC}"
        echo -e "   Diff:      ${MAGENTA}${diff_percent}%${NC}"
        echo ""

        # Network overhead explanation
        local overhead_percent=$(awk "BEGIN {printf \"%.1f\", ((${tx_bytes}-${file_size_bytes})/${file_size_bytes})*100}")
        echo -e "${BOLD}📡 Network Overhead:${NC} ${YELLOW}${overhead_percent}%${NC}"
        echo -e "   ${CYAN}(Includes TCP/IP headers, retransmissions, etc.)${NC}"
        echo ""

        # Accuracy assessment - use awk for safer comparison
        local is_accurate=$(awk "BEGIN {print (${diff_percent} <= 5 ? 1 : 0)}")
        local is_acceptable=$(awk "BEGIN {print (${diff_percent} <= 10 ? 1 : 0)}")
        local is_fair=$(awk "BEGIN {print (${diff_percent} <= 15 ? 1 : 0)}")

        if [ "${is_accurate}" -eq 1 ]; then
            echo -e "${BOLD}${GREEN}✅ Upload measurement is ACCURATE (±5%)${NC}"
        elif [ "${is_acceptable}" -eq 1 ]; then
            echo -e "${BOLD}${YELLOW}⚠️  Upload measurement is acceptable (±10%)${NC}"
        elif [ "${is_fair}" -eq 1 ]; then
            echo -e "${BOLD}${YELLOW}⚠️  Upload measurement has expected network overhead (±15%)${NC}"
        else
            echo -e "${BOLD}${RED}❌ Upload measurement may be INACCURATE (>${diff_percent}%)${NC}"
        fi
    else
        print_error "Cannot calculate accuracy: file size is 0"
    fi
    echo ""

    # Clean up
    rm -f "${test_file}" /tmp/rclone_output.log

    print_info "Note: Uploaded file location: ${remote_path}"
    echo ""

    # Step 6: Send post-test snapshot
    print_info "Step 6/6: Sending post-test traffic snapshot to Telegram..."
    sleep 2
    send_traffic_snapshot "After Upload Test"
    print_success "Post-test snapshot sent"
    echo ""

    print_info "Check your Telegram bot for before/after traffic comparison"
    echo ""
    read -p "Press Enter to continue..." < /dev/tty
}

# Function to test both download and upload
test_both() {
    echo "======================================"
    echo "  📊 Combined Test (Download + Upload)"
    echo "======================================"
    echo ""

    print_info "This test will download and upload files to test bidirectional traffic."
    echo ""

    read -p "Continue? (y/N): " confirm < /dev/tty
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 0
    fi

    echo ""

    # Check rclone first
    check_rclone
    local rclone_status=$?

    if [ $rclone_status -ne 0 ]; then
        print_error "rclone is required for upload test!"
        echo ""
        read -p "Continue with download test only? (y/N): " confirm < /dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 0
        fi
        test_download
        return 0
    fi

    # Select remote
    print_info "Selecting rclone remote for upload..."
    local remote=$(select_rclone_remote)

    if [ -z "$remote" ]; then
        print_error "No remote selected"
        return 1
    fi

    print_success "Selected remote: ${remote}"
    echo ""

    load_config
    local interface="${NETWORK_INTERFACE}"

    # Get download URL
    echo "Download URL options:"
    echo "  1) Default: http://speedtest.tele2.net/100MB.zip (100MB)"
    echo "  2) Custom URL"
    echo ""
    read -p "Select option (1-2) [1]: " url_choice < /dev/tty
    url_choice=${url_choice:-1}

    local download_url
    case "$url_choice" in
        2)
            echo ""
            read -p "Enter custom download URL: " download_url < /dev/tty
            if [ -z "$download_url" ]; then
                print_error "No URL provided, using default"
                download_url="http://speedtest.tele2.net/100MB.zip"
            fi
            ;;
        *)
            download_url="http://speedtest.tele2.net/100MB.zip"
            ;;
    esac
    echo ""

    # Get upload size
    echo "Upload file size:"
    read -p "Enter size in MB [100]: " upload_size_mb < /dev/tty
    upload_size_mb=${upload_size_mb:-100}
    echo ""

    # Send pre-test snapshot
    print_info "Sending pre-test traffic snapshot to Telegram..."
    send_traffic_snapshot "Before Combined Test"
    print_success "Pre-test snapshot sent"
    echo ""

    # Get baseline
    print_info "Recording baseline traffic..."
    local stats_before=$(get_current_stats "${interface}")
    print_success "Baseline recorded"
    echo ""

    # === Download Test ===
    echo "======================================"
    echo "  📥 Phase 1: Download Test"
    echo "======================================"
    echo ""

    print_info "Downloading from: ${download_url}"
    echo ""
    local download_file="/tmp/test_combined_download_$(date +%s).tmp"

    # Download with progress bar
    if wget --progress=bar:force -O "${download_file}" "${download_url}" 2>&1; then
        local dl_size=$(get_file_size_bytes "${download_file}")
        local dl_size_human=$(bytes_to_human ${dl_size})
        echo ""
        print_success "Download completed: ${dl_size_human}"
    else
        echo ""
        print_error "Download failed"
        rm -f "${download_file}"
        read -p "Press Enter to continue..." < /dev/tty
        return 1
    fi
    echo ""

    # === Upload Test ===
    echo "======================================"
    echo "  📤 Phase 2: Upload Test"
    echo "======================================"
    echo ""

    print_info "Creating ${upload_size_mb}MB upload file..."
    echo ""
    local upload_file="/tmp/test_combined_upload_$(date +%s).dat"
    dd if=/dev/zero of="${upload_file}" bs=1M count=${upload_size_mb} status=progress 2>&1 | tail -1

    local ul_size=$(get_file_size_bytes "${upload_file}")
    local ul_size_human=$(bytes_to_human ${ul_size})
    echo ""

    print_info "Uploading ${ul_size_human} to ${remote}..."
    echo ""
    local remote_path="${remote}:vps-traffic-test/test_combined_$(date +%Y%m%d_%H%M%S).dat"

    # Upload with progress display
    if rclone copy "${upload_file}" "${remote_path%/*}" --progress --stats-one-line 2>&1; then
        echo ""
        print_success "Upload completed"
    else
        echo ""
        print_error "Upload failed"
        rm -f "${download_file}" "${upload_file}"
        read -p "Press Enter to continue..." < /dev/tty
        return 1
    fi
    echo ""

    # === Results ===
    echo "======================================"
    echo "  📊 Combined Test Results"
    echo "======================================"
    echo ""

    print_info "Measuring traffic difference..."
    local stats_after=$(get_current_stats "${interface}")
    local diff=$(calculate_diff_gb "${stats_before}" "${stats_after}")

    local rx_gb=$(echo "$diff" | cut -d':' -f1)
    local tx_gb=$(echo "$diff" | cut -d':' -f2)
    local total_gb=$(echo "$diff" | cut -d':' -f3)
    local rx_bytes=$(echo "$diff" | cut -d':' -f4)
    local tx_bytes=$(echo "$diff" | cut -d':' -f5)

    local dl_size_gb=$(awk "BEGIN {printf \"%.3f\", ${dl_size}/1073741824}")
    local ul_size_gb=$(awk "BEGIN {printf \"%.3f\", ${ul_size}/1073741824}")
    local total_expected_gb=$(awk "BEGIN {printf \"%.3f\", (${dl_size}+${ul_size})/1073741824}")

    echo ""
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════╗"
    echo -e "║   📊 Combined Test Results         ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}📁 File Sizes:${NC}"
    echo -e "   Downloaded: ${GREEN}${dl_size_gb} GB${NC} ${CYAN}(${dl_size_human})${NC}"
    echo -e "   Uploaded:   ${GREEN}${ul_size_gb} GB${NC} ${CYAN}(${ul_size_human})${NC}"
    echo -e "   Total:      ${BOLD}${GREEN}${total_expected_gb} GB${NC}"
    echo ""
    echo -e "${BOLD}📊 Traffic Measured:${NC}"
    echo -e "   ⬇️  Download: ${CYAN}${rx_gb} GB${NC}"
    echo -e "   ⬆️  Upload:   ${CYAN}${tx_gb} GB${NC}"
    echo -e "   📦 Total:    ${BOLD}${CYAN}${total_gb} GB${NC}"
    echo ""

    # Accuracy checks
    local dl_accuracy=$(awk "BEGIN {printf \"%.1f\", (${rx_bytes}/${dl_size})*100}")
    local ul_accuracy=$(awk "BEGIN {printf \"%.1f\", (${tx_bytes}/${ul_size})*100}")
    local total_expected_bytes=$((dl_size + ul_size))
    local total_measured_bytes=$((rx_bytes + tx_bytes))
    local total_accuracy=$(awk "BEGIN {printf \"%.1f\", (${total_measured_bytes}/${total_expected_bytes})*100}")

    echo -e "${BOLD}📈 Accuracy Analysis:${NC}"
    echo -e "   Download: ${YELLOW}${dl_accuracy}%${NC}"
    echo -e "   Upload:   ${YELLOW}${ul_accuracy}%${NC}"
    echo -e "   Total:    ${BOLD}${YELLOW}${total_accuracy}%${NC}"
    echo ""

    # Overall assessment
    # Calculate absolute difference using awk conditional
    local total_diff=$(awk "BEGIN {d=100-${total_accuracy}; printf \"%.1f\", (d<0?-d:d)}")

    # Use awk for safer comparison
    local is_accurate=$(awk "BEGIN {print (${total_diff} <= 5 ? 1 : 0)}")
    local is_acceptable=$(awk "BEGIN {print (${total_diff} <= 10 ? 1 : 0)}")
    local is_fair=$(awk "BEGIN {print (${total_diff} <= 15 ? 1 : 0)}")

    if [ "${is_accurate}" -eq 1 ]; then
        echo -e "${BOLD}${GREEN}✅ Traffic measurement is ACCURATE (±5%)${NC}"
    elif [ "${is_acceptable}" -eq 1 ]; then
        echo -e "${BOLD}${YELLOW}⚠️  Traffic measurement is acceptable (±10%)${NC}"
    elif [ "${is_fair}" -eq 1 ]; then
        echo -e "${BOLD}${YELLOW}⚠️  Traffic measurement has expected network overhead (±15%)${NC}"
    else
        echo -e "${BOLD}${RED}❌ Traffic measurement may be INACCURATE (>${total_diff}%)${NC}"
    fi
    echo ""

    # Clean up
    rm -f "${download_file}" "${upload_file}"

    # Send post-test snapshot
    print_info "Sending post-test traffic snapshot to Telegram..."
    sleep 2
    send_traffic_snapshot "After Combined Test"
    print_success "Post-test snapshot sent"
    echo ""

    print_info "Check your Telegram bot for before/after traffic comparison"
    echo ""
    read -p "Press Enter to continue..." < /dev/tty
}

# Function to show traffic test menu
show_traffic_test_menu() {
    clear
    echo "======================================"
    echo "  🧪 Traffic Accuracy Test"
    echo "======================================"
    echo ""
    print_info "This test will measure traffic monitoring accuracy by:"
    echo "  - Downloading a test file of known size"
    echo "  - Uploading a test file of known size"
    echo "  - Comparing measured vs actual file sizes"
    echo "  - Accounting for network overhead"
    echo "  - Sending before/after snapshots to Telegram"
    echo ""

    print_info "Requirements:"
    echo "  - Download: Uses wget (no additional setup needed)"
    echo "  - Upload: Requires rclone installation & configuration"
    echo ""

    print_info "Accuracy Standards:"
    echo "  - ✅ Excellent: ±5% (accounting for TCP/IP overhead)"
    echo "  - ⚠️  Good: ±10% (acceptable variation)"
    echo "  - ⚠️  Fair: ±15% (expected network overhead)"
    echo "  - ❌ Poor: >±15% (may indicate issues)"
    echo ""

    read -p "Press Enter to start the test, or Ctrl+C to cancel..." < /dev/tty
    echo ""

    # Run the combined test
    test_both
}
