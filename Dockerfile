# IBVAP — single-container deployment image (CPU inference)
#
# Why CPU-torch: free cloud hosts give 2 vCPU / ~16 GB RAM / no GPU. The CPU
# CUDA wheels (2.5+ GB of nvidia-* packages) are dead weight there, and torch
# falls back to CPU automatically when CUDA is absent — same code, no config.
#
# Local GPU demo stays as-is (native venv, scripts/start_ibvap.bat).
#
# Build:  docker build -t ibvap .
# Run:    docker run --rm -p 8000:8000 --env-file deploy/env.cloud.example ibvap
#           (expects a reachable Postgres; DATABASE_URL points at it)

FROM python:3.11-slim-bookworm

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

# opencv needs libgl/libglib; ffmpeg gives OpenCV every practical decoder
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 libglib2.0-0 ffmpeg curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ---- frontend build -------------------------------------------------------
COPY frontend/package.json frontend/package-lock.json frontend/
RUN cd frontend && npm ci

COPY frontend/ frontend/
RUN cd frontend && npm run build && rm -rf frontend/src frontend/node_modules

# ---- backend deps ---------------------------------------------------------
COPY backend/requirements.txt backend/requirements.txt
# Install CPU torch first (pinned, ~200 MB) so the resolver keeps it,
# then the rest of the requirements (ultralytics will not override it).
RUN pip install --no-cache-dir torch==2.3.1 --index-url https://download.pytorch.org/whl/cpu \
    && pip install --no-cache-dir -r backend/requirements.txt

# ---- app ------------------------------------------------------------------
COPY backend/ backend/
COPY USER_MANUAL.md README.md ./

# Bake demo videos + models into the image so a cold Space boots with working
# simulated feeds; pipeline auto-downloads them if missing (offline-safe).
COPY assets/videos/ assets/videos/
COPY yolo11n.pt .

# Evidence must be writable in-container
RUN mkdir -p evidence assets/models && chmod -R a+w evidence assets/models

ENV IBVAP_DEMO=1 \
    IBVAP_CPU_ONLY=1 \
    API_HOST=0.0.0.0 \
    API_PORT=8000

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s \
    CMD curl -fsS http://127.0.0.1:8000/api/health || exit 1

CMD ["python", "-m", "uvicorn", "app.main:app", \
     "--app-dir", "backend", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
