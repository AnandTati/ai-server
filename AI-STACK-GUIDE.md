# AI Stack - Complete Setup Guide

A self-hosted AI stack with LLM-based intent detection, web search, and conversation memory.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Deployment](#deployment)
5. [Configuration](#configuration)
6. [Testing](#testing)
7. [Development](#development)
8. [API Reference](#api-reference)
9. [Troubleshooting](#troubleshooting)
10. [Quick Reference](#quick-reference)

---

## Overview

### Features

- **Smart Router** - LLM-based intent detection routes queries to the best model
- **Web Search** - Automatic web search via SearXNG for current information
- **Conversation Memory** - FAISS-powered semantic memory across sessions
- **Model Indicator** - Shows which model and intent handled each response
- **Remote Coding Agent** - Use from any device on your network (see [CODING-AGENT.md](CODING-AGENT.md))
- **OpenWebUI** - Chat interface at http://localhost:3000 (defaults to "auto")
- **Whisper** - Speech-to-text transcription

### Architecture Diagram

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
│     ┌────────────┼────────────┐                                 │
│     ▼            ▼            ▼                                 │
│ ┌───────┐  ┌──────────┐  ┌─────────┐                            │
│ │SearXNG│  │  Intent  │  │  FAISS  │                            │
│ │ :8080 │  │Detection │  │ Memory  │                            │
│ └───────┘  └──────────┘  └─────────┘                            │
│                  │                                              │
│     ┌────────────┴────────────┐                                 │
│     ▼                         ▼                                 │
│ ┌─────────────┐       ┌─────────────┐                           │
│ │qwen2.5-coder│       │  qwen2.5    │                           │
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

### Request Processing Flow

```
┌───────────────────────────────────────────────────────────────────────────┐
│                           REQUEST PROCESSING FLOW                         │
└───────────────────────────────────────────────────────────────────────────┘

  User Query                                                      Response
      │                                                              ▲
      ▼                                                              │
┌───────────────────────────────────────────────────────────────────────────┐
│                            SMART ROUTER                                   │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  1. LLM INTENT CLASSIFICATION                                             │
│     ┌─────────────────────────────────────────────────────────────┐       │
│     │  "What is the current Python version?" ──► SEARCH           │       │
│     │  "Write a Python function to sort"     ──► CODING           │       │
│     │  "Summarize this article"              ──► SUMMARIZE        │       │
│     │  "What is the capital of France?"      ──► GENERAL          │       │
│     └─────────────────────────────────────────────────────────────┘       │
│                              │                                            │
│                              ▼                                            │
│  2. WEB SEARCH (if SEARCH intent)                                         │
│     ┌─────────────────────────────────────────────────────────────┐       │
│     │  Query ──► SearXNG ──► Top 3 Results ──► Inject as Context  │       │
│     └─────────────────────────────────────────────────────────────┘       │
│                              │                                            │
│                              ▼                                            │
│  3. RETRIEVE MEMORY (FAISS)                                               │
│     ┌─────────────────────────────────────────────────────────────┐       │
│     │  Query ──► Embedding ──► FAISS Search ──► Similar Messages  │       │
│     └─────────────────────────────────────────────────────────────┘       │
│                              │                                            │
│                              ▼                                            │
│  4. ROUTE TO MODEL                                                        │
│     ┌─────────────────────────────────────────────────────────────┐       │
│     │  CODING ────────► qwen2.5-coder:14b                         │       │
│     │  SEARCH ────────► qwen2.5:14b (with web results)            │       │
│     │  SUMMARIZE ─────► qwen2.5:14b                               │       │
│     │  GENERAL ───────► qwen2.5:14b                               │       │
│     └─────────────────────────────────────────────────────────────┘       │
│                              │                                            │
│                              ▼                                            │
│  5. ADD MODEL INDICATOR + STORE IN MEMORY                                 │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

### Model Configuration (Optimized for 12GB VRAM)

| Model | Purpose | VRAM |
|-------|---------|------|
| `qwen2.5-coder:14b` | Coding + Technical | ~9GB |
| `qwen2.5:14b` | General + Search + Summarization | ~9GB |
| `nomic-embed-text` | Embeddings for FAISS memory | ~274MB |

---

## Prerequisites

### Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| GPU VRAM | 8GB | 12GB+ |
| RAM | 16GB | 32GB |
| Storage | 50GB | 100GB+ |
| GPU | RTX 3060 | RTX 4070/5070+ |

### Software Requirements

- Docker with NVIDIA GPU support
- Docker Compose v2+
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
chmod +x tests/test_suite.sh
```

### 3. Run Bootstrap (First-time Setup)

```bash
./bootstrap.sh
```

**What bootstrap does:**

1. Creates data directories:
   - `data/ollama/` - Model weights
   - `data/openwebui/` - Chat history
   - `data/smart-router/` - FAISS memory
   - `data/searxng/` - Search config

2. Starts Ollama container temporarily

3. Pulls required models:
   - `qwen2.5-coder:14b` (coding) ~9GB
   - `qwen2.5:14b` (general) ~9GB
   - `nomic-embed-text` (embeddings) ~274MB

4. Starts all services

**Note:** This downloads ~20GB of model data. First run takes time.

---

## Deployment

### Option 1: Manual Start/Stop

```bash
# Start the stack
./ai-on.sh

# Stop the stack
./ai-off.sh
```

### Option 2: Systemd Service (Recommended for Auto-Start)

```bash
# Install the service
sudo ./install-service.sh

# Service commands
sudo systemctl enable ai-stack   # Enable auto-start on boot
sudo systemctl start ai-stack    # Start now
sudo systemctl stop ai-stack     # Stop
sudo systemctl status ai-stack   # Check status
sudo systemctl disable ai-stack  # Disable auto-start
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
| OpenWebUI | http://localhost:3000 | Web chat (default model: auto) |
| Smart Router | http://localhost:8000 | API endpoint |
| SearXNG | http://localhost:8080 | Web search interface |
| Ollama | http://localhost:11434 | Direct LLM access |
| Whisper | http://localhost:9000 | Speech-to-text (localhost only) |

---

## Configuration

### Single Source of Truth: models.env

All model settings are in `models.env`:

```env
# Models
CODING_MODEL=qwen2.5-coder:14b
GENERAL_MODEL=qwen2.5:14b
EMBEDDING_MODEL=nomic-embed-text

# Service URLs (internal Docker network)
OLLAMA_BASE_URL=http://ollama:11434
SEARXNG_URL=http://searxng:8080
```

### OpenWebUI Settings (docker-compose.yml)

```yaml
openwebui:
  environment:
    OPENAI_API_BASE_URL: http://router:8000/v1
    OPENAI_API_KEY: local-ai
    DEFAULT_MODELS: "auto"                    # Default to smart routing
    ENABLE_RAG_WEB_SEARCH: "true"
    RAG_WEB_SEARCH_ENGINE: "searxng"
    SEARXNG_QUERY_URL: "http://searxng:8080/search?q=<query>&format=json"
```

### Changing Models

1. Edit `models.env`:
   ```env
   CODING_MODEL=your-new-coder-model
   GENERAL_MODEL=your-new-general-model
   ```

2. Pull the new model:
   ```bash
   docker exec ollama ollama pull <model-name>
   ```

3. Rebuild and restart router:
   ```bash
   docker compose build router
   docker compose up -d router
   ```

### Managing Ollama Models

```bash
# List installed models
docker exec ollama ollama list

# Pull a new model
docker exec ollama ollama pull <model-name>

# Delete unused model
docker exec ollama ollama rm <model-name>

# Show model info
docker exec ollama ollama show <model-name>
```

---

## Testing

### Run the Full Test Suite

```bash
./tests/test_suite.sh           # Run all 31 tests
./tests/test_suite.sh --quick   # Skip LLM-dependent tests
./tests/test_suite.sh --verbose # Show detailed output
```

### Test Categories (31 tests)

| # | Category | Tests | Description |
|---|----------|-------|-------------|
| 1 | Health & Infrastructure | 5 | Router, Ollama, SearXNG, OpenWebUI connectivity |
| 2 | Smart Routing | 3 | Coding, general, summarization routing |
| 3 | Conversation History | 1 | Context retention across messages |
| 4 | Web Search | 2 | Manual search, chat search trigger |
| 5 | URL Fetching | 2 | Valid/invalid URL handling |
| 6 | Memory System | 2 | FAISS stats, memory search |
| 7 | API Compatibility | 2 | OpenAI format compliance |
| 8 | Error Handling | 3 | Empty messages, missing fields, invalid JSON |
| 9 | LLM Intent Detection | 7 | CODING, SEARCH, GENERAL, SUMMARIZE intents |
| 10 | Model Indicator Display | 4 | Footer in responses, correct model shown |

### Manual API Testing

```bash
# Health check
curl http://localhost:8000/health

# List models
curl http://localhost:8000/v1/models

# Chat with auto-routing (triggers intent detection)
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "What is the current Python version?"}]
  }'

# Classify intent only (no chat response)
curl -X POST http://localhost:8000/v1/classify \
  -H "Content-Type: application/json" \
  -d '{"query": "Write a Python function to sort a list"}'

# Manual web search
curl -X POST http://localhost:8000/v1/search \
  -H "Content-Type: application/json" \
  -d '{"query": "latest AI news"}'

# Fetch URL content
curl -X POST http://localhost:8000/v1/fetch \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'

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
├── docker-compose.yml          # Main orchestration
├── models.env                  # Model config (single source of truth)
├── bootstrap.sh                # Initial setup
├── ai-on.sh / ai-off.sh        # Start/stop scripts
├── install-service.sh          # Systemd installer
├── ai-stack.service.template   # Service template
├── CODING-AGENT.md             # Remote coding agent setup guide
│
├── smart-router/               # Intelligent routing service
│   ├── Dockerfile
│   └── main.py                 # Router with LLM intent detection
│
├── tests/
│   └── test_suite.sh           # Comprehensive tests (31 tests)
│
├── whisper/
│   └── Dockerfile
│
└── data/                       # Persistent data (gitignored)
    ├── ollama/                 # Model weights (~20GB+)
    ├── openwebui/              # Chat history & settings
    ├── smart-router/           # FAISS + SQLite
    │   ├── memory.faiss        # Vector embeddings
    │   └── memory.db           # Message metadata
    └── searxng/                # Search config
        └── settings.yml
```

### Making Code Changes

```bash
# Edit router code
vim smart-router/main.py

# Rebuild the container
docker compose build router

# Restart with new code
docker compose up -d router

# Run tests to verify
./tests/test_suite.sh
```

### LLM-Based Intent Classification

The router uses the LLM itself to classify queries (not keyword matching):

```python
INTENT_CLASSIFICATION_PROMPT = """Classify this user query into exactly ONE category.
Reply with ONLY the category name, nothing else.

Categories:
- SEARCH: Query needs current/real-time information from the web (news, current
  versions, recent events, prices, weather, live data, anything that changes over time)
- CODING: Query is about programming, code, debugging, software development,
  technical implementation
- SUMMARIZE: Query asks to summarize, condense, or extract key points from text
- GENERAL: All other queries (facts, explanations, creative writing, general knowledge)

Query: "{query}"
Category:"""
```

### Intent Routing Table

| Intent | Routes To | Web Search | Use Case |
|--------|-----------|------------|----------|
| CODING | qwen2.5-coder:14b | No | Code generation, debugging |
| SEARCH | qwen2.5:14b | Yes | Current events, versions, news |
| SUMMARIZE | qwen2.5:14b | No | Text condensation |
| GENERAL | qwen2.5:14b | No | Facts, explanations |

### Model Indicator

When using "auto" model, responses include a footer:

```
---
*🤖 Model: qwen2.5-coder:14b | Intent: coding*
```

This helps verify queries are being routed correctly.

---

## API Reference

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/v1/models` | List models (auto, qwen2.5-coder, qwen2.5) |
| POST | `/v1/chat/completions` | Chat (OpenAI compatible) |
| POST | `/v1/classify` | Classify query intent |
| POST | `/v1/search` | Web search via SearXNG |
| POST | `/v1/fetch` | Fetch and parse URL content |
| GET | `/v1/memory/stats` | Memory statistics |
| POST | `/v1/memory/search` | Search conversation memory |

### Chat Request Format

```json
{
  "model": "auto",
  "messages": [
    {"role": "system", "content": "You are helpful."},
    {"role": "user", "content": "What is the current Python version?"}
  ],
  "stream": false,
  "user": "default"
}
```

**Model options:**

| Model | Description |
|-------|-------------|
| `auto` | LLM-based intent detection + smart routing (recommended) |
| `qwen2.5-coder:14b` | Force coding model (bypasses intent detection) |
| `qwen2.5:14b` | Force general model (bypasses intent detection) |

### Chat Response Format

```json
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "qwen2.5-coder:14b",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "Response text...\n\n---\n*🤖 Model: qwen2.5-coder:14b | Intent: coding*"
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 100,
    "completion_tokens": 50,
    "total_tokens": 150
  }
}
```

### Classify Request/Response

**Request:**
```json
{"query": "Write a Python function to sort a list"}
```

**Response:**
```json
{"intent": "CODING", "needs_search": false}
```

### Search Request/Response

**Request:**
```json
{"query": "latest Python news", "num_results": 5}
```

**Response:**
```json
{
  "query": "latest Python news",
  "results": [
    {"title": "...", "url": "...", "snippet": "..."},
    ...
  ]
}
```

### Memory Stats Response

```json
{
  "total_messages": 150,
  "faiss_vectors": 300,
  "unique_users": 1,
  "embedding_cache_size": 50
}
```

---

## Troubleshooting

### Check Logs

```bash
# Router logs (shows intent detection and routing)
docker logs ai-router -f

# Filter for intent classification
docker logs ai-router -f 2>&1 | grep Intent

# All service logs
docker compose logs -f

# Specific service
docker compose logs -f ollama
docker compose logs -f searxng
```

### Common Issues

#### Web search not triggering

**Symptoms:** Getting outdated answers for current info questions

**Solution:**
1. Make sure "auto" model is selected in OpenWebUI (not a specific model)
2. Check logs: `docker logs ai-router -f | grep Intent`
3. Should see: `[Intent] LLM classified as SEARCH`
4. Specific models bypass intent detection entirely

#### Wrong model being used

**Symptoms:** Coding questions not going to coder model

**Solution:**
1. Use "auto" model to enable smart routing
2. Check the model indicator in the response footer
3. Verify logs show correct intent classification

#### GPU not detected

```bash
# Verify GPU is visible
nvidia-smi

# Test Docker GPU access
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi

# Check Ollama GPU usage
docker logs ollama | grep -i gpu
```

#### Memory issues

```bash
# Check memory stats
curl http://localhost:8000/v1/memory/stats

# Reset memory completely
rm data/smart-router/memory.*
docker compose restart router
```

#### Services not starting

```bash
# Check container status
docker compose ps

# Check specific service logs
docker compose logs ollama
docker compose logs router
docker compose logs openwebui
docker compose logs searxng
```

#### Restart everything

```bash
docker compose down
docker compose up -d
```

#### Rebuild everything

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

---

## Quick Reference

### Commands

| Action | Command |
|--------|---------|
| Start | `./ai-on.sh` or `docker compose up -d` |
| Stop | `docker compose down` |
| Logs | `docker logs ai-router -f` |
| Test | `./tests/test_suite.sh` |
| Health | `curl http://localhost:8000/health` |
| Memory Stats | `curl http://localhost:8000/v1/memory/stats` |
| Rebuild Router | `docker compose build router && docker compose up -d router` |
| Reset Memory | `rm data/smart-router/memory.* && docker compose restart router` |

### URLs

| Service | URL |
|---------|-----|
| Web Chat | http://localhost:3000 |
| API | http://localhost:8000/v1 |
| Web Search | http://localhost:8080 |
| Ollama | http://localhost:11434 |

### File Locations

| File | Purpose |
|------|---------|
| `models.env` | Model configuration |
| `docker-compose.yml` | Service orchestration |
| `smart-router/main.py` | Router logic |
| `tests/test_suite.sh` | Test suite |
| `data/ollama/` | Model weights (~20GB+) |
| `data/openwebui/` | Chat history, user accounts |
| `data/smart-router/memory.faiss` | Vector embeddings |
| `data/smart-router/memory.db` | Message metadata (SQLite) |
| `data/searxng/settings.yml` | Search engine config |

### Backup & Restore

```bash
# Backup all data
tar -czvf ai-stack-backup.tar.gz data/

# Restore
tar -xzvf ai-stack-backup.tar.gz
```
