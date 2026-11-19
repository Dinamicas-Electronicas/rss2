// RSS2 — Agregador multilingüe de noticias RSS
// Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
// SPDX-License-Identifier: MIT

import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      '/api': {
        target: 'http://localhost:8888',
        changeOrigin: true,
      },
    },
  },
})
