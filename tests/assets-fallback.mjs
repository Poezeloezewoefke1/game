// Verifies the external-asset layer degrades gracefully: every model, normal
// map and HDRI request is blocked, and the game must still boot, start an
// expedition and fall back to procedural assets without runtime errors.
import { chromium } from 'playwright';

const URL = process.env.ABYSSAL_URL || 'http://localhost:4173/';
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const page = await browser.newPage({ viewport: { width: 640, height: 360 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
let blocked = 0;
await page.route(/\/(models|textures)\//, (route) => { blocked++; route.abort(); });
await page.goto(URL);
await page.waitForFunction(() => window.__ABYSSAL && window.__ABYSSAL.mode === 'menu', null, { timeout: 180000 });
await page.click('button[data-act=new]');
await page.waitForTimeout(300);
await page.keyboard.press('Space');
await page.waitForFunction(() => window.__ABYSSAL.mode === 'play', null, { timeout: 30000 });
const r = await page.evaluate(() => {
  const g = window.__ABYSSAL;
  g.renderer.setAnimationLoop(null);
  g.simulate(1);
  return { failures: g.assets.failures.length, fishExternal: !!g.world.creatures.fish.external, fishCount: g.world.creatures.fish.mesh.count, mode: g.mode, err: g.lastError ? String(g.lastError) : null };
});
const ok = blocked > 0 && r.failures >= 5 && !r.fishExternal && r.fishCount > 0 && r.mode === 'play' && !r.err && errors.length === 0;
console.log(`${ok ? 'PASS' : 'FAIL'}  game runs on procedural fallbacks with all external assets blocked`, JSON.stringify({ blocked, ...r, errors: errors.slice(0, 3) }));
await browser.close();
process.exit(ok ? 0 : 1);
