import { createServer } from "./app.js";
import { initTracing } from "./tracing.js";

initTracing(process.env.SERVICE_NAME ?? "node-http-service");
const port = Number(process.env.PORT ?? 8080);
const server = createServer().listen(port, () =>
  console.log(JSON.stringify({ level: "INFO", msg: "listening", port })),
);
// Keep serving while endpoint removal propagates to the load balancer, then drain.
const delayMs = Number(process.env.SHUTDOWN_DELAY_SECONDS ?? 5) * 1000;
process.on("SIGTERM", () => setTimeout(() => server.close(() => process.exit(0)), delayMs));
