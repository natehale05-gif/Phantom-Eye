import { defineConfig } from 'vite';
import cesium from 'vite-plugin-cesium';

// Relative base so the build works both at the domain root and under a
// GitHub Pages project subpath (e.g. https://<user>.github.io/Phantom-Eye/).
export default defineConfig({
  base: './',
  plugins: [cesium()],
  server: {
    host: true,
    port: 5173,
  },
  build: {
    target: 'esnext',
    chunkSizeWarningLimit: 4096,
  },
});
