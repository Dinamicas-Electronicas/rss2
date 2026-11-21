#!/usr/bin/env bash
# RSS2 — Agregador multilingüe de noticias RSS
# Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
# SPDX-License-Identifier: MIT

# Siembra la tabla `feeds` desde feeds.csv.
#
# Sin feeds el ingestor no tiene nada que recolectar y la aplicación arranca
# vacía. El CSV del repositorio es la lista curada de fuentes (1.655 filas).
#
# Uso:
#   ./scripts/seed-feeds.sh            # feeds.csv del repositorio
#   ./scripts/seed-feeds.sh otro.csv   # cualquier CSV con las mismas columnas
#
# Es idempotente: las URLs que ya existen se dejan intactas
# (ON CONFLICT (url) DO NOTHING), así que se puede ejecutar en cada despliegue.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CSV="${1:-feeds.csv}"
if [ ! -f "$CSV" ]; then
    echo "ERROR: no se encuentra el CSV de feeds: $CSV" >&2
    exit 1
fi

if [ ! -f .env ]; then
    echo "ERROR: falta .env (ejecuta ./scripts/bootstrap-env.sh)" >&2
    exit 1
fi

# Carga POSTGRES_USER / POSTGRES_DB del .env sin exportar el resto.
DB_USER="$(grep -E '^POSTGRES_USER=' .env | cut -d= -f2- | tr -d '"' | tr -d "'")"
DB_NAME="$(grep -E '^POSTGRES_DB=' .env | cut -d= -f2- | tr -d '"' | tr -d "'")"
DB_USER="${DB_USER:-rss}"
DB_NAME="${DB_NAME:-rss}"

psql_run() {
    docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" "$@"
}

echo "==> Esperando a que el esquema esté inicializado"
# En el primer arranque Postgres está aceptando conexiones (y pg_isready dice
# "ok") MIENTRAS aplica init-db/. Se espera a una tabla de las últimas
# migraciones (66) para no sembrar ni arrancar el ingestor con un esquema a
# medias (noticias.feed_id es de la 61 y noticias.lang de la 64).
for _ in $(seq 1 150); do
    if psql_run -tA -c "SELECT to_regclass('public.feeds') IS NOT NULL AND to_regclass('public.noticias_enrich_log') IS NOT NULL" 2>/dev/null | grep -q '^t$'; then
        break
    fi
    sleep 2
done

echo "==> Sembrando feeds desde $CSV"

psql_run -q -c "
CREATE UNLOGGED TABLE IF NOT EXISTS _seed_feeds (
    id            INTEGER,
    nombre        TEXT,
    descripcion   TEXT,
    url           TEXT,
    categoria_id  INTEGER,
    categoria     TEXT,
    pais_id       INTEGER,
    pais          TEXT,
    idioma        TEXT,
    activo        TEXT,
    fallos        TEXT
);"

psql_run -q -c "TRUNCATE _seed_feeds;"

# \copy es una meta-orden de psql: lee el CSV por la entrada estándar del
# contenedor (docker compose exec -T), sin montar el fichero en la BD.
psql_run -q -c "\\copy _seed_feeds FROM pstdin WITH (FORMAT csv, HEADER true)" < "$CSV"

BEFORE="$(psql_run -tA -c "SELECT count(*) FROM feeds;")"

# categoria_id / pais_id se resuelven por nombre para no depender de que los
# ids del CSV coincidan con el seed de init-db/.
psql_run -q -c "
INSERT INTO feeds (nombre, descripcion, url, categoria_id, pais_id, idioma, activo, fallos)
SELECT
    NULLIF(btrim(s.nombre), ''),
    NULLIF(btrim(s.descripcion), ''),
    btrim(s.url),
    c.id,
    p.id,
    NULLIF(left(lower(btrim(coalesce(s.idioma, ''))), 2), ''),
    CASE
        WHEN lower(btrim(coalesce(s.activo, 'true'))) IN ('true', 't', '1', 'yes', 'si') THEN TRUE
        ELSE FALSE
    END,
    CASE
        WHEN btrim(coalesce(s.fallos, '')) ~ '^[0-9]+$' THEN btrim(s.fallos)::integer
        ELSE 0
    END
FROM _seed_feeds s
LEFT JOIN categorias c ON c.nombre = btrim(s.categoria)
LEFT JOIN paises p     ON p.nombre = btrim(s.pais)
WHERE coalesce(btrim(s.url), '') <> ''
ON CONFLICT (url) DO NOTHING;"

psql_run -q -c "DROP TABLE IF EXISTS _seed_feeds;"

AFTER="$(psql_run -tA -c "SELECT count(*) FROM feeds;")"

echo "==> Feeds en la base de datos: ${AFTER} (nuevos: $((AFTER - BEFORE)))"

# El INSERT va por SQL directo, así que no pasa por el CRUD y no dispara la
# invalidación de caché del backend: sin esto, con el backend levantado la
# lista de feeds seguiría devolviendo total=0 hasta una hora (TTLMedium).
# Best-effort: si Redis no está levantado (primer arranque) no hay caché que
# purgar y el script no debe fallar por ello.
REDIS_PASS="$(grep -E '^REDIS_PASSWORD=' .env | cut -d= -f2- | tr -d '"' | tr -d "'")"
if docker compose ps --status running --services 2>/dev/null | grep -qx redis; then
    docker compose exec -T -e REDIS_PASSWORD="$REDIS_PASS" redis sh -lc '
        redis-cli --no-auth-warning -a "$REDIS_PASSWORD" DEL stats >/dev/null
        for k in $(redis-cli --no-auth-warning -a "$REDIS_PASSWORD" --scan --pattern "feedlist:*"); do
            redis-cli --no-auth-warning -a "$REDIS_PASSWORD" DEL "$k" >/dev/null
        done' >/dev/null 2>&1 || true
    echo "==> Caché de stats y listado de feeds invalidada"
fi
