#!/bin/bash

# Traffic Accuracy Test Module
# This module provides functions to test traffic monitoring accuracy

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

    echo "${rx_gb}:${tx_gb}:${total_gb}"
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
        echo ""
        return 1
    fi

    echo ""
    echo "Available rclone remotes:"
    echo ""

    local i=1
    local remote_array=()
    while IFS= read -r remote; do
        echo "  ${i}) ${remote}"
        remote_array+=("$remote")
        ((i++))
    done <<< "$remotes"

    echo "  0) Cancel"
    echo ""

    read -p "Select remote: " choice < /dev/tty

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#remote_array[@]}" ]; then
        echo "${remote_array[$((choice-1))]}"
        return 0
    else
        echo ""
        return 1
    fi
}

# Function to test download
test_download() {
    echo "======================================"
    echo "  📥 Download Test (100MB)"
    echo "======================================"
    echo ""

    load_config
    local interface="${NETWORK_INTERFACE}"

    print_info "Network Interface: ${interface}"
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
    print_info "Step 3/5: Downloading 100MB test file..."
    local test_file="/tmp/test_download_100mb_$(date +%s).zip"

    if wget -O "${test_file}" http://speedtest.tele2.net/100MB.zip 2>&1 | tee /tmp/wget_output.log | grep -E "saved|downloaded"; then
        print_success "Download completed"
    else
        print_error "Download failed"
        rm -f "${test_file}" /tmp/wget_output.log
        read -p "Press Enter to continue..." < /dev/tty
        return 1
    fi
    echo ""

    # Step 4: Measure traffic
    print_info "Step 4/5: Measuring traffic difference..."
    local stats_after=$(get_current_stats "${interface}")
    local diff=$(calculate_diff_gb "${stats_before}" "${stats_after}")

    local rx_gb=$(echo "$diff" | cut -d':' -f1)
    local tx_gb=$(echo "$diff" | cut -d':' -f2)
    local total_gb=$(echo "$diff" | cut -d':' -f3)

    echo ""
    echo "📊 Test Results:"
    echo "  ⬇️  Download: ${rx_gb} GB (Expected: ~0.100 GB)"
    echo "  ⬆️  Upload:   ${tx_gb} GB"
    echo "  📦 Total:    ${total_gb} GB"
    echo ""

    # Accuracy check
    local accuracy=$(awk "BEGIN {printf \"%.1f\", (${rx_gb}/0.1)*100}")
    echo "  🎯 Download Accuracy: ${accuracy}%"

    if (( $(echo "${rx_gb} >= 0.095 && ${rx_gb} <= 0.105" | bc -l) )); then
        print_success "✅ Download measurement is ACCURATE (±5%)"
    elif (( $(echo "${rx_gb} >= 0.09 && ${rx_gb} <= 0.11" | bc -l) )); then
        print_warning "⚠️  Download measurement is acceptable (±10%)"
    else
        print_error "❌ Download measurement may be INACCURATE"
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
    echo "  📤 Upload Test (100MB)"
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
    print_info "Step 2/6: Creating 100MB test file..."
    local test_file="/tmp/test_upload_100mb_$(date +%s).dat"
    dd if=/dev/zero of="${test_file}" bs=1M count=100 2>&1 | grep -E "copied|bytes"
    print_success "Test file created"
    echo ""

    # Step 3: Get baseline
    print_info "Step 3/6: Recording baseline traffic..."
    local stats_before=$(get_current_stats "${interface}")
    print_success "Baseline recorded"
    echo ""

    # Step 4: Upload test file
    print_info "Step 4/6: Uploading 100MB to ${remote}..."
    local remote_path="${remote}:vps-traffic-test/test_upload_$(date +%Y%m%d_%H%M%S).dat"

    if rclone copy "${test_file}" "${remote_path%/*}" --progress 2>&1 | tee /tmp/rclone_output.log | tail -1; then
        print_success "Upload completed"
    else
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

    echo ""
    echo "📊 Test Results:"
    echo "  ⬇️  Download: ${rx_gb} GB"
    echo "  ⬆️  Upload:   ${tx_gb} GB (Expected: ~0.100 GB)"
    echo "  📦 Total:    ${total_gb} GB"
    echo ""

    # Accuracy check
    local accuracy=$(awk "BEGIN {printf \"%.1f\", (${tx_gb}/0.1)*100}")
    echo "  🎯 Upload Accuracy: ${accuracy}%"

    if (( $(echo "${tx_gb} >= 0.095 && ${tx_gb} <= 0.105" | bc -l) )); then
        print_success "✅ Upload measurement is ACCURATE (±5%)"
    elif (( $(echo "${tx_gb} >= 0.09 && ${tx_gb} <= 0.11" | bc -l) )); then
        print_warning "⚠️  Upload measurement is acceptable (±10%)"
    else
        print_error "❌ Upload measurement may be INACCURATE"
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

    print_info "This test will:"
    echo "  1. Download 100MB file"
    echo "  2. Upload 100MB file to cloud storage"
    echo "  3. Compare traffic measurements"
    echo ""

    read -p "Continue? (y/N): " confirm < /dev/tty
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 0
    fi

    echo ""

    # Check rclone first
    check_rclone
    local rclone_status=$?

    if [ $rclone_status -eq 1 ]; then
        print_error "rclone is not installed! Upload test will be skipped."
        echo ""
        read -p "Continue with download test only? (y/N): " confirm < /dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 0
        fi
        test_download
        return 0
    elif [ $rclone_status -eq 2 ]; then
        print_error "rclone is not configured! Upload test will be skipped."
        echo ""
        read -p "Continue with download test only? (y/N): " confirm < /dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 0
        fi
        test_download
        return 0
    fi

    # Select remote
    print_info "Selecting rclone remote for upload test..."
    local remote=$(select_rclone_remote)

    if [ -z "$remote" ]; then
        print_error "No remote selected"
        return 1
    fi

    print_success "Selected remote: ${remote}"
    echo ""

    load_config
    local interface="${NETWORK_INTERFACE}"

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

    print_info "Downloading 100MB test file..."
    local download_file="/tmp/test_combined_download_$(date +%s).zip"

    if wget -O "${download_file}" http://speedtest.tele2.net/100MB.zip 2>&1 | grep -E "saved|downloaded"; then
        print_success "Download completed"
    else
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

    print_info "Creating 100MB upload test file..."
    local upload_file="/tmp/test_combined_upload_$(date +%s).dat"
    dd if=/dev/zero of="${upload_file}" bs=1M count=100 2>&1 | grep -E "copied|bytes"
    echo ""

    print_info "Uploading 100MB to ${remote}..."
    local remote_path="${remote}:vps-traffic-test/test_combined_$(date +%Y%m%d_%H%M%S).dat"

    if rclone copy "${upload_file}" "${remote_path%/*}" --progress 2>&1 | tail -1; then
        print_success "Upload completed"
    else
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

    echo ""
    echo "📊 Traffic Measured:"
    echo "  ⬇️  Download: ${rx_gb} GB (Expected: ~0.100 GB)"
    echo "  ⬆️  Upload:   ${tx_gb} GB (Expected: ~0.100 GB)"
    echo "  📦 Total:    ${total_gb} GB (Expected: ~0.200 GB)"
    echo ""

    # Accuracy checks
    local dl_accuracy=$(awk "BEGIN {printf \"%.1f\", (${rx_gb}/0.1)*100}")
    local ul_accuracy=$(awk "BEGIN {printf \"%.1f\", (${tx_gb}/0.1)*100}")
    local total_accuracy=$(awk "BEGIN {printf \"%.1f\", (${total_gb}/0.2)*100}")

    echo "📈 Accuracy Analysis:"
    echo "  Download Accuracy: ${dl_accuracy}%"
    echo "  Upload Accuracy:   ${ul_accuracy}%"
    echo "  Total Accuracy:    ${total_accuracy}%"
    echo ""

    # Overall assessment
    if (( $(echo "${total_gb} >= 0.19 && ${total_gb} <= 0.21" | bc -l) )); then
        print_success "✅ Traffic measurement is ACCURATE (±5%)"
    elif (( $(echo "${total_gb} >= 0.18 && ${total_gb} <= 0.22" | bc -l) )); then
        print_warning "⚠️  Traffic measurement is acceptable (±10%)"
    else
        print_error "❌ Traffic measurement may be INACCURATE"
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
    while true; do
        clear
        echo "======================================"
        echo "  🧪 Traffic Accuracy Test"
        echo "======================================"
        echo ""
        print_info "Test traffic monitoring accuracy by:"
        echo "  - Downloading/uploading known file sizes"
        echo "  - Comparing measured vs expected traffic"
        echo "  - Sending before/after snapshots to Telegram"
        echo ""
        echo "1) 📥 Test Download (100MB)"
        echo "2) 📤 Test Upload (100MB)"
        echo "3) 📊 Test Both (Download + Upload)"
        echo "4) ℹ️  Requirements & Info"
        echo "0) ⬅️  Back to Main Menu"
        echo ""
        read -p "Select an option: " choice < /dev/tty
        echo ""

        case "${choice}" in
            1)
                test_download
                ;;
            2)
                test_upload
                ;;
            3)
                test_both
                ;;
            4)
                clear
                echo "======================================"
                echo "  ℹ️  Requirements & Information"
                echo "======================================"
                echo ""
                echo "📥 Download Test:"
                echo "  - Downloads 100MB file from speedtest.tele2.net"
                echo "  - Measures download traffic accuracy"
                echo "  - No additional requirements"
                echo ""
                echo "📤 Upload Test:"
                echo "  - Requires rclone to be installed and configured"
                echo "  - Uploads 100MB to your cloud storage"
                echo "  - You can configure rclone with: rclone config"
                echo ""
                echo "📊 Combined Test:"
                echo "  - Runs both download and upload tests"
                echo "  - Provides comprehensive accuracy assessment"
                echo "  - Expected total traffic: ~0.200 GB"
                echo ""
                echo "💡 Tips:"
                echo "  - Tests send Telegram notifications before/after"
                echo "  - Compare the traffic changes in notifications"
                echo "  - Accuracy within ±10% is generally acceptable"
                echo "  - Network overhead may cause slight variations"
                echo ""
                read -p "Press Enter to continue..." < /dev/tty
                ;;
            0|"")
                return 0
                ;;
            *)
                print_error "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}
