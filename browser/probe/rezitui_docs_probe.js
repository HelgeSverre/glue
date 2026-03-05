const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

(async () => {
  const targets = [
    'https://rezitui.dev/docs/design-system',
    'https://rezitui.dev/docs',
    'https://rezitui.dev/',
  ];

  fs.mkdirSync(path.join('browser', 'screenshots'), { recursive: true });

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1400, height: 2000 } });
  const page = await context.newPage();

  const out = [];
  for (const url of targets) {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.waitForLoadState('networkidle', { timeout: 90000 });

    const slug = url
      .replace(/^https?:\/\//, '')
      .replace(/[^a-zA-Z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '');

    await page.screenshot({
      path: path.join('browser', 'screenshots', `${slug}.png`),
      fullPage: true,
    });

    const data = await page.evaluate(() => {
      const clean = (s) => (s || '').replace(/\s+/g, ' ').trim();
      const pick = (sel, n = 120) =>
        Array.from(document.querySelectorAll(sel))
          .map((el) => clean(el.textContent))
          .filter(Boolean)
          .slice(0, n);

      const links = Array.from(document.querySelectorAll('a[href]'))
        .map((a) => ({ href: a.getAttribute('href') || '', text: clean(a.textContent) }))
        .filter((x) => x.href && x.text)
        .slice(0, 800);

      return {
        title: document.title,
        h1: pick('h1', 20),
        h2: pick('h2', 120),
        h3: pick('h3', 240),
        nav: pick('nav a, aside a', 300),
        links,
      };
    });

    out.push({ url, ...data });
  }

  fs.writeFileSync('browser/rezitui-docs-scan.json', JSON.stringify(out, null, 2));

  await browser.close();
})();
