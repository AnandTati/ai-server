# Smart Router Dockerfile
# =======================
# Builds the intelligent query router with FAISS memory support
#
# Dependencies:
#   - fastapi: Web framework for API endpoints
#   - uvicorn: ASGI server
#   - httpx: Async HTTP client for Ollama communication
#   - faiss-cpu: Facebook AI Similarity Search for vector storage
#   - numpy: Required for FAISS operations

FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for FAISS
# libgomp1: OpenMP runtime required by FAISS for parallel operations
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    fastapi \
    uvicorn \
    httpx \
    faiss-cpu \
    numpy

# Copy application code
COPY main.py .

# Create data directory (will be mounted as volume)
RUN mkdir -p /data

EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
