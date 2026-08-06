import { useEffect, useState } from "react";

export function App() {
  const [health, setHealth] = useState("checking...");

  useEffect(() => {
    fetch("/health")
      .then((r) => r.json())
      .then((d) => setHealth(d.status))
      .catch(() => setHealth("error"));
  }, []);

  const buildNumber = import.meta.env.VITE_BUILD_NUMBER ?? "local";

  return (
    <main style={{ fontFamily: "sans-serif", padding: 40 }}>
      <h1>SkyData Demo</h1>
      <p>This app mirrors the SkyStudio CI/CD flow: build a Docker image, push to a
        registry, deploy to a container web app.</p>
      <p>
        <strong>Build:</strong> {buildNumber}
      </p>
      <p>
        <strong>Health:</strong> {health}
      </p>
    </main>
  );
}
