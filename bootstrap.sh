#\!/usr/bin/env bash
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
#   3. Pulls LLM models (2-model optimized setup):
#      - deepseek-r1:14b  - For coding and complex reasoning
#      - qwen3:8b         - For general chat and summarization
#   4. Pulls embedding model for FAISS memory:
#      - nomic-embed-text - Generates 768-dim vectors for semantic search
#   5. Stops Ollama service
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

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================================================
# Model Configuration (2-Model Setup)
# =============================================================================
# Optimized for 12GB VRAM - only 2 LLM models needed
# These MUST match docker-compose.yml environment variables

# Coding model: DeepSeek-R1 14B
# - Advanced reasoning capabilities (rivals O3/Gemini 2.5 Pro)
# - Excellent for code generation, debugging, algorithms
# - ~9GB VRAM
CODING_MODEL="deepseek-r1:14b"

# General model: Qwen3 8B
# - Handles general conversation AND summarization
# - Strong multilingual support
# - ~5GB VRAM
GENERAL_MODEL="qwen3:8b"

# Embedding model: Nomic Embed Text
# - Generates 768-dimensional vectors for semantic similarity
# - Used by FAISS for conversation memory retrieval
# - Lightweight (~274MB)
EMBEDDING_MODEL="nomic-embed-text"

# =============================================================================
# Helper Functions
# =============================================================================

print_status() {
    echo ""
    echo "=============================================="
    echo "  $1"
    echo "=============================================="
}

print_info() {
    echo "[INFO] $1"
}

print_error() {
    echo "[ERROR] $1" >&2
}

# Wait for Ollama to be ready
wait_for_ollama() {
    print_info "Waiting for Ollama to be ready..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
            print_info "Ollama is ready\!"
            return 0
        fi
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done

    print_error "Ollama failed to start"
    return 1
}

# Pull a model with progress indication
pull_model() {
    local model_name="$1"
    local model_purpose="$2"

    print_info "Pulling $model_purpose model: $model_name"
    
    if docker compose exec -T ollama ollama pull "$model_name"; then
        print_info "Successfully pulled: $model_name"
        return 0
    else
        print_error "Failed to pull: $model_name"
        return 1
    fi
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

print_status "AI Stack Bootstrap"

command -v docker >/dev/null || { print_error "Docker is not installed"; exit 1; }
docker compose version >/dev/null 2>&1 || { print_error "Docker Compose not available"; exit 1; }

# =============================================================================
# Create Data Directories
# =============================================================================

print_status "Creating Data Directories"

mkdir -p "$SCRIPT_DIR/data/ollama"
mkdir -p "$SCRIPT_DIR/data/openwebui"
mkdir -p "$SCRIPT_DIR/data/smart-router"

print_info "Data directories created:"
print_info "  - data/ollama/        (model weights)"
print_info "  - data/openwebui/     (user data)"
print_info "  - data/smart-router/  (FAISS memory)"

# =============================================================================
# Start Ollama Service
# =============================================================================

print_status "Starting Ollama Service"

docker compose up -d ollama

if \! wait_for_ollama; then
    print_error "Failed to start Ollama. Check: docker compose logs ollama"
    exit 1
fi

# =============================================================================
# Pull AI Models (2-Model Setup)
# =============================================================================

print_status "Pulling AI Models"
print_info "2-model setup optimized for 12GB VRAM"
print_info "This will download approximately 15GB of model data."

# Pull embedding model first (smallest, needed for memory)
pull_model "$EMBEDDING_MODEL" "Embedding (FAISS memory)"

# Pull LLM models
pull_model "$CODING_MODEL" "Coding + Reasoning"
pull_model "$GENERAL_MODEL" "General + Summarization"

# =============================================================================
# Verify Models
# =============================================================================

print_status "Verifying Installed Models"
docker compose exec -T ollama ollama list

# =============================================================================
# Stop Ollama
# =============================================================================

print_status "Stopping Bootstrap Services"
docker compose down

# =============================================================================
# Summary
# =============================================================================

print_status "Bootstrap Complete\!"

echo "Models installed (2-model setup):"
echo "  - $CODING_MODEL (coding + reasoning)"
echo "  - $GENERAL_MODEL (general + summarization)"
echo "  - $EMBEDDING_MODEL (FAISS memory)"
echo ""
echo "Data stored in: $SCRIPT_DIR/data/"
echo ""
echo "Next steps:"
echo "  1. Start the stack:    ./ai-on.sh"
echo "  2. Open browser:       http://localhost:3000"
echo "  3. Create account and start chatting\!"
echo ""

# =============================================================================
# Cleanup Old Models
# =============================================================================
# Remove models that are no longer needed to free up disk space

print_status "Cleaning Up Old Models"

# List of models to keep
KEEP_MODELS="$CODING_MODEL $GENERAL_MODEL $EMBEDDING_MODEL"

# Get all installed models
INSTALLED=$(docker compose exec -T ollama ollama list 2>/dev/null | tail -n +2 | awk "{print \$1}")

for model in $INSTALLED; do
    # Check if model should be kept
    keep=false
    for keep_model in $KEEP_MODELS; do
        if [[ "$model" == "$keep_model" ]]; then
            keep=true
            break
        fi
    done
    
    if [[ "$keep" == "false" ]]; then
        print_info "Removing unused model: $model"
        docker compose exec -T ollama ollama rm "$model" 2>/dev/null || true
    else
        print_info "Keeping model: $model"
    fi
done

print_info "Cleanup complete"
