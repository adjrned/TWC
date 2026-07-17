import { defineConfig } from 'vite'
import { viteStaticCopy } from 'vite-plugin-static-copy'

export default defineConfig({
  base: './',
  plugins: [
    viteStaticCopy({
      targets: [
        { src: 'builds', dest: '.' },
        { src: 'twicons', dest: '.' },
        { src: 'data', dest: '.' },
      ]
    })
  ],
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
  }
})
