import { createServer } from "./app.js";
import { initTracing } from "./tracing.js";

initTracing(process.env.SERVICE_NAME ?? "node-http-service");
const port = Number(process.env.PORT ?? 8080);
const server = createServer().listen(port, () =>
  console.log(JSON.stringify({ level: "INFO", msg: "listening", port })),
);
process.on("SIGTERM", () => server.close(() => process.exit(0)));
