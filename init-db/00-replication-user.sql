-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

-- Rol de replicación para el streaming replication (init-replica/).
--
-- Se usa current_database() en vez de un nombre fijo: el init se ejecuta con
-- ON_ERROR_STOP=1 y, si POSTGRES_DB no es "rss", un GRANT a una base
-- inexistente abortaba toda la inicialización.
--
-- La contraseña es aleatoria si no se ha definido rss.replica_password; queda
-- visible en el log de inicialización de Postgres. Si no se despliega una
-- réplica, el rol no se usa (no expone puerto fuera de la red interna).

DO $$
DECLARE
    replica_password TEXT := coalesce(
        nullif(current_setting('rss.replica_password', true), ''),
        md5(random()::text || clock_timestamp()::text)
    );
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') THEN
        EXECUTE format('CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD %L', replica_password);
        RAISE NOTICE 'Rol replicator creado. Contraseña: %', replica_password;
    END IF;

    EXECUTE format('GRANT CONNECT ON DATABASE %I TO replicator', current_database());
END
$$;
