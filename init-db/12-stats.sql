-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

CREATE TABLE IF NOT EXISTS translation_stats (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP DEFAULT NOW(),
    lang_to VARCHAR(10)
);

CREATE INDEX IF NOT EXISTS idx_trans_stats_date ON translation_stats(created_at);
CREATE INDEX IF NOT EXISTS idx_trans_stats_lang ON translation_stats(lang_to);
