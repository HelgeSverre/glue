const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

(async () => {
  const url='https://rezitui.dev/docs/design-system';
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1500, height: 2400 } });
  await page.goto(url,{waitUntil:'domcontentloaded',timeout:90000});
  await page.waitForLoadState('networkidle',{timeout:90000});
  await page.screenshot({path:'browser/screenshots/rezitui_design_system_detail.png',fullPage:true});

  const data=await page.evaluate(()=>{
    const clean=(s)=>(s||'').replace(/\s+/g,' ').trim();
    const code=Array.from(document.querySelectorAll('pre code')).map(el=>clean(el.textContent)).filter(Boolean);
    const paras=Array.from(document.querySelectorAll('main p')).map(el=>clean(el.textContent)).filter(Boolean);
    const lists=Array.from(document.querySelectorAll('main li')).map(el=>clean(el.textContent)).filter(Boolean);
    return {
      title: document.title,
      h2: Array.from(document.querySelectorAll('h2')).map(el=>clean(el.textContent)).filter(Boolean),
      h3: Array.from(document.querySelectorAll('h3')).map(el=>clean(el.textContent)).filter(Boolean),
      code,
      paras: paras.slice(0,120),
      lists: lists.slice(0,240),
    };
  });

  fs.writeFileSync('browser/rezitui-design-system-detail.json',JSON.stringify(data,null,2));
  await browser.close();
})();
