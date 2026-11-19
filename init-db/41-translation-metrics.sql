-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

-- Translation throughput metrics (additive, no data loss)
ALTER TABLE translation_stats ADD COLUMN IF NOT EXISTS items_translated INTEGER DEFAULT 0;
ALTER TABLE translation_stats ADD COLUMN IF NOT EXISTS elapsed_ms INTEGER DEFAULT 0;
ALTER TABLE translation_stats ADD COLUMN IF NOT EXISTS hostname VARCHAR(100);