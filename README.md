# AI Stack

A self-hosted AI stack with intelligent query routing, featuring:
- **Ollama** - Local LLM backend (GPU accelerated)
- **Smart Router** - Auto-routes queries to the best model
- **OpenWebUI** - Chat interface
- **Whisper** - Speech-to-text

---

## Folder Structure

```
ai-stack/
├── docker-compose.yml            # Main orchestration file
├── bootstrap.sh                  # Initial setup script
├── init_models.py                # Model initialization & registration
├── ai-on.sh                      # Manual start script
├── ai-off.sh                     # Manual stop + shutdown script
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
│   ├── main.py                   # Router logic with keyword classification
│   └── requirements.txt
│
├── whisper/                      # Speech-to-text service
│   ├── Dockerfile
│   ├── app.py
│   └── requirements.txt
│
└── data/                         # Persistent data (gitignored)
    ├── ollama/                   # Model weights & rendered configs
    └── openwebui/                # Chat history & settings
```

---

## Services & Ports

| Service | Container | Port | Description |
|---------|-----------|------|-------------|
| Ollama | ollama | 11434 | LLM inference engine |
| Smart Router | ai-router | 8000 | Intelligent query routing |
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

## Setup Instructions

### Prerequisites

- Docker with NVIDIA GPU support
- Python 3.x
- NVIDIA GPU with 12GB+ VRAM

### 1. Bootstrap (First-time Setup)

```bash
cd ~/ai-stack
./bootstrap.sh
```

**What bootstrap.sh does:**

1. Checks for Docker and Python
2. Creates Python virtual environment (.venv/)
3. Installs Python dependencies (pyyaml, jinja2, requests, etc.)
4. Starts Ollama container
5. Runs init_models.py to:
   - Pull base models from Ollama registry
   - Render custom Modelfiles with system prompts
   - Register model aliases (deepseek, qwen, llama3)
6. Starts all remaining services (router, openwebui, whisper)

### 2. Enable Auto-Start (Systemd)

Run the installer script (auto-detects paths):

```bash
./install-service.sh
```

This will:
- Detect your install directory and username
- Generate the systemd service file
- Install and enable the service

**Manual commands after installation:**

```bash
sudo systemctl start ai-stack    # Start now
sudo systemctl stop ai-stack     # Stop
sudo systemctl status ai-stack   # Check status
sudo systemctl disable ai-stack  # Disable auto-start
```

### 3. Access

- **OpenWebUI**: http://localhost:3000
- **API Endpoint**: http://localhost:8000/v1

---

## Manual Commands

```bash
# Start stack
./ai-on.sh

# Stop stack + shutdown system
./ai-off.sh

# Just stop containers (no shutdown)
docker compose down

# View logs
docker compose logs -f router
docker compose logs -f ollama

# Restart specific service
docker compose restart router
```

---

## Model Configuration

### Current Models

Configured in docker-compose.yml:

```yaml
environment:
  - CODING_MODEL=deepseek-coder:6.7b-instruct-q4_K_M
  - SUMMARY_MODEL=qwen2.5:7b-instruct-q4_K_M
  - GENERAL_MODEL=llama3.1:8b-instruct-q4_K_M
```

### Change Models

1. Edit docker-compose.yml router environment
2. Restart router: docker compose up -d router

### Pull New Models

```bash
docker exec ollama ollama pull <model-name>
```

### List Installed Models

```bash
docker exec ollama ollama list
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

# View router logs
docker logs ai-router -f

# Check GPU usage
nvidia-smi

# Restart everything
docker compose down && docker compose up -d
```
