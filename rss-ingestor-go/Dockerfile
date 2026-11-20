# RSS2 — Agregador multilingüe de noticias RSS
# Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
# SPDX-License-Identifier: MIT

FROM golang:1.27-alpine AS builder

WORKDIR /app

# Install git and SSL certs
RUN apk add --no-cache git ca-certificates

# Copy source code immediately
COPY . .

# Download dependencies (go.mod/go.sum estan versionados: no hace falta tidy)
RUN go mod download

# Build the Go app
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o rss-ingestor .

# Final stage
FROM alpine:3.23

WORKDIR /root/

# Copy the Pre-built binary file from the previous stage
COPY --from=builder /app/rss-ingestor .
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Command to run the executable
CMD ["./rss-ingestor"]
