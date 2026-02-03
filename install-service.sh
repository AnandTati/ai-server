#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CURRENT_USER="$(whoami)"
SERVICE_FILE="/etc/systemd/system/ai-stack.service"

echo "=== AI Stack Service Installer ==="
echo "Install directory: $SCRIPT_DIR"
echo "User: $CURRENT_USER"
echo ""

# Generate service file from template
sed -e "s|{{INSTALL_DIR}}|$SCRIPT_DIR|g" \
    -e "s|{{USER}}|$CURRENT_USER|g" \
    "$SCRIPT_DIR/ai-stack.service.template" > /tmp/ai-stack.service

echo "Generated service file:"
cat /tmp/ai-stack.service
echo ""

read -p "Install to systemd? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo cp /tmp/ai-stack.service "$SERVICE_FILE"
    sudo systemctl daemon-reload
    sudo systemctl enable ai-stack.service
    echo ""
    echo "✅ Service installed and enabled"
    echo ""
    echo "Commands:"
    echo "  sudo systemctl start ai-stack   # Start now"
    echo "  sudo systemctl status ai-stack  # Check status"
    echo "  sudo systemctl disable ai-stack # Disable auto-start"
else
    echo "Cancelled"
fi
