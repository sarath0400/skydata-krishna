import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Frontend builds into dist/; Express serves dist/ in production.
// In dev, Vite proxies /health and /api to the Express server on 8080.
export default defineConfig({
  plugins: [react()],
  build: { outDir: "dist" },
  server: {
    port: 5173,
    proxy: {
      "/health": "http://localhost:8080",
      "/api": "http://localhost:8080"
    }
  }
});
