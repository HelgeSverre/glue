/** @type {import('playwright').PlaywrightTestConfig} */
module.exports = {
  testDir: '.',
  timeout: 120000,
  retries: 0,
  workers: 1,
  reporter: 'line',
  use: {
    headless: true,
    viewport: { width: 1400, height: 2000 },
  },
};
