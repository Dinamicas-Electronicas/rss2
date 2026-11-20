#!/usr/bin/env bash
# RSS2 — Agregador multilingüe de noticias RSS
# Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
# SPDX-License-Identifier: MIT

# Crea .env a partir de .env.example con contraseñas aleatorias.
#
# Es idempotente: si .env ya existe no lo toca (para no invalidar la base ni
# las sesiones existentes). Lo llama deploy.sh, pero también se puede ejecutar
# a mano: ./scripts/bootstrap-env.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ -f .env ]; then
    echo "==> .env ya existe; no se modifica"
    exit 0
fi

if [ ! -f .env.example ]; then
    echo "ERROR: no se encuentra .env.example" >&2
    exit 1
fi

gen_hex() {
    local bytes="$1"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex "$bytes"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import secrets; print(secrets.token_hex($bytes))"
    else
        echo "ERROR: se necesita openssl o python3 para generar credenciales" >&2
        exit 1
    fi
}

PG_PASSWORD="$(gen_hex 24)"
REDIS_PASSWORD="$(gen_hex 24)"
SECRET_KEY="$(gen_hex 32)"
GRAFANA_PASSWORD="$(gen_hex 16)"
TTS_API_KEY="$(gen_hex 32)"

cp .env.example .env

# Los valores son hexadecimales: seguros para sed y para las URLs de conexión.
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${PG_PASSWORD}|" .env
sed -i "s|^DB_PASS=.*|DB_PASS=${PG_PASSWORD}|" .env
sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${REDIS_PASSWORD}|" .env
sed -i "s|^SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|" .env
sed -i "s|^GRAFANA_PASSWORD=.*|GRAFANA_PASSWORD=${GRAFANA_PASSWORD}|" .env
sed -i "s|^TTS_API_KEY=.*|TTS_API_KEY=${TTS_API_KEY}|" .env

chmod 600 .env

cat <<EOF
==> .env creado con credenciales aleatorias (permisos 600)

    POSTGRES_PASSWORD / DB_PASS : ${PG_PASSWORD}
    REDIS_PASSWORD              : ${REDIS_PASSWORD}
    SECRET_KEY                  : guardada en .env
    GRAFANA_PASSWORD            : ${GRAFANA_PASSWORD}

    Guárdalas en un gestor de contraseñas. Si borras .env tendrás que
    regenerar la base de datos: las credenciales viven en data/pgdata.
EOF
