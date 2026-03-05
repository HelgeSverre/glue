const { test } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const targets = [
  'https://rezitui.dev/docs/design-system',
  'https://rezitui.dev/docs',
  'https://rezitui.dev/'
];

test('probe rezitui docs', async ({ page }) => {
  const out = [];
  for (const url of targets) {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForLoadState('networkidle', { timeout: 60000 });

    const slug = url
      .replace(/^https?:\/\//, '')
      .replace(/[^a-zA-Z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '');

    await page.screenshot({
      path: path.join('browser', 'screenshots', `${slug}.png`),
      fullPage: true,
    });

    const data = await page.evaluate(() => {
      const txt = (el) => (el?.textContent || '').replace(/\s+/g, ' ').trim();
      const pick = (sel, n = 80) =>
        Array.from(document.querySelectorAll(sel))
          .map((el) => txt(el))
          .filter(Boolean)
          .slice(0, n);

      const links = Array.from(document.querySelectorAll('a[href]'))
        .map((a) => ({
          href: a.getAttribute('href') || '',
          text: txt(a),
        }))
        .filter((a) => a.href && a.text)
        .slice(0, 400);

      return {
        title: document.title,
        h1: pick('h1', 5),
        h2: pick('h2', 60),
        h3: pick('h3', 120),
        nav: pick('nav a, aside a', 200),
        links,
      };
    });

    out.push({ url, ...data });
  }

  fs.mkdirSync('browser', { recursive: true });
  fs.writeFileSync('browser/rezitui-docs-scan.json', JSON.stringify(out, null, 2));
});
