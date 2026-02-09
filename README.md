# AI Stack

A self-hosted AI stack with intelligent LLM-based query routing, web search, and conversation memory.

## Features

- **Smart Router** - LLM-based intent detection routes queries to the best model
- **Web Search** - Automatic web search via SearXNG for current information queries
- **Conversation Memory** - FAISS-powered semantic memory across sessions
- **Model Indicator** - Shows which model and intent handled each response
- **Remote Coding Agent** - Use from any device on your network ([setup guide](CODING-AGENT.md))
- **Ollama** - Local LLM backend with GPU acceleration
- **OpenWebUI** - Chat interface (defaults to "auto" routing)
- **SearXNG** - Self-hosted privacy-respecting web search
- **Whisper** - Speech-to-text transcription

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER ACCESS                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│    Browser (:3000)          API Client (:8000)         Voice (:9000)        │
│         │                         │                         │               │
│         ▼                         ▼                         ▼               │
│    ┌─────────┐              ┌──────────┐              ┌─────────┐           │
│    │OpenWebUI│              │API Direct│              │ Whisper │           │
│    └────┬────┘              └────┬─────┘              └────┬────┘           │
│         │                        │                         │                │
│         └────────────┬───────────┘                         │                │
│                      ▼                                     │                │
│              ┌───────────────┐                             │                │
│              │ Smart Router  │◄────────────────────────────┘                │
│              │   (:8000)     │         (speech-to-text)                     │
│              └───────┬───────┘                                              │
│                      │                                                      │
│         ┌────────────┼────────────┐                                         │
│         ▼            ▼            ▼                                         │
│    ┌─────────┐ ┌──────────┐ ┌─────────┐                                     │
│    │ SearXNG │ │  LLM     │ │  FAISS  │                                     │
│    │ (:8080) │ │ Intent   │ │ Memory  │                                     │
│    │  Web    │ │Detection │ │ System  │                                     │
│    │ Search  │ │          │ │         │                                     │
│    └─────────┘ └──────────┘ └─────────┘                                     │
│                      │                                                      │
│         ┌────────────┴────────────┐                                         │
│         ▼                         ▼                                         │
│  ┌──────────────┐        ┌──────────────┐                                   │
│  │qwen2.5-coder │        │   qwen2.5    │                                   │
│  │    :14b      │        │    :14b      │                                   │
│  │  (coding)    │        │  (general)   │                                   │
│  └──────┬───────┘        └──────┬───────┘                                   │
│         └───────────┬───────────┘                                           │
│                     ▼                                                       │
│             ┌───────────────┐                                               │
│             │    Ollama     │                                               │
│             │   (:11434)    │                                               │
│             │    [GPU]      │                                               │
│             └───────────────┘                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Request Processing Flow

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
│     │  Query sent to LLM with classification prompt               │       │
│     │                                                             │       │
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
│     │                                                             │       │
│     │  [Web Search Results]                                       │       │
│     │  1. Python 3.14 released October 2025...                    │       │
│     │  2. Python version history...                               │       │
│     │  3. Download Python...                                      │       │
│     └─────────────────────────────────────────────────────────────┘       │
│                              │                                            │
│                              ▼                                            │
│  3. RETRIEVE MEMORY (FAISS)                                               │
│     ┌─────────────────────────────────────────────────────────────┐       │
│     │  Query ──► Embedding ──► FAISS Search ──► Similar Messages  │       │
│     │                                              │              │       │
│     │                              ┌───────────────┘              │       │
│     │                              ▼                              │       │
│     │                    Inject as context                        │       │
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
│  5. ADD MODEL INDICATOR (when using "auto")                               │
│     ┌─────────────────────────────────────────────────────────────┐       │
│     │  Response + "\n\n---\n*🤖 Model: X | Intent: Y*"            │       │
│     └─────────────────────────────────────────────────────────────┘       │
│                              │                                            │
│                              ▼                                            │
│  6. STORE IN MEMORY                                                       │
│     ┌─────────────────────────────────────────────────────────────┐       │
│     │  User message ──► Embedding ──► FAISS Index                 │       │
│     │  Assistant response ──► Embedding ──► FAISS Index           │       │
│     │  Metadata ──► SQLite (timestamp, model, intent)             │       │
│     └─────────────────────────────────────────────────────────────┘       │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## Memory Architecture (FAISS + SQLite)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         CONVERSATION MEMORY SYSTEM                           │
└──────────────────────────────────────────────────────────────────────────────┘

                         ┌─────────────────┐
                         │  User Message   │
                         └────────┬────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │   nomic-embed-text      │
                    │   (Embedding Model)     │
                    │   768 dimensions        │
                    └────────────┬────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
                    ▼                         ▼
    ┌───────────────────────┐   ┌───────────────────────┐
    │     FAISS Index       │   │    SQLite Database    │
    │  (memory.faiss)       │   │    (memory.db)        │
    ├───────────────────────┤   ├───────────────────────┤
    │                       │   │                       │
    │  ┌─────────────────┐  │   │  ┌─────────────────┐  │
    │  │ Vector [0.12,   │  │   │  │ id: 1           │  │
    │  │  0.45, -0.23,   │  │   │  │ faiss_id: 0     │  │
    │  │  ... 768 dims]  │  │   │  │ role: user      │  │
    │  └─────────────────┘  │   │  │ content: "..."  │  │
    │  ┌─────────────────┐  │   │  │ timestamp: ...  │  │
    │  │ Vector [...]    │  │   │  │ model_used: ... │  │
    │  └─────────────────┘  │   │  │ query_type: ... │  │
    │  ┌─────────────────┐  │   │  └─────────────────┘  │
    │  │ Vector [...]    │  │   │  ┌─────────────────┐  │
    │  └─────────────────┘  │   │  │ id: 2           │  │
    │         ...           │   │  │ ...             │  │
    │                       │   │  └─────────────────┘  │
    └───────────────────────┘   └───────────────────────┘
              │                           │
              │      SIMILARITY SEARCH    │
              │◄──────────────────────────┤
              │                           │
              ▼                           │
    ┌───────────────────┐                 │
    │ Top K Similar IDs │─────────────────┘
    └───────────────────┘        METADATA LOOKUP
              │
              ▼
    ┌───────────────────────┐
    │ Relevant Context      │
    │ Injected into Prompt  │
    └───────────────────────┘
```

---

## Container Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DOCKER COMPOSE STACK                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         ai-net (bridge network)                     │    │
│  ├─────────────────────────────────────────────────────────────────────┤    │
│  │                                                                     │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │    │
│  │  │   ollama     │  │  ai-router   │  │  openwebui   │               │    │
│  │  │              │  │              │  │              │               │    │
│  │  │ :11434 ◄─────┼──┤ :8000  ◄─────┼──┤ :3000        │               │    │
│  │  │              │  │              │  │              │               │    │
│  │  │ [GPU]        │  │ [FAISS]      │  │ [WebUI]      │               │    │
│  │  │ LLM Engine   │  │ Intent+Route │  │ Chat UI      │               │    │
│  │  └──────┬───────┘  └──────┬───────┘  └──────────────┘               │    │
│  │         │                 │                                         │    │
│  │  ┌──────────────┐         │                                         │    │
│  │  │   searxng    │◄────────┘                                         │    │
│  │  │   :8080      │  (web search)                                     │    │
│  │  │ [Search]     │                                                   │    │
│  │  └──────────────┘                                                   │    │
│  │                                                                     │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         VOLUMES (./data/)                           │    │
│  ├────────────────┬────────────────┬──────────────────┬────────────────┤    │
│  │ data/ollama/   │ data/smart-    │ data/openwebui/  │ data/searxng/  │    │
│  │                │ router/        │                  │                │    │
│  │ - Model weights│ - memory.faiss │ - User accounts  │ - settings.yml │    │
│  │ - Config       │ - memory.db    │ - Chat history   │ - Search prefs │    │
│  │ (~20GB+)       │ (~few MB)      │ - Settings       │                │    │
│  └────────────────┴────────────────┴──────────────────┴────────────────┘    │
│                                                                             │
│  ┌──────────────┐                                                           │
│  │   whisper    │  (separate, localhost only :9000)                         │
│  │   [GPU]      │                                                           │
│  │ Speech-to-   │                                                           │
│  │ Text         │                                                           │
│  └──────────────┘                                                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Smart Routing - LLM Intent Detection

Unlike keyword-based routing, the Smart Router uses the LLM itself to understand query intent:

### Intent Classification Prompt

```
Classify this user query into exactly ONE category. Reply with ONLY the category name.

Categories:
- SEARCH: Query needs current/real-time information from the web (news, current
  versions, recent events, prices, weather, live data, anything that changes over time)
- CODING: Query is about programming, code, debugging, software development,
  technical implementation
- SUMMARIZE: Query asks to summarize, condense, or extract key points from text
- GENERAL: All other queries (facts, explanations, creative writing, general knowledge)

Query: "{user_query}"
Category:
```

### Routing Table

| Intent | Model | Web Search | Use Case |
|--------|-------|------------|----------|
| **CODING** | qwen2.5-coder:14b | No | Code generation, debugging, technical questions |
| **SEARCH** | qwen2.5:14b | Yes | Current events, latest versions, prices, weather |
| **SUMMARIZE** | qwen2.5:14b | No | Condensing text, extracting key points |
| **GENERAL** | qwen2.5:14b | No | Facts, explanations, creative writing |

### Model Indicator

When using "auto" model, every response includes a footer showing:
```
---
*🤖 Model: qwen2.5-coder:14b | Intent: coding*
```

This helps you verify that queries are being routed correctly.

---

## Folder Structure

```
ai-stack/
├── docker-compose.yml          # Main orchestration file
├── models.env                  # Model configuration (SINGLE SOURCE OF TRUTH)
├── bootstrap.sh                # Initial setup script
├── ai-on.sh                    # Manual start script
├── ai-off.sh                   # Manual stop script
├── install-service.sh          # Systemd service installer
├── ai-stack.service.template   # Service template (portable)
├── README.md                   # This file
├── AI-STACK-GUIDE.md           # Detailed setup guide
├── CODING-AGENT.md             # Remote coding agent setup
│
├── smart-router/               # Intelligent routing service
│   ├── Dockerfile
│   └── main.py                 # Router logic (LLM intent + FAISS memory)
│
├── tests/
│   └── test_suite.sh           # Comprehensive test suite (31 tests)
│
├── whisper/                    # Speech-to-text service
│   └── Dockerfile
│
└── data/                       # Persistent data (gitignored)
    ├── ollama/                 # Model weights (~20GB+)
    ├── openwebui/              # Chat history & settings
    ├── smart-router/           # FAISS memory storage
    │   ├── memory.faiss        # Vector embeddings
    │   └── memory.db           # Message metadata (SQLite)
    └── searxng/                # Search engine config
        └── settings.yml
```

---

## Services & Ports

| Service | Container | Port | Description |
|---------|-----------|------|-------------|
| Ollama | ollama | 11434 | LLM inference engine (GPU) |
| Smart Router | ai-router | 8000 | Intent detection + routing + memory |
| OpenWebUI | openwebui | 3000 | Web chat interface |
| SearXNG | searxng | 8080 | Self-hosted web search |
| Whisper | whisper | 9000 (localhost) | Speech-to-text |

---

## Configuration

### Model Configuration (models.env)

All model settings are in a single file `models.env`:

```env
# Models
CODING_MODEL=qwen2.5-coder:14b
GENERAL_MODEL=qwen2.5:14b
EMBEDDING_MODEL=nomic-embed-text

# Service URLs (internal Docker network)
OLLAMA_BASE_URL=http://ollama:11434
SEARXNG_URL=http://searxng:8080
```

### OpenWebUI Configuration

OpenWebUI is configured via environment variables in `docker-compose.yml`:

```yaml
environment:
  OPENAI_API_BASE_URL: http://router:8000/v1
  OPENAI_API_KEY: local-ai
  DEFAULT_MODELS: "auto"                    # Default to auto-routing
  ENABLE_RAG_WEB_SEARCH: "true"
  RAG_WEB_SEARCH_ENGINE: "searxng"
  SEARXNG_QUERY_URL: "http://searxng:8080/search?q=<query>&format=json"
```

---

## Setup Instructions

### Prerequisites

- Docker with NVIDIA GPU support
- Docker Compose v2+
- NVIDIA GPU with 12GB+ VRAM (RTX 3080, 4070, 5070 or better)
- 32GB RAM recommended
- 100GB+ storage

### 1. Bootstrap (First-time Setup)

```bash
cd ~/ai-stack
chmod +x bootstrap.sh ai-on.sh ai-off.sh install-service.sh
./bootstrap.sh
```

**What bootstrap does:**
1. Creates data directories
2. Starts Ollama container
3. Pulls required models:
   - qwen2.5-coder:14b (coding) ~9GB
   - qwen2.5:14b (general) ~9GB
   - nomic-embed-text (embeddings) ~274MB
4. Starts all services (router, openwebui, searxng, whisper)

### 2. Enable Auto-Start (Systemd)

```bash
sudo ./install-service.sh
```

**Systemd commands:**
```bash
sudo systemctl enable ai-stack   # Enable auto-start on boot
sudo systemctl start ai-stack    # Start now
sudo systemctl stop ai-stack     # Stop
sudo systemctl status ai-stack   # Check status
sudo systemctl disable ai-stack  # Disable auto-start
```

### 3. Access

- **OpenWebUI**: http://localhost:3000 (select "auto" model)
- **API Endpoint**: http://localhost:8000/v1
- **SearXNG**: http://localhost:8080
- **Ollama Direct**: http://localhost:11434

---

## Manual Commands

```bash
# Start stack
./ai-on.sh
# or
docker compose up -d

# Stop stack
./ai-off.sh
# or
docker compose down

# View logs
docker compose logs -f
docker compose logs -f router
docker compose logs -f ollama

# Restart specific service
docker compose restart router

# Rebuild router after code changes
docker compose build router
docker compose up -d router

# Check container status
docker compose ps

# Check GPU usage
nvidia-smi
```

---

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/v1/models` | List available models |
| POST | `/v1/chat/completions` | Chat (OpenAI compatible) |
| POST | `/v1/classify` | Classify query intent |
| POST | `/v1/search` | Manual web search |
| POST | `/v1/fetch` | Fetch URL content |
| GET | `/v1/memory/stats` | Memory statistics |
| POST | `/v1/memory/search` | Search conversation memory |

### API Examples

```bash
# Health check
curl http://localhost:8000/health

# List models
curl http://localhost:8000/v1/models

# Chat with auto-routing
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "What is the current Python version?"}]
  }'

# Chat with specific model (bypasses intent detection)
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder:14b",
    "messages": [{"role": "user", "content": "Write a sorting algorithm"}]
  }'

# Classify intent only
curl http://localhost:8000/v1/classify \
  -H "Content-Type: application/json" \
  -d '{"query": "What is the latest news about AI?"}'

# Manual web search
curl http://localhost:8000/v1/search \
  -H "Content-Type: application/json" \
  -d '{"query": "Python 3.14 release date"}'

# Fetch URL content
curl http://localhost:8000/v1/fetch \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'

# Memory stats
curl http://localhost:8000/v1/memory/stats

# Search past conversations
curl http://localhost:8000/v1/memory/search \
  -H "Content-Type: application/json" \
  -d '{"query": "python debugging", "k": 5}'
```

---

## Conversation Memory (FAISS)

The Smart Router includes FAISS-powered conversation memory for context-aware responses.

### How It Works

1. Every message is embedded using `nomic-embed-text` model (768 dimensions)
2. Embeddings stored in FAISS index for fast similarity search
3. When you ask a question, relevant past conversations are retrieved
4. Context is injected into the prompt for better responses

### Features

- **Cross-session memory** - Remembers across browser sessions
- **Semantic search** - Finds relevant context by meaning, not just keywords
- **Persistent storage** - Survives container restarts
- **Per-user isolation** - Memory is separated by user ID

### Memory API

```bash
# Check memory statistics
curl http://localhost:8000/v1/memory/stats
# Returns: {"total_messages": 150, "faiss_vectors": 300, "unique_users": 1, ...}

# Search past conversations
curl -X POST http://localhost:8000/v1/memory/search \
  -H "Content-Type: application/json" \
  -d '{"query": "python debugging", "k": 5}'

# Reset memory (if needed)
rm ~/ai-stack/data/smart-router/memory.*
docker compose restart router
```

---

## Testing

Run the comprehensive test suite (31 tests across 10 categories):

```bash
./tests/test_suite.sh           # Run all tests
./tests/test_suite.sh --quick   # Run quick tests only (no LLM calls)
./tests/test_suite.sh --verbose # Show detailed output
```

### Test Categories

| # | Category | Tests | Description |
|---|----------|-------|-------------|
| 1 | Health & Infrastructure | 5 | Service connectivity |
| 2 | Smart Routing | 3 | Model selection |
| 3 | Conversation History | 1 | Context retention |
| 4 | Web Search | 2 | SearXNG integration |
| 5 | URL Fetching | 2 | URL content retrieval |
| 6 | Memory System | 2 | FAISS stats & search |
| 7 | API Compatibility | 2 | OpenAI format |
| 8 | Error Handling | 3 | Invalid input handling |
| 9 | LLM Intent Detection | 7 | Intent classification |
| 10 | Model Indicator Display | 4 | Footer verification |

---

## Changing Models

### 1. Edit models.env

```env
CODING_MODEL=qwen2.5-coder:14b
GENERAL_MODEL=qwen2.5:14b
EMBEDDING_MODEL=nomic-embed-text
```

### 2. Pull the new model

```bash
docker exec ollama ollama pull <model-name>
```

### 3. Rebuild and restart router

```bash
docker compose build router
docker compose up -d router
```

### Managing Models

```bash
# List installed models
docker exec ollama ollama list

# Pull new model
docker exec ollama ollama pull <model-name>

# Delete unused model
docker exec ollama ollama rm <model-name>

# Check model info
docker exec ollama ollama show <model-name>
```

---

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| GPU VRAM | 8GB | 12GB+ |
| RAM | 16GB | 32GB |
| Storage | 50GB | 100GB+ |
| GPU | RTX 3060 | RTX 4070/5070+ |

### VRAM Usage (Approximate)

| Model | VRAM |
|-------|------|
| qwen2.5-coder:14b | ~9GB |
| qwen2.5:14b | ~9GB |
| nomic-embed-text | ~274MB |

Note: Only one main model is loaded at a time. Ollama swaps models as needed.

---

## Troubleshooting

### Check Status

```bash
# Container status
docker compose ps

# Router logs (see intent detection and routing)
docker logs ai-router -f

# All logs
docker compose logs -f

# GPU usage
nvidia-smi
```

### Common Issues

**Web search not triggering:**
- Ensure "auto" model is selected in OpenWebUI (not a specific model)
- Check logs: `docker logs ai-router -f | grep Intent`
- Should see: `[Intent] LLM classified as SEARCH`

**Wrong model being used:**
- Specific models bypass intent detection
- Use "auto" for smart routing

**Memory issues:**
```bash
# Check memory stats
curl http://localhost:8000/v1/memory/stats

# Reset memory
rm data/smart-router/memory.*
docker compose restart router
```

**GPU not detected:**
```bash
# Verify GPU
nvidia-smi

# Test Docker GPU access
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

**Restart everything:**
```bash
docker compose down
docker compose up -d
```

---

## Backup & Restore

All persistent data is in `data/` directory:

```bash
# Backup
tar -czvf ai-stack-backup.tar.gz data/

# Restore
tar -xzvf ai-stack-backup.tar.gz
```

### What's Backed Up

| Directory | Contents |
|-----------|----------|
| data/ollama/ | Model weights (~20GB+) |
| data/openwebui/ | User accounts, chat history, settings |
| data/smart-router/ | FAISS index, SQLite database |
| data/searxng/ | Search engine configuration |
