// RSS2 — Agregador multilingüe de noticias RSS
// Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
// SPDX-License-Identifier: MIT

/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_URL: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
