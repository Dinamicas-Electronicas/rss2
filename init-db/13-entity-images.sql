-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

CREATE TABLE IF NOT EXISTS entity_images (
    id SERIAL PRIMARY KEY,
    entity_name TEXT UNIQUE NOT NULL,
    image_url TEXT,
    summary TEXT,
    source TEXT DEFAULT 'wikipedia',
    last_checked TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
