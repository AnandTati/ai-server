# AI Stack - Complete Setup Guide

A self-hosted AI stack with intelligent query routing and conversation memory.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Deployment](#deployment)
5. [Testing](#testing)
6. [Development](#development)
7. [API Reference](#api-reference)
8. [Troubleshooting](#troubleshooting)

---

## Overview

### Features
- **Ollama** - Local LLM backend (GPU accelerated)
- **Smart Router** - Auto-routes queries to the best model + FAISS memory
- **OpenWebUI** - Chat interface at http://localhost:3000
- **Whisper** - Speech-to-text

### Architecture
```
┌─────────────────────────────────────────────────────────────────┐
│                         USER ACCESS                             │
├─────────────────────────────────────────────────────────────────┤
│  Browser (:3000)       API Client (:8000)      Voice (:9000)    │
│       │                      │                      │           │
│       ▼                      ▼                      ▼           │
│  ┌─────────┐           ┌──────────┐           ┌─────────┐       │
│  │OpenWebUI│           │API Direct│           │ Whisper │       │
│  └────┬────┘           └────┬─────┘           └────┬────┘       │
│       │                     │                      │            │
│       └──────────┬──────────┘                      │            │
│                  ▼                                 │            │
│          ┌───────────────┐                         │            │
│          │ Smart Router  │◄────────────────────────┘            │
│          │   (:8000)     │                                      │
│          └───────┬───────┘                                      │
│                  │                                              │
│     ┌────────────┴────────────┐                                 │
│     ▼                         ▼                                 │
│ ┌─────────────┐       ┌─────────────┐                           │
│ │deepseek-r1  │       │   qwen3     │                           │
│ │  (coding)   │       │  (general)  │                           │
│ └──────┬──────┘       └──────┬──────┘                           │
│        └───────────┬─────────┘                                  │
│                    ▼                                            │
│            ┌───────────────┐                                    │
│            │    Ollama     │                                    │
│            │   (:11434)    │                                    │
│            │    [GPU]      │                                    │
│            └───────────────┘                                    │
└─────────────────────────────────────────────────────────────────┘
```

### 2-Model Setup (Optimized for 12GB VRAM)

| Model | Purpose | VRAM |
|-------|---------|------|
| `deepseek-r1:14b` | Coding + Reasoning | ~9GB |
| `qwen3:8b` | General Chat + Summarization | ~5GB |
| `nomic-embed-text` | Embeddings for FAISS memory | ~274MB |

---

## Prerequisites

### Hardware Requirements
| Component | Minimum | Recommended |
|-----------|---------|-------------|
| GPU VRAM | 8GB | 12GB+ |
| RAM | 16GB | 32GB |
| Storage | 50GB | 100GB+ |

### Software Requirements
- Docker with NVIDIA GPU support
- Docker Compose
- Python 3.x
- NVIDIA drivers + CUDA

### Verify GPU Setup
```bash
# Check NVIDIA driver
nvidia-smi

# Check Docker GPU access
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

---

## Installation

### 1. Clone the Repository
```bash
cd ~
git clone <repository-url> ai-stack
cd ai-stack
```

### 2. Make Scripts Executable
```bash
chmod +x bootstrap.sh ai-on.sh ai-off.sh install-service.sh
chmod +x tests/run_tests.sh
```

### 3. Run Bootstrap (First-time Setup)
```bash
./bootstrap.sh
```

**What bootstrap does:**
1. Creates data directories (`data/ollama/`, `data/openwebui/`, `data/smart-router/`)
2. Starts Ollama container temporarily
3. Pulls required models:
   - `deepseek-r1:14b` (coding + reasoning)
   - `qwen3:8b` (general + summarization)
   - `nomic-embed-text` (embeddings for FAISS)
4. Cleans up any unused models
5. Stops services

**Note:** This downloads ~15GB of model data.

---

## Deployment

### Option 1: Manual Start/Stop

**Start the stack:**
```bash
./ai-on.sh
```

**Stop the stack:**
```bash
./ai-off.sh
```

**Note:** `ai-off.sh` also shuts down the system. Edit it if you only want to stop containers.

### Option 2: Systemd Service (Recommended for Auto-Start)

**Install the service:**
```bash
sudo ./install-service.sh
```

**Service commands:**
```bash
# Enable auto-start on boot
sudo systemctl enable ai-stack

# Start now
sudo systemctl start ai-stack

# Check status
sudo systemctl status ai-stack

# Stop
sudo systemctl stop ai-stack

# Disable auto-start
sudo systemctl disable ai-stack
```

### Option 3: Docker Compose Directly
```bash
# Start
docker compose up -d

# Stop
docker compose down

# View logs
docker compose logs -f

# View specific service logs
docker compose logs -f router
docker compose logs -f ollama
```

### Access Points
| Service | URL | Description |
|---------|-----|-------------|
| OpenWebUI | http://localhost:3000 | Web chat interface |
| Smart Router | http://localhost:8000 | API endpoint |
| Ollama | http://localhost:11434 | Direct LLM access |
| Whisper | http://localhost:9000 | Speech-to-text (localhost only) |

---

## Testing

### Run the Full Test Suite
```bash
./tests/run_tests.sh
```

### Test Coverage (19 tests)

**Basic Health & API:**
- Health check endpoint
- Model list endpoint
- Memory stats endpoint

**Routing Tests - Coding:**
- Python query → deepseek-r1
- Debug query → deepseek-r1
- Function query → deepseek-r1

**Routing Tests - General:**
- Greeting → qwen3
- Question → qwen3
- Ideas query → qwen3

**Routing Tests - Summarization:**
- Summarize query → qwen3
- TL;DR query → qwen3

**Word Boundary Tests:**
- "Jason" (name) should NOT trigger coding (json keyword)
- "math class" should NOT trigger coding (class keyword)

**Streaming Tests:**
- Basic streaming response
- Streaming with coding query

**Response Tests:**
- Required OpenAI fields present
- Message content not empty

**Error Handling:**
- Empty messages returns 400/422
- Invalid JSON returns error

### Manual API Testing

```bash
# Health check
curl http://localhost:8000/health

# List models
curl http://localhost:8000/v1/models

# Chat (auto-routing)
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "Write a python function"}],
    "stream": false
  }'

# Chat (specific model)
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3:8b",
    "messages": [{"role": "user", "content": "Hello"}],
    "stream": false
  }'

# Streaming chat
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "Tell me a joke"}],
    "stream": true
  }'

# Memory stats
curl http://localhost:8000/v1/memory/stats

# Search memory
curl -X POST http://localhost:8000/v1/memory/search \
  -H "Content-Type: application/json" \
  -d '{"query": "python debugging", "k": 5}'
```

---

## Development

### Project Structure
```
ai-stack/
├── docker-compose.yml            # Main orchestration file
├── bootstrap.sh                  # Initial setup script
├── ai-on.sh                      # Start script
├── ai-off.sh                     # Stop script
├── install-service.sh            # Systemd service installer
├── ai-stack.service.template     # Service template
├── README.md
│
├── smart-router/                 # Intelligent routing service
│   ├── Dockerfile
│   ├── main.py                   # Router logic with FAISS memory
│   └── requirements.txt
│
├── tests/
│   └── run_tests.sh              # Test suite (19 tests)
│
├── ollama/                       # Ollama configuration
│   ├── models.env
│   └── models.yaml
│
├── whisper/                      # Speech-to-text service
│   └── Dockerfile
│
└── data/                         # Persistent data (gitignored)
    ├── ollama/                   # Model weights (~20GB+)
    ├── openwebui/                # Chat history & settings
    └── smart-router/             # FAISS memory storage
        ├── memory.faiss          # Vector embeddings
        └── memory.db             # Message metadata (SQLite)
```

### Making Code Changes

1. **Edit the smart router:**
   ```bash
   vim smart-router/main.py
   ```

2. **Rebuild the container:**
   ```bash
   docker compose build router
   ```

3. **Restart with new code:**
   ```bash
   docker compose up -d router
   ```

4. **Run tests:**
   ```bash
   ./tests/run_tests.sh
   ```

### Smart Router Classification

**Coding Keywords (routes to deepseek-r1:14b):**
```
code, function, program, script, debug, error, bug, python, javascript,
java, rust, golang, c++, sql, html, css, api, algorithm, data structure,
compile, syntax, variable, loop, array, list, dictionary, object, method,
import, def, async, await, return, print(, console.log, git, docker,
kubernetes, database, query, regex, json, xml, implement, refactor,
optimize, write a, create a, build a, fix this, fix the, how to code,
programming
```

**Summarization Keywords (routes to qwen3:8b):**
```
summarize, summary, summarization, condense, brief, tldr, key points,
main points, overview, recap, synopsis, shorten, reduce, simplify this text,
explain briefly, in short, bullet points, highlight, extract
```

**General (routes to qwen3:8b):**
- Everything else

### Changing Models

1. Edit `docker-compose.yml`:
   ```yaml
   environment:
     - CODING_MODEL=deepseek-r1:14b
     - GENERAL_MODEL=qwen3:8b
     - EMBEDDING_MODEL=nomic-embed-text
   ```

2. Pull the new model:
   ```bash
   docker exec ollama ollama pull <model-name>
   ```

3. Restart router:
   ```bash
   docker compose restart router
   ```

### Managing Models

```bash
# List installed models
docker exec ollama ollama list

# Pull a new model
docker exec ollama ollama pull <model-name>

# Delete unused model
docker exec ollama ollama rm <model-name>
```

---

## API Reference

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/v1/models` | List available models |
| POST | `/v1/chat/completions` | Chat (OpenAI compatible) |
| GET | `/v1/memory/stats` | Memory statistics |
| POST | `/v1/memory/search` | Search conversation memory |

### Chat Request
```json
{
  "model": "auto",
  "messages": [
    {"role": "system", "content": "You are helpful."},
    {"role": "user", "content": "Hello"}
  ],
  "stream": false,
  "user": "default"
}
```

**Model options:**
- `auto` - Let router decide based on query
- `deepseek-r1:14b` - Force coding model
- `qwen3:8b` - Force general model

### Memory Search Request
```json
{
  "query": "search term",
  "user_id": "default",
  "k": 5
}
```

---

## Troubleshooting

### Services Not Starting

```bash
# Check container status
docker compose ps

# Check specific logs
docker compose logs ollama
docker compose logs router
docker compose logs openwebui
```

### GPU Issues

```bash
# Check GPU usage
nvidia-smi

# Verify Docker GPU access
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

### Router Not Connecting to Ollama

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Check router logs
docker compose logs -f router
```

### Out of VRAM

```bash
# Check current GPU memory
nvidia-smi

# Solutions:
# 1. Use smaller models
# 2. Reduce context length
# 3. Stop other GPU applications
```

### Reset FAISS Memory

```bash
rm data/smart-router/memory.*
docker compose restart router
```

### Restart Everything

```bash
docker compose down
docker compose up -d
```

### Backup & Restore

```bash
# Backup all data
tar -czvf ai-stack-backup.tar.gz data/

# Restore
tar -xzvf ai-stack-backup.tar.gz
```

---

## Quick Reference

### Start Stack
```bash
./ai-on.sh
# or
docker compose up -d
```

### Stop Stack
```bash
docker compose down
```

### View Logs
```bash
docker compose logs -f
docker compose logs -f router
```

### Run Tests
```bash
./tests/run_tests.sh
```

### Check Health
```bash
curl http://localhost:8000/health
```

### Access Web UI
Open http://localhost:3000 in browser

---

## File Locations

| File | Purpose |
|------|---------|
| `data/ollama/` | Model weights (~20GB+) |
| `data/openwebui/` | User accounts, chat history |
| `data/smart-router/memory.faiss` | Vector embeddings |
| `data/smart-router/memory.db` | Message metadata (SQLite) |
