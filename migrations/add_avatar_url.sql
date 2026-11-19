-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

-- Add avatar_url column to users table if it doesn't exist
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS avatar_url TEXT;
