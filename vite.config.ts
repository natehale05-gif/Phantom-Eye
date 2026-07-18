import { defineConfig } from 'vite';
import cesium from 'vite-plugin-cesium';

// Relative base so the build works both at the domain root and under a
// GitHub Pages project subpath (e.g. https://<user>.github.io/Phantom-Eye/).
export default defineConfig({
  base: './',
  plugins: [
    cesium(),
    // vite-plugin-cesium injects a blocking <script src="cesium/Cesium.js">
    // (several MB) at the very top of <head>, ahead of everything else —
    // the browser has to download and execute all of it before parsing the
    // rest of the document or painting anything. Adding `defer` lets parsing
    // and first paint proceed immediately; `window.Cesium` is still
    // guaranteed ready before main.ts runs since it's a module script (also
    // deferred) that sits later in document order, and defer/module scripts
    // execute in relative document order.
    {
      name: 'defer-cesium-script',
      transformIndexHtml: {
        order: 'post',
        handler: (html: string) =>
          html.replace(
            '<script src="cesium/Cesium.js"></script>',
            '<script defer src="cesium/Cesium.js"></script>',
          ),
      },
    },
  ],
  server: {
    host: true,
    port: 5173,
  },
  build: {
    target: 'esnext',
    chunkSizeWarningLimit: 4096,
  },
});
