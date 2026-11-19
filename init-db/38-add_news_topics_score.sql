-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

BEGIN;

-- El worker topics escribe en score (topics/main.go usa news_topics.score)
ALTER TABLE news_topics
    ADD COLUMN IF NOT EXISTS score INTEGER DEFAULT 0;

COMMIT;
