-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

-- Tabla favoritos ya existe en 00-complete-schema.sql con columna user_id
-- Agregar índices adicionales

CREATE INDEX IF NOT EXISTS idx_favoritos_user ON favoritos(user_id);
CREATE INDEX IF NOT EXISTS idx_favoritos_noticia ON favoritos(noticia_id);
