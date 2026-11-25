import http from "node:http";
import { context, propagation, trace, SpanStatusCode } from "@opentelemetry/api";
import client from "prom-client";

const serviceName = process.env.SERVICE_NAME ?? "node-http-service";
client.collectDefaultMetrics();
const requests = new client.Counter({
  name: "http_requests_total",
  help: "HTTP requests.",
  labelNames: ["method", "path", "code"],
});
const latency = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "HTTP request latency.",
  labelNames: ["method", "path"],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
});

function log(fields: Record<string, unknown>): void {
  console.log(JSON.stringify({ time: new Date().toISOString(), level: "INFO", service: serviceName, ...fields }));
}

function busy(ms: number): void {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    /* burn CPU for load tests */
  }
}

type Handler = (url: URL, res: http.ServerResponse) => void;

const routes: Record<string, Handler> = {
  "/": (_u, res) => {
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({ service: serviceName, template: "node-http-service", status: "ok" }));
  },
  "/healthz": (_u, res) => void res.end("ok"),
  "/work": (u, res) => {
    const ms = Math.min(Math.max(Number(u.searchParams.get("ms") ?? 0) || 0, 0), 5000);
    busy(ms);
    res.end("done");
  },
};

export function createServer(): http.Server {
  const tracer = trace.getTracer(serviceName);
  return http.createServer(async (req, res) => {
    const url = new URL(req.url ?? "/", "http://localhost");
    if (url.pathname === "/metrics") {
      res.setHeader("content-type", client.register.contentType);
      res.end(await client.register.metrics());
      return;
    }
    const path = url.pathname in routes ? url.pathname : "other";
    const parent = propagation.extract(context.active(), req.headers);
    const span = tracer.startSpan(`${req.method} ${path}`, {}, parent);
    const start = process.hrtime.bigint();
    const handler = routes[url.pathname];
    if (handler) handler(url, res);
    else {
      res.statusCode = 404;
      res.end("not found");
    }
    const seconds = Number(process.hrtime.bigint() - start) / 1e9;
    const method = req.method ?? "GET";
    requests.inc({ method, path, code: String(res.statusCode) });
    latency.observe({ method, path }, seconds);
    if (res.statusCode >= 500) span.setStatus({ code: SpanStatusCode.ERROR });
    span.end();
    if (path !== "/healthz") {
      log({
        method,
        path,
        code: res.statusCode,
        duration_ms: seconds * 1000,
        trace_id: span.spanContext().traceId,
      });
    }
  });
}
