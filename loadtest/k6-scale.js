// k6 scale test: CPU-heavy requests at a constant arrival rate, to drive the HPA from 2 to >= 4 replicas.
import http from "k6/http";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";
const SERVICE = __ENV.SERVICE || "orders-api";

export const options = {
  scenarios: {
    ramp: {
      executor: "ramping-arrival-rate",
      startRate: 5,
      timeUnit: "1s",
      preAllocatedVUs: 60,
      maxVUs: 200,
      stages: [
        { target: 30, duration: "30s" },
        { target: 30, duration: __ENV.HOLD || "4m" },
        { target: 0, duration: "10s" },
      ],
    },
  },
  thresholds: { http_req_failed: ["rate<0.05"] },
};

export default function () {
  http.get(`${BASE_URL}/svc/${SERVICE}/work?ms=50`);
}
