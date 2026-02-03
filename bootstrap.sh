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
#   3. Pulls LLM models for different task types:
#      - deepseek-coder: For programming and code-related tasks
#      - qwen2.5: For summarization and text condensation
#      - llama3.1: For general conversation and Q&A
#   4. Pulls embedding model for FAISS memory:
#      - nomic-embed-text: Generates 768-dim vectors for semantic search
#   5. Stops Ollama service
#
# Requirements:
#   - Docker and Docker Compose installed
#   - NVIDIA GPU with drivers (for GPU acceleration)
#   - ~25GB disk space for models
#   - Internet connection for downloading models
#
# Usage:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh
#
# =============================================================================

set -euo pipefail

# Get the directory where this script is located
# This makes the script work regardless of where it is called from
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================================================
# Model Configuration
# =============================================================================
# These model names MUST match the docker-compose.yml environment variables.
# If you change models here, update docker-compose.yml to match.

# Coding model: DeepSeek Coder 6.7B (Q4_K_M quantization)
# - Optimized for code generation, debugging, and programming tasks
# - Q4_K_M quantization: Good balance of quality and VRAM usage (~4GB)
CODING_MODEL="deepseek-coder:6.7b-instruct-q4_K_M"

# Summarization model: Qwen 2.5 7B (Q4_K_M quantization)
# - Excellent at condensing long text into concise summaries
# - Good instruction-following for structured outputs
SUMMARY_MODEL="qwen2.5:7b-instruct-q4_K_M"

# General model: Llama 3.1 8B (Q4_K_M quantization)
# - Well-rounded model for general conversation
# - Good at reasoning, Q&A, and creative tasks
GENERAL_MODEL="llama3.1:8b-instruct-q4_K_M"

# Embedding model: Nomic Embed Text
# - Generates 768-dimensional vectors for semantic similarity
# - Used by FAISS for conversation memory retrieval
# - Lightweight (~274MB) and fast
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

# Wait for Ollama to be ready (accepts connections)
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

# Check for Docker
command -v docker >/dev/null || { print_error "Docker is not installed"; exit 1; }

# Check for Docker Compose
docker compose version >/dev/null 2>&1 || { print_error "Docker Compose not available"; exit 1; }

# =============================================================================
# Create Data Directories
# =============================================================================
# These directories store all persistent data:
# - data/ollama:       Downloaded model weights (~20GB+)
# - data/openwebui:    User accounts and chat history
# - data/smart-router: FAISS index and SQLite database for conversation memory

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
# We only need Ollama running to pull models.

print_status "Starting Ollama Service"

docker compose up -d ollama

if \! wait_for_ollama; then
    print_error "Failed to start Ollama. Check: docker compose logs ollama"
    exit 1
fi

# =============================================================================
# Pull AI Models
# =============================================================================
# Models are pulled in order of importance.

print_status "Pulling AI Models"
print_info "This will download approximately 20-25GB of model data."

# Pull embedding model first (smallest, needed for memory)
pull_model "$EMBEDDING_MODEL" "Embedding (FAISS memory)"

# Pull LLM models
pull_model "$CODING_MODEL" "Coding"
pull_model "$SUMMARY_MODEL" "Summarization"
pull_model "$GENERAL_MODEL" "General"

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

echo "Models installed:"
echo "  - $CODING_MODEL (coding tasks)"
echo "  - $SUMMARY_MODEL (summarization)"
echo "  - $GENERAL_MODEL (general chat)"
echo "  - $EMBEDDING_MODEL (FAISS memory)"
echo ""
echo "Data stored in: $SCRIPT_DIR/data/"
echo ""
echo "Next steps:"
echo "  1. Start the stack:    ./ai-on.sh"
echo "  2. Open browser:       http://localhost:3000"
echo "  3. Create account and start chatting\!"
echo ""
