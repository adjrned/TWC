import { defineConfig } from 'vite'

// Static files (data/, builds/, twicons/) live in public/ and are copied into
// dist/ as-is, at the same URLs (e.g. /TWC/data/items.json).
export default defineConfig({
  base: '/TWC/',
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
  }
})
