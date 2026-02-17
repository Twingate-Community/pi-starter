# Twingate Connector for Raspberry Pi

Automated Raspberry Pi image builder that creates ready-to-deploy Twingate Connectors.

## Features

- **Automatic Provisioning**: Connector creates itself via API on first boot
- **Pre-configured Image**: Twingate Connector package pre-installed
- **Auto-Updates**: Configurable automatic updates via unattended-upgrades

## What's Included

- Raspberry Pi OS (Full or Lite) (64-bit) base
- Pre-installed Twingate Connector package
- First-boot provisioning service
- Systemd service configuration
- Configurable auto-update system
- Comprehensive logging

## Quick Start

### 1. Download the Latest Image

Download the latest pre-built image from [Releases](https://github.com/yourusername/pi-starter/releases/latest)

### 2. Flash to SD Card

#### Tools

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) or [Balena Etcher](https://www.balena.io/etcher/):

#### Manual Flash

```bash
# On macOS/Linux with dd (alternative to GUI tools)
sudo dd if=twingate-connector-pi.img of=/dev/sdX bs=4M status=progress
sync
```

### 3. Configure

Mount the boot partition and create your configuration. This can be done by plugging the SD card back in after flashing.

Rename `twingate-config.txt.example` to `twingate-config.txt` then open the file in a text editor.

**Required Configuration:**

```ini
TWINGATE_NETWORK=yourcompany
TWINGATE_API_KEY=your_api_key_here
TWINGATE_REMOTE_NETWORK_ID=your_remote_network_id
```

**Get API Key:**

1. Log into the Twingate Admin Console
2. Go to Settings > API
3. Click "Generate Token"
4. Give it a name and `Read, Write, Provision` permissions and click "Generate"
5. Copy the token into your config file. This is the only time the Admin Console will show it to you

**Get Remote Network ID:**

1. In the Admin Console, go to Networks
2. Click on your Remote Network
3. Copy the ID from the URL (e.g., `https://{yourcompany}.twingate.com/networks/{remoteNetworkId}` or similar format)

### 4. Boot

Insert your SD card into Raspberry Pi, plug in an ethernet cable and power cable. The Connector will:

1. Read configuration from boot partition
2. Call Twingate API to create Connector
3. Generate and retrieve access tokens
4. Configure and start the Connector service
5. Set up auto-updates (if enabled)
6. Restart the Pi

This process can take a few minutes. If 10 minutes goes by and you still don't see the Connector in the Admin Console, check the troubleshooting guide.

**Default Credentials:**

```
Username: pi
Password: raspberry
```

SSH is enabled by default. **Important:** Change the password after first login:

```bash
passwd
```

Check provisioning status:

```bash
# View log on boot partition
cat /boot/firmware/twingate-provision.log

# Or SSH into Pi and check
sudo journalctl -u twingate-firstboot
sudo systemctl status twingate-connector
```

## SSH Access

SSH is enabled by default with these credentials:

```
Username: pi
Password: raspberry
```

### Disable SSH

To disable SSH before first boot, remove the ssh file from boot partition. This can be done when you configure the Connector by deleting the `ssh` file on the SD card.

Or disable after boot:

```bash
sudo systemctl disable ssh
sudo systemctl stop ssh
```

### Secure SSH (Recommended)

After first login, improve security:

```bash
# Change password
passwd

# Or set up SSH key authentication
mkdir -p ~/.ssh
nano ~/.ssh/authorized_keys
# Paste your public key

# Disable password authentication
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
sudo systemctl restart ssh
```

## Configuration Options

```ini
# Required: Your Twingate network name
TWINGATE_NETWORK=yourcompany

# Required: API key from Admin Console
TWINGATE_API_KEY=your_api_key_here

# Required: Remote Network ID to deploy Connector to
TWINGATE_REMOTE_NETWORK_ID=your_remote_network_id

# Optional: Custom Connector name
# Leave empty to auto-generate: twingate-pi-<hostname>
CONNECTOR_NAME=

# Auto-updates enabled/disabled
AUTO_UPDATE_ENABLED=true

# Update time (24-hour format)
AUTO_UPDATE_TIME=03:00
```

## Building Your Own Image

### Prerequisites

- Docker installed and running
- 8GB+ free disk space
- Or: Linux system with sudo access (for manual build)

### Build Steps (Docker - Recommended)

```bash
# Clone repository
git clone https://github.com/yourusername/pi-starter.git
cd pi-starter

# Build with Docker (handles everything automatically)
bash scripts/build-with-docker.sh

# Compress for distribution (optional)
xz -9 twingate-connector-pi.img
```

### Manual Build (Linux only)

```bash
# Download base Raspberry Pi OS image
wget https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2025-12-04/2025-12-04-raspios-trixie-arm64-lite.img.xz
xz -d *.img.xz

# Run customization script
sudo bash scripts/customize-image.sh raspios-lite.img twingate-connector-pi.img

# Compress for distribution
xz -9 twingate-connector-pi.img
```

### Custom Default Password

To set a custom default password instead of "raspberry":

```bash
# Generate a password hash
bash scripts/generate-password-hash.sh

# Follow the instructions to update customize-image.sh
```

## Auto-Updates

The image includes configurable automatic updates:

- **Default**: Enabled, runs at 3:00 AM local time
- **Managed by**: `unattended-upgrades` + systemd timer
- **Scope**: Only Twingate packages
- **No reboot required**: Connector gracefully restarts

### Disable Auto-Updates

Set the auto update flag to false in the `twingate-config.txt` file:

```ini
AUTO_UPDATE_ENABLED=false
```

Or disable after provisioning:

```bash
sudo systemctl stop apt-daily-upgrade.timer
sudo systemctl disable apt-daily-upgrade.timer
```

### Change Update Time

Edit `/etc/systemd/system/apt-daily-upgrade.timer.d/override.conf`:

```ini
[Timer]
OnCalendar=
OnCalendar=*-*-* 04:00:00
```

Then reload:

```bash
sudo systemctl daemon-reload
sudo systemctl restart apt-daily-upgrade.timer
```

## 🔍 Troubleshooting

### Check Provisioning Status

```bash
# View provisioning log
cat /boot/firmware/twingate-provision.log

# Check service status
sudo systemctl status twingate-firstboot
sudo systemctl status twingate-connector

# View service logs
sudo journalctl -u twingate-connector -f
```

### Re-provision Connector

If provisioning fails or you want to re-provision (including Connector in Admin Console):

```bash
# Remove provisioned flag and reboot
sudo rm /etc/twingate/.provisioned
sudo reboot
```

### Common Issues

**Connector not showing in Admin Console:**

- Check `/boot/firmware/twingate-provision.log` for errors
- Verify API key is correct with required permissions
- Ensure Raspberry Pi has internet connection
- Check Twingate network name is correct

**Service won't start:**

```bash
# Check service logs
sudo journalctl -u twingate-connector -n 50

# Verify configuration
sudo cat /etc/twingate/connector.conf

# Test connectivity
ping -c 4 $(echo $TWINGATE_NETWORK).twingate.com
```

## GitHub Actions CI/CD

The repository includes automated image building:

### Automatic Builds

- **Daily Check**: Runs at 2 / 3 AM UTC to check for new Connector, and Raspberry Pi OS versions
- **Auto-Release**: Creates GitHub release when new version detected
- **Version Tracking**: Prevents duplicate builds

### Workflow Features

- Checks Twingate repository for latest Connector version
- Only builds if version changed
- Generates SHA256 checksums
- Creates detailed release notes
- Compresses images with XZ

## 📁 Repository Structure

```bash
pi-starter/
├── .github/
│   └── workflows/
│       └── build-image.yml          # CI/CD pipeline
├── scripts/
│   ├── twingate-provision.sh        # First-boot provisioning script
│   ├── install-connector.sh         # Connector installation for image build
│   ├── customize-image.sh           # Image customization script
│   ├── build-with-docker.sh         # Docker-based build script
│   └── generate-password-hash.sh    # Password hash generator
├── config/
│   └── twingate-config.txt.example  # Configuration template
├── Dockerfile                        # Docker build configuration
└── README.md
```

## 🔒 Security Considerations

- **API Key**: Removed from config file after first boot provisioning
- **Tokens**: Stored in `/etc/twingate/connector.conf` with 600 permissions
- **Logs**: Contain no sensitive data
- **Boot Partition**: Accessible without root, don't leave API key in config after setup
- **Default Credentials**: Uses standard pi/raspberry - **CHANGE IMMEDIATELY** after first login
- **SSH**: Enabled by default for remote access

**Best Practices:**

1. **Change default password immediately** after first login: `passwd`
2. Use unique Connector names for tracking
3. Rotate API keys periodically
4. Use SSH keys instead of password authentication

## Documentation Links

- [Twingate Connector Documentation](https://www.twingate.com/docs/connectors)
- [Twingate API Reference](https://www.twingate.com/docs/api)
- [Linux Connector Deployment](https://www.twingate.com/docs/connectors-on-linux)

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details

---

**Need Help?** Reach out on [Twingate's subreddit](https://www.reddit.com/r/twingate)
