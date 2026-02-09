# Coding Agent Setup

Use your AI server as the brain for a local coding agent on your laptop/desktop.

---

## How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SELF-HOSTED CODING AGENT                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   YOUR LAPTOP                                    AI SERVER                  │
│   ┌─────────────────────────────┐          ┌──────────────────┐             │
│   │                             │          │                  │             │
│   │   Aider CLI                 │ ──API──► │   Ollama API     │             │
│   │   (runs LOCALLY)            │  :11434  │   qwen2.5-coder  │             │
│   │                             │          │                  │             │
│   │   • Direct file access      │          │   • AI brain     │             │
│   │   • Direct command exec     │          │   • GPU powered  │             │
│   │   • Git integration         │          │   • No API costs │             │
│   │   • No SSH needed           │          │                  │             │
│   │                             │          └──────────────────┘             │
│   └─────────────────────────────┘                                           │
│                                                                             │
│   The CLI runs on YOUR machine, only the "thinking" is done by the server   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

This is the same pattern as Claude Code - a local CLI with remote AI.

---

## AI Server Info

| Setting | Value |
|---------|-------|
| Server IP | `192.168.1.31` |
| Ollama API | `http://192.168.1.31:11434` |
| Coding Model | `qwen2.5-coder:14b` |
| General Model | `qwen2.5:14b` |

---

## Setup on macOS

### 1. Install Aider

```bash
# Option A: Using pip
pip install aider-chat

# Option B: Using Homebrew
brew install aider
```

### 2. Configure Environment

Add to your `~/.zshrc`:

```bash
# AI Server connection
export OLLAMA_API_BASE="http://192.168.1.31:11434"
```

Then reload:

```bash
source ~/.zshrc
```

### 3. Create Config File (Optional)

```bash
cat > ~/.aider.conf.yml << 'EOF'
# Aider configuration for remote AI server
model: ollama_chat/qwen2.5-coder:14b

# Git settings
auto-commits: true
dirty-commits: true

# Editor settings
edit-format: whole
stream: true

# Disable analytics
analytics: false
show-model-warnings: false
EOF
```

---

## Setup on Linux

### 1. Install Aider

```bash
pip install aider-chat
```

### 2. Configure Environment

Add to your `~/.bashrc`:

```bash
export OLLAMA_API_BASE="http://192.168.1.31:11434"
```

Then reload:

```bash
source ~/.bashrc
```

---

## Setup on Windows

### 1. Install Aider

```powershell
pip install aider-chat
```

### 2. Configure Environment

```powershell
# Set permanently
[Environment]::SetEnvironmentVariable("OLLAMA_API_BASE", "http://192.168.1.31:11434", "User")

# Or set for current session
$env:OLLAMA_API_BASE = "http://192.168.1.31:11434"
```

---

## Usage

### Start a New Project

```bash
mkdir ~/my-project
cd ~/my-project
git init
aider
```

### Work on Existing Project

```bash
cd ~/existing-project
aider
```

### One-Shot Commands

```bash
# Create a file
aider --message "Create a Python script that downloads images from a URL"

# Fix a bug
aider --message "Fix the bug in main.py where the loop never terminates"

# Add a feature
aider --message "Add input validation to the user registration form"
```

### Add Files to Context

```bash
# Start with specific files
aider src/main.py src/utils.py

# Or add inside aider
> /add src/helpers.py
```

---

## Aider Commands

| Command | Description |
|---------|-------------|
| `/add <file>` | Add file to context |
| `/drop <file>` | Remove file from context |
| `/run <cmd>` | Run a shell command |
| `/diff` | Show pending changes |
| `/commit` | Commit changes |
| `/undo` | Undo last change |
| `/clear` | Clear chat history |
| `/help` | Show all commands |
| `/quit` | Exit aider |

---

## Example Session

```
$ cd ~/projects
$ mkdir web-scraper && cd web-scraper
$ git init
$ aider

Aider v0.86.1
Model: ollama_chat/qwen2.5-coder:14b with whole edit format
Git repo: .git with 0 files

> Create a Python web scraper that:
> 1. Takes a URL as input
> 2. Downloads all images from the page
> 3. Saves them to a local folder
> 4. Shows progress with a progress bar

[Aider creates scraper.py, requirements.txt, README.md]

> Add error handling for network failures and invalid URLs

[Aider updates scraper.py with try/except blocks]

> Write unit tests for the scraper

[Aider creates test_scraper.py]

> /run pytest
[Tests run locally on your machine]

> /quit
```

---

## Troubleshooting

### Cannot connect to AI server

```bash
# Test connection
curl http://192.168.1.31:11434/api/tags

# If it fails, check:
# 1. AI server is running: ssh timbi@timtimi "docker ps"
# 2. Firewall allows port 11434
# 3. You are on the same network
```

### Model not found

```bash
# List available models
curl http://192.168.1.31:11434/api/tags | jq '.models[].name'

# Use correct model name
aider --model ollama_chat/qwen2.5-coder:14b
```

### Slow responses

The first request may be slow as the model loads into GPU memory. Subsequent requests will be faster.

---

## Alternative: VS Code + Continue.dev

If you prefer an IDE experience:

1. Install VS Code
2. Install "Continue" extension
3. Configure Continue to use your AI server:

```json
{
  "models": [
    {
      "title": "AI Server - Coder",
      "provider": "ollama",
      "model": "qwen2.5-coder:14b",
      "apiBase": "http://192.168.1.31:11434"
    }
  ]
}
```

---

## Security Note

The Ollama API is exposed on your local network without authentication. Only use this on a trusted network. For remote access over the internet, set up:

1. VPN to your home network, or
2. SSH tunnel: `ssh -L 11434:localhost:11434 timbi@your-server-ip`
