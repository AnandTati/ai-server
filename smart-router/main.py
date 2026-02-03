import os
import re
import httpx
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Smart Router")

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")

# Model routing configuration
MODELS = {
    "coding": os.getenv("CODING_MODEL", "deepseek:latest"),
    "summarization": os.getenv("SUMMARY_MODEL", "qwen:latest"),
    "general": os.getenv("GENERAL_MODEL", "llama3:latest"),
}

# Keywords for classification
CODING_KEYWORDS = [
    "code", "function", "class", "program", "script", "debug", "error", "bug",
    "python", "javascript", "java", "rust", "golang", "c++", "sql", "html", "css",
    "api", "algorithm", "data structure", "compile", "syntax", "variable",
    "loop", "array", "list", "dictionary", "object", "method", "import",
    "def ", "async", "await", "return", "print(", "console.log", "git",
    "docker", "kubernetes", "database", "query", "regex", "json", "xml",
    "implement", "refactor", "optimize", "write a", "create a", "build a",
    "fix this", "fix the", "how to code", "programming"
]

SUMMARY_KEYWORDS = [
    "summarize", "summary", "summarization", "condense", "brief", "tldr",
    "key points", "main points", "overview", "recap", "synopsis",
    "shorten", "reduce", "simplify this text", "explain briefly",
    "in short", "bullet points", "highlight", "extract"
]

def classify_query(messages: list) -> str:
    """Classify the query based on keywords in the conversation."""
    # Get the last user message
    text = ""
    for msg in reversed(messages):
        if msg.get("role") == "user":
            text = msg.get("content", "").lower()
            break
    
    if not text:
        return "general"
    
    # Check for summarization keywords first (more specific)
    for keyword in SUMMARY_KEYWORDS:
        if keyword in text:
            logger.info(f"Classified as SUMMARIZATION (keyword: {keyword})")
            return "summarization"
    
    # Check for coding keywords
    for keyword in CODING_KEYWORDS:
        if keyword in text:
            logger.info(f"Classified as CODING (keyword: {keyword})")
            return "coding"
    
    logger.info("Classified as GENERAL (no specific keywords)")
    return "general"


@app.get("/v1/models")
async def list_models():
    """List available models."""
    models = [
        {"id": "auto", "object": "model", "created": 0, "owned_by": "smart-router"},
        {"id": "deepseek", "object": "model", "created": 0, "owned_by": "ollama"},
        {"id": "qwen", "object": "model", "created": 0, "owned_by": "ollama"},
        {"id": "llama3", "object": "model", "created": 0, "owned_by": "ollama"},
    ]
    return {"object": "list", "data": models}


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """Handle chat completions with intelligent routing."""
    try:
        body = await request.json()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {e}")
    
    requested_model = body.get("model", "auto")
    messages = body.get("messages", [])
    stream = body.get("stream", False)
    
    # Determine which model to use
    if requested_model == "auto":
        category = classify_query(messages)
        target_model = MODELS[category]
        logger.info(f"AUTO-ROUTING: {category} -> {target_model}")
    elif requested_model in ["deepseek", "coding"]:
        target_model = MODELS["coding"]
    elif requested_model in ["qwen", "summary", "summarization"]:
        target_model = MODELS["summarization"]
    elif requested_model in ["llama3", "general"]:
        target_model = MODELS["general"]
    else:
        # Pass through unknown models
        target_model = requested_model
    
    # Update the model in the request
    body["model"] = target_model
    
    logger.info(f"Routing to model: {target_model}")
    
    # Forward to Ollama
    url = f"{OLLAMA_BASE_URL}/v1/chat/completions"
    
    if stream:
        async def stream_response():
            async with httpx.AsyncClient(timeout=300.0) as client:
                async with client.stream("POST", url, json=body) as response:
                    async for chunk in response.aiter_bytes():
                        yield chunk
        
        return StreamingResponse(stream_response(), media_type="text/event-stream")
    else:
        async with httpx.AsyncClient(timeout=300.0) as client:
            response = await client.post(url, json=body)
            result = response.json()
            # Add routing info to response
            if "model" in result:
                result["routed_from"] = requested_model
            return JSONResponse(content=result)


@app.get("/health")
async def health():
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
