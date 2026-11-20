# RSS2 — Agregador multilingüe de noticias RSS
# Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
# SPDX-License-Identifier: MIT

FROM python:3.11-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    patchelf gcc git curl wget \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    TOKENIZERS_PARALLELISM=false \
    HF_HOME=/root/.cache/huggingface

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip

# CPU-only PyTorch
RUN pip install --no-cache-dir torch==2.15.0 --index-url https://download.pytorch.org/whl/cpu

RUN pip install --no-cache-dir \
    ctranslate2==4.9.0 \
    sentencepiece==0.2.3 \
    transformers==5.23.0 \
    protobuf==6.33.5 \
    "numpy==1.26.4" \
    websocket-client

RUN find /usr/local/lib/python3.11/site-packages/ctranslate2* \
    -name "libctranslate2-*.so.*" -o -name "libctranslate2.so*" | \
    xargs -I {} patchelf --clear-execstack {} || true

COPY worker.py /app/worker.py

# Valores por defecto: CPU + int8 (sin GPU)
ENV CT2_DEVICE=${CT2_DEVICE:-cpu}
ENV CT2_COMPUTE_TYPE=${CT2_COMPUTE_TYPE:-int8}

CMD ["python", "/app/worker.py"]