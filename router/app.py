import os
import time
import logging
from fastapi import FastAPI, Request
import requests

OLLAMA = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ai-router")

app = FastAPI(title = "AI Router")

CODER_MODEL = "deepseek-coder:6.7b-instruct-q4_K_M"
SUMMARY_MODEL = "qwen2.5:7b-instruct-q4_K_M"
GENERAL_MODEL = "llama3.1:8b-instruct-q4_K_M"

MODELS = [
    {
        "id": GENERAL_MODEL,
        "object": "model",
        "owned_by": "local",
    },
    {
        "id": CODER_MODEL,
        "object": "model",
        "owned_by": "local",
    },
    {
        "id": SUMMARY_MODEL,
        "object": "model",
        "owned_by": "local",
    },
]

MODEL_IDS = [m["id"] for m in MODELS]


# ------------------------------
# Utility Functions
# ------------------------------
def call_ollama(model: str, prompt: str):
    """Call Ollama API with retries and error handling"""
    if model not in MODEL_IDS:
        return f"[ERROR] Model {model} is not registered in router"

    max_retries = 2
    for attempt in range(1, max_retries + 1):
        try:
            logger.info(f"[Attempt {attempt}] Sending prompt to model {model}")
            r = requests.post(
                f"{OLLAMA}/api/generate",
                json={"model": model, "prompt": prompt, "stream": False},
                timeout=300,
            )
            r.raise_for_status()
            response = r.json().get("response", "[ERROR] No response field from Ollama")
            logger.info(f"Received response from Ollama: {response[:100]}...")
            return response
        except requests.exceptions.RequestException as e:
            logger.warning(f"Ollama request failed: {str(e)}")
            time.sleep(1)

    return "[ERROR] Ollama unreachable after retries"


def select_model(prompt: str):
    """Select model based on prompt content"""
    prompt_l = prompt.lower()
    if any(x in prompt_l for x in ["code", "bug", "error", "function", "class"]):
        return CODER_MODEL
    elif any(x in prompt_l for x in ["summarize", "summary", "explain"]):
        return SUMMARY_MODEL
    else:
        return GENERAL_MODEL


# ------------------------------
# API Endpoints
# ------------------------------
@app.get("/v1/models")
def list_models():
    return {
        "object": "list",
        "data": MODELS,
    }


@app.post("/v1/chat/completions")
async def chat(request: Request):
    """Chat endpoint similar to OpenAI API"""
    body = await request.json()
    if "messages" not in body or not body["messages"]:
        return {"error": "No messages provided"}

    prompt = body["messages"][-1]["content"].strip()
    model = select_model(prompt)
    output = call_ollama(model, prompt)

    return {
        "id": "chatcmpl-local",
        "object": "chat.completion",
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": output},
                "finish_reason": "stop",
            }
        ],
    }


@app.get("/v1/health")
def health():
    """Check if Ollama is reachable"""
    try:
        r = requests.get(f"{OLLAMA}/api/tags", timeout=2)
        if r.status_code == 200:
            return {"status": "ok"}
    except Exception as e:
        logger.warning(f"Health check failed: {str(e)}")
    return {"status": "ollama unreachable", "error": str(e)}
