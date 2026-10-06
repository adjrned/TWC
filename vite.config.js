import { defineConfig } from 'vite'
import { viteStaticCopy } from 'vite-plugin-static-copy'

export default defineConfig({
  base: '/TWC/',
  plugins: [
    viteStaticCopy({
      targets: [
        { src: 'builds', dest: '.' },
        { src: 'twicons/*.webp', dest: 'twicons' },
        { src: 'twicons/manifest.json', dest: 'twicons' },
        { src: 'data', dest: '.' },
      ]
    })
  ],
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
  }
})
