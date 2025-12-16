FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required tools for image customization
RUN apt-get update && \
    apt-get install -y \
    curl \
    gnupg \
    jq \
    apt-transport-https \
    ca-certificates \
    kpartx \
    parted \
    dosfstools \
    xz-utils \
    wget \
    whois \
    qemu-user-static \
    binfmt-support \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy project files
COPY scripts/ /build/scripts/
COPY config/ /build/config/

# Build arguments
ARG BASE_IMAGE_URL=https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2024-11-19/2024-11-19-raspios-bookworm-arm64-lite.img.xz
ARG OUTPUT_IMAGE=twingate-connector-pi.img

# Download and extract base image during build
RUN echo "→ Downloading base image..." && \
    wget -q --show-progress "$BASE_IMAGE_URL" -O base.img.xz && \
    echo "→ Extracting image..." && \
    xz -d base.img.xz

# Entry point will customize and export the image
# This needs to run with --privileged for loop device mounting
COPY <<'EOF' /build/entrypoint.sh
#!/bin/bash
set -euo pipefail

echo "→ Customizing image..."
bash /build/scripts/customize-image.sh /build/base.img /build/twingate-connector-pi.img

echo "→ Exporting image to /output..."
cp /build/twingate-connector-pi.img /output/

echo "→ Build complete!"
ls -lh /output/twingate-connector-pi.img
EOF

RUN chmod +x /build/entrypoint.sh

VOLUME ["/output"]

ENTRYPOINT ["/build/entrypoint.sh"]
