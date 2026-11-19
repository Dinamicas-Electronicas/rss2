-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

BEGIN;

-- Columnas para el clustering de noticias (cluster_worker.py)
ALTER TABLE eventos
    ADD COLUMN IF NOT EXISTS centroid JSONB,
    ADD COLUMN IF NOT EXISTS total_traducciones INTEGER DEFAULT 1,
    ADD COLUMN IF NOT EXISTS fecha_inicio TIMESTAMP,
    ADD COLUMN IF NOT EXISTS fecha_fin TIMESTAMP,
    ADD COLUMN IF NOT EXISTS n_noticias INTEGER DEFAULT 1;

COMMIT;
