-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

-- Optimiza las consultas de entidades (GetEntityMentions): de 6+ segundos a
-- ~30 ms para entidades frecuentes.
--
-- Este script existía en el repositorio como un fichero con comillas en el
-- nombre ("/home/x/rss2/init-db/55-optimize-entity-queries.sql"), un residuo
-- de un script de movimiento roto, así que nunca se aplicaba. Se restaura con
-- un nombre válido y numeración posterior a todas las tablas que indexa.

-- Índice para búsquedas de tags sin distinguir mayúsculas.
CREATE INDEX IF NOT EXISTS idx_tags_valor_lower ON public.tags USING btree (lower(valor));

-- Índice compuesto para los JOIN con entity_aliases (GetEntityMentions).
CREATE INDEX IF NOT EXISTS idx_entity_aliases_canonical ON public.entity_aliases (lower(canonical_name));
