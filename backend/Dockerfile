# RSS2 — Agregador multilingüe de noticias RSS
# Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
# SPDX-License-Identifier: MIT

FROM golang:1.27-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev git

# Cachea las dependencias: solo se descargan si cambian go.mod/go.sum.
# Antes se ejecutaba `go mod tidy` en cada build, que puede modificar go.sum y
# descargar módulos de test que no hacen falta para compilar.
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Una sola invocacion de `go build` para los 10 binarios: comparte el cache de
# compilacion y paraleliza, en vez de 10 builds secuenciales. El nombre del
# binario es el del directorio del paquete.
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -buildvcs=false -o /out/ \
        ./cmd/server \
        ./cmd/scraper \
        ./cmd/discovery \
        ./cmd/wiki_worker \
        ./cmd/topics \
        ./cmd/related \
        ./cmd/sanitize \
        ./cmd/entityscan \
        ./cmd/event_clustering \
        ./cmd/cooccurrences \
    && mv /out/wiki_worker /out/wiki-worker

FROM alpine:3.23

RUN apk add --no-cache ca-certificates tzdata postgresql-client

WORKDIR /app

# Copia los binarios con sus nombres finales (server, scraper, wiki-worker...).
COPY --from=builder /out/ /

# Symlinks for convenience
RUN ln -s /server /usr/local/bin/server && \
    ln -s /scraper /usr/local/bin/scraper && \
    ln -s /discovery /usr/local/bin/discovery && \
    ln -s /wiki-worker /usr/local/bin/wiki-worker && \
    ln -s /topics /usr/local/bin/topics && \
    ln -s /related /usr/local/bin/related && \
    ln -s /sanitize /usr/local/bin/sanitize && \
    ln -s /entityscan /usr/local/bin/entityscan && \
    ln -s /event_clustering /usr/local/bin/event_clustering && \
    ln -s /cooccurrences /usr/local/bin/cooccurrences

ENV PATH="/usr/local/bin:${PATH}"

EXPOSE 8080

ENTRYPOINT ["/server"]
