// k6 smoke: a light constant load against a golden service through Traefik.
import http from "k6/http";
import { check } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";
const SERVICE = __ENV.SERVICE || "orders-api";

export const options = {
  vus: 5,
  duration: __ENV.DURATION || "30s",
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<500"],
  },
};

export default function () {
  const res = http.get(`${BASE_URL}/svc/${SERVICE}/work?ms=5`);
  check(res, { "status is 200": (r) => r.status === 200 });
}
