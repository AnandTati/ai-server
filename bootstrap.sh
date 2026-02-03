#!/usr/bin/env bash
set -euo pipefail

echo "▶ Bootstrapping AI stack..."

# ---- sanity checks ----
command -v docker >/dev/null || { echo "Docker missing"; exit 1; }
command -v python3 >/dev/null || { echo "Python3 missing"; exit 1; }

# ---- python deps (isolated) ----
if [ ! -d ".venv" ]; then
  echo "▶ Creating virtualenv"
  python3 -m venv .venv
fi

source .venv/bin/activate

echo "▶ Installing Python deps"
pip install --upgrade pip >/dev/null
pip install python-dotenv pyyaml jinja2 requests >/dev/null

# ---- start ollama only ----
echo "▶ Starting Ollama"
docker compose up -d ollama

# ---- init models ----
echo "▶ Initializing models"
python init_models.py

# ---- start rest of stack ----
echo "▶ Starting router + UI"
docker compose up -d

echo "✅ Stack ready"
