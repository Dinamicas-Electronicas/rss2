-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

ALTER TABLE traducciones ADD COLUMN IF NOT EXISTS vectorization_date TIMESTAMP;
ALTER TABLE traducciones ADD COLUMN IF NOT EXISTS qdrant_point_id TEXT;
