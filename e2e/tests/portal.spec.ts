import { expect, test } from "@playwright/test";

// Golden path: create a service in the portal, wait for ArgoCD to report Healthy, open the service URL.
test("create service becomes Healthy and is reachable", async ({ page, request }) => {
  const name = `e2e-${Date.now().toString(36)}`;

  await page.goto("/");
  await page.getByRole("link", { name: "+ Create service" }).click();
  await page.fill("#name", name);
  await page.selectOption("#template", "go-http");
  await page.fill("#team", "qa");
  await page.getByRole("button", { name: "Create service" }).click();

  await expect(page).toHaveURL(new RegExp(`/services/${name}$`));
  await expect(page.locator("#health")).toHaveText("Healthy", { timeout: 4 * 60_000 });
  await expect(page.locator("#sync")).toHaveText("Synced");

  const res = await request.get(`/svc/${name}/`);
  expect(res.ok()).toBeTruthy();
  expect((await res.json()).service).toBe(name);

  page.once("dialog", (d) => d.accept());
  await page.getByRole("button", { name: "Delete service" }).click();
  await expect(page).toHaveURL(/\/$/);
});
