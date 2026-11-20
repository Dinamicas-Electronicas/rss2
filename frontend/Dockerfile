# RSS2 — Agregador multilingüe de noticias RSS
# Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
# SPDX-License-Identifier: MIT

FROM node:24-alpine AS builder

WORKDIR /app

COPY package*.json ./
# npm ci usa el lockfile tal cual: build reproducible y sin resolver rangos.
RUN npm ci

COPY . .
RUN npm run build

FROM nginx:1.30-alpine

COPY --from=builder /app/dist /usr/share/nginx/html

COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
