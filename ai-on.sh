#!/bin/bash
# =============================================================================
# AI Stack - Start Script
# =============================================================================
# Starts all AI stack services in detached mode.
#
# Services started:
#   - ollama: LLM inference engine
#   - router: Smart query router with FAISS memory
#   - openwebui: Web interface
#   - whisper: Speech-to-text
#
# Usage: ./ai-on.sh
# =============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Starting AI Stack..."
docker compose up -d

echo ""
echo "Services started:"
echo "  - OpenWebUI:    http://localhost:3000"
echo "  - Smart Router: http://localhost:8000"
echo "  - Ollama API:   http://localhost:11434"
echo ""
echo "View logs: docker compose logs -f"
