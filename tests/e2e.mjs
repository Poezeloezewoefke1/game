// End-to-end gameplay tests. Builds are served by `vite preview`; run with:
//   npm run build && npm run preview &  then  npm test
// Uses Playwright + Chromium (software WebGL is fine). Logic is stepped with
// game.simulate() so the tests do not depend on frame rate.
import { chromium } from 'playwright';

const URL = process.env.ABYSSAL_URL || 'http://localhost:4173/';
const results = [];
let failures = 0;

function check(name, cond, detail = '') {
  results.push(`${cond ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
  if (!cond) failures++;
}

const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const page = await browser.newPage({ viewport: { width: 800, height: 450 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

await page.goto(URL);
await page.waitForFunction(() => window.__ABYSSAL && window.__ABYSSAL.mode === 'menu', null, { timeout: 180000 });
check('boots to main menu', true);
await page.evaluate(() => localStorage.clear());

// New game + skip intro
await page.click('button[data-act=new]');
await page.waitForTimeout(300);
await page.keyboard.press('Space');
await page.waitForFunction(() => window.__ABYSSAL.mode === 'play', null, { timeout: 30000 });
// real keyboard input through the live game loop (frames are slow under
// software WebGL, so wait on game state rather than fixed delays)
await page.evaluate(() => { const g = window.__ABYSSAL; g.settings.quality = 'low'; g.applySettings(); });
const startX = await page.evaluate(() => window.__ABYSSAL.player.pos.x);
await page.keyboard.down('KeyW');
const moved = await page.waitForFunction((x) => window.__ABYSSAL.player.pos.x > x + 0.5, startX, { timeout: 90000 }).then(() => true, () => false);
await page.keyboard.up('KeyW');
check('keyboard input moves the diver (live loop)', moved);
await page.keyboard.press('Tab');
const opened = await page.waitForFunction(() => window.__ABYSSAL.mode === 'pda', null, { timeout: 60000 }).then(() => true, () => false);
await page.keyboard.press('Tab');
const closed = await page.waitForFunction(() => window.__ABYSSAL.mode === 'play', null, { timeout: 60000 }).then(() => true, () => false);
check('Tab opens and closes the wrist PDA', opened && closed);
await page.evaluate(() => {
  const g = window.__ABYSSAL;
  g.player.place(new g.player.pos.constructor(2.8, -20, 0), -Math.PI / 2, 0.1);
});
await page.waitForFunction(() => window.__ABYSSAL.findInteraction()?.it?.type === 'stationTerminal', null, { timeout: 60000 }).catch(() => {});
await page.keyboard.press('KeyE');
await page.waitForFunction(() => window.__ABYSSAL.mode === 'pda', null, { timeout: 60000 }).catch(() => {});
const termState = await page.evaluate(() => ({ mode: window.__ABYSSAL.mode, pda: window.__ABYSSAL.ui.pdaMode }));
check('E at the terminal opens the station fabricator', termState.mode === 'pda' && termState.pda === 'station', JSON.stringify(termState));
await page.keyboard.press('Escape');
await page.waitForTimeout(600);
// stop the render loop: logic is stepped manually from here
await page.evaluate(() => { const g = window.__ABYSSAL; if (g.mode === 'pda') g.closePDA(); g.input.onLockChange = null; g.everLocked = false; g.input.unlock(); g.input.down.clear(); g.input.endFrame(); if (g.mode === 'pause') g.resume(); g.mode = 'play'; g.renderer.setAnimationLoop(null); g.player.place(new g.player.pos.constructor(-1.6, -20, 0.4), -Math.PI / 2, 0); });

const r = await page.evaluate(() => {
  const g = window.__ABYSSAL;
  const V = g.player.pos.constructor;
  const out = {};
  const hold = (code, secs) => { g.input.simulate(code, true); g.simulate(secs); g.input.simulate(code, false); g.simulate(0.1); };

  out.spawnInPool = g.player.inAirPocket && Math.abs(g.player.pos.x) < 4;
  out.o2Start = g.state.o2;

  // --- movement: swim forward (towards +x from spawn yaw)
  const p0 = g.player.pos.clone();
  hold('KeyW', 1.0);
  out.moved = g.player.pos.distanceTo(p0);

  // --- station collision: the pool railing keeps the diver inside the moonpool
  g.player.place(new V(0, -20, 0), -Math.PI / 2, 0);
  hold('KeyW', 3);
  out.poolRadius = Math.hypot(g.player.pos.x, g.player.pos.z);

  // --- terrain collision: dive hard into the seabed on the shelf
  g.player.place(new V(-60, -24, -100), 0, -1.4);
  hold('KeyC', 4);
  const ground = g.world.terrain.heightAt(g.player.pos.x, g.player.pos.z);
  out.aboveGround = g.player.pos.y - ground;

  // --- oxygen drains underwater...
  g.player.place(new V(-60, -24, -100), 0, 0);
  g.state.o2 = g.o2Max;
  g.simulate(5);
  out.o2AfterDive = g.state.o2;
  // ...and refills at the surface
  g.player.place(new V(-60, -0.05, -100), 0, 0);
  g.simulate(2);
  out.surfaced = g.player.surfaced;
  out.o2AfterSurface = g.state.o2;

  // --- drowning damages health
  g.player.place(new V(-60, -24, -100), 0, 0);
  g.state.o2 = 0.5;
  const h0 = g.state.health;
  g.simulate(2);
  out.drownDamage = h0 - g.state.health;
  g.state.health = 100; g.state.o2 = g.o2Max;

  // --- depth damage beyond suit rating
  g.player.place(new V(SITES_X(), -150, 300), 0, 0);
  function SITES_X() { return 20; }
  const h1 = g.state.health;
  g.simulate(1);
  out.pressureDamage = h1 - g.state.health;
  g.state.health = 100;
  return out;
});
check('player spawns in the moonpool air pocket', r.spawnInPool);
check('swimming moves the player', r.moved > 2, `${r.moved.toFixed(2)} m`);
check('moonpool railing collision', r.poolRadius < 3.3, `r=${r.poolRadius.toFixed(2)}`);
check('terrain collision keeps diver above seabed', r.aboveGround > 0.3, `${r.aboveGround.toFixed(2)} m`);
check('oxygen drains underwater', r.o2AfterDive < r.o2Start - 3.5, `${r.o2AfterDive.toFixed(1)}s left`);
check('oxygen refills at the surface', r.surfaced && r.o2AfterSurface >= r.o2Start - 0.01 && r.o2AfterSurface > r.o2AfterDive, `${r.o2AfterSurface.toFixed(1)}s`);
check('drowning causes damage', r.drownDamage > 5, `-${r.drownDamage.toFixed(1)}`);
check('exceeding suit rating causes damage', r.pressureDamage > 2, `-${r.pressureDamage.toFixed(1)}`);

// --- scanning
const scan = await page.evaluate(() => {
  const g = window.__ABYSSAL;
  const sb = g.world.creatures.shellbacks.list[0];
  const target = sb.p.clone().setY(sb.p.y + 0.5);
  const from = target.clone().add(new target.constructor(0, 2, 6));
  g.player.place(from, 0, 0);
  // aim at the target
  const d = target.clone().sub(from);
  g.player.yaw = Math.atan2(-d.x, -d.z);
  g.player.pitch = Math.atan2(d.y, Math.hypot(d.x, d.z));
  g.player.applyCamera();
  g.camera.updateMatrixWorld();
  const found = g.findScanTarget();
  g.input.simulate('KeyF', true);
  for (let i = 0; i < 120 && !g.state.databank.includes('shellback'); i++) {
    sb.p.copy(target).setY(target.y - 0.5); // hold still for the test
    g.player.place(from, g.player.yaw, g.player.pitch);
    g.simulate(1 / 30);
  }
  g.input.simulate('KeyF', false);
  return { found: found && found.id, scanned: g.state.databank.includes('shellback') };
});
check('scanner acquires a creature target', scan.found === 'shellback', String(scan.found));
check('holding scan adds a databank entry', scan.scanned);

// --- collecting resources
const col = await page.evaluate(() => {
  const g = window.__ABYSSAL;
  const n = g.world.resources.nodes.find((x) => x.type === 'ferrite' && !x.collected);
  const eye = n.pos.clone().add(new n.pos.constructor(0, 1.6, 1.6));
  g.player.place(eye, 0, 0);
  const d = n.pos.clone().setY(n.pos.y + 0.3).sub(eye);
  g.player.yaw = Math.atan2(-d.x, -d.z);
  g.player.pitch = Math.atan2(d.y, Math.hypot(d.x, d.z));
  g.player.applyCamera();
  g.camera.updateMatrixWorld();
  const before = g.count('ferrite');
  const it = g.findInteraction();
  g.doInteract(it);
  return { kind: it && it.kind, before, after: g.count('ferrite'), collected: n.collected };
});
check('interaction targets a resource deposit', col.kind === 'resource', String(col.kind));
check('collecting adds to inventory and removes the deposit', col.after === col.before + 1 && col.collected);

// --- progression: power cell, station power, Kestrel
const prog = await page.evaluate(() => {
  const g = window.__ABYSSAL;
  const out = {};
  g.state.inventory.ferrite = 3; g.state.inventory.lumen = 2;
  out.cantUpgradeWithoutPower = !g.canCraft({ ...g.constructor.RECIPE_tank2 || { id: 'x', where: 'station', cost: {}, gives: { upgrade: 'tank', level: 1 } } }, 'station').ok;
  out.crafted = g.craft('powerCell', 'station');
  out.hasCell = g.hasItem('powerCell');
  const core = g.world.structures.interactables.find((i) => i.type === 'powerCore');
  g.doInteract({ kind: 'struct', it: core });
  out.power = g.state.flags.power;
  out.subOnline = g.sub.online && g.sub.power > 50;
  out.logs = g.state.logs.length;
  out.hull2Blueprint = g.state.blueprints.includes('hull2');
  out.echoActive = g.state.objectives.echo === 'active';
  // upgrade crafting
  g.state.inventory.ferrite = 3; g.state.inventory.kelpFiber = 2;
  out.tankBefore = g.o2Max;
  g.craft('tank2', 'station');
  out.tankAfter = g.o2Max;
  // pilot the Kestrel
  g.player.place(g.sub.pos.clone().add(new g.sub.pos.constructor(0, 0, 4)), 0, 0);
  g.enterSub();
  out.inSub = g.inSub;
  const s0 = g.sub.pos.clone();
  g.input.simulate('KeyW', true); g.simulate(3); g.input.simulate('KeyW', false);
  out.subMoved = g.sub.pos.distanceTo(s0);
  out.o2InSub = g.state.o2 === g.o2Max;
  g.exitSub(true);
  out.exited = !g.inSub;
  return out;
});
check('power cell can be fabricated', prog.crafted && prog.hasCell);
check('installing the cell restores station power', prog.power);
check('station power brings the Kestrel online', prog.subOnline);
check('station logs + blueprint unlocked', prog.logs >= 6 && prog.hull2Blueprint, `${prog.logs} logs`);
check('next objectives unlock', prog.echoActive);
check('crafted upgrade applies (O2 tank)', prog.tankAfter > prog.tankBefore, `${prog.tankBefore} -> ${prog.tankAfter}`);
check('Kestrel can be boarded and piloted', prog.inSub && prog.subMoved > 5, `${prog.subMoved.toFixed(1)} m`);
check('oxygen is supplied inside the Kestrel', prog.o2InSub);
check('can exit the Kestrel', prog.exited);

// --- save / load round trip
const save = await page.evaluate(() => {
  const g = window.__ABYSSAL;
  g.lastHurt = 99;
  g.state.inventory.silica = 7;
  g.player.place(new g.player.pos.constructor(12, -25, 40), 1.0, 0);
  const ok = g.saveGame(true);
  g.state.inventory.silica = 0;
  g.player.place(new g.player.pos.constructor(-200, -30, 0), 0, 0);
  const loaded = g.loadGame();
  g.renderer.setAnimationLoop(null);
  return { ok, loaded, silica: g.count('silica'), pos: g.player.pos.toArray(), power: g.state.flags.power, mode: g.mode };
});
check('save writes to storage', save.ok);
check('load restores inventory, position and progress', save.loaded && save.silica === 7 && Math.abs(save.pos[0] - 12) < 0.5 && save.power, JSON.stringify(save.pos.map((v) => +v.toFixed(1))));

// --- death and restart
const death = await page.evaluate(() => {
  const g = window.__ABYSSAL;
  g.state.inventory.ferrite = 10;
  g.die('test');
  const dead = g.mode === 'dead';
  g.respawn();
  return { dead, mode: g.mode, health: g.state.health, inPool: g.player.inAirPocket || Math.hypot(g.player.pos.x, g.player.pos.z) < 4, ferrite: g.count('ferrite') };
});
check('death screen and respawn at station', death.dead && death.mode === 'play' && death.health === 100 && death.inPool);
check('death costs a share of carried materials', death.ferrite === 7, `${death.ferrite} ferrite`);

// --- ending sequence
const ending = await page.evaluate(() => {
  const g = window.__ABYSSAL;
  g.state.upgrades.hull = 2;
  g.state.inventory.resonanceKey = 1;
  ['shardA', 'shardB', 'shardC'].forEach((s) => g.state.picked.push(s));
  g.evaluate();
  const gate = g.world.structures.gateCenter;
  g.sub.place(gate.clone().add(new gate.constructor(0, 0, 40)), 0);
  g.enterSub();
  const it = g.world.structures.interactables.find((i) => i.type === 'gate');
  g.camera.position.copy(g.sub.pos);
  g.doInteract({ kind: 'struct', it });
  const started = !!g.cinematic;
  g.simulate(15);
  return { started, ending: g.state.flags.ending, mode: g.mode, beyond: g.state.objectives.beyond };
});
check('Resonance Key starts the Threshold sequence', ending.started);
check('story conclusion reached', ending.ending && ending.mode === 'ending' && ending.beyond === 'active', ending.mode);

// --- every synthesized sound effect runs without throwing
const audio = await page.evaluate(() => {
  const a = window.__ABYSSAL.audio;
  const fails = [];
  const calls = ['ui', 'uiOpen', 'uiClose', 'ping', 'scanComplete', 'pickup', 'craft', 'denied', 'damage', 'warn', 'creak', 'splash', 'heartbeat', 'discovery', 'powerOn', 'crystalRing', 'deepGroan', 'endingSwell'];
  for (const c of calls) { try { a[c](); } catch (e) { fails.push(`${c}: ${e.message}`); } }
  try { a.breathe(true); a.cantorCall(200, 0.3); a.creatureClick(10); a.stalkerScreech(30); a.shimmer(10); a.echo(100); a.playChord(50); a.playChord(300); a.voiceLog(true); a.voiceLog(false); } catch (e) { fails.push(e.message); }
  return { ready: a.ready, fails };
});
check('audio engine initialised and all effects play', audio.ready && audio.fails.length === 0, audio.fails.join(', '));

check('no runtime errors', errors.length === 0, errors.slice(0, 3).join(' | '));
console.log(results.join('\n'));
console.log(`\n${results.length - failures}/${results.length} checks passed`);
await browser.close();
process.exit(failures ? 1 : 0);
