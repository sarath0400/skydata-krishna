import express from "express";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const app = express();

// Health endpoint — the CI deploy job polls this after restart.
app.get("/health", (_req, res) => {
  res.status(200).json({ status: "ok", uptime: process.uptime() });
});

// Example API endpoint.
app.get("/api/hello", (_req, res) => {
  res.json({ message: "hello from skydata-demo", build: process.env.BUILD_NUMBER ?? "local" });
});

// Serve the built frontend (Vite output) and SPA fallback.
const clientDir = path.resolve(__dirname, "../dist");
app.use(express.static(clientDir));
app.get("*", (_req, res) => {
  res.sendFile(path.join(clientDir, "index.html"));
});

const port = Number(process.env.PORT) || 8080;

// Don't bind a port under test (supertest drives the app object directly).
if (process.env.NODE_ENV !== "test") {
  app.listen(port, () => {
    console.log(`skydata-demo server listening on ${port}`);
  });
}
