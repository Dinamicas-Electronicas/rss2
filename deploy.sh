#!/usr/bin/env bash
# RSS2 — Agregador multilingüe de noticias RSS
# Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
# SPDX-License-Identifier: MIT

# Despliegue de RSS2 en un solo paso.
#
#   ./deploy.sh                 # primera instalación y actualizaciones
#   ./deploy.sh --with-tts      # incluye el servicio de voz (pesado)
#   ./deploy.sh --no-seed       # no importa feeds.csv
#   ./deploy.sh --no-build      # omite el build explícito (usa la caché)
#
# Hace, en orden:
#   1. Crea .env con credenciales aleatorias si no existe.
#   2. Crea los directorios de datos y modelos.
#   3. Construye las imágenes en el orden correcto (backend primero: los
#      workers Go reutilizan su imagen).
#   4. Levanta la base de datos y siembra `feeds` desde feeds.csv antes de
#      arrancar el ingestor (idempotente).
#   5. Levanta el resto del stack y espera a que la API responda.
#
# La primera ejecución descarga modelos de HuggingFace y compila torch/spaCy:
# entre 20 y 40 minutos según la máquina. Las siguientes usan la caché.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

color() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33mAVISO: %s\033[0m\n' "$*"; }
die()   { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Uso:
  ./deploy.sh                 primera instalación y actualizaciones
  ./deploy.sh --with-tts      incluye el servicio de voz (pesado)
  ./deploy.sh --no-seed       no importa feeds.csv
  ./deploy.sh --no-build      omite el build explícito (usa la caché)
  ./deploy.sh --help          muestra esta ayuda
EOF
}

WITH_TTS=0
SEED_FEEDS=1
DO_BUILD=1

for arg in "$@"; do
    case "$arg" in
        --with-tts) WITH_TTS=1 ;;
        --no-seed)  SEED_FEEDS=0 ;;
        --no-build) DO_BUILD=0 ;;
        -h|--help)  usage; exit 0 ;;
        *) die "opción desconocida: $arg (usa --help)" ;;
    esac
done

command -v docker >/dev/null 2>&1 || die "Docker no está instalado"
docker compose version >/dev/null 2>&1 || die "se requiere Docker Compose v2 (docker compose)"
command -v curl >/dev/null 2>&1 || die "se requiere curl"

color "1/5 Preparando credenciales y directorios"
./scripts/bootstrap-env.sh
mkdir -p data/wiki_images data/tts_audio data/tts_voices data/tts_tmp \
         data/redis-data data/prometheus data/grafana models hf_cache
# Grafana (uid 472) y Prometheus (nobody) no pueden escribir en directorios
# creados por el usuario del host: sin esto el perfil `monitoring` entra en
# bucle de reinicio con "GF_PATHS_DATA is not writable".
chmod 0777 data/prometheus data/grafana
chmod +x scripts/seed-feeds.sh

# Se leen solo las claves necesarias: `source .env` ejecutaria cualquier
# contenido del fichero y rompe con valores que llevan espacios.
env_value() {
    grep -E "^$1=" .env 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'"
}
PORT="$(env_value RSS2_PORT)"; PORT="${PORT:-8888}"
PG_USER="$(env_value POSTGRES_USER)"; PG_USER="${PG_USER:-rss}"
PG_DB="$(env_value POSTGRES_DB)"; PG_DB="${PG_DB:-rss}"

if [ "$DO_BUILD" = "1" ]; then
    color "2/5 Construyendo imágenes (la primera vez tarda 20-40 min)"
    # En serie, no en paralelo: en máquinas de 4 núcleos compilar torch y
    # spaCy a la vez dispara la carga y puede acabar en OOM.
    # backend primero: su imagen la reutilizan 7 workers Go.
    for svc in backend frontend ingestor translator; do
        echo "    -> $svc"
        # --pull refresca las imagenes base (python/node/golang/alpine): sin
        # esto Docker reutiliza la etiqueta local y un redespliegue no recoge
        # los parches de seguridad publicados desde el build anterior.
        docker compose build --pull "$svc"
    done
    # Después el resto. langdetect no se construye aquí: reutiliza la imagen
    # de translation-scheduler (rss2-pyworkers).
    for svc in translation-scheduler ner embeddings; do
        echo "    -> $svc"
        docker compose build --pull "$svc"
    done
else
    color "2/5 Omitiendo build (--no-build)"
    warn "--no-build reutiliza las imagenes YA construidas."
    warn "Si cambiaste Dockerfiles, dependencias o versiones base, NO se aplicaran."
fi

color "3/5 Preparando la base de datos"
# La base se levanta sola y se siembra ANTES de arrancar el ingestor: su
# primer ciclo es inmediato y, si la tabla `feeds` estuviera vacía, no habría
# noticias hasta el siguiente tick (RSS_POKE_INTERVAL_MIN).
docker compose up -d db

for _ in $(seq 1 60); do
    # -h 127.0.0.1: por socket pg_isready responde durante la inicialización.
    if docker compose exec -T db pg_isready -h 127.0.0.1 -U "$PG_USER" -d "$PG_DB" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

if [ "$SEED_FEEDS" = "1" ]; then
    ./scripts/seed-feeds.sh
fi

# La imagen fija pgvector 0.8.7. Si la base venia de una version anterior de la
# extension, esto actualiza el SQL de la extension. Es idempotente: si ya esta
# al dia no hace nada, y `IF EXISTS` cubre una base recien creada.
docker compose exec -T db psql -U "$PG_USER" -d "$PG_DB" \
    -c "ALTER EXTENSION IF EXISTS vector UPDATE;" >/dev/null 2>&1 || true

color "4/5 Levantando servicios"
# En la primera ejecución `up` se queda esperando a translator-models, que
# descarga y convierte NLLB (~2,4 GB, 5-15 min). No está colgado:
#   docker compose logs -f translator-models
if ! docker compose up -d; then
    die "el stack no arrancó. Revisa: docker compose logs --tail=80 db backend translator-models"
fi

if [ "$WITH_TTS" = "1" ]; then
    if [ ! -d models/chatterbox ] || [ ! -d models/openvoice ]; then
        warn "Faltan los pesos de TTS. Ejecuta 'make tts-models' y vuelve a lanzar"
        warn "'docker compose --profile tts up -d tts' cuando termine la descarga."
    else
        color "   Construyendo y levantando TTS"
        docker compose --profile tts build --pull tts
        docker compose --profile tts up -d tts
    fi
fi

color "5/5 Esperando a que la API responda (puede tardar varios minutos)"
READY=0
for _ in $(seq 1 300); do
    # /api/news no usa caché: si se sondea /api/stats antes de que el
    # ingestor inserte nada, el "0" se queda cacheado y la portada parece
    # vacía aunque ya haya noticias.
    if curl -fsS "http://127.0.0.1:${PORT}/api/news?page=1&per_page=1" >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 2
done

docker compose ps

if [ "$READY" != "1" ]; then
    warn "La API todavía no responde. Revisa los logs:"
    echo "    docker compose logs --tail=50 backend nginx"
    exit 1
fi

cat <<EOF

RSS2 está funcionando:

    Web        http://localhost:${PORT}
    API        http://localhost:${PORT}/api
    Salud      http://localhost:${PORT}/api/stats

El PRIMER usuario que se registre queda como administrador.
El ingestor empieza a traer noticias en el siguiente ciclo (unos minutos).
Si es la primera vez, el traductor sigue convirtiendo NLLB en segundo plano:
    docker compose logs -f translator-models

Comandos útiles:
    make verify
    docker compose ps
    docker compose logs -f backend ingestor translator
    ./deploy.sh --with-tts        # añadir el noticiario por voz (tras make tts-models)
    docker compose --profile monitoring up -d
EOF
