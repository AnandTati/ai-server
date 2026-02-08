"""
Smart Router for AI Stack
==========================
A FastAPI service that intelligently routes queries to appropriate Ollama models
based on query classification.

2-Model Setup (optimized for 12GB VRAM):
- CODING_MODEL: deepseek-r1:14b for coding + reasoning
- GENERAL_MODEL: qwen3:8b for general chat + summarization

Features:
- Keyword-based query classification
- FAISS-powered conversation memory for context retrieval
- SQLite metadata storage for message persistence
- Cross-session memory support
- AUTO URL FETCHING: Detects URLs and fetches content
- AUTO WEB SEARCH: Detects search queries and uses SearXNG

Environment Variables:
- OLLAMA_BASE_URL: Ollama API endpoint (default: http://ollama:11434)
- CODING_MODEL: Model for coding queries (default: deepseek-r1:14b)
- GENERAL_MODEL: Model for general + summarization (default: qwen3:8b)
- EMBEDDING_MODEL: Model for generating embeddings (default: nomic-embed-text)
- DATA_DIR: Directory for persistent storage (default: /data)
- SEARXNG_URL: SearXNG search endpoint (default: http://searxng:8080)
"""

import os
import re
import json
import sqlite3
import asyncio
import logging
from datetime import datetime
from typing import Optional, List, Dict, Any
from contextlib import asynccontextmanager
from urllib.parse import urlparse, quote_plus

import httpx
import numpy as np
import faiss
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse


def word_match(keyword: str, text: str) -> bool:
    """Check if keyword exists as a whole word in text."""
    pattern = r"\b" + re.escape(keyword.strip()) + r"\b"
    return bool(re.search(pattern, text, re.IGNORECASE))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# =============================================================================
# Configuration
# =============================================================================

OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://ollama:11434")
CODING_MODEL = os.environ.get("CODING_MODEL", "deepseek-r1:14b")
GENERAL_MODEL = os.environ.get("GENERAL_MODEL", "qwen3:8b")
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "nomic-embed-text")
DATA_DIR = os.environ.get("DATA_DIR", "/data")
SEARXNG_URL = os.environ.get("SEARXNG_URL", "http://searxng:8080")

# Memory configuration
MAX_CONTEXT_MESSAGES = 5
SIMILARITY_THRESHOLD = 0.7
EMBEDDING_DIM = 768  # nomic-embed-text dimension

# Web fetch configuration
MAX_URL_CONTENT_LENGTH = 8000  # Max characters to include from fetched URL
MAX_SEARCH_RESULTS = 3  # Number of search results to include

# =============================================================================
# Classification Keywords
# =============================================================================

CODING_KEYWORDS = [
    "code", "function", "program", "script", "debug", "error", "bug",
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

# Keywords that trigger web search
SEARCH_KEYWORDS = [
    # Explicit search requests
    "search for", "search the web", "look up", "find out", "google",
    "search online", "find online", "check online", "look online",
    "search internet", "on the internet", "from the web",
    # Current events / time-sensitive
    "what is the latest", "what are the latest", "latest news",
    "current news", "recent news", "latest update", "breaking news",
    "today", "yesterday", "this week", "2024", "2025", "2026",
    "who won", "what happened",
    # Information requests (common patterns)
    "news about", "tell me about", "information about", "info on",
    "what do you know about", "can you find", "find me",
    # Capability/feature queries
    "latest version", "new features", "recent updates",
    "what can", "capabilities of", "features of"
]

# =============================================================================
# URL and Web Search Utilities
# =============================================================================

# Regex to find URLs in text
URL_PATTERN = re.compile(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    re.IGNORECASE
)

def extract_urls(text: str) -> List[str]:
    """Extract all URLs from text and clean them."""
    urls = URL_PATTERN.findall(text)
    cleaned = []
    for url in urls:
        # Remove trailing punctuation that's likely not part of the URL
        url = url.rstrip('.,;:!?)\'\"')
        # Also handle markdown link syntax [text](url)
        if url.endswith(')') and '(' not in url:
            url = url.rstrip(')')
        if url:
            cleaned.append(url)
    return cleaned

def needs_web_search(text: str) -> bool:
    """Check if the query needs web search."""
    text_lower = text.lower()

    # Check explicit search keywords
    for keyword in SEARCH_KEYWORDS:
        if keyword in text_lower:
            logger.info(f"[Web] Search triggered by keyword: {keyword}")
            return True

    # Check for standalone "latest" with a topic
    if "latest" in text_lower and len(text_lower.split()) > 2:
        logger.info("[Web] Search triggered by 'latest' keyword")
        return True

    return False

def extract_search_query(text: str) -> str:
    """Extract the search query from user message."""
    # Remove common prefixes
    text_lower = text.lower()
    prefixes = [
        "search for", "search the web for", "look up", "find out about",
        "google", "search online for", "find online", "search internet for",
        "what is the latest on", "what are the latest", "can you search",
        "please search", "could you search", "search"
    ]

    result = text
    for prefix in prefixes:
        if text_lower.startswith(prefix):
            result = text[len(prefix):].strip()
            break

    # Clean up
    result = result.strip("?.,!")
    return result if result else text

async def fetch_url_content(url: str) -> Optional[str]:
    """Fetch content from a URL and extract text."""
    try:
        logger.info(f"[Web] Fetching URL: {url}")
        async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as client:
            response = await client.get(url, headers={
                "User-Agent": "Mozilla/5.0 (compatible; AIStack/1.0)"
            })

            if response.status_code != 200:
                logger.warning(f"[Web] URL returned {response.status_code}: {url}")
                return None

            content_type = response.headers.get("content-type", "")

            if "text/html" in content_type:
                # Simple HTML text extraction
                html = response.text
                # Remove script and style tags
                html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
                html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)
                # Remove HTML tags
                text = re.sub(r'<[^>]+>', ' ', html)
                # Clean up whitespace
                text = re.sub(r'\s+', ' ', text).strip()
                # Truncate
                if len(text) > MAX_URL_CONTENT_LENGTH:
                    text = text[:MAX_URL_CONTENT_LENGTH] + "..."
                logger.info(f"[Web] Fetched {len(text)} chars from {url}")
                return text

            elif "text/plain" in content_type or "application/json" in content_type:
                text = response.text[:MAX_URL_CONTENT_LENGTH]
                if len(response.text) > MAX_URL_CONTENT_LENGTH:
                    text += "..."
                return text

            else:
                logger.warning(f"[Web] Unsupported content type: {content_type}")
                return None

    except Exception as e:
        logger.error(f"[Web] Failed to fetch {url}: {e}")
        return None

async def search_web(query: str) -> List[Dict[str, str]]:
    """Search the web using SearXNG."""
    try:
        search_url = f"{SEARXNG_URL}/search"
        logger.info(f"[Web] Searching: {query}")

        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(search_url, params={
                "q": query,
                "format": "json",
                "categories": "general"
            })

            if response.status_code != 200:
                logger.warning(f"[Web] Search returned {response.status_code}")
                return []

            data = response.json()
            results = []

            for item in data.get("results", [])[:MAX_SEARCH_RESULTS]:
                results.append({
                    "title": item.get("title", ""),
                    "url": item.get("url", ""),
                    "content": item.get("content", "")[:500]
                })

            logger.info(f"[Web] Found {len(results)} search results")
            return results

    except Exception as e:
        logger.error(f"[Web] Search failed: {e}")
        return []

async def enhance_with_web_content(messages: List[Dict], user_message: str) -> List[Dict]:
    """Enhance messages with web content (URLs or search results)."""
    web_context = []

    # Check for URLs in the message
    urls = extract_urls(user_message)
    if urls:
        for url in urls[:3]:  # Limit to 3 URLs
            content = await fetch_url_content(url)
            if content:
                web_context.append(f"[Content from {url}]:\n{content}")

    # Check if web search is needed
    elif needs_web_search(user_message):
        search_query = extract_search_query(user_message)
        results = await search_web(search_query)
        if results:
            search_text = f"[Web search results for: {search_query}]\n\n"
            for i, r in enumerate(results, 1):
                search_text += f"{i}. {r['title']}\n   URL: {r['url']}\n   {r['content']}\n\n"
            web_context.append(search_text)

    # If we have web context, inject it into messages
    if web_context:
        # Find the last user message and prepend web context to it
        messages = [msg.copy() for msg in messages]  # Deep copy

        for i in range(len(messages) - 1, -1, -1):
            if messages[i].get("role") == "user":
                original_content = messages[i].get("content", "")
                web_info = "\n\n".join(web_context)

                # Prepend web results directly to user message
                messages[i]["content"] = f"""I found this current information from the web that you should use to answer my question:

---WEB SEARCH RESULTS (USE THIS INFO)---
{web_info}
---END WEB RESULTS---

Now, using the above web information, please answer: {original_content}"""

                logger.info(f"[Web] Injected web context into user message")
                break

    return messages

# =============================================================================
# Conversation Memory (FAISS + SQLite)
# =============================================================================

class ConversationMemory:
    """
    FAISS-powered conversation memory with SQLite metadata storage.
    """

    def __init__(self, data_dir: str):
        self.data_dir = data_dir
        self.faiss_path = os.path.join(data_dir, "memory.faiss")
        self.db_path = os.path.join(data_dir, "memory.db")

        os.makedirs(data_dir, exist_ok=True)

        self.index = self._load_or_create_index()
        self._init_database()
        self._embedding_cache: Dict[str, np.ndarray] = {}

    def _load_or_create_index(self) -> faiss.IndexFlatIP:
        """Load existing FAISS index or create new one."""
        if os.path.exists(self.faiss_path):
            logger.info(f"[Memory] Loading FAISS index from {self.faiss_path}")
            return faiss.read_index(self.faiss_path)
        else:
            logger.info(f"[Memory] Creating new FAISS index (dim={EMBEDDING_DIM})")
            return faiss.IndexFlatIP(EMBEDDING_DIM)

    def _init_database(self):
        """Initialize SQLite database with messages table."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                faiss_id INTEGER UNIQUE,
                user_id TEXT,
                session_id TEXT,
                role TEXT,
                content TEXT,
                model_used TEXT,
                query_type TEXT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)

        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_user_session
            ON messages(user_id, session_id)
        """)

        conn.commit()
        conn.close()
        logger.info(f"[Memory] SQLite database initialized at {self.db_path}")

    async def get_embedding(self, text: str) -> np.ndarray:
        """Get embedding vector for text using Ollama embedding API."""
        cache_key = text[:200]
        if cache_key in self._embedding_cache:
            return self._embedding_cache[cache_key]

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{OLLAMA_BASE_URL}/api/embeddings",
                    json={"model": EMBEDDING_MODEL, "prompt": text}
                )

                if response.status_code != 200:
                    logger.error(f"[Memory] Embedding error: {response.text}")
                    return np.zeros(EMBEDDING_DIM, dtype=np.float32)

                data = response.json()
                embedding = np.array(data["embedding"], dtype=np.float32)

                norm = np.linalg.norm(embedding)
                if norm > 0:
                    embedding = embedding / norm

                self._embedding_cache[cache_key] = embedding
                return embedding
        except Exception as e:
            logger.error(f"[Memory] Embedding failed: {e}")
            return np.zeros(EMBEDDING_DIM, dtype=np.float32)

    async def store_message(
        self,
        content: str,
        role: str,
        user_id: str = "default",
        session_id: str = "default",
        model_used: str = None,
        query_type: str = None
    ):
        """Store a message in memory with its embedding."""
        embedding = await self.get_embedding(content)

        faiss_id = self.index.ntotal
        self.index.add(embedding.reshape(1, -1))

        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("""
            INSERT INTO messages (faiss_id, user_id, session_id, role, content, model_used, query_type)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (faiss_id, user_id, session_id, role, content, model_used, query_type))

        conn.commit()
        conn.close()

        if faiss_id % 10 == 0:
            self.save_index()

    async def retrieve_context(
        self,
        query: str,
        user_id: str = "default",
        k: int = MAX_CONTEXT_MESSAGES
    ) -> List[Dict[str, Any]]:
        """Retrieve relevant past messages for context."""
        if self.index.ntotal == 0:
            return []

        query_embedding = await self.get_embedding(query)

        scores, indices = self.index.search(
            query_embedding.reshape(1, -1),
            min(k * 2, self.index.ntotal)
        )

        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        results = []
        for score, idx in zip(scores[0], indices[0]):
            if idx == -1 or score < SIMILARITY_THRESHOLD:
                continue

            cursor.execute("""
                SELECT role, content, model_used, query_type, timestamp
                FROM messages
                WHERE faiss_id = ? AND user_id = ?
            """, (int(idx), user_id))

            row = cursor.fetchone()
            if row:
                results.append({
                    "role": row[0],
                    "content": row[1],
                    "model_used": row[2],
                    "query_type": row[3],
                    "timestamp": row[4],
                    "similarity": float(score)
                })

            if len(results) >= k:
                break

        conn.close()
        results.sort(key=lambda x: x["timestamp"], reverse=True)
        return results

    def save_index(self):
        """Persist FAISS index to disk."""
        faiss.write_index(self.index, self.faiss_path)
        logger.info(f"[Memory] FAISS index saved ({self.index.ntotal} vectors)")

    def get_stats(self) -> Dict[str, Any]:
        """Get memory statistics."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("SELECT COUNT(*) FROM messages")
        message_count = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(DISTINCT user_id) FROM messages")
        user_count = cursor.fetchone()[0]

        conn.close()

        return {
            "total_messages": message_count,
            "faiss_vectors": self.index.ntotal,
            "unique_users": user_count,
            "embedding_cache_size": len(self._embedding_cache)
        }

# =============================================================================
# Query Classification
# =============================================================================

def classify_query(messages: list) -> str:
    """Classify query based on keywords."""
    text = ""
    for msg in reversed(messages):
        if msg.get("role") == "user":
            content = msg.get("content", "")
            if isinstance(content, list):
                for part in content:
                    if isinstance(part, dict) and part.get("type") == "text":
                        text = part.get("text", "").lower()
                        break
            else:
                text = content.lower()
            break

    if not text:
        return "general"

    # Check for summarization keywords first (more specific)
    for keyword in SUMMARY_KEYWORDS:
        if word_match(keyword, text):
            logger.info(f"Classified as SUMMARIZATION (keyword: {keyword})")
            return "summarization"

    # Check for coding keywords
    for keyword in CODING_KEYWORDS:
        if word_match(keyword, text):
            logger.info(f"Classified as CODING (keyword: {keyword})")
            return "coding"

    logger.info("Classified as GENERAL (no specific keywords)")
    return "general"

def get_model_for_classification(classification: str) -> str:
    """Map classification to model."""
    if classification == "coding":
        return CODING_MODEL
    elif classification == "summarization":
        return GENERAL_MODEL
    return GENERAL_MODEL

# =============================================================================
# FastAPI Application
# =============================================================================

memory: Optional[ConversationMemory] = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    global memory

    logger.info(f"[Router] Starting Smart Router...")
    logger.info(f"[Router] Ollama URL: {OLLAMA_BASE_URL}")
    logger.info(f"[Router] SearXNG URL: {SEARXNG_URL}")
    logger.info(f"[Router] Models - Coding: {CODING_MODEL}, General: {GENERAL_MODEL}")
    logger.info(f"[Router] Data Directory: {DATA_DIR}")
    logger.info(f"[Router] Web features: URL fetching + Auto search enabled")

    memory = ConversationMemory(DATA_DIR)

    yield

    if memory:
        memory.save_index()
        logger.info("[Router] Memory saved. Shutting down.")

app = FastAPI(
    title="Smart Router",
    description="Intelligent query router with conversation memory and web access",
    version="3.0.0",
    lifespan=lifespan
)

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "version": "3.0.0",
        "features": ["routing", "memory", "url_fetch", "web_search"],
        "memory_stats": memory.get_stats() if memory else None
    }

@app.get("/v1/models")
async def list_models():
    """List available models."""
    return {
        "object": "list",
        "data": [
            {"id": "auto", "object": "model", "created": 0, "owned_by": "smart-router"},
            {"id": CODING_MODEL, "object": "model", "created": 0, "owned_by": "ollama"},
            {"id": GENERAL_MODEL, "object": "model", "created": 0, "owned_by": "ollama"},
        ]
    }

@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """OpenAI-compatible chat completions with intelligent routing, memory, and web access."""
    global memory

    body = await request.json()
    messages = body.get("messages", [])

    # Validate messages
    if not messages:
        raise HTTPException(status_code=400, detail="messages cannot be empty")

    requested_model = body.get("model", "auto")
    stream = body.get("stream", False)
    user_id = body.get("user", "default")

    # Get the last user message
    last_user_msg = None
    for msg in reversed(messages):
        if msg.get("role") == "user":
            content = msg.get("content", "")
            if isinstance(content, str):
                last_user_msg = content
            break

    # Enhance messages with web content (URL fetching or search)
    if last_user_msg:
        messages = await enhance_with_web_content(messages, last_user_msg)

    # Determine target model
    if requested_model == "auto":
        classification = classify_query(messages)
        target_model = get_model_for_classification(classification)
        logger.info(f"[Router] Auto-routing: {classification} -> {target_model}")
    else:
        target_model = requested_model
        classification = "manual"
        logger.info(f"[Router] Manual selection: {target_model}")

    # Retrieve context from memory
    if memory and last_user_msg:
        context_messages = await memory.retrieve_context(last_user_msg, user_id)

        if context_messages and context_messages[0]["similarity"] > 0.75:
            context_text = "\n".join([
                f"[Previous {m['query_type']} conversation]: {m['content'][:200]}..."
                for m in context_messages[:3]
            ])

            system_idx = 0
            for i, msg in enumerate(messages):
                if msg.get("role") == "system":
                    system_idx = i + 1
                    break

            messages.insert(system_idx, {
                "role": "system",
                "content": f"Relevant context from previous conversations:\n{context_text}"
            })
            logger.info(f"[Router] Added {len(context_messages)} context messages")

    # Store user message in memory
    if memory and last_user_msg:
        await memory.store_message(
            content=last_user_msg,
            role="user",
            user_id=user_id,
            query_type=classification
        )

    # Forward to Ollama
    body["messages"] = messages
    body["model"] = target_model

    if stream:
        async def stream_response():
            full_response = ""
            async with httpx.AsyncClient(timeout=300.0) as client:
                async with client.stream(
                    "POST",
                    f"{OLLAMA_BASE_URL}/v1/chat/completions",
                    json=body,
                    headers={"Content-Type": "application/json"}
                ) as response:
                    async for chunk in response.aiter_bytes():
                        try:
                            chunk_str = chunk.decode()
                            for line in chunk_str.split("\n"):
                                if line.startswith("data: ") and line != "data: [DONE]":
                                    data = json.loads(line[6:])
                                    delta = data.get("choices", [{}])[0].get("delta", {})
                                    if "content" in delta:
                                        full_response += delta["content"]
                        except:
                            pass
                        yield chunk

            if memory and full_response:
                await memory.store_message(
                    content=full_response,
                    role="assistant",
                    user_id=user_id,
                    model_used=target_model,
                    query_type=classification
                )

        return StreamingResponse(stream_response(), media_type="text/event-stream")
    else:
        async with httpx.AsyncClient(timeout=300.0) as client:
            response = await client.post(
                f"{OLLAMA_BASE_URL}/v1/chat/completions",
                json=body,
                headers={"Content-Type": "application/json"}
            )

            result = response.json()

            if memory and "choices" in result:
                assistant_content = result["choices"][0].get("message", {}).get("content", "")
                if assistant_content:
                    await memory.store_message(
                        content=assistant_content,
                        role="assistant",
                        user_id=user_id,
                        model_used=target_model,
                        query_type=classification
                    )

            return JSONResponse(content=result)

@app.get("/v1/memory/stats")
async def memory_stats():
    """Get conversation memory statistics."""
    if not memory:
        raise HTTPException(status_code=503, detail="Memory not initialized")
    return memory.get_stats()

@app.post("/v1/memory/search")
async def memory_search(request: Request):
    """Search conversation memory."""
    if not memory:
        raise HTTPException(status_code=503, detail="Memory not initialized")

    body = await request.json()
    query = body.get("query", "")
    user_id = body.get("user_id", "default")
    k = body.get("k", 5)

    results = await memory.retrieve_context(query, user_id, k)
    return {"results": results}

# New endpoint to manually fetch a URL
@app.post("/v1/fetch")
async def fetch_url(request: Request):
    """Manually fetch content from a URL."""
    body = await request.json()
    url = body.get("url", "")

    if not url:
        raise HTTPException(status_code=400, detail="url is required")

    content = await fetch_url_content(url)
    if content:
        return {"url": url, "content": content}
    else:
        raise HTTPException(status_code=502, detail="Failed to fetch URL")

# New endpoint to manually search
@app.post("/v1/search")
async def search(request: Request):
    """Manually search the web."""
    body = await request.json()
    query = body.get("query", "")

    if not query:
        raise HTTPException(status_code=400, detail="query is required")

    results = await search_web(query)
    return {"query": query, "results": results}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
