// Captures the proof screenshots with headless Chromium.
// Usage: BASE_URL=http://localhost:8080 SHOTS=<dir> PREFIX=local|eks SERVICE=orders-api node capture.mjs
import { chromium } from "@playwright/test";
import fs from "node:fs";

const base = process.env.BASE_URL ?? "http://localhost:8080";
const out = process.env.SHOTS ?? "../proof/phase1-local/screenshots";
const prefix = process.env.PREFIX ?? "local";
const svc = process.env.SERVICE ?? "orders-api";
fs.mkdirSync(out, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const shot = async (name) => {
  await page.screenshot({ path: `${out}/${name}.png`, fullPage: false });
  console.log("captured", name);
};
const grafana = (path) => `${base}/grafana${path}`;
const explore = (ds, uid, query) =>
  grafana(`/explore?orgId=1&schemaVersion=1&panes=${encodeURIComponent(JSON.stringify({
    a: { datasource: uid, queries: [{ refId: "A", datasource: { type: ds, uid }, ...query }], range: { from: "now-30m", to: "now" } },
  }))}`);

const names = prefix === "local"
  ? { catalog: "01-portal-catalog", create: "02-portal-create", healthy: "03-service-healthy", argo: "04-argocd-tree",
      golden: "05-grafana-golden-signals", slo: "06-grafana-slo", loki: "07-loki-logs", tempo: "08-tempo-trace", cost: "09-cost-panel" }
  : { catalog: "01-eks-portal-catalog", healthy: "02-eks-service-healthy", argo: "03-eks-argocd-tree", golden: "04-eks-grafana", cost: "05-eks-cost" };

// Portal
await page.goto(`${base}/`);
await page.locator(`text=${svc}`).first().waitFor();
await page.locator(".badge.Healthy").first().waitFor({ timeout: 120_000 });
await shot(names.catalog);
if (names.create) {
  await page.goto(`${base}/services/new`);
  await page.fill("#name", "payments-worker");
  await page.selectOption("#template", "node-http");
  await page.fill("#team", "payments");
  await shot(names.create);
}
await page.goto(`${base}/services/${svc}`);
await page.locator("#health.Healthy").waitFor({ timeout: 120_000 });
await page.waitForFunction(() => document.querySelector("#cost")?.textContent?.includes("$"), null, { timeout: 60_000 }).catch(() => {});
await shot(names.healthy);

// ArgoCD tree of the root application
await page.goto(`${base}/argocd/applications/argocd/root?view=tree`);
await page.waitForTimeout(8000);
await shot(names.argo);

// Grafana dashboards
await page.goto(grafana(`/d/golden-signals/service-golden-signals?var-service=${svc}&from=now-30m&to=now&refresh=`));
await page.waitForTimeout(12_000);
await shot(names.golden);
if (names.slo) {
  await page.goto(grafana("/d/platform-slo/platform-slo-golden-service-availability-target-99-5?from=now-30m&to=now"));
  await page.waitForTimeout(10_000);
  await shot(names.slo);
}
await page.goto(grafana("/d/platform-overview/platform-overview?from=now-30m&to=now"));
await page.waitForTimeout(12_000);
await shot(names.cost);

// Loki logs and a Tempo trace (Explore)
if (names.loki) {
  await page.goto(explore("loki", "loki", { expr: `{app="${svc}"} | json` }));
  await page.waitForTimeout(10_000);
  await shot(names.loki);
  const search = await page.request.get(grafana("/api/datasources/proxy/uid/tempo/api/search?limit=5&q=" + encodeURIComponent(`{resource.service.name="${svc}"}`)));
  const traces = (await search.json()).traces ?? [];
  if (traces.length) {
    await page.goto(explore("tempo", "tempo", { queryType: "traceql", query: traces[0].traceID }));
    await page.waitForTimeout(10_000);
    await shot(names.tempo);
  } else {
    console.error("no traces found in Tempo");
    process.exitCode = 1;
  }
}
await browser.close();
