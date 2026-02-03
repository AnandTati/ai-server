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
├── docker-compose.yml          # Main orchestration file
├── bootstrap.sh                # Initial setup script
├── init_models.py              # Model initialization & registration
├── ai-on.sh                    # Manual start script (portable)
├── ai-off.sh                   # Manual stop + shutdown script
├── ai-stack.service            # Systemd service file
├── README.md
│
├── ollama/                     # Ollama configuration
│   ├── models.env              # Model name mappings
│   ├── models.yaml             # Model settings (temp, system prompts)
│   └── Modelfile.tmpl          # Template for custom models
│
├── smart-router/               # Intelligent routing service
│   ├── Dockerfile
│   ├── main.py                 # Router logic with keyword classification
│   └── requirements.txt
│
├── whisper/                    # Speech-to-text service
│   ├── Dockerfile
│   ├── app.py
│   └── requirements.txt
│
└── data/                       # Persistent data (gitignored)
    ├── ollama/                 # Model weights & rendered configs
    └── openwebui/              # Chat history & settings
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
| `auto` | Auto-detect | Let router decide |
| `deepseek` | deepseek-coder:6.7b-instruct-q4_K_M | Coding tasks |
| `qwen` | qwen2.5:7b-instruct-q4_K_M | Summarization |
| `llama3` | llama3.1:8b-instruct-q4_K_M | General chat |

**Auto-Detection Keywords:**

- **Coding** → `code`, `function`, `debug`, `python`, `javascript`, `api`, `implement`, etc.
- **Summarization** → `summarize`, `tldr`, `brief`, `key points`, `condense`, etc.
- **General** → Everything else

---

## Setup Instructions

### Prerequisites

- Docker with NVIDIA GPU support
- Python 3.x
- NVIDIA GPU with 12GB+ VRAM

### 1. Clone & Bootstrap

```bash
cd ~/ai-stack
./bootstrap.sh
```

This will:
- Create Python virtual environment
- Install dependencies
- Start Ollama
- Pull and register models
- Start all services

### 2. Enable Auto-Start (Systemd)

```bash
# Copy service file
sudo cp ~/ai-stack/ai-stack.service /etc/systemd/system/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable ai-stack.service
sudo systemctl start ai-stack.service

# Check status
sudo systemctl status ai-stack.service
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

### Change Models

Edit `docker-compose.yml` router environment:

```yaml
environment:
  - CODING_MODEL=qwen3-coder:7b       # Change coding model
  - SUMMARY_MODEL=qwen3:7b            # Change summary model
  - GENERAL_MODEL=llama4:8b           # Change general model
```

Then restart:

```bash
docker compose up -d router
```

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
