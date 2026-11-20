-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

CREATE TABLE IF NOT EXISTS traduccion_embeddings (
  id             SERIAL PRIMARY KEY,
  traduccion_id  INT NOT NULL REFERENCES traducciones(id) ON DELETE CASCADE,
  model          TEXT NOT NULL,
  dim            INT NOT NULL,
  -- Array clasico: lo leen event_clustering y la vista embeddings.
  embedding      DOUBLE PRECISION[] NOT NULL,
  -- Columna pgvector: la escriben embeddings_worker y la usan related y la
  -- busqueda semantica (services/ml.go). Sin ella el worker fallaba con
  -- 'column "embedding_vector" does not exist' en una base nueva: solo la
  -- creaba migrations/47, que init-db/ no ejecuta.
  embedding_vector vector(384),
  created_at     TIMESTAMP DEFAULT NOW(),
  UNIQUE (traduccion_id, model)
);

-- Para bases creadas con el esquema antiguo (o si el CREATE de arriba ya
-- existia): anadir la columna de forma idempotente.
ALTER TABLE traduccion_embeddings
  ADD COLUMN IF NOT EXISTS embedding_vector vector(384);

CREATE INDEX IF NOT EXISTS idx_tr_emb_traduccion_id ON traduccion_embeddings(traduccion_id);
CREATE INDEX IF NOT EXISTS idx_tr_emb_model          ON traduccion_embeddings(model);

-- Indice HNSW para busqueda por similitud coseno (pgvector).
CREATE INDEX IF NOT EXISTS idx_tr_emb_vector_hnsw
  ON traduccion_embeddings
  USING hnsw (embedding_vector vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'embeddings'
  ) THEN
    EXECUTE 'ALTER TABLE embeddings RENAME TO embeddings_legacy';
  END IF;
EXCEPTION WHEN others THEN
  NULL;
END$$;

CREATE OR REPLACE VIEW embeddings AS
SELECT
  te.traduccion_id,
  te.dim,
  te.embedding AS vec
FROM traduccion_embeddings te
WHERE te.model = 'sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2';

CREATE TABLE IF NOT EXISTS related_noticias (
  id                      SERIAL PRIMARY KEY,
  noticia_id              VARCHAR(32) REFERENCES noticias(id) ON DELETE CASCADE,
  related_id              VARCHAR(32) REFERENCES noticias(id) ON DELETE CASCADE,
  traduccion_id           INT REFERENCES traducciones(id) ON DELETE CASCADE,
  score                   DOUBLE PRECISION NOT NULL,
  created_at              TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_related_by_tr        ON related_noticias (traduccion_id);
CREATE INDEX IF NOT EXISTS idx_related_by_relatedid ON related_noticias (related_id);

