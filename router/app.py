import os
import time
import logging
import json
from fastapi import FastAPI, Request
import requests
import faiss
import numpy as np
from sentence_transformers import SentenceTransformer
from pathlib import Path

# ------------------------------
# Configuration
# ------------------------------
OLLAMA = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")
FAISS_INDEX_PATH = Path("./faiss/chat_index.faiss")
META_PATH = Path("./faiss/chat_metadata.json")
EMBEDDING_MODEL_NAME = "all-MiniLM-L6-v2"  # lightweight local embedding

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ai-router")

app = FastAPI(title="AI Router with Memory")

# ------------------------------
# Models
# ------------------------------
MODELS = {
    "generic_model": {
        "id": "generic_model",
        "name": "llama3.1:8b-instruct-q4_K_M",
        "object": "model",
        "owned_by": "local",
    },
    "coder_model": {
        "id": "coder_model",
        "name": "deepseek-coder:6.7b-instruct-q4_K_M",
        "object": "model",
        "owned_by": "local",
    },
    "summary_model": {
        "id": "summary_model",
        "name": "qwen2.5:7b-instruct-q4_K_M",
        "object": "model",
        "owned_by": "local",
    },
}

MODEL_IDS = [m["name"] for m in MODELS.values()]

# ------------------------------
# FAISS / Embeddings Setup
# ------------------------------
Path("./faiss").mkdir(exist_ok=True)

embedding_model = SentenceTransformer(EMBEDDING_MODEL_NAME)

# Initialize FAISS index
dimension = embedding_model.get_sentence_embedding_dimension()
if FAISS_INDEX_PATH.exists():
    index = faiss.read_index(str(FAISS_INDEX_PATH))
    logger.info("FAISS index loaded from disk")
else:
    index = faiss.IndexFlatL2(dimension)
    logger.info("FAISS index created")

# Load metadata
if META_PATH.exists():
    with open(META_PATH, "r") as f:
        metadata = json.load(f)
    logger.info("Metadata loaded from disk")
else:
    metadata = []

# ------------------------------
# Helper Functions
# ------------------------------
def call_ollama(model_name: str, prompt: str):
    """Call Ollama API with retries and error handling"""
    max_retries = 2
    for attempt in range(1, max_retries + 1):
        try:
            logger.info(f"[Attempt {attempt}] Sending prompt to model {model_name}")
            r = requests.post(
                f"{OLLAMA}/api/generate",
                json={"model": model_name, "prompt": prompt, "stream": False},
                timeout=300,
            )
            r.raise_for_status()
            response = r.json().get("response", "[ERROR] No response field from Ollama")
            logger.info(f"Received response: {response[:100]}...")
            return response
        except requests.exceptions.RequestException as e:
            logger.warning(f"Ollama request failed: {str(e)}")
            time.sleep(1)
    return "[ERROR] Ollama unreachable after retries"


def select_model(prompt: str):
    """Select model based on prompt content"""
    prompt_l = prompt.lower()
    if any(x in prompt_l for x in ["code", "bug", "error", "function", "class"]):
        return MODELS["coder_model"]["name"]
    elif any(x in prompt_l for x in ["summarize", "summary", "explain"]):
        return MODELS["summary_model"]["name"]
    else:
        return MODELS["generic_model"]["name"]


def save_index_and_meta():
    """Persist FAISS index and metadata"""
    faiss.write_index(index, str(FAISS_INDEX_PATH))
    with open(META_PATH, "w") as f:
        json.dump(metadata, f, indent=2)
    logger.info("FAISS index and metadata saved")


def embed_text(text: str) -> np.ndarray:
    """Convert text to vector embedding"""
    return embedding_model.encode([text]).astype("float32")


def retrieve_context(chat_id: str, prompt: str, top_k: int = 5) -> str:
    """Retrieve top-k relevant messages from past conversation"""
    if len(metadata) == 0 or index.ntotal == 0:
        return ""
    prompt_vector = embed_text(prompt)
    D, I = index.search(prompt_vector, top_k)
    context_texts = []
    for idx in I[0]:
        if idx < len(metadata) and metadata[idx]["chat_id"] == chat_id:
            context_texts.append(metadata[idx]["content"])
    return "\n".join(context_texts)


# ------------------------------
# API Endpoints
# ------------------------------
@app.get("/v1/models")
def list_models():
    return {"object": "list", "data": list(MODELS.values())}


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
    return {"status": "unknown"}


@app.post("/v1/chat/completions")
async def chat(request: Request):
    """Chat endpoint with memory using FAISS embeddings"""
    body = await request.json()
    if "messages" not in body or not body["messages"]:
        return {"error": "No messages provided"}

    chat_id = body.get("chat_id", "default_chat")
    prompt = body["messages"][-1]["content"].strip()

    # Retrieve context from past messages
    context = retrieve_context(chat_id, prompt)
    if context:
        logger.info(f"Context found for chat_id={chat_id}")
        prompt_with_context = f"{context}\nUser: {prompt}\nAssistant:"
    else:
        prompt_with_context = prompt

    # Select model
    model_name = select_model(prompt)

    # Call Ollama
    output = call_ollama(model_name, prompt_with_context)

    # Save user and assistant messages to FAISS
    for role, content in [("user", prompt), ("assistant", output)]:
        vector = embed_text(content)
        index.add(vector)
        metadata.append({"chat_id": chat_id, "role": role, "content": content})

    save_index_and_meta()

    return {
        "id": "chatcmpl-local",
        "object": "chat.completion",
        "choices": [{"index": 0, "message": {"role": "assistant", "content": output}, "finish_reason": "stop"}],
    }
