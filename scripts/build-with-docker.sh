#!/bin/bash
set -euo pipefail

################################################################################
# Docker Image Builder
# 
# This script builds the Twingate Connector Pi image entirely within Docker.
# The Dockerfile downloads the base image, customizes it, and exports the result.
#
# Usage: ./build-with-docker.sh [output-directory]
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT_DIR="${1:-$PROJECT_ROOT}"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

echo "=========================================="
echo "Twingate Connector Pi Image Builder"
echo "=========================================="
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    echo "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
    exit 1
fi

echo "Output directory: $OUTPUT_DIR"
echo ""
echo "→ Building Docker image (downloads and extracts base image)..."
echo ""

# Build the Docker image (downloads and extracts base Raspberry Pi OS)
docker build -t twingate-pi-builder "$PROJECT_ROOT"

BUILD_EXIT=$?
if [ $BUILD_EXIT -ne 0 ]; then
    echo ""
    echo "✗ Docker build failed with exit code $BUILD_EXIT"
    exit $BUILD_EXIT
fi

echo ""
echo "→ Customizing and exporting image..."
echo ""

# Run the container with --privileged for loop device mounting
# This customizes the image and exports it to the host
docker run --rm --privileged -v "$OUTPUT_DIR:/output" twingate-pi-builder

RUN_EXIT=$?
if [ $RUN_EXIT -ne 0 ]; then
    echo ""
    echo "✗ Image export failed with exit code $RUN_EXIT"
    exit $RUN_EXIT
fi

echo ""
echo "=========================================="
echo "✓ Build complete!"
echo "=========================================="
echo ""
echo "Output directory: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"/*.img 2>/dev/null || echo "No .img files found"
echo ""
echo "Next steps:"
echo "1. Flash to SD card: Use Balena Etcher or Raspberry Pi Imager"
echo "2. Configure: Edit twingate-config.txt on the boot partition"
echo "3. Boot your Raspberry Pi and wait 2-5 minutes"
echo ""
echo "To compress for distribution:"
echo "  xz -9 $OUTPUT_DIR/twingate-connector-pi.img"
