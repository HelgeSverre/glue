---
name: profiling-web
description: Use when profiling web application performance — diagnosing slow pages, optimizing Core Web Vitals, analyzing bundles, finding memory leaks, profiling runtime JavaScript, or automating Lighthouse audits. Triggers on requests to profile, optimize, audit, or diagnose performance issues in web applications.
---

# Web Performance Profiling

## Decision Tree

```
Performance problem → What kind?
│
├─ Page loads slowly (LCP, TTFB)
│  └─ Run Lighthouse → analyze waterfall → fix blocking resources
│
├─ Page feels janky (scrolling, animations, interactions)
│  └─ CDP runtime profiling → find long tasks, layout thrashing → optimize
│
├─ Page uses too much memory / leaks
│  └─ CDP heap snapshots → compare snapshots → find growing objects
│
├─ Bundle is too large
│  └─ Bundle analysis → identify large dependencies → split or replace
│
├─ Interaction is slow (button click, form submit)
│  └─ CDP interaction profiling → measure INP → find blocking JS
│
├─ Need to track performance over time
│  └─ Lighthouse CI → run on every PR → compare scores
│
└─ Don't know what's wrong
   └─ Start with Lighthouse (covers page-load issues),
      then use CDP profiling for runtime/interaction issues
```

## Lighthouse Automation

### CLI Setup

```bash
# Install
npm install -g lighthouse
# or use npx: npx lighthouse

# Basic audit
lighthouse https://example.com --output json --output-path report.json

# Headless (for CI)
lighthouse https://example.com \
  --chrome-flags="--headless --no-sandbox" \
  --output json \
  --output-path report.json

# Specific categories only
lighthouse https://example.com \
  --only-categories=performance \
  --output json \
  --output-path report.json

# Mobile vs Desktop
lighthouse https://example.com --preset=desktop --output json --output-path desktop.json
lighthouse https://example.com --output json --output-path mobile.json  # mobile is default
```

### Parsing Lighthouse Results

```typescript
import { readFileSync } from "fs";

const report = JSON.parse(readFileSync("report.json", "utf-8"));

// Overall scores (0-1, multiply by 100 for percentage)
const { categories, audits } = report;
console.log(`Performance: ${(categories.performance.score * 100).toFixed(0)}`);
console.log(`Accessibility: ${(categories.accessibility.score * 100).toFixed(0)}`);

// Core Web Vitals
const lcp = audits["largest-contentful-paint"].numericValue; // ms
const cls = audits["cumulative-layout-shift"].numericValue; // score
const tbt = audits["total-blocking-time"].numericValue; // ms (proxy for INP)

console.log(`LCP: ${lcp.toFixed(0)}ms ${lcp < 2500 ? "PASS" : "FAIL"}`);
console.log(`CLS: ${cls.toFixed(3)} ${cls < 0.1 ? "PASS" : "FAIL"}`);
console.log(`TBT: ${tbt.toFixed(0)}ms ${tbt < 200 ? "PASS" : "FAIL"}`);

// Opportunities (actionable recommendations)
for (const [id, audit] of Object.entries(audits) as any) {
  const savings = audit?.details?.overallSavingsMs ?? 0;
  if (audit?.details?.type === "opportunity" && savings > 100) {
    console.log(`  ${audit.title}: save ~${savings.toFixed(0)}ms`);
  }
}
```

### Before/After Comparison

```bash
# Baseline
lighthouse https://example.com --output json --output-path before.json
# Make changes, deploy
lighthouse https://example.com --output json --output-path after.json
```

```typescript
const before = JSON.parse(readFileSync("before.json", "utf-8"));
const after = JSON.parse(readFileSync("after.json", "utf-8"));

const metrics = [
  ["LCP", "largest-contentful-paint", "ms"],
  ["FCP", "first-contentful-paint", "ms"],
  ["TBT", "total-blocking-time", "ms"],
  ["CLS", "cumulative-layout-shift", ""],
  ["Speed Index", "speed-index", "ms"],
] as const;

for (const [name, auditId, unit] of metrics) {
  const b = before.audits[auditId].numericValue;
  const a = after.audits[auditId].numericValue;
  const change = b ? ((a - b) / b) * 100 : 0;
  console.log(`${name}: ${b.toFixed(1)}${unit} → ${a.toFixed(1)}${unit} (${change > 0 ? "+" : ""}${change.toFixed(1)}%)`);
}
```

## Core Web Vitals — Diagnosis & Fixes

### Thresholds Reference

| Metric | Good | Needs Improvement | Poor |
| --- | --- | --- | --- |
| LCP (Largest Contentful Paint) | < 2.5s | 2.5s - 4.0s | > 4.0s |
| INP (Interaction to Next Paint) | < 200ms | 200ms - 500ms | > 500ms |
| CLS (Cumulative Layout Shift) | < 0.1 | 0.1 - 0.25 | > 0.25 |

### LCP — Target: < 2500ms

| Cause | Diagnosis | Fix |
| --- | --- | --- |
| Slow server response | TTFB > 800ms in Lighthouse | Server-side caching, CDN, edge rendering |
| Render-blocking CSS/JS | "Eliminate render-blocking resources" audit | Inline critical CSS, defer non-critical JS, `async`/`defer` attributes |
| Large hero image | LCP element is an `<img>` with large file size | Compress, use WebP/AVIF, add `loading="eager"` + `fetchpriority="high"` |
| Web fonts blocking render | FOIT visible in filmstrip | `font-display: swap`, preload key fonts |
| Client-side rendering | LCP element rendered by JavaScript | SSR/SSG the critical content |

```html
<!-- Preload LCP image -->
<link rel="preload" as="image" href="/hero.webp" fetchpriority="high">

<!-- Preload critical font -->
<link rel="preload" as="font" type="font/woff2" href="/font.woff2" crossorigin>
```

### INP — Target: < 200ms

43% of websites fail the INP threshold — it is the most commonly failed Core Web Vital.

| Cause | Diagnosis | Fix |
| --- | --- | --- |
| Long tasks blocking main thread | TBT > 200ms, long tasks in CDP trace | Break work into chunks with `scheduler.yield()` or `requestIdleCallback` |
| Heavy event handlers | Specific click/input handlers > 50ms in CPU profile | Debounce, move computation to Web Worker |
| Excessive re-renders (React) | React DevTools Profiler shows unnecessary renders | `React.memo`, `useMemo`, `useCallback` for expensive computations |
| Layout thrashing | Alternating DOM read/write in CDP trace | Batch reads before writes (see CDP section below) |
| Hydration blocking | Hydration takes > 100ms | Progressive hydration, islands architecture |

### CLS — Target: < 0.1

| Cause | Diagnosis | Fix |
| --- | --- | --- |
| Images without dimensions | CLS audit points to `<img>` elements | Always set `width` and `height` attributes |
| Dynamic content insertion | Ads, banners, or embeds inject above the fold | Reserve space with CSS `aspect-ratio` or fixed height containers |
| Web fonts causing reflow | Text size changes when font loads | `font-display: swap` + `size-adjust` in `@font-face` |
| Late-loading CSS | Stylesheet loads and shifts layout | Inline critical CSS, preload remaining |

## CDP Runtime Profiling (Beyond Lighthouse)

Lighthouse measures page-load performance. For **runtime** issues (interaction latency, janky scrolling, memory leaks), use the Chrome DevTools Protocol (CDP) directly via Playwright.

### Setup: CDP Session via Playwright

```typescript
import { chromium } from "playwright";

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext();
const page = await context.newPage();
const client = await context.newCDPSession(page);

// Enable performance domains
await client.send("Performance.enable");
await client.send("Runtime.enable");
```

### Runtime Metrics Snapshot

Capture runtime metrics before and after an interaction to measure its cost:

```typescript
async function getMetrics(client: any) {
  const { metrics } = await client.send("Performance.getMetrics");
  return Object.fromEntries(metrics.map((m: any) => [m.name, m.value]));
}

// Baseline
const before = await getMetrics(client);

// Perform interaction
await page.click('[data-testid="action-button"]');
await page.waitForLoadState("networkidle");

// After
const after = await getMetrics(client);

// Key deltas
console.log(`Layouts triggered: ${after.LayoutCount - before.LayoutCount}`);
console.log(`Layout time: ${((after.LayoutDuration - before.LayoutDuration) * 1000).toFixed(1)}ms`);
console.log(`Style recalcs: ${after.RecalcStyleCount - before.RecalcStyleCount}`);
console.log(`Script time: ${((after.ScriptDuration - before.ScriptDuration) * 1000).toFixed(1)}ms`);
console.log(`Heap used: ${((after.JSHeapUsedSize - before.JSHeapUsedSize) / 1024 / 1024).toFixed(1)}MB`);
console.log(`DOM nodes: ${after.Nodes} (delta: ${after.Nodes - before.Nodes})`);
console.log(`Event listeners: ${after.JSEventListeners} (delta: ${after.JSEventListeners - before.JSEventListeners})`);
```

**Key thresholds for interaction metrics:**

| Metric | Good | Warning | Critical |
| --- | --- | --- | --- |
| LayoutCount per interaction | < 2 | 2-5 | > 5 (layout thrashing) |
| LayoutDuration per frame | < 4ms | 4-10ms | > 10ms |
| RecalcStyleCount per interaction | < 3 | 3-10 | > 10 |
| ScriptDuration per interaction | < 50ms | 50-150ms | > 150ms |
| JSHeapUsedSize growth per interaction | < 0.5MB | 0.5-2MB | > 2MB |

### CPU Profiling (JavaScript Hot Functions)

Profile JavaScript execution to find which functions are slow:

```typescript
// Start CPU profiler with high-resolution sampling
await client.send("Profiler.enable");
await client.send("Profiler.setSamplingInterval", { interval: 100 }); // 100 microseconds
await client.send("Profiler.start");

// Execute the interaction you want to profile
await page.click('[data-testid="heavy-action"]');
await page.waitForLoadState("networkidle");

// Stop and analyze
const { profile } = await client.send("Profiler.stop");

// Find hot functions (nodes with most self-time / hitCount)
const nodes = profile.nodes;
const hotFunctions = nodes
  .filter((n: any) => n.hitCount > 0)
  .sort((a: any, b: any) => b.hitCount - a.hitCount)
  .slice(0, 10);

for (const node of hotFunctions) {
  const { functionName, url, lineNumber } = node.callFrame;
  console.log(`${functionName || "(anonymous)"} at ${url}:${lineNumber} — ${node.hitCount} samples`);
}
```

### Tracing (Timeline Recording)

Capture a Chrome trace for detailed analysis of rendering, layout, and paint events:

```typescript
// Standard profiling categories
await client.send("Tracing.start", {
  categories: [
    "devtools.timeline",
    "v8.execute",
    "blink.user_timing",
  ].join(","),
  options: "sampling-frequency=10000",
});

// Perform interactions
await page.click('[data-testid="action"]');
await page.waitForLoadState("networkidle");

// Collect trace
const traceChunks: any[] = [];
client.on("Tracing.dataCollected", (data: any) => {
  traceChunks.push(...data.value);
});
await client.send("Tracing.end");

// Wait for trace data
await new Promise((resolve) => client.on("Tracing.tracingComplete", resolve));

// Save trace (open in chrome://tracing or DevTools Performance tab)
const { writeFileSync } = await import("fs");
writeFileSync("trace.json", JSON.stringify({ traceEvents: traceChunks }));

// Analyze: find long tasks (>50ms)
const longTasks = traceChunks.filter(
  (e: any) => e.name === "RunTask" && e.dur && e.dur > 50_000 // microseconds
);
console.log(`Long tasks (>50ms): ${longTasks.length}`);
```

**Tracing category presets:**

| Preset | Categories | Use When |
| --- | --- | --- |
| Standard | `devtools.timeline`, `v8.execute`, `blink.user_timing` | General profiling, low overhead |
| Deep | + `disabled-by-default-devtools.timeline.frame`, `disabled-by-default-v8.cpu_profiler` | Detailed frame timing and JS profiling |
| Layout debug | + `disabled-by-default-devtools.timeline.invalidationTracking` | Investigating layout thrashing |
| Memory | `devtools.timeline`, `disabled-by-default-v8.gc` | GC pressure analysis |

### Collecting Core Web Vitals via CDP

Inject PerformanceObservers before navigation to capture real CWV metrics:

```typescript
// Inject observers BEFORE navigating
await page.evaluateOnNewDocument(() => {
  (window as any).__perfMetrics = { lcp: null, cls: 0, longTasks: [], interactions: [] };

  new PerformanceObserver((list) => {
    const entries = list.getEntries();
    (window as any).__perfMetrics.lcp = entries[entries.length - 1];
  }).observe({ type: "largest-contentful-paint", buffered: true });

  new PerformanceObserver((list) => {
    for (const entry of list.getEntries()) {
      if (!(entry as any).hadRecentInput) {
        (window as any).__perfMetrics.cls += (entry as any).value;
      }
    }
  }).observe({ type: "layout-shift", buffered: true });

  new PerformanceObserver((list) => {
    (window as any).__perfMetrics.longTasks.push(...list.getEntries());
  }).observe({ type: "longtask", buffered: true });

  new PerformanceObserver((list) => {
    (window as any).__perfMetrics.interactions.push(...list.getEntries());
  }).observe({ type: "event", buffered: true, durationThreshold: 16 });
});

// Navigate
await page.goto("https://example.com");
await page.waitForLoadState("networkidle");

// Collect
const metrics = await page.evaluate(() => JSON.stringify((window as any).__perfMetrics));
console.log(JSON.parse(metrics));
```

### Framework Detection

Detect the frontend framework to apply framework-specific profiling:

```typescript
const framework = await page.evaluate(() => {
  if ((window as any).__REACT_DEVTOOLS_GLOBAL_HOOK__) return "react";
  if ((window as any).__VUE_DEVTOOLS_GLOBAL_HOOK__) return "vue";
  if ((window as any).ng?.getComponent) return "angular";
  if (document.querySelector("[data-svelte-h]")) return "svelte";
  return "unknown";
});

console.log(`Detected framework: ${framework}`);
// Apply framework-specific profiling based on detection
```

## Memory Profiling

### Heap Snapshots via CDP

```typescript
// Take initial snapshot
await client.send("HeapProfiler.enable");

// Perform actions that might leak
for (let i = 0; i < 10; i++) {
  await page.click(".action-button");
  await page.waitForLoadState("networkidle");
}

// Force GC to isolate real leaks from pending garbage
await client.send("HeapProfiler.collectGarbage");

// Take heap snapshot
const chunks: string[] = [];
client.on("HeapProfiler.addHeapSnapshotChunk", (params: any) => {
  chunks.push(params.chunk);
});
await client.send("HeapProfiler.takeHeapSnapshot");

writeFileSync("heap-snapshot.heapsnapshot", chunks.join(""));
// Open in Chrome DevTools Memory tab for analysis
```

### Heap Sampling (Lower Overhead)

For steady-state memory analysis without full heap snapshots:

```typescript
await client.send("HeapProfiler.startSampling", {
  samplingInterval: 32768,
});

// ... execute interactions ...

const { profile } = await client.send("HeapProfiler.stopSampling");
// profile.head contains allocation tree — functions that allocate the most memory
```

### Detecting Memory Leaks

Pattern: take snapshot → perform action → undo action → force GC → take snapshot → compare.

Growth between snapshots after undo + GC = leak candidate.

**Heap growth monitoring:**

```typescript
// Monitor JSHeapUsedSize over time during interactions
const heapSamples: number[] = [];
const interval = setInterval(async () => {
  const m = await getMetrics(client);
  heapSamples.push(m.JSHeapUsedSize);
}, 500);

// ... perform 20 interaction cycles ...

clearInterval(interval);

// Analyze: monotonic growth after GC = likely leak
// Sawtooth pattern = normal GC behavior
```

**Memory thresholds:**

| Metric | Good | Warning | Critical |
| --- | --- | --- | --- |
| Initial JS heap | < 10MB | 10-50MB | > 50MB |
| Heap growth per interaction | < 0.5MB | 0.5-2MB | > 2MB |
| Heap growth after GC | 0 | < 1MB/min | > 1MB/min (leak) |
| Detached DOM nodes after GC | 0 | 1-10 | > 10 (leak) |
| Event listener count growth | 0/cycle | < 5/cycle | > 5/cycle (leak) |

Common leak sources:
- Event listeners not removed on component unmount
- `setInterval`/`setTimeout` not cleared
- Closures holding references to detached DOM nodes
- Global caches that grow without bounds
- WebSocket/EventSource connections not closed

## Anti-Pattern Detection

### Layout Thrashing

JavaScript reads a layout property, writes to the DOM, then reads again — forcing the browser to recalculate layout on every iteration.

**Properties that trigger layout** (reading any of these after a DOM write forces a synchronous layout):
`offsetTop/Left/Width/Height`, `scrollTop/Left/Width/Height`, `clientTop/Left/Width/Height`, `getComputedStyle()`, `getBoundingClientRect()`, `innerHeight/Width`, `scrollIntoView()`, `focus()`

**Detection via CDP metrics:**
```typescript
// If LayoutCount delta > 5 for a single interaction = layout thrashing
const before = await getMetrics(client);
await page.click('[data-testid="action"]');
const after = await getMetrics(client);
if (after.LayoutCount - before.LayoutCount > 5) {
  console.warn("Layout thrashing detected!");
}
```

**Fix pattern:**
```javascript
// BAD: read-write-read-write in loop (thrashing)
items.forEach((el) => {
  el.style.height = el.offsetHeight * 2 + "px"; // read then write each iteration
});

// GOOD: batch reads, then batch writes
const heights = items.map((el) => el.offsetHeight); // all reads first
items.forEach((el, i) => {
  el.style.height = heights[i] * 2 + "px"; // all writes after
});
```

### DOM Complexity

```typescript
// Check DOM size via CDP
const { root } = await client.send("DOM.getDocument", { depth: -1 });

// Count nodes recursively
function countNodes(node: any): number {
  let count = 1;
  for (const child of node.children ?? []) count += countNodes(child);
  return count;
}

const nodeCount = countNodes(root);
console.log(`DOM nodes: ${nodeCount} ${nodeCount > 1500 ? "WARNING: excessive" : "OK"}`);
```

| Metric | Good | Warning | Critical |
| --- | --- | --- | --- |
| Total DOM nodes | < 800 | 800-1500 | > 1500 |
| Maximum DOM depth | < 15 | 15-32 | > 32 |
| Max children per element | < 30 | 30-60 | > 60 |

### Unused CSS Detection

```typescript
// Start CSS coverage tracking
await client.send("CSS.enable");
await client.send("CSS.startRuleUsageTracking");

// Navigate and interact
await page.goto("https://example.com");
await page.waitForLoadState("networkidle");

// Stop and analyze
const { ruleUsage } = await client.send("CSS.stopRuleUsageTracking");
const total = ruleUsage.length;
const unused = ruleUsage.filter((r: any) => !r.used).length;
console.log(`CSS rules: ${total} total, ${unused} unused (${((unused / total) * 100).toFixed(0)}%)`);
```

### JS Code Coverage

```typescript
await client.send("Profiler.enable");
await client.send("Profiler.startPreciseCoverage", {
  callCount: true,
  detailed: true,
});

// Navigate and interact
await page.goto("https://example.com");
await page.waitForLoadState("networkidle");

const { result } = await client.send("Profiler.takePreciseCoverage");

for (const script of result) {
  const totalBytes = script.functions.reduce(
    (sum: number, fn: any) =>
      sum + fn.ranges.reduce((s: number, r: any) => s + r.endOffset - r.startOffset, 0),
    0
  );
  const usedBytes = script.functions.reduce(
    (sum: number, fn: any) =>
      sum + fn.ranges.filter((r: any) => r.count > 0).reduce((s: number, r: any) => s + r.endOffset - r.startOffset, 0),
    0
  );
  if (totalBytes > 10000) {
    console.log(`${script.url}: ${((usedBytes / totalBytes) * 100).toFixed(0)}% used (${(totalBytes / 1024).toFixed(0)}KB)`);
  }
}
```

## Bundle Analysis

### webpack

```bash
npx webpack --profile --json > stats.json
npx webpack-bundle-analyzer stats.json
```

### Vite / Rollup

```bash
npm install -D rollup-plugin-visualizer
# Add to vite.config.ts: plugins: [visualizer({ open: true, gzipSize: true })]
npm run build
```

### source-map-explorer (any bundler)

```bash
npx source-map-explorer dist/bundle.js
npx source-map-explorer dist/*.js --html analysis.html
```

### What to Look For

| Signal | Problem | Fix |
| --- | --- | --- |
| `moment.js` > 200KB | Full locale data included | Switch to `date-fns` or `dayjs` |
| `lodash` > 70KB | Entire library imported | Use `lodash-es` with tree-shaking or individual imports |
| Duplicate packages | Same lib at multiple versions | Dedupe with `npm dedupe` or resolve in package.json |
| Large polyfills | Babel polyfills for modern browsers | Update browserslist, use `useBuiltIns: 'usage'` |
| Uncompressed assets | JS/CSS served without gzip/brotli | Enable compression on server/CDN |

## Network Thresholds

| Metric | Good | Warning | Critical |
| --- | --- | --- | --- |
| Total page weight | < 1MB | 1-3MB | > 3MB |
| Total JS (compressed) | < 200KB | 200-500KB | > 500KB |
| Total CSS (compressed) | < 50KB | 50-150KB | > 150KB |
| Total images | < 500KB | 500KB-1.5MB | > 1.5MB |
| HTTP requests | < 30 | 30-80 | > 80 |
| Render-blocking resources | 0 | 1-2 | > 2 |
| TTFB | < 200ms | 200-600ms | > 600ms |

## Lighthouse CI (Automated Tracking)

```bash
npm install -g @lhci/cli
lhci autorun --config=lighthouserc.json
```

```json
{
  "ci": {
    "collect": {
      "url": ["http://localhost:3000/", "http://localhost:3000/about"],
      "numberOfRuns": 3,
      "startServerCommand": "npm run start"
    },
    "assert": {
      "assertions": {
        "categories:performance": ["error", { "minScore": 0.9 }],
        "first-contentful-paint": ["warn", { "maxNumericValue": 2000 }],
        "largest-contentful-paint": ["error", { "maxNumericValue": 2500 }],
        "cumulative-layout-shift": ["error", { "maxNumericValue": 0.1 }],
        "total-blocking-time": ["warn", { "maxNumericValue": 200 }]
      }
    },
    "upload": {
      "target": "temporary-public-storage"
    }
  }
}
```

```yaml
# GitHub Actions
- name: Lighthouse CI
  run: |
    npm install -g @lhci/cli
    lhci autorun
  env:
    LHCI_GITHUB_APP_TOKEN: ${{ secrets.LHCI_GITHUB_APP_TOKEN }}
```

## Verification Checklist

Before reporting profiling results:

- [ ] Ran Lighthouse at least 3 times and took median scores (results vary per run)
- [ ] Tested both mobile and desktop presets
- [ ] Core Web Vitals (LCP, INP/TBT, CLS) explicitly measured and compared to thresholds
- [ ] For runtime issues: used CDP profiling (not just Lighthouse) to measure interaction cost
- [ ] Bundle size measured with gzip/brotli sizes (raw size is misleading)
- [ ] Before/after comparison uses same conditions (same server, same network, same browser flags)
- [ ] Memory leak detection used forced GC before taking comparison snapshots
- [ ] Recommendations are specific and actionable (not just "improve performance")
- [ ] Each recommendation includes expected impact (e.g., "~300ms LCP improvement")
