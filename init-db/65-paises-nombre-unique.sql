-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

-- Restricción UNIQUE en paises.nombre
--
-- 00-complete-schema.sql ya la declara en línea (`nombre VARCHAR(100) NOT NULL
-- UNIQUE`), así que en una base nueva la restricción ya existe y volver a
-- añadirla abortaba toda la inicialización desde cero con
-- "relation "paises_nombre_key" already exists".
--
-- En bases antiguas creadas antes de ese cambio podía faltar, y sin UNIQUE el
-- seed de 04-paises.sql se duplicaba cada vez que se ejecutaba (la init
-- duplicaba los scripts al reaplicarlos desde 47-pgvector-init.sh): 390 filas
-- para 195 países y la asignación de códigos ISO de la migración 99 reventaba
-- con "duplicate key value violates unique constraint paises_iso2_key".
--
-- Se añade solo si no existe ya una UNIQUE sobre (nombre): idempotente.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint c
          JOIN pg_class t ON t.oid = c.conrelid
          JOIN pg_namespace n ON n.oid = t.relnamespace
         WHERE n.nspname = current_schema()
           AND t.relname = 'paises'
           AND c.contype = 'u'
           AND c.conkey = ARRAY[(
                SELECT a.attnum
                  FROM pg_attribute a
                 WHERE a.attrelid = t.oid
                   AND a.attname = 'nombre'
           )]
    ) THEN
        ALTER TABLE paises
            ADD CONSTRAINT paises_nombre_key UNIQUE (nombre);
    END IF;
END $$;
