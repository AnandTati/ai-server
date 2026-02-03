#!/bin/bash
# =============================================================================
# AI Stack - Stop Script
# =============================================================================
# Stops all AI stack services gracefully.
#
# This will:
#   - Save any pending FAISS index updates
#   - Stop all containers
#   - Free GPU memory
#
# Data is preserved in the data/ directory.
#
# Usage: ./ai-off.sh
# =============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Stopping AI Stack..."
docker compose down

echo ""
echo "All services stopped."
echo "Data preserved in: $SCRIPT_DIR/data/"

echo ""
echo "Shutting down the system"
sudo shutdown now
