# =============================================================================
# konumumyemek.com · Production Dockerfile (Railway / Render / Cloud-Ready)
# =============================================================================
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8765

WORKDIR /app

# Sistem sertifikaları ve temel ağ araçları (Supabase HTTPS/TLS için)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Python bağımlılıkları (supabase-py)
COPY requirements.txt /app/requirements.txt
RUN pip install --upgrade pip && pip install -r /app/requirements.txt

# Web KDS Paneli, Supabase SQL Şeması ve Sunucu Dosyaları
COPY web /app/web
COPY supabase /app/supabase

EXPOSE 8765

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS http://127.0.0.1:${PORT}/api/health || exit 1

CMD ["python3", "/app/web/server.py"]
