#!/bin/bash
# Traffic Database Reset Script
# This script safely resets the traffic database to use the new detailed format

set -e

echo "=========================================="
echo "Traffic Database Reset Utility"
echo "=========================================="
echo ""

# Configuration (modify if your paths are different)
INSTALL_DIR="/opt/vps-traffic-reporter"
DATA_FILE="${INSTALL_DIR}/data/traffic.db"
BACKUP_FILE="${DATA_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
SCRIPT_PATH="${INSTALL_DIR}/traffic_monitor.sh"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  Please run as root (use sudo)"
    exit 1
fi

# Step 1: Check if database exists
echo "Step 1: Checking current database..."
if [ -f "${DATA_FILE}" ]; then
    echo "✓ Found database at: ${DATA_FILE}"
    echo "  Current size: $(ls -lh ${DATA_FILE} | awk '{print $5}')"
    echo "  Last modified: $(ls -l ${DATA_FILE} | awk '{print $6, $7, $8}')"
else
    echo "ℹ️  No existing database found. Will create new one."
fi
echo ""

# Step 2: Backup old database (if exists)
if [ -f "${DATA_FILE}" ]; then
    echo "Step 2: Creating backup..."
    cp "${DATA_FILE}" "${BACKUP_FILE}"
    echo "✓ Backup created: ${BACKUP_FILE}"
    echo ""
fi

# Step 3: Check and disable cron temporarily
echo "Step 3: Checking cron jobs..."
CRON_DISABLED=0
if crontab -l 2>/dev/null | grep -q "${SCRIPT_PATH}"; then
    echo "✓ Found active cron job for traffic monitor"
    echo "  Temporarily disabling cron..."

    # Backup current crontab
    crontab -l > /tmp/crontab.backup.$$

    # Comment out the traffic monitor line
    crontab -l | sed "s|^\([^#].*${SCRIPT_PATH}.*\)|#\1  # Disabled by reset script|" | crontab -

    echo "✓ Cron job disabled temporarily"
    CRON_DISABLED=1
else
    echo "ℹ️  No active cron job found (this is fine)"
fi
echo ""

# Step 4: Delete old database
echo "Step 4: Removing old database..."
if [ -f "${DATA_FILE}" ]; then
    rm -f "${DATA_FILE}"
    echo "✓ Old database deleted"
else
    echo "ℹ️  No database to delete"
fi
echo ""

# Step 5: Initialize new database
echo "Step 5: Initializing new database with detailed format..."
if [ -x "${SCRIPT_PATH}" ]; then
    # Run the script once to initialize
    ${SCRIPT_PATH}
    echo "✓ New database initialized"
else
    echo "⚠️  Script not found or not executable: ${SCRIPT_PATH}"
    echo "   Please check your installation"
    exit 1
fi
echo ""

# Step 6: Verify new database format
echo "Step 6: Verifying new database format..."
if [ -f "${DATA_FILE}" ]; then
    echo "✓ New database created successfully"
    echo ""
    echo "Database content:"
    echo "----------------------------------------"
    cat "${DATA_FILE}"
    echo "----------------------------------------"
    echo ""

    # Check if it has the new format (baseline_rx and baseline_tx)
    if grep -q "baseline_rx=" "${DATA_FILE}" && grep -q "baseline_tx=" "${DATA_FILE}"; then
        echo "✓ New detailed format confirmed (with baseline_rx/baseline_tx)"
    else
        echo "⚠️  Warning: Database may not be in new format"
    fi
else
    echo "⚠️  Database was not created. Please check for errors."
    exit 1
fi
echo ""

# Step 7: Re-enable cron
if [ ${CRON_DISABLED} -eq 1 ]; then
    echo "Step 7: Re-enabling cron job..."
    # Restore original crontab
    crontab /tmp/crontab.backup.$$
    rm -f /tmp/crontab.backup.$$
    echo "✓ Cron job re-enabled"
    echo ""
fi

# Summary
echo "=========================================="
echo "✅ Database Reset Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  • Old database backed up to: ${BACKUP_FILE}"
echo "  • New database created at: ${DATA_FILE}"
echo "  • Format: Detailed with separate RX/TX tracking"
echo "  • Cron job: $([ ${CRON_DISABLED} -eq 1 ] && echo 'Re-enabled' || echo 'Not affected')"
echo ""
echo "Next steps:"
echo "  1. Wait for the next scheduled report (or run script manually)"
echo "  2. Check Telegram bot for new detailed format"
echo "  3. If you need to restore old data: cp ${BACKUP_FILE} ${DATA_FILE}"
echo ""
echo "Done! 🎉"
