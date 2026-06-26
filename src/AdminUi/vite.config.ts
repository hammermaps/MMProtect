import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { resolve } from 'path'

export default defineConfig({
  plugins: [vue()],
  base: '/admin/',
  build: {
    outDir: resolve(__dirname, '../LicenseServer/wwwroot/admin'),
    emptyOutDir: true,
  },
})
