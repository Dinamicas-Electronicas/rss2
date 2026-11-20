# RSS2 — Agregador multilingüe de noticias RSS
# Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
# SPDX-License-Identifier: MIT

FROM python:3.11-slim-bookworm

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev gcc git curl \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    TOKENIZERS_PARALLELISM=false \
    HF_HOME=/root/.cache/huggingface

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip

RUN pip install --no-cache-dir torch==2.15.0 --index-url https://download.pytorch.org/whl/cpu

RUN pip install --no-cache-dir \
    ctranslate2==4.9.0 \
    sentencepiece==0.2.3 \
    transformers==5.23.0 \
    protobuf==6.33.5 \
    "numpy==1.26.4" \
    psycopg2-binary==2.9.10 \
    redis \
    requests>=2.34.2 \
    beautifulsoup4>=4.15.0 \
    lxml>=6.1.3 \
    langdetect \
    nltk \
    scikit-learn>=1.9.1 \
    pandas \
    sentence-transformers==6.3.0 \
    spacy>=3.8,<4.0

RUN python -m spacy download es_core_news_lg

COPY workers/ ./workers/
COPY init-db/ ./init-db/
COPY migrations/ ./migrations/
COPY entity_config.json .

ENV DB_HOST=db
ENV DB_PORT=5432
ENV DB_NAME=rss
ENV DB_USER=rss
ENV DB_PASS=${DB_PASS}

CMD ["python", "-m", "workers.embeddings_worker"]
