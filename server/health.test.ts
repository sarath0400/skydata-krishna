import { describe, it, expect } from "vitest";
import request from "supertest";
import { app } from "./index";

describe("server", () => {
  it("GET /health returns ok", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ok");
  });

  it("GET /api/hello returns a message", async () => {
    const res = await request(app).get("/api/hello");
    expect(res.status).toBe(200);
    expect(res.body.message).toContain("skydata-demo");
  });
});
