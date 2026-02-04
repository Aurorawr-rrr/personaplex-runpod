# PersonaPlex RunPod Serverless Dockerfile
# Based on NVIDIA's official PersonaPlex Dockerfile with RunPod integration

ARG BASE_IMAGE="nvcr.io/nvidia/cuda"
ARG BASE_IMAGE_TAG="12.4.1-runtime-ubuntu22.04"

FROM ${BASE_IMAGE}:${BASE_IMAGE_TAG} AS base

# Install uv for fast Python package management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    libopus-dev \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Clone PersonaPlex repository
# Note: You can also COPY a local clone instead
RUN git clone https://github.com/NVIDIA/personaplex.git /app/personaplex-repo

# Copy moshi module from cloned repo
RUN cp -r /app/personaplex-repo/moshi /app/moshi

# Create Python virtual environment and install dependencies
WORKDIR /app/moshi
RUN uv venv /app/moshi/.venv --python 3.12
RUN uv sync

# Install RunPod SDK
RUN /app/moshi/.venv/bin/pip install runpod

# Create SSL directory
RUN mkdir -p /app/ssl

# Copy RunPod handler
WORKDIR /app
COPY rp_handler.py /app/rp_handler.py

# Environment variables
ENV PYTHONUNBUFFERED=1
ENV HF_HOME=/app/.cache/huggingface
ENV PERSONAPLEX_PORT=8998

# Pre-download model weights (optional - makes cold starts faster but increases image size)
# Uncomment if you want model baked into the image:
# ARG HF_TOKEN
# RUN if [ -n "$HF_TOKEN" ]; then \
#     /app/moshi/.venv/bin/python -c "from huggingface_hub import snapshot_download; snapshot_download('nvidia/personaplex-7b-v1', token='$HF_TOKEN')"; \
# fi

# Expose PersonaPlex server port
EXPOSE 8998

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8998/health || exit 1

# Run the RunPod handler
CMD ["/app/moshi/.venv/bin/python", "/app/rp_handler.py"]
