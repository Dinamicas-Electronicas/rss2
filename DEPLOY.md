# RSS2 — Guía de despliegue

Esta guía cubre el despliegue desde cero, las actualizaciones y las tareas de
operación habituales. Para la visión general del proyecto, ver
[README.md](./README.md).

---

## 1. Requisitos

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| Docker | Engine 24+ y Compose v2 (`docker compose`) | última versión |
| CPU | 4 vCPU | 6–8 vCPU |
| RAM | 8 GB libres | 16 GB (especialmente con TTS) |
| Disco | 30 GB | 60 GB+ (imágenes ML + `data/pgdata` + audios) |
| Red | Salida a internet en el primer arranque | — |

Patrones de datos que usa el compose: `data/` (Postgres, Redis, audios,
imágenes), `models/` (NLLB y pesos de voz) y `hf_cache/` (HuggingFace). Se
crean solos y no se versionan.

---

## 2. Despliegue en un paso

```bash
git clone https://github.com/Dinamicas-Electronicas/rss2.git
cd rss2
./deploy.sh
```

El script:

1. Crea `.env` con contraseñas aleatorias si no existe (`chmod 600`).
2. Crea `data/`, `models/` y `hf_cache/`.
3. Construye `backend` → `frontend`/`ingestor`/`translator` → workers Python.
4. Levanta la base de datos e importa `feeds.csv` **antes** de arrancar el
   ingestor (idempotente), para que su primer ciclo ya tenga fuentes.
5. Levanta el resto del stack (el perfil `tts` queda fuera) y espera a que la
   API responda (`GET /api/news`).

Opciones:

```bash
./deploy.sh --with-tts   # incluye el noticiario por voz (tras make tts-models)
./deploy.sh --no-seed    # no importa feeds.csv
./deploy.sh --no-build   # omite el build explícito (usa la caché)
./deploy.sh --help
```

Al terminar:

| Servicio | URL |
|----------|-----|
| Web | http://localhost:8888 |
| API | http://localhost:8888/api |
| Salud | http://localhost:8888/api/stats |

El **primer usuario registrado** obtiene rol de administrador.

---

## 3. Despliegue manual

Equivalente al script, útil para entender o depurar:

```bash
cp .env.example .env
# Editar: POSTGRES_PASSWORD, REDIS_PASSWORD, SECRET_KEY, GRAFANA_PASSWORD
# (o ./scripts/bootstrap-env.sh para generarlas automáticamente)

docker compose build --pull backend
docker compose build --pull frontend ingestor translator translation-scheduler ner embeddings
docker compose up -d

./scripts/seed-feeds.sh
docker compose ps
```

`docker compose build --pull && docker compose up -d` también funciona en un clon limpio. Las
imágenes compartidas tienen etiqueta fija (`rss2-backend`, `rss2-pyworkers`,
`rss2-translator`), de modo que Compose las construye y no intenta descargarlas
de Docker Hub.

> **`--pull` no es opcional para actualizaciones de seguridad.** Sin él Docker
> reutiliza las etiquetas locales de `python:3.11-slim-bookworm`,
> `node:24-alpine`, `golang:1.27-alpine`, etc., y el redespliegue no recoge los
> parches publicados desde el build anterior. Lo mismo aplica a las imágenes
> externas del compose (`redis`, `nginx`, `pgvector`): se actualizan al hacer
> `docker compose pull` / `up`.

### Por qué el build va en dos pasos

`wiki`, `topics`, `related`, `scraper`, `discovery`, `event-clustering` y
`cooccurrences` **reutilizan la imagen del backend**; `langdetect` reutiliza la
de `translation-scheduler`. Construir dos servicios contra la misma etiqueta en
un solo comando provoca conflictos (`AlreadyExists`). Por eso `deploy.sh` y el
`Makefile` separan el build.

---

## 4. Qué ocurre en el primer arranque

| Fase | Qué pasa | Tiempo típico (4 vCPU) |
|------|----------|------------------------|
| Build | torch, spaCy, sentence-transformers, Go | 15–30 min |
| `db` | Aplica `init-db/*.sql` (solo la primera vez) | 1–2 min |
| `translator-models` | Descarga NLLB (~2,4 GB) y lo convierte a CTranslate2 | 5–15 min |
| `embeddings` | Descarga el modelo multilingüe a `hf_cache/` | 1–3 min |
| `backend` | Crea índices y refresca estadísticas en segundo plano | 1–5 min |
| `ingestor` | Primer ciclo sobre 1.655 feeds | 2–10 min |

Los traductores no arrancan hasta que `translator-models` termina con código
0. Si la conversión falla, el fallo es explícito:

```bash
docker compose logs translator-models
```

### 4.1. Cachés de Redis en el primer arranque

El backend cachea en Redis varias respuestas con TTL largo. En un arranque
desde cero eso puede dejar la aplicación "vacía" aunque los datos ya estén en
PostgreSQL. Incidencias observadas y corregidas en el despliegue verificado del
2026-11-21:

| Clave | Endpoint | TTL | Cómo se envenena | Síntoma |
|-------|----------|-----|------------------|---------|
| `stats` | `GET /api/stats` | 1 h | Consultar las estadísticas antes de que el ingestor inserte la primera noticia | Portada con todos los contadores a 0 durante una hora |
| `feedlist:*` | `GET /api/feeds` | 1 h | Ejecutar `scripts/seed-feeds.sh` (o un `INSERT` masivo) con el backend ya levantado | La lista de feeds responde `total: 0` |

El CRUD de feeds sí invalida `feedlist:*`, pero el seed no. Para que no ocurra,
**siembra los feeds antes de arrancar el backend** (es lo que hace
`deploy.sh`) y no consultes `/api/stats` hasta que el ingestor haya insertado
noticias.

Corrección en caliente, sin reiniciar ni vaciar toda la caché:

```bash
RP=$(grep -E '^REDIS_PASSWORD=' .env | cut -d= -f2)
docker compose exec -T -e REDIS_PASSWORD="$RP" redis sh -lc '
  redis-cli --no-auth-warning -a "$REDIS_PASSWORD" DEL stats
  for k in $(redis-cli --no-auth-warning -a "$REDIS_PASSWORD" --scan --pattern "feedlist:*"); do
    redis-cli --no-auth-warning -a "$REDIS_PASSWORD" DEL "$k"
  done'
```

Tras la purga, `curl -s localhost:8888/api/stats` y `/api/feeds` devuelven los
totales reales. Si se levanta el stack a mano con `docker compose up -d`, el
orden recomendado es: `db` → `./scripts/seed-feeds.sh` → resto.

---

## 5. Actualizar una instalación existente

```bash
git pull
docker compose build --pull backend
docker compose build --pull frontend ingestor translator translation-scheduler ner embeddings
docker compose up -d
```

Notas:

- `init-db/` **solo se ejecuta al inicializar `data/pgdata`**. Las migraciones
  nuevas no se aplican solas en una base existente: revisa `migrations/` y
  aplícalas a mano antes de reconstruir imágenes que dependan de ellas.
- Tras recrear `backend`, reinicia `nginx` si usas una configuración antigua:
  la incluida resuelve el upstream dinámicamente y ya no lo necesita.
- Si cambias el formato de respuestas cacheadas:
  `docker compose exec redis redis-cli -a "$REDIS_PASSWORD" FLUSHDB`.

---

## 6. Perfiles opcionales

```bash
# Noticiario por voz (imagen pesada; requiere pesos)
make tts-models
docker compose --profile tts up -d --build tts

# Traductor con GPU NVIDIA (nvidia-container-toolkit)
docker compose --profile gpu up -d

# Prometheus + Grafana + cAdvisor
docker compose --profile monitoring up -d

# ...y ver Grafana en http://localhost:3001 (solo loopback)
docker compose -f docker-compose.yml -f docker-compose.local.yml \
  --profile monitoring up -d
```

El perfil `tts` no se levanta con `docker compose up -d`; sin él, los endpoints
`/api/tts/*` responden `503` y el resto funciona con normalidad.

---

## 7. Verificación

```bash
make verify                              # contenedores + API + datos
docker compose ps                        # todos "healthy" salvo los one-shot
curl -s localhost:8888/api/stats         # API + BD + Redis
docker compose exec -T db psql -U rss -d rss -c "SELECT count(*) FROM feeds;"
docker compose exec -T db psql -U rss -d rss -c "SELECT count(*) FROM noticias;"
```

Comprobación del esquema (detecta migraciones de `init-db/` que falten en la
base viva):

```bash
make check-schema
```

> Despliegue de referencia verificado el 2026-11-21 (8 vCPU, 23 GiB): los 19
> servicios base y los 3 de `monitoring` quedaron `healthy`, con 0 reinicios y
> 0 OOM; `check-schema` sin deriva; 55.962 noticias y 1.655 feeds tras el
> primer ciclo del ingestor.

---

## 8. Backup y restauración

```bash
# Backup comprimido
docker compose exec -T db pg_dump -U rss -d rss -Fc -Z 6 > data/backup-$(date +%F).dump

# Restauración
docker compose exec -T db pg_restore -U rss -d rss --clean --if-exists < data/backup-XXXX.dump
```

No borres `data/pgdata` en producción: contiene el directorio de datos de
PostgreSQL. Un reset del corpus (TRUNCATE + reingesta) está documentado en
[AGENTS.md](./AGENTS.md#resetting-the-news-corpus).

---

## 9. Problemas frecuentes

| Síntoma | Causa / solución |
|---------|------------------|
| `pull access denied … rss2-backend` | Compose intenta descargar una imagen local. Usa el `docker-compose.yml` actual (etiquetas fijas) y construye el backend primero. |
| La web tarda en abrir | El backend crea índices al arrancar; espera a que esté `healthy`. |
| Portada vacía | `feeds` vacío o primer ciclo del ingestor aún en curso: `./scripts/seed-feeds.sh` y `docker compose logs -f ingestor`. Si ya hay noticias, revisa la caché `stats` (§4.1). |
| `/api/stats` devuelve 0 con noticias ya insertadas | Caché `stats` (TTL 1 h) sembrada antes de la ingesta: purga la clave (§4.1). |
| `/api/feeds` devuelve `total: 0` tras sembrar | Caché `feedlist:*` no invalidada por el seed: purga las claves (§4.1). |
| `ingestor`: `Error fetching … context deadline exceeded` o `HTTP 403` | Feeds caídos o que bloquean al bot. Son fallos por feed, no del stack; se reintentan en el siguiente ciclo y `fallos` los desactiva. |
| Redis: `WARNING Memory overcommit must be enabled!` | Aviso del host, no del stack. Recomendado: `sudo sysctl vm.overcommit_memory=1` y dejarlo en `/etc/sysctl.conf`. |
| `translator-models` falla | Sin salida a internet o sin espacio para ~2,4 GB. |
| `502` tras recrear `backend` | Reinicia `nginx` (`docker compose restart nginx`) si tu `nginx.conf` es antiguo. |
| Redis en bucle | `REDIS_PASSWORD` vacía en `.env`: el `requirepass` queda sin argumento. |
| TTS responde `503` | Perfil `tts` desactivado (comportamiento normal) o pesos sin preparar. |
| `translations_pending` muy alto | El scheduler encola los 12 idiomas de `idiomas_disponibles`; los traductores locales solo procesan `TARGET_LANGS` (por defecto `es`). El resto queda pendiente para los remote workers. Es el cuello de botella documentado; no es un fallo. |

---

## 10. Actualizaciones de seguridad (noviembre 2026)

Se actualizaron las imágenes base y las dependencias con avisos conocidos:

| Componente | Versión anterior | Versión actual |
|------------|------------------|----------------|
| Node (build frontend) | 20 | 24 |
| Go (backend/ingestor) | 1.23 / 1.25 | 1.27 |
| Alpine (runtime) | `latest` | 3.23 |
| nginx | `alpine` | 1.30-alpine |
| Redis | 7 | 8.8 |
| pgvector | `pg16` flotante | 0.8.7-pg16-bookworm |
| Prometheus / Grafana / cAdvisor | `latest` | v3.16.0 / 13.2.6 / v0.52.1 |
| Python (workers) | `3.11-slim` flotante | `3.11-slim-bookworm` |
| transformers | 4.36–4.44 | 5.23.0 |
| torch | 2.1.0 | 2.15.0 (CPU) / 2.11.0 (TTS) |
| CTranslate2 | 3.24.0 | 4.9.0 |
| pgx / jwt / x/net | 5.4.3 / 5.0.0 / 0.30 | 5.9.2 / 5.2.2 / 0.62.0 |
| vite / vitest / axios | 5 / 1 / 1.6 | 8 / 5 / 1.21 |

Procedimiento para aplicarlas en un host ya desplegado:

```bash
# 1. Reconstruir (el backend primero: los workers reutilizan su imagen)
docker compose build --pull backend
docker compose build --pull frontend ingestor translator translation-scheduler ner embeddings
docker compose --profile tts build tts        # opcional; imagen grande (~8-10 GB)

# 2. Recrear servicios
docker compose up -d

# 3. Gateway: nginx resuelve el upstream al arrancar
docker compose restart nginx

# 4. Monitoreo (perfil opcional), con las etiquetas fijadas
docker compose --profile monitoring up -d --force-recreate prometheus grafana cadvisor

# 5. pgvector: si la extensión instalada es anterior a 0.8.7
docker compose exec -T db psql -U rss -d rss -c "ALTER EXTENSION vector UPDATE;"

# 6. GPU (solo si se usa el perfil gpu)
docker compose --profile gpu build --pull translator-gpu
```

Los **remote workers** (`remote-worker/`) deben actualizarse en bloque:
`ctranslate2==4.9.0`, `transformers==5.23.0`, `torch==2.15.0`. Mezclar
versiones de CTranslate2/Transformers con los traductores locales puede
producir traducciones inconsistentes.

Comprobaciones rápidas:

```bash
cd frontend && npm audit && npm test -- --run && npm run build
cd backend && go run golang.org/x/vuln/cmd/govulncheck@latest ./...
cd ../rss-ingestor-go && go run golang.org/x/vuln/cmd/govulncheck@latest ./...
```

> Nota: `python:3.11-slim-bookworm` se mantiene a propósito. Python 3.11 sigue
> recibiendo parches de seguridad hasta octubre de 2027 y es la versión que
> soportan MeloTTS/OpenVoice/spaCy con los pines actuales.

---

## 11. Imágenes precompiladas (GitHub Actions + GHCR)

`.github/workflows/images.yml` construye y publica las imágenes en GitHub
Container Registry. Se ejecuta solo si pasan los tests de `ci.yml` y publica:

| Imagen | Cuándo |
|---|---|
| `rss2-backend`, `rss2-frontend`, `rss2-ingestor`, `rss2-pyworkers`, `rss2-translator`, `rss2-translator-gpu`, `rss2-embeddings`, `rss2-ner` | cada push a `master` y cada tag `v*` |
| `rss2-tts` | manual desde **Actions → Images → Run workflow**, con `build_heavy=true` |

Etiquetas publicadas: `latest` (solo `master`/`main`), `sha-<commit>` y el tag
`v*` si aplica. Para producción usa siempre la etiqueta `sha-…`.

Tras el primer run, los paquetes de GHCR suelen crearse **privados**. Para que
el servidor pueda descargarlos sin autenticarse, cámbialos a públicos en
**GitHub → Packages → rss2-… → Package settings**, o haz:

```bash
docker login ghcr.io -u <usuario> -p <token-con-read:packages>
```

Despliegue con las imágenes ya construidas:

```bash
RSS2_TAG=sha-752ad1e ./scripts/deploy-images.sh
# equivale a:
docker compose -f docker-compose.yml -f docker-compose.images.yml pull
docker compose -f docker-compose.yml -f docker-compose.images.yml up -d --no-build
```

Variables:

| Variable | Por defecto | Uso |
|---|---|---|
| `RSS2_REGISTRY` | `ghcr.io/dinamicas-electronicas` | namespace del registro (fork/otra org) |
| `RSS2_TAG` | `latest` | etiqueta a desplegar (`sha-…` recomendado) |

> Aviso: el conjunto completo ronda los 15 GB extraídos. En un host con poco
> disco, limpia antes (`docker system prune`) o publica/despliega solo las
> imágenes que necesites. Los perfiles `tts`/`gpu` no se descargan si no se
> activan con `COMPOSE_PROFILES=tts,gpu`.

---

© 2026 Dinámicas Electrónicas · <dinamicas.electronicas@gmail.com> · Licencia MIT
