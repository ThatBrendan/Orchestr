/** Local landing regression checks; external requests are blocked. */
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';
const origin = 'http://127.0.0.1:5173';
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const context = await browser.newContext();
await context.route('**/*', route => new URL(route.request().url()).origin === origin ? route.continue() : route.fulfill({status:200,contentType:'application/json',body:'[]'}));
const page = await context.newPage();
const errors = [];
page.on('pageerror', e => errors.push(e.message));
page.on('console', m => { if(m.type() === 'error') errors.push(m.text()); });
await mkdir('/tmp/orchestrio-landing-qa', { recursive: true });
try {
  for (const [width,height] of [[1440,900],[1280,900],[1024,768],[768,1024],[430,932],[390,844],[375,812]]) {
    await page.setViewportSize({width,height});
    await page.goto(origin);
    await page.getByRole('heading', {level:1}).waitFor();
    await page.evaluate(() => document.fonts.ready);
    assert.equal(await page.locator('h1').count(), 1);
    assert.match(await page.locator('h1').innerText(), /Plans need more than messages\./);
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `Overflow at ${width}`);
    const clipped = await page.locator('main *').evaluateAll(els => els.filter(el => {const r=el.getBoundingClientRect();return r.width>0 && (r.left < -1 || r.right > innerWidth+1);}).map(el=>el.tagName+'.'+el.className));
    assert.deepEqual(clipped, [], `Clipped content at ${width}`);
    assert.equal(await page.locator('#how-it-works article').count(), 3);
    assert.equal(await page.locator('#use-cases article').count(), 4);
    assert.equal(await page.locator('figure :is(button,a,input)').count(), 0);
    await page.screenshot({path:`/tmp/orchestrio-landing-qa/${width}.png`,fullPage:true});
    if(width < 768) {
      const menu = page.getByRole('button',{name:'Open menu'});
      await menu.focus(); await page.keyboard.press('Enter');
      assert.equal(await page.getByRole('button',{name:'Close menu'}).getAttribute('aria-expanded'),'true');
    }
    for(const label of ['Product','How it works','Use cases']) {
      if(width < 768 && await page.getByRole('button',{name:'Open menu'}).isVisible()) await page.getByRole('button',{name:'Open menu'}).click();
      const link = page.locator('header').getByRole('link',{name:label,exact:true});
      const href = await link.getAttribute('href');
      await link.click();
      await page.waitForFunction(hash => location.hash === hash, href.slice(href.indexOf('#')));
      // Wait for the router's smooth scroll to settle, then check sticky header clearance.
      await page.waitForTimeout(900);
      const top = await page.locator(new URL(href,origin).hash).evaluate(el=>el.getBoundingClientRect().top);
      assert(top >= 63 && top < height, `${label} target at ${width}: ${top}`);
    }
    console.log(`PASS layout, sections and navigation: ${width} × ${height}`);
  }
  await page.setViewportSize({width:1440,height:900}); await page.goto(origin);
  await page.getByRole('heading', {level:1}).waitFor();
  await page.keyboard.press('Tab');
  assert.equal(await page.locator(':focus').innerText(), 'Skip to content');
  assert.notEqual(await page.locator(':focus').evaluate(el=>getComputedStyle(el).outlineStyle),'none');
  const destinations = await page.locator('a').evaluateAll(els=>[...new Set(els.map(el=>el.getAttribute('href')))]);
  for(const href of destinations) {
    assert(href && href !== '#', `Dead link: ${href}`);
    if(href.startsWith('mailto:')) continue;
    const url = new URL(href, origin);
    if(url.hash) { assert.equal(await page.locator(url.hash).count(),1); continue; }
    const response = await page.goto(url.href);
    assert(response.ok(), href);
    await page.locator('h1').waitFor();
    assert(!/not found/i.test(await page.locator('h1').innerText()), href);
  }
  await page.goto(origin); await page.locator('header').getByRole('link',{name:'Log in',exact:true}).click(); await page.waitForURL(origin+'/login');
  await page.goto(origin); await page.locator('main').getByRole('link',{name:'Get started',exact:true}).first().click(); await page.waitForURL(origin+'/signup');
  await page.emulateMedia({reducedMotion:'reduce'}); await page.goto(origin);
  assert.equal(await page.evaluate(()=>getComputedStyle(document.documentElement).scrollBehavior),'auto');
  await page.locator('header').getByRole('link',{name:'How it works',exact:true}).click();
  await page.waitForFunction(()=>Math.abs(document.querySelector('#how-it-works').getBoundingClientRect().top-80)<2);
  const contrast = await page.evaluate(() => {
    const style=getComputedStyle(document.documentElement);
    const color=name=>style.getPropertyValue('--'+name).trim().split(/\s+/).map(Number);
    const luminance=rgb=>rgb.map(v=>{v/=255;return v<=0.04045?v/12.92:((v+0.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[0.2126,0.7152,0.0722][i],0);
    return [['text','page'],['text-secondary','page'],['text-muted','surface'],['brand','brand-soft'],['accent','accent-soft'],['warning','warning-soft'],['surface','brand-hover']].map(([fg,bg])=>{const a=luminance(color(fg)),b=luminance(color(bg));return {fg,bg,ratio:(Math.max(a,b)+0.05)/(Math.min(a,b)+0.05)};});
  });
  for(const pair of contrast) assert(pair.ratio >= 4.5, JSON.stringify(pair));
  console.log('PASS semantic text contrast pairs:', contrast.map(p=>p.ratio.toFixed(2)).join(', '));
  assert.deepEqual(errors, []);
  console.log('PASS CTA routes, footer destinations, keyboard focus, reduced-motion CSS and no console errors');
} finally { await browser.close(); }
