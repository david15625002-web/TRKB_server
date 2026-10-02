/* --------------------------------------------------------------------------
   Smoke + layout check for the prototype.

   Not a unit test suite - it verifies the things that silently break:
   every screen renders, the countdown ticks, interactions change state, all
   8 theme combinations produce genuinely distinct colours, and no screen
   leaks horizontal page scroll at phone width.

   It caught three real bugs: 306px of overflow on jadwal and 29px on obrolan
   (grid/flex items default to min-width:auto), and the phone tab bar staying
   visible on desktop (a media query losing to a later declaration).

   Usage:  npm i -D playwright && node mockup/tests/check.mjs ./shots
   -------------------------------------------------------------------------- */

import { chromium } from 'playwright';
const OUT = process.argv[2] || './shots';
const errors = [];
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 1000 } });
page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
page.on('console', m => { const t=m.text(); if (m.type()==='error' && !t.includes('ERR_CERT') && !t.includes('fonts.g')) errors.push('CONSOLE: '+t); });

await page.goto(new URL('../index.html', import.meta.url).href, { waitUntil: 'load' });
await page.waitForTimeout(900);

const pages = ['beranda','jadwal','tugas','obrolan','organisasi','profil','pengaturan','notifikasi'];
for (const p of pages) {
  await page.evaluate(p => { S.laman = p; render(); }, p);
  await page.waitForTimeout(120);
  const n = await page.$eval('#view', el => el.innerText.length);
  if (n < 60) errors.push(`EMPTY PAGE: ${p}`);
}
console.log('  all 8 screens render');

// countdown — generous window, it updates once per second
await page.evaluate(() => { S.laman='beranda'; render(); });
const c1 = await page.$eval('#cd', e => e.textContent);
await page.waitForTimeout(2600);
const c2 = await page.$eval('#cd', e => e.textContent);
console.log(`  countdown ${c1} -> ${c2} ${c1!==c2?'(ticking)':'(STATIC)'}`);
if (c1===c2) errors.push('countdown not ticking');

// task toggle — test on the TUGAS page, where completed tasks remain visible
await page.evaluate(() => { S.laman='tugas'; render(); });
await page.waitForTimeout(150);
const d1 = await page.$$eval('.task.done', e=>e.length);
await page.click('.task:not(.done) .check');
await page.waitForTimeout(260);
const d2 = await page.$$eval('.task.done', e=>e.length);
console.log(`  task toggle: done ${d1} -> ${d2}`);
if (d2 !== d1+1) errors.push(`task toggle: expected ${d1+1} done, got ${d2}`);
const toasts = await page.$$eval('.toast', e=>e.length);
console.log(`  toast fired: ${toasts>0}`);
if (!toasts) errors.push('no toast on completion');

// approval queue
await page.evaluate(() => { S.laman='beranda'; render(); });
await page.waitForTimeout(150);
const a1 = await page.$$eval('[data-act="setuju"]', e=>e.length);
await page.click('[data-act="setuju"]');
await page.waitForTimeout(220);
const a2 = await page.$$eval('[data-act="setuju"]', e=>e.length);
console.log(`  approval: pending ${a1} -> ${a2}`);
if (a2 !== a1-1) errors.push('approval did not remove the row');

// modal
await page.evaluate(() => { S.laman='tugas'; render(); });
await page.waitForTimeout(120);
await page.click('[data-act="tambahTugas"]');
await page.waitForTimeout(260);
const modal = await page.$$eval('.modal', e=>e.length);
console.log(`  modal opens: ${modal>0}`);
if (!modal) errors.push('add-task modal did not open');
await page.keyboard.press('Escape');
await page.waitForTimeout(180);
if ((await page.$$eval('.modal', e=>e.length)) > 0) errors.push('Escape did not close the modal');
console.log('  modal closes on Escape');

// chat
await page.evaluate(() => { S.laman='obrolan'; render(); });
await page.waitForTimeout(150);
const m1 = await page.$$eval('.msg', e=>e.length);
await page.fill('#msgin', 'Tes kirim pesan panjang tanpa spasi:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
await page.press('#msgin', 'Enter');
await page.waitForTimeout(240);
console.log(`  chat send: ${m1} -> ${await page.$$eval('.msg', e=>e.length)}`);

// Every accent seed x mode must produce a genuinely distinct palette.
const SEEDS = ['green','blue','orange'];   // the Duolingo brand accents
const seen = new Set();
for (const sd of SEEDS) {
  for (const mo of ['light','dark']) {
    await page.evaluate(([sd,mo]) => { S.seed=sd; S.mode=mo; S.laman='beranda'; applyTheme(); render(); }, [sd,mo]);
    await page.waitForTimeout(260);
    const c = await page.evaluate(() => {
      const r = getComputedStyle(document.documentElement);
      return getComputedStyle(document.body).backgroundColor + '|'
           + r.getPropertyValue('--accent').trim() + '|'
           + r.getPropertyValue('--accent-text').trim();
    });
    seen.add(c);
    if (mo === 'light') await page.screenshot({ path: `${OUT}/seed-${sd}.png` });
  }
}
const want = SEEDS.length * 2;
console.log(`  accents: ${want} seed x mode combinations produced ${seen.size} distinct palettes`);
if (seen.size < want) errors.push(`palettes not distinct: only ${seen.size}/${want}`);

// 'system' must resolve to a concrete mode, never leak through to the tokens.
await page.evaluate(() => { S.mode='system'; applyTheme(); });
const resolved = await page.evaluate(() => document.documentElement.getAttribute('data-mode'));
console.log(`  mode "system" resolves to: ${resolved}`);
if (!['light','dark'].includes(resolved)) errors.push(`system mode leaked "${resolved}" into data-mode`);
await page.evaluate(() => { S.seed='green'; S.mode='light'; applyTheme(); render(); });

// phone overflow
await page.setViewportSize({ width: 360, height: 760 });
for (const p of pages) {
  await page.evaluate(p => { S.seed='green'; S.mode='light'; S.laman=p; applyTheme(); render(); }, p);
  await page.waitForTimeout(200);
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  console.log(`  phone/${p.padEnd(11)} overflow ${over}px ${over>2?'<-- PROBLEM':'ok'}`);
  if (over > 2) errors.push(`horizontal overflow on ${p}: ${over}px`);
  if (['beranda','jadwal','obrolan','profil'].includes(p)) await page.screenshot({ path: `${OUT}/phone-${p}.png` });
}

// 320px, the narrowest phone worth supporting
await page.setViewportSize({ width: 320, height: 700 });
for (const p of pages) {
  await page.evaluate(p => { S.laman=p; render(); }, p);
  await page.waitForTimeout(160);
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  if (over > 2) errors.push(`320px overflow on ${p}: ${over}px`);
}
console.log('  320px width: checked all 8 screens');

// reduced motion
await page.evaluate(() => { S.gerak=false; applyTheme(); render(); });
await page.waitForTimeout(150);
console.log('  reduced-motion toggle applies: ' + await page.evaluate(() => document.documentElement.getAttribute('data-motion')));

await browser.close();
console.log('\n' + (errors.length ? 'ERRORS:\n  ' + errors.join('\n  ') : 'NO ERRORS — all checks passed'));
process.exit(errors.length ? 1 : 0);
