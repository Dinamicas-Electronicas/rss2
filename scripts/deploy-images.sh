#!/usr/bin/env bash
# RSS2 — Agregador multilingüe de noticias RSS
# Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
# SPDX-License-Identifier: MIT

# Despliega las imagenes publicadas en GHCR (no construye en el host).
#
#   ./scripts/deploy-images.sh
#   RSS2_TAG=sha-752ad1e ./scripts/deploy-images.sh
#   RSS2_REGISTRY=ghcr.io/mi-fork ./scripts/deploy-images.sh
#
# Requiere que los paquetes de GHCR sean publicos, o haber hecho antes:
#   docker login ghcr.io -u <usuario> -p <token-con-read:packages>

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILES=(-f docker-compose.yml -f docker-compose.images.yml)
TAG="${RSS2_TAG:-latest}"

echo "==> Descargando imagenes (tag: $TAG)"
docker compose "${FILES[@]}" pull

echo "==> Levantando servicios sin construir"
docker compose "${FILES[@]}" up -d --no-build --remove-orphans

# La imagen fija pgvector 0.8.7: actualiza el SQL de la extension si la base
# venia de una version anterior. Idempotente.
echo "==> Actualizando extension vector de PostgreSQL"
docker compose "${FILES[@]}" exec -T db sh -c \
    'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER EXTENSION IF EXISTS vector UPDATE;"' \
    >/dev/null 2>&1 || true

# nginx resuelve el upstream del backend al arrancar: tras recrearlo hay que
# reiniciarlo para que no se quede con la IP antigua.
echo "==> Reiniciando nginx"
docker compose "${FILES[@]}" restart nginx >/dev/null 2>&1 || true

echo "==> Estado"
docker compose "${FILES[@]}" ps
