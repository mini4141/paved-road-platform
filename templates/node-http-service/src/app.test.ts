import assert from "node:assert/strict";
import { test } from "node:test";
import type { AddressInfo } from "node:net";
import { createServer } from "./app.js";

test("GET /healthz returns ok", async () => {
  const server = createServer().listen(0);
  const { port } = server.address() as AddressInfo;
  const res = await fetch(`http://127.0.0.1:${port}/healthz`);
  assert.equal(res.status, 200);
  assert.equal(await res.text(), "ok");
  server.close();
});
