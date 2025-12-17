#!/bin/bash
set -euo pipefail

################################################################################
# Twingate Connector First-Boot Provisioning Script
# 
# This script runs on first boot of a Raspberry Pi to:
# 1. Read configuration from /boot/firmware/twingate-config.txt
# 2. Call Twingate API to create a Connector and get tokens
# 3. Install and configure the Twingate Connector systemd service
# 4. Set up auto-updates based on user preferences
################################################################################

LOG_FILE="/var/log/twingate-provision.log"
# Support both old and new boot partition locations
if [ -f "/boot/firmware/twingate-config.txt" ]; then
    CONFIG_FILE="/boot/firmware/twingate-config.txt"
elif [ -f "/boot/twingate-config.txt" ]; then
    CONFIG_FILE="/boot/twingate-config.txt"
else
    CONFIG_FILE="/boot/firmware/twingate-config.txt"  # Default to new location
fi
CONNECTOR_CONFIG="/etc/twingate/connector.conf"
UPDATE_CONFIG="/etc/twingate/update-config"
PROVISIONED_FLAG="/etc/twingate/.provisioned"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# Check if already provisioned
if [ -f "$PROVISIONED_FLAG" ]; then
    log "System already provisioned. Exiting."
    exit 0
fi

log "Starting Twingate Connector provisioning..."

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    log_error "Please create the configuration file with your Twingate settings."
    exit 1
fi

# Source the configuration file
log "Reading configuration from $CONFIG_FILE"
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Validate required configuration
if [ -z "${TWINGATE_NETWORK:-}" ]; then
    log_error "TWINGATE_NETWORK is not set in configuration"
    exit 1
fi

if [ -z "${TWINGATE_API_KEY:-}" ]; then
    log_error "TWINGATE_API_KEY is not set in configuration"
    exit 1
fi

if [ -z "${TWINGATE_REMOTE_NETWORK_ID:-}" ]; then
    log_error "TWINGATE_REMOTE_NETWORK_ID is not set in configuration"
    log_error "Please specify the Remote Network ID where the connector should be deployed"
    exit 1
fi

# Set defaults for optional parameters
CONNECTOR_NAME="${CONNECTOR_NAME:-twingate-pi-$(hostname)}"
AUTO_UPDATE_ENABLED="${AUTO_UPDATE_ENABLED:-true}"
AUTO_UPDATE_TIME="${AUTO_UPDATE_TIME:-03:00}"

log "Configuration loaded:"
log "  Network: $TWINGATE_NETWORK"
log "  Remote Network ID: $TWINGATE_REMOTE_NETWORK_ID"
log "  Connector Name: $CONNECTOR_NAME"
log "  Auto-updates: $AUTO_UPDATE_ENABLED"
log "  Update Time: $AUTO_UPDATE_TIME"

# Construct API endpoint (trailing slash is required!)
GRAPHQL_URL="https://${TWINGATE_NETWORK}.twingate.com/api/graphql/"
log "GraphQL API endpoint: $GRAPHQL_URL"

# Wait for network connectivity
log "Checking network connectivity..."
MAX_RETRIES=60
RETRY_COUNT=0
NETWORK_READY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s --connect-timeout 5 --max-time 10 "https://${TWINGATE_NETWORK}.twingate.com" > /dev/null 2>&1; then
        NETWORK_READY=true
        log "Network connectivity confirmed after $RETRY_COUNT attempts."
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $((RETRY_COUNT % 5)) -eq 0 ]; then
        # Log every 5th attempt to reduce log spam
        log "Waiting for network connectivity... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    fi
    sleep 3
done

if [ "$NETWORK_READY" != "true" ]; then
    log_error "Failed to establish network connectivity after $MAX_RETRIES attempts ($(($MAX_RETRIES * 3)) seconds)."
    log_error "Please check your network connection and try again."
    log_error "You can reboot the Pi to retry provisioning: sudo reboot"
    exit 1
fi

# Function to call GraphQL API
call_graphql_api() {
    local query="$1"
    local response
    
    response=$(curl -s -X POST "$GRAPHQL_URL" \
        -H "Content-Type: application/json" \
        -H "X-API-KEY: $TWINGATE_API_KEY" \
        -d "$query")
    
    echo "$response"
}

# Step 1: Create Connector
log "Creating connector: $CONNECTOR_NAME"

query=$(jq -n \
    --arg name "$CONNECTOR_NAME" \
    --arg remoteNetworkId "$TWINGATE_REMOTE_NETWORK_ID" \
    '{
        query: "mutation($name: String!, $remoteNetworkId: ID!) { connectorCreate(name: $name, remoteNetworkId: $remoteNetworkId, hasStatusNotificationsEnabled: true) { ok error entity { id name } } }",
        variables: {
            name: $name,
            remoteNetworkId: $remoteNetworkId
        }
    }')

response=$(call_graphql_api "$query")

# Check if response is empty
if [ -z "$response" ]; then
    log_error "Failed to create connector. Empty response from API."
    log_error "This could indicate a network issue or invalid API endpoint."
    exit 1
fi

# Log the full response for debugging
log "API Response: $response"

# Check for GraphQL errors
if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
    error_details=$(echo "$response" | jq -r '.errors[] | "\(.message) (path: \(.path // "N/A"))"')
    log_error "Failed to create connector. GraphQL errors:"
    log_error "$error_details"
    exit 1
fi

# Check if data exists
if ! echo "$response" | jq -e '.data.connectorCreate' > /dev/null 2>&1; then
    log_error "Failed to create connector. Invalid response structure."
    log_error "Response: $response"
    exit 1
fi

ok=$(echo "$response" | jq -r '.data.connectorCreate.ok')
if [ "$ok" != "true" ]; then
    error_msg=$(echo "$response" | jq -r '.data.connectorCreate.error // "Unknown error"')
    log_error "Failed to create connector: $error_msg"
    exit 1
fi

CONNECTOR_ID=$(echo "$response" | jq -r '.data.connectorCreate.entity.id')
log "Connector created successfully! ID: $CONNECTOR_ID"

# Step 2: Generate Tokens
log "Generating access and refresh tokens..."

query=$(jq -n \
    --arg connectorId "$CONNECTOR_ID" \
    '{
        query: "mutation($connectorId: ID!) { connectorGenerateTokens(connectorId: $connectorId) { ok error connectorTokens { accessToken refreshToken } } }",
        variables: {
            connectorId: $connectorId
        }
    }')

response=$(call_graphql_api "$query")

# Check if response is empty
if [ -z "$response" ]; then
    log_error "Failed to generate tokens. Empty response from API."
    exit 1
fi

# Log the full response for debugging
log "Token generation response: $response"

# Check for GraphQL errors
if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
    error_details=$(echo "$response" | jq -r '.errors[] | "\(.message) (path: \(.path // "N/A"))"')
    log_error "Failed to generate tokens. GraphQL errors:"
    log_error "$error_details"
    exit 1
fi

# Check if data exists
if ! echo "$response" | jq -e '.data.connectorGenerateTokens' > /dev/null 2>&1; then
    log_error "Failed to generate tokens. Invalid response structure."
    log_error "Response: $response"
    exit 1
fi

ok=$(echo "$response" | jq -r '.data.connectorGenerateTokens.ok')
if [ "$ok" != "true" ]; then
    error_msg=$(echo "$response" | jq -r '.data.connectorGenerateTokens.error // "Unknown error"')
    log_error "Failed to generate tokens: $error_msg"
    exit 1
fi

ACCESS_TOKEN=$(echo "$response" | jq -r '.data.connectorGenerateTokens.connectorTokens.accessToken')
REFRESH_TOKEN=$(echo "$response" | jq -r '.data.connectorGenerateTokens.connectorTokens.refreshToken')

log "Tokens generated successfully!"

# Step 3: Verify Twingate Connector is installed
log "Verifying Twingate Connector installation..."

if ! command -v twingate-connector &> /dev/null; then
    log_error "Twingate Connector is not installed!"
    log_error "This image was not built correctly. Please use a properly built image."
    exit 1
fi

if ! systemctl list-unit-files | grep -q twingate-connector.service; then
    log_error "Twingate Connector service not found!"
    log_error "This image was not built correctly. Please use a properly built image."
    exit 1
fi

log "Twingate Connector installation verified."

# Step 4: Configure Twingate Connector
log "Configuring Twingate Connector..."

# Create config directory with proper permissions (same as setup script)
install -d -m 0700 /etc/twingate

# Write configuration file (following setup script format)
cat > "$CONNECTOR_CONFIG" << EOF
TWINGATE_NETWORK=${TWINGATE_NETWORK}
TWINGATE_ACCESS_TOKEN=${ACCESS_TOKEN}
TWINGATE_REFRESH_TOKEN=${REFRESH_TOKEN}
EOF

# Set proper permissions (as per setup script)
chmod 0600 "$CONNECTOR_CONFIG"

log "Connector configuration written to $CONNECTOR_CONFIG"

# Create provisioned flag NOW to prevent recreating connector if service fails
log "Marking system as provisioned..."
mkdir -p "$(dirname "$PROVISIONED_FLAG")"
echo "Provisioned on $(date)" > "$PROVISIONED_FLAG"
echo "Connector ID: $CONNECTOR_ID" >> "$PROVISIONED_FLAG"
echo "Connector Name: $CONNECTOR_NAME" >> "$PROVISIONED_FLAG"
log "Provisioned flag created - connector will not be recreated on subsequent runs"

# Step 5: Enable connector service
log "Enabling Twingate Connector service..."

# Enable service to start on boot
systemctl enable twingate-connector || {
    log_error "Failed to enable Twingate Connector service"
    exit 1
}

log "Twingate Connector service enabled successfully."
log "Service will start automatically after reboot."

# Step 6: Configure auto-updates
# Save update configuration for future reference
cat > "$UPDATE_CONFIG" << EOF
AUTO_UPDATE_ENABLED=${AUTO_UPDATE_ENABLED}
AUTO_UPDATE_TIME=${AUTO_UPDATE_TIME}
EOF

if [ "$AUTO_UPDATE_ENABLED" = "true" ]; then
    log "Configuring unattended-upgrades for Twingate packages..."
    
    # Install unattended-upgrades if not present
    if ! dpkg -l | grep -q unattended-upgrades; then
        apt-get update
        apt-get install -y unattended-upgrades
    fi
    
    # Configure unattended-upgrades for Twingate
    cat > /etc/apt/apt.conf.d/51twingate-unattended-upgrades << 'EOF'
// Enable automatic updates for Twingate packages
Unattended-Upgrade::Origins-Pattern {
    "origin=Twingate";
};

Unattended-Upgrade::Package-Blacklist {
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    # Configure timer for specified time
    mkdir -p /etc/systemd/system/apt-daily-upgrade.timer.d
    cat > /etc/systemd/system/apt-daily-upgrade.timer.d/override.conf << EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* ${AUTO_UPDATE_TIME}:00
RandomizedDelaySec=0
EOF

    systemctl daemon-reload
    systemctl enable apt-daily-upgrade.timer
fi

# Step 7: Clean up sensitive data
log "Cleaning up sensitive configuration data..."

# Remove API key from config file but keep other settings
if [ -f "$CONFIG_FILE" ]; then
    sed -i 's/^TWINGATE_API_KEY=.*/TWINGATE_API_KEY=*** REMOVED FOR SECURITY ***/' "$CONFIG_FILE"
    log "API key removed from $CONFIG_FILE"
fi

# Step 8: Copy log to boot partition for easy access
log "Copying log to boot partition for easy access..."
# Try both boot partition locations
cp "$LOG_FILE" /boot/firmware/twingate-provision.log 2>/dev/null || \
cp "$LOG_FILE" /boot/twingate-provision.log 2>/dev/null || true

log "============================================"
log "Twingate Connector provisioning completed!"
log "Connector ID: $CONNECTOR_ID"
log "Connector Name: $CONNECTOR_NAME"
log "Status: Check the Twingate Admin Console"
log "Rebooting system to start Connector service..."
log "============================================"

# Reboot the system to start the Connector service cleanly
sync
reboot
