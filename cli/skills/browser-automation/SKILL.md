---
name: browser-automation
description: Use when the user needs to automate browser interactions — testing web apps, scraping data, filling forms, monitoring pages, or verifying UI behavior. Triggers on requests involving Playwright, browser testing, web scraping, screenshot verification, form automation, or end-to-end testing.
---

# Browser Automation with Playwright

Write TypeScript scripts using `playwright`. Install with `npx playwright install chromium`. Do not use Selenium, Puppeteer, or requests-based scraping unless the user explicitly asks.

**Artifact convention**: All screenshots go to `./browser/screenshots/`, all recordings go to `./browser/recordings/`. Create these directories before running.

```bash
mkdir -p browser/screenshots browser/recordings
```

## Decision Tree

```
Task received → What kind?
│
├─ Testing a local web app
│  ├─ Server already running? → Go to "Reconnaissance-Then-Action"
│  └─ Server not running? → Start server, wait for ready, then test
│
├─ Scraping/extracting data from a live site
│  ├─ Static content (articles, docs)? → Single page load, extract, done
│  └─ Dynamic content (SPA, infinite scroll)? → Wait for networkidle, then extract
│     May need scroll loop: scroll → wait → check for new content → repeat
│
├─ Form filling / interaction
│  └─ Go to "Reconnaissance-Then-Action" (always inspect first)
│
├─ Monitoring / visual regression
│  └─ Screenshot comparison: take baseline → wait/change → take comparison → diff
│
├─ Auth-protected content
│  └─ Go to "Authentication" section first
│
└─ Need isolation / CI / no local Chrome
   └─ Go to "Docker Execution" section
```

## Reconnaissance-Then-Action (MANDATORY)

Never hardcode selectors from reading source code. The rendered DOM may differ from the source. Always:

```typescript
import { chromium } from "playwright";

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
await page.goto("http://localhost:3000");

// STEP 1: Wait for the page to actually be ready
await page.waitForLoadState("networkidle"); // Critical for SPAs

// STEP 2: Reconnaissance — discover what's on the page
await page.screenshot({
  path: "browser/screenshots/recon.png",
  fullPage: true,
});
// Read the screenshot to understand the page layout

// STEP 3: Discover selectors from the live DOM
const buttons = await page.locator("button").all();
const inputs = await page.locator("input").all();
const links = await page.locator("a").all();

// STEP 4: Act using discovered selectors
await page.locator('button:has-text("Submit")').click();

// STEP 5: Verify the action worked
await page.waitForLoadState("networkidle");
await page.screenshot({ path: "browser/screenshots/after-action.png" });
// Read screenshot to verify result

await browser.close();
```

## Selector Strategy (Priority Order)

Use the most stable selector available. Never use index-based selectors (`nth-child`, array indices).

| Priority | Selector Type           | Example                          | When to Use                   |
| -------- | ----------------------- | -------------------------------- | ----------------------------- |
| 1        | `data-testid`           | `[data-testid="submit-btn"]`     | Always preferred if available |
| 2        | ARIA role + name        | `role=button[name="Submit"]`     | Accessible apps               |
| 3        | Text content            | `text=Sign In`                   | Visible, stable labels        |
| 4        | CSS with semantics      | `form.login input[type="email"]` | Structural selectors          |
| 5        | CSS class (last resort) | `.btn-primary`                   | Only if nothing else works    |

```typescript
// Good — stable selectors
await page.locator('[data-testid="login-button"]').click();
await page.getByRole("button", { name: "Submit" }).click();
await page.getByText("Sign In").click();
await page.locator('input[type="email"]').fill("user@example.com");

// Bad — fragile selectors
await page.locator("div > div:nth-child(3) > button").click(); // breaks on any layout change
await page.locator(".css-1a2b3c").click(); // hashed class names
```

## Waiting Strategy

The single biggest source of flaky browser automation is inadequate waiting. Rules:

```typescript
// RULE 1: Always wait after navigation
await page.goto(url);
await page.waitForLoadState("networkidle");

// RULE 2: Wait for specific elements before interacting
await page.waitForSelector('[data-testid="dashboard"]', { timeout: 10_000 });

// RULE 3: After clicking something that triggers navigation or API calls
await page.locator("button").click();
await page.waitForLoadState("networkidle");

// RULE 4: For dynamic content that loads asynchronously
await page.waitForSelector(".results-loaded", { state: "visible" });

// RULE 5: For content that appears after animation
await page.waitForTimeout(300); // Only for animations, not data loading

// RULE 6: For SPAs that update the URL without full navigation
await page.waitForURL("**/dashboard", { timeout: 10_000 });
```

**When to use which wait:**

| Situation                            | Wait Method                                        |
| ------------------------------------ | -------------------------------------------------- |
| Page navigation                      | `waitForLoadState("networkidle")`                  |
| Element appears                      | `waitForSelector(selector, { state: "visible" })`  |
| Element disappears (loading spinner) | `waitForSelector(".spinner", { state: "hidden" })` |
| URL changes (SPA)                    | `waitForURL(pattern)`                              |
| API response                         | `waitForResponse(urlOrPredicate)`                  |
| Animation completes                  | `waitForTimeout(ms)` — last resort only            |

## Authentication

### Session Reuse (Preferred)

Log in once, save state, reuse across runs:

```typescript
import { chromium } from "playwright";

// First run: log in and save state
const context = await browser.newContext();
const page = await context.newPage();
await page.goto("https://app.example.com/login");
await page.waitForLoadState("networkidle");
await page.fill('input[type="email"]', "user@example.com");
await page.fill('input[type="password"]', "password");
await page.click('button[type="submit"]');
await page.waitForURL("**/dashboard");
await context.storageState({ path: "auth-state.json" });
await context.close();

// Subsequent runs: reuse saved state
const authedContext = await browser.newContext({
  storageState: "auth-state.json",
});
const authedPage = await authedContext.newPage();
await authedPage.goto("https://app.example.com/dashboard"); // Already logged in
```

### OAuth / SSO

OAuth flows open popups. Handle them:

```typescript
const [popup] = await Promise.all([
  context.waitForEvent("page"),
  page.click("text=Sign in with Google"),
]);
await popup.waitForLoadState("networkidle");
await popup.fill('input[type="email"]', email);
await popup.click("text=Next");
await popup.waitForLoadState("networkidle");
await popup.fill('input[type="password"]', password);
await popup.click("text=Next");
// Popup closes automatically, main page redirects
await page.waitForURL("**/dashboard");
```

### Environment Variables for Credentials

Never hardcode credentials. Always read from environment:

```typescript
const username = process.env.TEST_USERNAME;
const password = process.env.TEST_PASSWORD;
if (!username || !password) {
  throw new Error("TEST_USERNAME and TEST_PASSWORD must be set");
}
```

## Screenshot-Driven Debugging Loop

When something doesn't work as expected, use this loop:

```typescript
async function debugStep(
  page: Page,
  stepName: string,
  action: () => Promise<void>,
) {
  await page.screenshot({
    path: `browser/screenshots/before-${stepName}.png`,
  });
  try {
    await action();
    await page.waitForLoadState("networkidle");
    await page.screenshot({
      path: `browser/screenshots/after-${stepName}.png`,
    });
  } catch (e) {
    await page.screenshot({
      path: `browser/screenshots/error-${stepName}.png`,
    });
    throw e; // Read the error screenshot to understand what happened
  }
}

// Usage
await debugStep(page, "login-click", () => page.click('[data-testid="login"]'));
```

## Recording Sessions

Record browser sessions for debugging or documentation:

```typescript
const context = await browser.newContext({
  recordVideo: {
    dir: "browser/recordings/",
    size: { width: 1280, height: 720 },
  },
});
const page = await context.newPage();

// ... perform actions ...

await context.close(); // Video is saved when context closes
```

## Data Extraction Patterns

### Table Scraping

```typescript
const rows = await page.locator("table tbody tr").all();
const data: string[][] = [];
for (const row of rows) {
  const cells = await row.locator("td").all();
  const rowData = await Promise.all(
    cells.map((cell) => cell.textContent().then((t) => (t ?? "").trim())),
  );
  data.push(rowData);
}
```

### Infinite Scroll

```typescript
let previousCount = 0;
while (true) {
  const items = await page.locator(".item").all();
  const currentCount = items.length;
  if (currentCount === previousCount) break; // No new items loaded
  previousCount = currentCount;
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(1000);
  await page.waitForLoadState("networkidle");
}
```

### Paginated Content

```typescript
const allData: string[] = [];
while (true) {
  const items = await page.locator(".result-item").all();
  const texts = await Promise.all(items.map((item) => item.textContent()));
  allData.push(...texts.filter((t): t is string => t !== null));

  const nextButton = page.locator('a:has-text("Next")');
  if ((await nextButton.count()) === 0 || (await nextButton.isDisabled())) {
    break;
  }
  await nextButton.click();
  await page.waitForLoadState("networkidle");
}
```

## Server Lifecycle Management

When testing a local app, manage the server process:

```typescript
import { spawn } from "child_process";
import { createConnection } from "net";

// Start server as background process
const server = spawn("npm", ["run", "dev"], {
  cwd: "/path/to/project",
  stdio: "pipe",
});

// Wait for server to be ready (poll the port)
async function waitForPort(port: number, timeout = 30_000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    try {
      await new Promise<void>((resolve, reject) => {
        const sock = createConnection({ port }, () => {
          sock.destroy();
          resolve();
        });
        sock.on("error", reject);
      });
      return;
    } catch {
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
  throw new Error(`Server failed to start on port ${port} within ${timeout}ms`);
}

await waitForPort(3000);

try {
  // ... run your Playwright automation ...
} finally {
  server.kill();
}
```

## Docker Execution

When you can't or don't want to install Chromium locally (CI, sandboxed environments, reproducibility), run Playwright in a Docker container. Mount `./browser/` so artifacts (screenshots, recordings) are accessible on the host.

### Dockerfile

```dockerfile
FROM node:22-slim AS base
RUN npx playwright install --with-deps chromium
WORKDIR /app

FROM base
COPY package.json ./
RUN npm install
COPY . .
# Scripts output to /app/browser/ which is mounted from host
CMD ["npx", "playwright", "test"]
```

### Running

```bash
# Build once
docker build -t playwright-runner .

# Run with volume mount — scripts are editable on host, Playwright runs in container
docker run --rm \
  -v "$(pwd)/browser:/app/browser" \
  -v "$(pwd)/scripts:/app/scripts" \
  -e TEST_USERNAME -e TEST_PASSWORD \
  playwright-runner \
  npx tsx scripts/my-automation.ts
```

### Docker Compose (for testing apps with dev servers)

```yaml
services:
  app:
    build: .
    ports:
      - "3000:3000"
    command: npm run dev

  playwright:
    build:
      context: .
      dockerfile: Dockerfile.playwright
    depends_on:
      - app
    volumes:
      - ./browser:/app/browser
      - ./scripts:/app/scripts
    environment:
      - BASE_URL=http://app:3000
    command: npx tsx scripts/my-automation.ts
```

**Key principles for Docker execution:**

- Mount `./browser/` as a volume so screenshots and recordings are accessible on host
- Mount `./scripts/` so you can edit automation scripts without rebuilding
- Pass credentials via `-e` environment variables, never bake into image
- Use `node:22-slim` as base — Playwright's `install --with-deps` adds what's needed
- For CI, use the official `mcr.microsoft.com/playwright:v1.50.0-noble` image instead

## Common Pitfalls

| Pitfall                                   | Fix                                                                            |
| ----------------------------------------- | ------------------------------------------------------------------------------ |
| Acting before page is ready               | Always `waitForLoadState("networkidle")` after navigation                      |
| Selectors from source code don't match    | Use reconnaissance pattern — inspect the live DOM                              |
| Flaky clicks on moving elements           | `waitForSelector({ state: "visible" })` before clicking                        |
| Stale element references after navigation | Re-query selectors after any page change                                       |
| "Element is not visible" errors           | Check if element is behind a modal, below fold, or hidden by CSS               |
| Timeout on slow pages                     | Increase timeout: `page.setDefaultTimeout(30_000)`                             |
| Headless renders differently              | Set viewport: `browser.newContext({ viewport: { width: 1280, height: 720 } })` |
| File download doesn't trigger             | Use `page.waitForEvent("download")`                                            |
| iframes not accessible                    | Switch context: `page.frameLocator("#iframe-id")`                              |

## Verification Checklist

Before considering browser automation complete:

- [ ] Every `goto()` is followed by a `waitForLoadState`
- [ ] No hardcoded selectors from reading source — all discovered from live DOM
- [ ] Credentials come from environment variables, never hardcoded
- [ ] Screenshots saved to `./browser/screenshots/` at key decision points
- [ ] Recordings (if any) saved to `./browser/recordings/`
- [ ] Error cases produce screenshots for debugging
- [ ] Browser is closed in a `finally` block or try/catch
- [ ] Server processes are cleaned up on exit
