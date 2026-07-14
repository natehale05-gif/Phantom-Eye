import { defineConfig } from 'vite';
import cesium from 'vite-plugin-cesium';

// Relative base so the bundle works when served from the app's bundled
// localhost asset server (flutter_inappwebview InAppLocalhostServer).
export default defineConfig({
  base: './',
  plugins: [cesium()],
  build: {
    target: 'esnext',
    outDir: 'dist',
    emptyOutDir: true,
    chunkSizeWarningLimit: 4096,
  },
});
