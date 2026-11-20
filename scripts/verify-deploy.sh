#!/usr/bin/env bash
# RSS2 — Agregador multilingüe de noticias RSS
# Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
# SPDX-License-Identifier: MIT

# Comprueba que el despliegue está sano: contenedores, API y datos.
#
#   ./scripts/verify-deploy.sh
#
# Sale con código 0 si todo lo crítico está bien y 1 si algo falla. Es de solo
# lectura: no reinicia ni modifica nada.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

[ -f .env ] || { echo "ERROR: falta .env (ejecuta ./deploy.sh)" >&2; exit 1; }

env_value() {
    grep -E "^$1=" .env 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'"
}
PORT="$(env_value RSS2_PORT)"; PORT="${PORT:-8888}"
PG_USER="$(env_value POSTGRES_USER)"; PG_USER="${PG_USER:-rss}"
PG_DB="$(env_value POSTGRES_DB)"; PG_DB="${PG_DB:-rss}"

FAILED=0
ok()   { printf '  \033[1;32mOK\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; FAILED=1; }
skip() { printf '  \033[1;33mSKIP\033[0m %s\n' "$*"; }

echo "== Contenedores =="
check_container() {
    local name="$1" required="$2"
    if ! docker inspect "$name" >/dev/null 2>&1; then
        if [ "$required" = "required" ]; then bad "$name no existe"; else skip "$name no está levantado (perfil opcional)"; fi
        return
    fi
    local status health
    status="$(docker inspect -f '{{.State.Status}}' "$name")"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "$name")"
    if [ "$status" != "running" ]; then
        # translator-models es de un solo uso: terminar en exited 0 es correcto.
        if [ "$name" = "rss2_translator_models" ] && [ "$status" = "exited" ] && [ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ]; then
            ok "$name terminó correctamente (modelo preparado)"
        else
            bad "$name está en estado '$status'"
        fi
    elif [ "$health" = "healthy" ] || [ "$health" = "-" ]; then
        ok "$name ($status${health:+, $health})"
    else
        bad "$name ($status, health=$health)"
    fi
}

for c in rss2_db rss2_redis rss2_backend rss2_frontend rss2_nginx rss2_ingestor \
         rss2_langdetect rss2_translation_scheduler rss2_translator; do
    check_container "$c" required
done
for c in rss2_ner rss2_embeddings rss2_wiki rss2_topics rss2_related \
         rss2_event_clustering rss2_scraper rss2_discovery rss2_cooccurrences; do
    check_container "$c" optional
done
check_container rss2_tts optional

echo "== API =="
http_check() {
    local path="$1" label="$2"
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "http://127.0.0.1:${PORT}${path}" || echo 000)"
    if [ "$code" = "200" ]; then ok "$label ($path)"; else bad "$label ($path) -> HTTP $code"; fi
}
http_check "/api/stats" "estadísticas"
http_check "/api/news?page=1&per_page=1" "noticias"
http_check "/api/feeds?per_page=1" "feeds"
http_check "/api/categories" "categorías"
http_check "/api/countries" "países"

echo "== Datos =="
db_scalar() {
    docker compose exec -T db psql -tA -U "$PG_USER" -d "$PG_DB" -c "$1" 2>/dev/null | tr -d '[:space:]'
}
FEEDS="$(db_scalar 'SELECT count(*) FROM feeds;')"
NEWS="$(db_scalar 'SELECT count(*) FROM noticias;')"
TRAD="$(db_scalar "SELECT count(*) FROM traducciones WHERE status='done';")"

[ -n "$FEEDS" ] && [ "$FEEDS" -gt 0 ] 2>/dev/null && ok "feeds: $FEEDS" || bad "feeds vacío (./scripts/seed-feeds.sh)"
[ -n "$NEWS" ]  && [ "$NEWS" -gt 0 ] 2>/dev/null  && ok "noticias: $NEWS"  || bad "sin noticias (revisa 'docker compose logs ingestor')"
if [ -n "$TRAD" ] && [ "$TRAD" -gt 0 ] 2>/dev/null; then
    ok "traducciones terminadas: $TRAD"
else
    skip "todavía sin traducciones terminadas (normal en los primeros minutos)"
fi

echo
if [ "$FAILED" = "0" ]; then
    echo "Despliegue correcto: http://localhost:${PORT}"
else
    echo "Hay fallos. Revisa: docker compose ps && docker compose logs --tail=80"
fi
exit "$FAILED"
