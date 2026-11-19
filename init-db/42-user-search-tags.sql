-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

-- Dynamic search tags per user (additive, no data loss)
CREATE TABLE IF NOT EXISTS user_search_tags (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    term TEXT NOT NULL,
    count INTEGER DEFAULT 1,
    last_used TIMESTAMP DEFAULT NOW(),
    UNIQUE (user_id, term)
);

CREATE INDEX IF NOT EXISTS idx_user_search_tags_user_count ON user_search_tags(user_id, count DESC, last_used DESC);