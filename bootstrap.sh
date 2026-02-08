#!/usr/bin/env bash
# =============================================================================
# AI Stack Bootstrap Script
# =============================================================================
#
# Purpose:
#   Downloads and configures all required AI models for the stack.
#   Run this script ONCE after initial setup, before starting the services.
#
# What it does:
#   1. Creates data directories for persistent storage
#   2. Starts Ollama service temporarily
#   3. Pulls LLM models (configured in models.env):
#      - CODING_MODEL: For coding and complex reasoning
#      - GENERAL_MODEL: For general chat and summarization
#      - EMBEDDING_MODEL: For FAISS memory semantic search
#   4. Starts all services
#
# Requirements:
#   - Docker and Docker Compose installed
#   - NVIDIA GPU with 12GB+ VRAM
#   - ~20GB disk space for models
#   - Internet connection for downloading models
#
# Usage:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh
#
# =============================================================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================================================
# Load Configuration from models.env
# =============================================================================

if [[ ! -f models.env ]]; then
    echo "[ERROR] models.env file not found!"
    echo "Please create models.env with model configuration."
    exit 1
fi

# shellcheck source=/dev/null
source models.env

# =============================================================================
# Display Configuration
# =============================================================================

echo ""
echo "=============================================="
echo "  AI Stack Bootstrap"
echo "=============================================="
echo ""
echo "Configuration from models.env:"
echo "  Coding model:    ${CODING_MODEL}"
echo "  General model:   ${GENERAL_MODEL}"
echo "  Embedding model: ${EMBEDDING_MODEL}"
echo ""

# =============================================================================
# Create Data Directories
# =============================================================================

echo "[INFO] Creating data directories..."
mkdir -p "$SCRIPT_DIR/data/ollama"
mkdir -p "$SCRIPT_DIR/data/openwebui"
mkdir -p "$SCRIPT_DIR/data/smart-router"
mkdir -p "$SCRIPT_DIR/data/searxng"

echo "[INFO] Data directories created:"
echo "  - data/ollama/        (model weights)"
echo "  - data/openwebui/     (user data)"
echo "  - data/smart-router/  (FAISS memory)"
echo "  - data/searxng/       (search config)"

# =============================================================================
# Start Ollama Service
# =============================================================================

echo ""
echo "[INFO] Starting Ollama service..."
docker compose up -d ollama

# Wait for Ollama to be ready
echo "[INFO] Waiting for Ollama API..."
max_attempts=30
attempt=1

while [ $attempt -le $max_attempts ]; do
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "[INFO] Ollama is ready!"
        break
    fi
    echo -n "."
    sleep 2
    attempt=$((attempt + 1))
done

if [ $attempt -gt $max_attempts ]; then
    echo ""
    echo "[ERROR] Ollama failed to start. Check: docker compose logs ollama"
    exit 1
fi

# =============================================================================
# Pull AI Models
# =============================================================================

echo ""
echo "=============================================="
echo "  Pulling AI Models"
echo "=============================================="
echo ""
echo "This may take a while depending on your connection..."
echo ""

# Pull embedding model first (smallest, needed for memory)
echo "[INFO] Pulling embedding model: ${EMBEDDING_MODEL}..."
docker exec ollama ollama pull "${EMBEDDING_MODEL}"

# Pull LLM models
echo ""
echo "[INFO] Pulling coding model: ${CODING_MODEL}..."
docker exec ollama ollama pull "${CODING_MODEL}"

echo ""
echo "[INFO] Pulling general model: ${GENERAL_MODEL}..."
docker exec ollama ollama pull "${GENERAL_MODEL}"

# =============================================================================
# Verify Models
# =============================================================================

echo ""
echo "=============================================="
echo "  Installed Models"
echo "=============================================="
docker exec ollama ollama list

# =============================================================================
# Start All Services
# =============================================================================

echo ""
echo "[INFO] Starting all services..."
docker compose up -d

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "=============================================="
echo "  Bootstrap Complete!"
echo "=============================================="
echo ""
echo "Services running:"
echo "  - OpenWebUI:    http://localhost:3000"
echo "  - API Endpoint: http://localhost:8000/v1"
echo "  - Ollama:       http://localhost:11434"
echo "  - SearXNG:      http://localhost:8080"
echo ""
echo "To change models, edit models.env and restart:"
echo "  docker compose down && docker compose up -d"
echo ""
