-- RSS2 — Agregador multilingüe de noticias RSS
-- Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
-- SPDX-License-Identifier: MIT

INSERT INTO categorias (nombre) VALUES
('Ciencia'),
('Cultura'),
('Deportes'),
('Economía'),
('Educación'),
('Entretenimiento'),
('Internacional'),
('Medio Ambiente'),
('Moda'),
('Opinión'),
('Política'),
('Salud'),
('Sociedad'),
('Tecnología'),
('Viajes')
ON CONFLICT DO NOTHING;

