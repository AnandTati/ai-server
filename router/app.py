from fastapi import FastAPI, Request
import requests
import os

OLLAMA = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")

app = FastAPI()

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


@app.get("/v1/models")
def list_models():
    return {
        "object": "list",
        "data": MODELS,
    }


def call_ollama(model: str, prompt: str):
    r = requests.post(
        f"{OLLAMA}/api/generate",
        json={
            "model": model,
            "prompt": prompt,
            "stream": False,
        },
        timeout=300,
    )

    if r.status_code == 404:
        return f"[ERROR] Model '{model}' not found in Ollama."

    r.raise_for_status()
    return r.json()["response"]

@app.post("/v1/chat/completions")
async def chat(request: Request):
    body = await request.json()
    prompt = body["messages"][-1]["content"]

    prompt_l = prompt.lower()

    if any(x in prompt_l for x in ["code", "bug", "error", "function", "class"]):
        model = CODER_MODEL
    elif any(x in prompt_l for x in ["summarize", "summary", "explain"]):
        model = SUMMARY_MODEL
    else:
        model = GENERAL_MODEL

    output = call_ollama(model, prompt)

    return {
        "id": "chatcmpl-local",
        "object": "chat.completion",
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": output,
                },
                "finish_reason": "stop",
            }
        ],
    }
