#!/bin/bash
set -euo pipefail

################################################################################
# Raspberry Pi Image Customization Script
# 
# This script customizes a Raspberry Pi OS Lite image with:
# 1. Pre-installed Twingate connector package
# 2. First-boot provisioning service
# 3. Example configuration file
#
# Usage: ./customize-image.sh <input-image> <output-image>
################################################################################

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input-image> <output-image>"
    echo "Example: $0 raspios-lite.img twingate-connector.img"
    exit 1
fi

INPUT_IMAGE="$1"
OUTPUT_IMAGE="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$INPUT_IMAGE" ]; then
    echo "Error: Input image not found: $INPUT_IMAGE"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

echo "Starting image customization..."
echo "Input: $INPUT_IMAGE"
echo "Output: $OUTPUT_IMAGE"

# Copy input image to output
echo "Copying base image..."
cp "$INPUT_IMAGE" "$OUTPUT_IMAGE"

# Mount the image using kpartx for better Docker compatibility
LOOP_DEVICE=$(losetup -f)
echo "Using loop device: $LOOP_DEVICE"

losetup -f "$OUTPUT_IMAGE"
LOOP_DEVICE=$(losetup -j "$OUTPUT_IMAGE" | cut -d: -f1)

# Use kpartx to create partition mappings
kpartx -av "$LOOP_DEVICE"

# Give the system time to create partition devices
sleep 2

# kpartx creates devices in /dev/mapper/
LOOP_NAME=$(basename "$LOOP_DEVICE")
ROOT_PART="/dev/mapper/${LOOP_NAME}p2"
BOOT_PART="/dev/mapper/${LOOP_NAME}p1"

echo "Root partition: $ROOT_PART"
echo "Boot partition: $BOOT_PART"

# Create mount points
MOUNT_ROOT="/mnt/pi-root-$$"
MOUNT_BOOT="/mnt/pi-boot-$$"

mkdir -p "$MOUNT_ROOT"
mkdir -p "$MOUNT_BOOT"

# Mount partitions
echo "Mounting partitions..."
mount "$ROOT_PART" "$MOUNT_ROOT"
mount "$BOOT_PART" "$MOUNT_BOOT"

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up..."
    umount "$MOUNT_BOOT" 2>/dev/null || true
    umount "$MOUNT_ROOT" 2>/dev/null || true
    kpartx -d "$LOOP_DEVICE" 2>/dev/null || true
    losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    rmdir "$MOUNT_BOOT" 2>/dev/null || true
    rmdir "$MOUNT_ROOT" 2>/dev/null || true
}

trap cleanup EXIT

# Copy provisioning script to image
echo "Installing provisioning script..."
mkdir -p "$MOUNT_ROOT/usr/local/bin"
cp "$SCRIPT_DIR/twingate-provision.sh" "$MOUNT_ROOT/usr/local/bin/"
chmod +x "$MOUNT_ROOT/usr/local/bin/twingate-provision.sh"

# Copy Connector installation script
cp "$SCRIPT_DIR/install-connector.sh" "$MOUNT_ROOT/usr/local/bin/"
chmod +x "$MOUNT_ROOT/usr/local/bin/install-connector.sh"

# Create systemd service for first-boot provisioning
echo "Creating first-boot service..."
cat > "$MOUNT_ROOT/etc/systemd/system/twingate-firstboot.service" << 'EOF'
[Unit]
Description=Twingate Connector First-Boot Provisioning
After=network-online.target systemd-time-wait-sync.service
Wants=network-online.target
Before=twingate-connector.service
ConditionPathExists=!/etc/twingate/.provisioned

[Service]
Type=oneshot
ExecStart=/usr/local/bin/twingate-provision.sh
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes
# Do not restart on failure - requires manual intervention or reboot
Restart=no

[Install]
WantedBy=multi-user.target
EOF

# Prepare chroot environment for installation and user creation
echo "Setting up chroot environment..."
mount -t proc proc "$MOUNT_ROOT/proc"
mount -t sysfs sys "$MOUNT_ROOT/sys"
mount -o bind /dev "$MOUNT_ROOT/dev"
mount -o bind /dev/pts "$MOUNT_ROOT/dev/pts"

# Copy resolv.conf for DNS resolution during install
cp /etc/resolv.conf "$MOUNT_ROOT/etc/resolv.conf"

# Copy qemu-aarch64-static for ARM emulation (if available)
if [ -f /usr/bin/qemu-aarch64-static ]; then
    echo "Setting up QEMU for ARM64 emulation..."
    cp /usr/bin/qemu-aarch64-static "$MOUNT_ROOT/usr/bin/"
else
    echo "Warning: qemu-aarch64-static not found, ARM emulation may not work"
fi

# Install Twingate Connector package
echo "Installing Twingate Connector package..."
chroot "$MOUNT_ROOT" /usr/local/bin/install-connector.sh

# Enable the first-boot service
echo "Enabling first-boot service..."
chroot "$MOUNT_ROOT" systemctl enable twingate-firstboot.service

# Remove qemu binary from image
if [ -f "$MOUNT_ROOT/usr/bin/qemu-aarch64-static" ]; then
    rm "$MOUNT_ROOT/usr/bin/qemu-aarch64-static"
fi

# Enable SSH by creating ssh file
echo "Enabling SSH..."
touch "$MOUNT_BOOT/ssh"

# Create userconf.txt for initial user setup (Raspberry Pi OS native mechanism)
# This is what Raspberry Pi Imager uses - it's processed by userconf-pi service
echo "Creating userconf.txt for initial user setup..."
# Generate password hash dynamically to match Raspberry Pi Imager behavior
# Default username: pi, password: raspberry
DEFAULT_PASSWORD="raspberry"
PASSWORD_HASH=$(echo "$DEFAULT_PASSWORD" | mkpasswd -m sha-512 --stdin)
echo "pi:$PASSWORD_HASH" > "$MOUNT_BOOT/userconf.txt"
chmod 644 "$MOUNT_BOOT/userconf.txt"
echo "Default credentials: pi / $DEFAULT_PASSWORD"

# Cleanup chroot mounts
echo "Cleaning up chroot environment..."
umount "$MOUNT_ROOT/dev/pts"
umount "$MOUNT_ROOT/dev"
umount "$MOUNT_ROOT/sys"
umount "$MOUNT_ROOT/proc"

# Copy example config to boot partition
echo "Adding example configuration..."
cp "$PROJECT_ROOT/config/twingate-config.txt.example" "$MOUNT_BOOT/twingate-config.txt.example"

# Create README on boot partition
cat > "$MOUNT_BOOT/TWINGATE_README.txt" << 'EOF'
Twingate Connector Raspberry Pi Image
======================================

This image contains a pre-installed Twingate connector that will be
automatically configured on first boot.

SETUP INSTRUCTIONS:
-------------------

1. Copy twingate-config.txt.example to twingate-config.txt
2. Edit twingate-config.txt with your Twingate settings:
   
   Required parameters:
   - TWINGATE_NETWORK: Your Twingate network name (subdomain)
   - TWINGATE_API_KEY: API key from Admin Console (Settings > API)
   - TWINGATE_REMOTE_NETWORK_ID: Remote Network ID to deploy connector to
   
   Optional parameters:
   - CONNECTOR_NAME: Custom connector name (auto-generated if empty)
   - AUTO_UPDATE_ENABLED: Enable automatic updates (default: true)
   - AUTO_UPDATE_TIME: Update check time in HH:MM format (default: 03:00)

3. Insert SD card into Raspberry Pi and power on
4. Wait 2-5 minutes for first boot provisioning to complete
5. Check /boot/firmware/twingate-provision.log for status
6. Verify connector status in Twingate Admin Console

DEFAULT CREDENTIALS:
--------------------

Username: pi
Password: raspberry

SSH is enabled by default. To disable, remove /boot/firmware/ssh file.

IMPORTANT: Change the default password after first login:
  passwd

FEATURES:
---------

- Automatic connector creation via API
- Secure token generation and configuration
- Optional automatic updates (configurable time)
- Systemd service management
- Detailed logging
- SSH enabled by default
- Pre-configured user credentials

For more information, visit: https://www.twingate.com/docs/connectors

TROUBLESHOOTING:
----------------

- Check logs: /boot/firmware/twingate-provision.log
- Service status: sudo systemctl status twingate-connector
- Re-provision: sudo rm /etc/twingate/.provisioned && sudo reboot

EOF

echo "Image customization completed successfully!"
echo "Output image: $OUTPUT_IMAGE"
echo ""
echo "Next steps:"
echo "1. Flash the image to an SD card"
echo "2. Mount the boot partition and configure twingate-config.txt"
echo "3. Boot the Raspberry Pi"

exit 0
