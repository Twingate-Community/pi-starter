#!/bin/bash
set -euo pipefail

################################################################################
# Twingate Connector Installation Script for Image Building
# 
# This script is used during image customization to:
# 1. Add Twingate APT repository
# 2. Pre-install the Twingate Connector package
# 3. Prevent the service from starting (will be configured on first boot)
################################################################################

LOG_FILE="/var/log/twingate-install.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "Installing Twingate Connector package for image build..."

# Install dependencies
log "Installing dependencies..."
apt-get update
apt-get install -y curl gnupg apt-transport-https ca-certificates jq

# Add Twingate repository (using official method from setup script)
log "Adding Twingate GPG key and APT repository..."

# Download and install GPG key
TWINGATE_GPG_KEY=/usr/share/keyrings/twingate-connector-keyring.gpg
if ! curl -fsSL "https://packages.twingate.com/apt/gpg.key" | gpg --dearmor -o "$TWINGATE_GPG_KEY"; then
    log "ERROR: Failed to download or process GPG key"
    exit 1
fi

# Add repository
echo "deb [signed-by=${TWINGATE_GPG_KEY}] https://packages.twingate.com/apt/ /" | tee /etc/apt/sources.list.d/twingate.list

# Update and install Connector
log "Installing Twingate Connector package..."
apt-get update
apt-get install -y twingate-connector

# Prevent service from starting until provisioned
log "Disabling Twingate Connector service until first boot provisioning..."
systemctl disable twingate-connector
systemctl stop twingate-connector 2>/dev/null || true

log "Twingate Connector package installed successfully!"
log "Service will be configured and started on first boot."

exit 0
