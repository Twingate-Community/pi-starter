#!/bin/bash
set -euo pipefail

################################################################################
# Password Hash Generator for Raspberry Pi Image
# 
# This script generates a SHA-512 password hash compatible with Raspberry Pi OS
# userconf.txt format. Use this to create a custom default password when building
# your own image.
#
# Usage: ./generate-password-hash.sh [username]
################################################################################

USERNAME="${1:-pi}"

echo "=========================================="
echo "Raspberry Pi Password Hash Generator"
echo "=========================================="
echo ""
echo "This script generates a password hash for the Raspberry Pi userconf.txt file."
echo "The userconf.txt mechanism is the official way Raspberry Pi OS handles"
echo "pre-configured user credentials on first boot."
echo ""
echo "Username: $USERNAME"
echo ""

# Check if mkpasswd is available
if ! command -v mkpasswd &> /dev/null; then
    echo "Error: mkpasswd is not installed."
    echo ""
    echo "Install it with:"
    echo "  Ubuntu/Debian: sudo apt-get install whois"
    echo "  macOS:         brew install pwgen (or use Docker method below)"
    echo ""
    echo "Alternative: Use Docker to generate the hash:"
    echo "  docker run --rm -it ubuntu:22.04 bash -c 'apt-get update && apt-get install -y whois && mkpasswd -m sha-512'"
    echo ""
    exit 1
fi

# Prompt for password
echo "Enter the password for user '$USERNAME':"
read -s PASSWORD
echo ""
echo "Confirm password:"
read -s PASSWORD_CONFIRM
echo ""

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "Error: Passwords do not match!"
    exit 1
fi

if [ -z "$PASSWORD" ]; then
    echo "Error: Password cannot be empty!"
    exit 1
fi

# Generate hash
echo "Generating SHA-512 hash..."
PASSWORD_HASH=$(echo "$PASSWORD" | mkpasswd -m sha-512 --stdin)

echo ""
echo "=========================================="
echo "Generated Hash"
echo "=========================================="
echo ""
echo "userconf.txt format:"
echo "$USERNAME:$PASSWORD_HASH"
echo ""
echo "=========================================="
echo "Usage Instructions"
echo "=========================================="
echo ""
echo "Option 1: Use in image build (customize-image.sh)"
echo "---------------------------------------------------"
echo "Edit scripts/customize-image.sh and replace the password generation section:"
echo ""
echo "  # Around line 150, replace:"
echo "  DEFAULT_PASSWORD=\"raspberry\""
echo "  PASSWORD_HASH=\$(echo \"\$DEFAULT_PASSWORD\" | mkpasswd -m sha-512 --stdin)"
echo ""
echo "  # With your custom hash:"
echo "  PASSWORD_HASH=\"$PASSWORD_HASH\""
echo ""
echo "Option 2: Manual userconf.txt (on SD card boot partition)"
echo "-----------------------------------------------------------"
echo "Create or edit /boot/firmware/userconf.txt on the SD card:"
echo ""
echo "  echo \"$USERNAME:$PASSWORD_HASH\" > /boot/firmware/userconf.txt"
echo ""
echo "This will set the password on first boot."
echo ""
echo "=========================================="
echo "Security Notes"
echo "=========================================="
echo ""
echo "- The hash is safe to store in version control (it's one-way encrypted)"
echo "- Users should still change their password after first login"
echo "- Consider using SSH keys instead of password authentication"
echo "- For production deployments, disable password authentication entirely"
echo ""
