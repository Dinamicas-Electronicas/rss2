// RSS2 — Agregador multilingüe de noticias RSS
// Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
// SPDX-License-Identifier: MIT

import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
    },
  },
})
