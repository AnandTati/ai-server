# AI Stack

A self-hosted AI stack with intelligent query routing and conversation memory, featuring:
- **Ollama** - Local LLM backend (GPU accelerated)
- **Smart Router** - Auto-routes queries to the best model + FAISS memory
- **OpenWebUI** - Chat interface
- **Whisper** - Speech-to-text

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
│    │deepseek │ │  qwen    │ │ llama3  │                                     │
│    │ (code)  │ │(summary) │ │(general)│                                     │
│    └────┬────┘ └────┬─────┘ └────┬────┘                                     │
│         └───────────┼────────────┘                                          │
│                     ▼                                                       │
│              ┌───────────────┐                                              │
│              │    Ollama     │                                              │
│              │   (:11434)    │                                              │
│              │   [GPU]       │                                              │
│              └───────────────┘                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Request Flow

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
│  1. CLASSIFY QUERY                                                        │
│     ┌─────────────────────────────────────────────────────────────┐       │
│     │  "Write a python function" ──► CODING keywords found        │       │
│     │  "Summarize this article"  ──► SUMMARY keywords found       │       │
│     │  "What is the weather?"    ──► GENERAL (no keywords)        │       │
│     └─────────────────────────────────────────────────────────────┘       │
│                              │                                            │
│                              ▼                                            │
│  2. RETRIEVE MEMORY (FAISS)                                               │
│     ┌─────────────────────────────────────────────────────────────┐       │
│     │  Query ──► Embedding ──► FAISS Search ──► Similar Messages  │       │
│     │                                              │              │       │
│     │                              ┌───────────────┘              │       │
│     │                              ▼                              │       │
│     │                    Inject as context                        │       │
│     └─────────────────────────────────────────────────────────────┘       │
│                              │                                            │
│                              ▼                                            │
│  3. ROUTE TO MODEL                                                        │
│     ┌─────────────────────────────────────────────────────────────┐       │
│     │  CODING ─────► deepseek-coder:6.7b-instruct-q4_K_M          │       │
│     │  SUMMARY ────► qwen2.5:7b-instruct-q4_K_M                   │       │
│     │  GENERAL ────► llama3.1:8b-instruct-q4_K_M                  │       │
│     └─────────────────────────────────────────────────────────────┘       │
│                              │                                            │
│                              ▼                                            │
│  4. STORE IN MEMORY                                                       │
│     ┌─────────────────────────────────────────────────────────────┐       │
│     │  User message ──► Embedding ──► FAISS Index                 │       │
│     │  Assistant response ──► Embedding ──► FAISS Index           │       │
│     │  Metadata ──► SQLite                                        │       │
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
    │  │ Vector [...]    │  │   │  │ query_type: ... │  │
    │  └─────────────────┘  │   │  └─────────────────┘  │
    │  ┌─────────────────┐  │   │  ┌─────────────────┐  │
    │  │ Vector [...]    │  │   │  │ id: 2           │  │
    │  └─────────────────┘  │   │  │ ...             │  │
    │         ...           │   │  └─────────────────┘  │
    │                       │   │         ...           │
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
│  │  │ :11434 ◄─────┼──┤ :8000  ◄─────┼──┤ :3000       │                │    │
│  │  │              │  │              │  │              │               │    │
│  │  │ [GPU]        │  │ [FAISS]      │  │ [WebUI]      │               │    │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘               │    │
│  │         │                 │                 │                       │    │
│  └─────────┼─────────────────┼─────────────────┼───────────────────────┘    │
│            │                 │                 │                            │
│            ▼                 ▼                 ▼                            │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         VOLUMES (./data/)                           │    │
│  ├──────────────────┬──────────────────┬───────────────────────────────┤    │
│  │ data/ollama/     │ data/smart-      │ data/openwebui/               │    │
│  │                  │ router/          │                               │    │
│  │ - Model weights  │ - memory.faiss   │ - User accounts               │    │
│  │ - Config         │ - memory.db      │ - Chat history                │    │
│  │ (~20GB+)         │ (~few MB)        │ - Settings                    │    │
│  └──────────────────┴──────────────────┴───────────────────────────────┘    │
│                                                                             │
│  ┌──────────────┐                                                           │
│  │   whisper    │  (separate, localhost only :9000)                         │
│  │   [GPU]      │                                                           │
│  └──────────────┘                                                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Folder Structure

```
ai-stack/
├── docker-compose.yml            # Main orchestration file
├── bootstrap.sh                  # Initial setup script
├── init_models.py                # Model initialization & registration
├── ai-on.sh                      # Manual start script
├── ai-off.sh                     # Manual stop script
├── install-service.sh            # Systemd service installer
├── ai-stack.service.template     # Service template (portable)
├── README.md
│
├── ollama/                       # Ollama configuration
│   ├── models.env                # Model name mappings
│   ├── models.yaml               # Model settings (temp, system prompts)
│   └── Modelfile.tmpl            # Template for custom models
│
├── smart-router/                 # Intelligent routing service
│   ├── Dockerfile
│   └── main.py                   # Router logic with FAISS memory
│
├── whisper/                      # Speech-to-text service
│   └── Dockerfile
│
└── data/                         # Persistent data (gitignored)
    ├── ollama/                   # Model weights & rendered configs
    ├── openwebui/                # Chat history & settings
    └── smart-router/             # FAISS memory storage
        ├── memory.faiss          # Vector embeddings
        └── memory.db             # Message metadata (SQLite)
```

---

## Services & Ports

| Service | Container | Port | Description |
|---------|-----------|------|-------------|
| Ollama | ollama | 11434 | LLM inference engine |
| Smart Router | ai-router | 8000 | Intelligent query routing + memory |
| OpenWebUI | openwebui | 3000 | Web chat interface |
| Whisper | whisper | 9000 (localhost) | Speech-to-text |

---

## Smart Router - How It Works

**Model Selection:**

| Select | Routes To | Use For |
|--------|-----------|---------|
| auto | Auto-detect | Let router decide |
| deepseek | deepseek-coder:6.7b-instruct-q4_K_M | Coding tasks |
| qwen | qwen2.5:7b-instruct-q4_K_M | Summarization |
| llama3 | llama3.1:8b-instruct-q4_K_M | General chat |

**Auto-Detection Keywords:**

- **Coding**: code, function, debug, python, javascript, api, implement, etc.
- **Summarization**: summarize, tldr, brief, key points, condense, etc.
- **General**: Everything else

---

## Conversation Memory (FAISS)

The Smart Router includes FAISS-powered conversation memory for context-aware responses.

**How It Works:**
1. Every message is embedded using `nomic-embed-text` model
2. Embeddings stored in FAISS index for fast similarity search
3. When you ask a question, relevant past conversations are retrieved
4. Context is injected into the prompt for better responses

**Features:**
- Cross-session memory (remembers across browser sessions)
- Semantic search (finds relevant context by meaning, not just keywords)
- Persistent storage (survives container restarts)

**Memory API:**

```bash
# Check memory statistics
curl http://localhost:8000/v1/memory/stats

# Search past conversations
curl -X POST http://localhost:8000/v1/memory/search \
  -H "Content-Type: application/json" \
  -d '{"query": "python debugging", "k": 5}'

# Reset memory (if needed)
rm ~/ai-stack/data/smart-router/memory.*
docker compose restart router
```

---

## Setup Instructions

### Prerequisites

- Docker with NVIDIA GPU support
- Python 3.x
- NVIDIA GPU with 12GB+ VRAM

### 1. Bootstrap (First-time Setup)

```bash
cd ~/ai-stack
chmod +x bootstrap.sh ai-on.sh ai-off.sh install-service.sh
./bootstrap.sh
```

**What bootstrap does:**
1. Creates data directories
2. Installs Python dependencies
3. Starts Ollama container
4. Pulls required models:
   - deepseek-coder:6.7b-instruct-q4_K_M (coding)
   - qwen2.5:7b-instruct-q4_K_M (summarization)
   - llama3.1:8b-instruct-q4_K_M (general)
   - nomic-embed-text (embeddings for FAISS)
5. Registers model aliases
6. Starts all services (router, openwebui, whisper)

### 2. Enable Auto-Start (Systemd)

Run the installer script (auto-detects paths):

```bash
sudo ./install-service.sh
```

This will:
- Detect your install directory and username
- Generate the systemd service file
- Install and enable the service

**Systemd commands:**

```bash
sudo systemctl enable ai-stack   # Enable auto-start on boot
sudo systemctl start ai-stack    # Start now
sudo systemctl stop ai-stack     # Stop
sudo systemctl status ai-stack   # Check status
sudo systemctl disable ai-stack  # Disable auto-start
```

### 3. Access

- **OpenWebUI**: http://localhost:3000
- **API Endpoint**: http://localhost:8000/v1
- **Ollama Direct**: http://localhost:11434

---

## Manual Commands

```bash
# Start stack
./ai-on.sh

# Stop stack
./ai-off.sh

# Just stop containers (alternative)
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
```

---

## Model Configuration

### Current Models

Configured in `docker-compose.yml`:

```yaml
environment:
  - CODING_MODEL=deepseek-coder:6.7b-instruct-q4_K_M
  - SUMMARY_MODEL=qwen2.5:7b-instruct-q4_K_M
  - GENERAL_MODEL=llama3.1:8b-instruct-q4_K_M
  - EMBEDDING_MODEL=nomic-embed-text
```

### Change Models

1. Edit `docker-compose.yml` router environment
2. Pull the new model: `docker exec ollama ollama pull <model-name>`
3. Restart router: `docker compose restart router`

### Pull New Models

```bash
docker exec ollama ollama pull <model-name>
```

### List Installed Models

```bash
docker exec ollama ollama list
```

### Delete Unused Models

```bash
docker exec ollama ollama rm <model-name>
```

---

## API Usage

### List Models

```bash
curl http://localhost:8000/v1/models
```

### Chat (Auto-Routing)

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "auto", "messages": [{"role": "user", "content": "Write a Python function"}]}'
```

### Chat (Specific Model)

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "deepseek", "messages": [{"role": "user", "content": "Hello"}]}'
```

### Health Check

```bash
curl http://localhost:8000/health
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

---

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| GPU VRAM | 8GB | 12GB+ |
| RAM | 16GB | 32GB |
| Storage | 50GB | 100GB+ |

---

## Troubleshooting

```bash
# Check container status
docker ps

# View router logs (see routing decisions)
docker logs ai-router -f

# Check GPU usage
nvidia-smi

# Check memory stats
curl http://localhost:8000/v1/memory/stats

# Restart everything
docker compose down && docker compose up -d

# Reset FAISS memory
rm data/smart-router/memory.* && docker compose restart router
```
