const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const widgetPaths = [
  '/docs/widgets/text',
  '/docs/widgets/spinner',
  '/docs/widgets/button',
  '/docs/widgets/tabs',
  '/docs/widgets/table',
  '/docs/widgets/modal',
  '/docs/widgets/grid',
  '/docs/widgets/command-palette',
  '/docs/widgets/bar-chart',
  '/docs/widgets/canvas',
  '/docs/widgets/callout',
];

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1400, height: 2200 } });
  const page = await context.newPage();

  const out = [];
  fs.mkdirSync(path.join('browser', 'screenshots', 'widgets'), { recursive: true });

  for (const p of widgetPaths) {
    const url = `https://rezitui.dev${p}`;
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 90000 });
      await page.waitForLoadState('networkidle', { timeout: 90000 });

      const slug = p.replace(/[^a-zA-Z0-9]+/g, '_').replace(/^_+|_+$/g, '');
      await page.screenshot({
        path: path.join('browser', 'screenshots', 'widgets', `${slug}.png`),
        fullPage: true,
      });

      const data = await page.evaluate(() => {
        const clean = (s) => (s || '').replace(/\s+/g, ' ').trim();
        const pick = (sel, n = 200) =>
          Array.from(document.querySelectorAll(sel))
            .map((el) => clean(el.textContent))
            .filter(Boolean)
            .slice(0, n);

        const codeBlocks = Array.from(document.querySelectorAll('pre code'))
          .map((el) => clean(el.textContent))
          .filter(Boolean)
          .slice(0, 12);

        const anchors = Array.from(document.querySelectorAll('a[href^="#"]'))
          .map((a) => ({ href: a.getAttribute('href') || '', text: clean(a.textContent) }))
          .filter((a) => a.href && a.text)
          .slice(0, 60);

        return {
          title: document.title,
          h1: pick('h1', 10),
          h2: pick('h2', 120),
          h3: pick('h3', 220),
          anchors,
          codeBlocks,
        };
      });

      out.push({ url, ok: true, ...data });
    } catch (err) {
      out.push({ url, ok: false, error: String(err) });
    }
  }

  fs.writeFileSync('browser/rezitui-widgets-scan.json', JSON.stringify(out, null, 2));
  await browser.close();
})();
