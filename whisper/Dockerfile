FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04

WORKDIR /app

RUN apt-get update && apt-get install -y \
    ffmpeg \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN pip3 install --no-cache-dir -r requirements.txt

COPY app.py .

ENV WHISPER_MODEL=large-v3
ENV DEVICE=cuda
ENV COMPUTE_TYPE=float16

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "9000"]
