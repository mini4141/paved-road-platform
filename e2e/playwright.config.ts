import { defineConfig } from "@playwright/test";

const outDir = process.env.REPORT_DIR ?? "../proof/phase1-local/tests/playwright";

export default defineConfig({
  testDir: "tests",
  timeout: 6 * 60_000,
  retries: 0,
  reporter: [
    ["list"],
    ["junit", { outputFile: `${outDir}/junit.xml` }],
    ["html", { outputFolder: `${outDir}/html`, open: "never" }],
  ],
  outputDir: `${outDir}/artifacts`,
  use: {
    baseURL: process.env.BASE_URL ?? "http://localhost:8080",
    screenshot: "only-on-failure",
  },
});
