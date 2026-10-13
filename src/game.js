// ABYSSAL: The Lost Ocean — game orchestration.

import * as THREE from 'three';
import { Terrain } from './world/terrain.js';
import { CollisionWorld } from './world/collision.js';
import { Environment } from './world/environment.js';
import { Flora } from './world/flora.js';
import { Structures } from './world/structures.js';
import { Resources } from './world/resources.js';
import { U, makeNoiseTexture } from './world/shading.js';
import { POIS, SITES, WORLD_HALF } from './world/layout.js';
import { Creatures } from './creatures/creatures.js';
import { Player } from './player/player.js';
import { Kestrel } from './player/kestrel.js';
import { ViewModel } from './player/viewmodel.js';
import { Input } from './core/input.js';
import { AudioEngine } from './core/audio.js';
import { Events } from './core/events.js';
import { Post } from './core/post.js';
import * as Store from './core/storage.js';
import { ITEMS, RECIPES, UPGRADES, INVENTORY_CAPACITY } from './data/items.js';
import { DATABANK, LOGS } from './data/lore.js';
import { evaluateObjectives, mainObjective, HINTS, LIFEFORMS } from './systems/story.js';
import { UI, formatTime } from './ui/ui.js';
import { clamp, smoothstep } from './core/noise.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);
const _v = new THREE.Vector3();
const _d = new THREE.Vector3();

const SPAWN = { pos: V(-1.6, -20.0, 0.4), yaw: -Math.PI / 2 };
const DOCK_YAW = 0; // nose north, out from under the north module
const STATION_LOGS = ['lindqvist1', 'varga1', 'mensah1', 'marchetti1', 'lindqvist2'];

const FLORA_SCAN = {
  seagrass: { id: 'seagrass', y: 0.4, r: 0.8 },
  kelp: { id: 'kelp', y: 3.5, r: 1.8 },
  branchCoral: { id: 'branchCoral', y: 1.2, r: 1.5 },
  fanCoral: { id: 'fanCoral', y: 1.0, r: 1.2 },
  brainCoral: { id: 'brainCoral', y: 0.4, r: 1.1 },
  tubeSponge: { id: 'tubeSponge', y: 0.8, r: 1.0 },
  anemone: { id: 'anemone', y: 0.3, r: 0.7 },
  lanternPlant: { id: 'lanternPlant', y: 1.2, r: 0.9 },
  crystal: { id: 'crystal', y: 1.0, r: 1.4 },
  tubeWorm: { id: 'tubeWorm', y: 0.6, r: 0.9 },
};

class ExploredGrid {
  constructor(size = 60) { this.size = size; this.data = new Uint8Array(size * size); }
  cell(x) { return Math.floor(((x + WORLD_HALF) / (WORLD_HALF * 2)) * this.size); }
  reveal(x, z, radiusM) {
    const r = Math.ceil(radiusM / ((WORLD_HALF * 2) / this.size));
    const ci = this.cell(x), cj = this.cell(z);
    let changed = false;
    for (let j = cj - r; j <= cj + r; j++) {
      for (let i = ci - r; i <= ci + r; i++) {
        if (i < 0 || j < 0 || i >= this.size || j >= this.size) continue;
        if ((i - ci) ** 2 + (j - cj) ** 2 > r * r + 1) continue;
        if (!this.data[j * this.size + i]) { this.data[j * this.size + i] = 1; changed = true; }
      }
    }
    return changed;
  }
  get(i, j) { return this.data[j * this.size + i]; }
  serialize() { let s = ''; for (let i = 0; i < this.data.length; i += 4) s += ((this.data[i] | (this.data[i + 1] << 1) | (this.data[i + 2] << 2) | (this.data[i + 3] << 3))).toString(16); return s; }
  restore(s) {
    this.data.fill(0);
    if (!s) return;
    for (let k = 0; k < s.length; k++) { const v = parseInt(s[k], 16); for (let b = 0; b < 4; b++) this.data[k * 4 + b] = (v >> b) & 1; }
  }
}

function freshState() {
  return {
    time: 0,
    o2: 75,
    health: 100,
    battery: 100,
    lamp: false,
    inventory: {},
    storage: {},
    upgrades: { tank: 0, suit: 0, fins: 0, sonar: 0, battery: 0, hull: 0 },
    blueprints: [],
    databank: [],
    logs: ['intro'],
    seen: [],
    discovered: [],
    objectives: {},
    picked: [],
    hintsDone: [],
    flags: { power: false, cellCrafted: false, ending: false },
    stats: { maxDepth: 0, deaths: 0 },
  };
}

export class Game {
  constructor(canvas) {
    this.canvas = canvas;
    this.events = new Events();
    this.settings = Store.loadSettings();
    this.audio = new AudioEngine();
    this.input = new Input(canvas);
    this.ui = new UI(this);
    this.mode = 'loading';
    this.state = freshState();
    this.stats = { moved: 0, collected: 0, pdaOpened: 0, pings: 0, lampToggles: 0, boarded: 0 };
    this.inSub = false;
    this.lastSaveTime = 0;
    this.clock = new THREE.Timer();
    this.sonarCooldown = 0;
    this.sonarMarks = [];
    this.lastHurt = 99;
    this.hurtFlash = 0;
    this.warnTimer = 0;
    this.breathTimer = 3;
    this.discoverTimer = 0;
    this.hintTimer = 0;
    this.currentHint = null;
    this.scan = { target: null, progress: 0, active: false };
    this.explored = new ExploredGrid(60);
    this.cinematic = null;
    this.menuT = 0;
    this.song = 0;
    this.everLocked = false;
    window.__ABYSSAL = this;
  }

  // ---------------------------------------------------------------- setup
  async init() {
    const r = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: false, powerPreference: 'high-performance' });
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.toneMappingExposure = 0.95;
    r.outputColorSpace = THREE.SRGBColorSpace;
    r.setClearColor(0x02101a);
    this.renderer = r;
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x041a26);
    this.camera = new THREE.PerspectiveCamera(this.settings.fov, window.innerWidth / window.innerHeight, 0.05, 1600);
    this.scene.add(this.camera);
    // headlamp
    this.lamp = new THREE.SpotLight(0xe8f6ff, 0, 48, 0.52, 0.7, 1.0);
    this.lamp.position.set(0.15, 0.05, 0);
    this.lamp.target.position.set(0, -0.6, -10);
    this.camera.add(this.lamp);
    this.camera.add(this.lamp.target);

    U.uNoiseTex.value = makeNoiseTexture(256);
    this.ui.setLoading(0.02, 'Sounding the seafloor…');
    const terrain = new Terrain();
    await terrain.generate((f) => this.ui.setLoading(0.05 + f * 0.55, 'Sounding the seafloor…'));
    terrain.build();
    this.scene.add(terrain.group);
    const collision = new CollisionWorld(terrain);
    this.ui.setLoading(0.62, 'Growing reefs and kelp…');
    await frame();
    this.env = new Environment(this.scene, this.settings.quality);
    const structures = new Structures(this.scene, terrain, collision);
    structures.build();
    const flora = new Flora(this.scene, terrain, collision, this.settings.quality);
    flora.build();
    this.ui.setLoading(0.8, 'Waking the wildlife…');
    await frame();
    const resources = new Resources(this.scene, terrain);
    resources.build(structures.resourceSpots);
    const creatures = new Creatures(this.scene, terrain, structures.caveChamber, this.events);
    this.world = { terrain, collision, structures, flora, resources, creatures, latticePos: structures.scannables.find((s) => s.id === 'veyruLattice').pos };
    this.buildFloraIndex();

    this.player = new Player(this.camera, collision);
    this.sub = new Kestrel(this.scene, collision);
    this.viewmodel = new ViewModel();
    this.viewmodel.attachCockpit(this.sub.buildCockpit());
    this.post = new Post(r, this.scene, this.viewmodel.scene, this.camera);
    this.bindEvents();
    this.applySettings();
    this.onResize();
    window.addEventListener('resize', () => this.onResize());
    this.input.onLockChange = (locked) => this.onLockChange(locked);
    this.canvas.addEventListener('click', () => {
      if (this.mode === 'play' && !this.input.locked) { this.audio.init(); this.input.lock(); }
    });
    this.ui.setLoading(0.95, 'Compiling shaders…');
    this.resetWorldState();
    this.compileOnce();
    this.ui.setLoading(1, 'Ready');
    await frame();
    this.toMenu();
    this.renderer.setAnimationLoop(() => this.tick());
  }

  compileOnce() {
    // render once from a few vantage points so shader compilation happens now
    this.camera.position.set(0, -20, 30);
    this.camera.lookAt(0, -20, 0);
    this.renderer.compile(this.scene, this.camera);
    this.post.render(0.016);
  }

  buildFloraIndex() {
    this.floraIndex = new Map();
    for (const set of this.world.flora.sets) {
      const def = FLORA_SCAN[set.name];
      if (!def) continue;
      for (const p of set.points) {
        const k = `${Math.floor(p.x / 20)},${Math.floor(p.z / 20)}`;
        let arr = this.floraIndex.get(k);
        if (!arr) { arr = []; this.floraIndex.set(k, arr); }
        arr.push({ id: def.id, pos: p.clone().setY(p.y + def.y), radius: def.r });
      }
    }
  }

  bindEvents() {
    const ev = this.events;
    ev.on('attack', (e) => {
      if (this.mode !== 'play') return;
      if (e.sub && this.inSub) {
        this.sub.hull = Math.max(0, this.sub.hull - e.damage);
        this.ui.notify('Hull impact', e.kind === 'stalker' ? 'Hollow Stalker attack' : 'Collision', '', 'amber');
        this.audio.damage();
        this.audio.creak();
        this.shake = 0.6;
      } else {
        this.damage(e.damage, e.kind === 'stalker' ? 'Killed by a Hollow Stalker.' : 'Mauled by a Razormaw.');
      }
      if (e.kind === 'stalker') this.audio.stalkerScreech(5);
    });
    ev.on('threat', (e) => {
      const d = e.pos.distanceTo(this.camera.position);
      if (e.kind === 'stalker') this.audio.stalkerScreech(d);
      else this.audio.creatureClick(d);
      if (!this.state.seen.includes(`threat:${e.kind}`)) {
        this.state.seen.push(`threat:${e.kind}`);
        this.ui.subtitle(e.kind === 'stalker'
          ? '<b>Suit:</b> Large predator approaching. Sonar pulses may startle it.'
          : '<b>Suit:</b> Territorial predator. Keep moving or leave its hunting ground.', 6);
      }
    });
    ev.on('stalkerScared', (e) => this.audio.stalkerScreech(e.pos.distanceTo(this.camera.position) + 30));
    ev.on('cantorCall', (e) => {
      _v.subVectors(e.pos, this.camera.position);
      const right = _d.set(1, 0, 0).applyQuaternion(this.camera.quaternion);
      const pan = clamp(_v.normalize().dot(right), -1, 1) * 0.8;
      this.audio.cantorCall(e.dist, pan);
    });
    ev.on('splash', (e) => { if (this.mode === 'play') this.audio.splash(); if (e.up && !this.player.inAirPocket) this.env.bubbles.spawn(this.player.pos.clone().setY(this.player.pos.y - 0.3), 10, 0.5, 0.09); });
  }

  onResize() {
    const w = window.innerWidth, h = window.innerHeight;
    const q = this.settings.quality;
    const pr = q === 'low' ? Math.min(window.devicePixelRatio, 0.75) : q === 'medium' ? Math.min(window.devicePixelRatio, 1) : Math.min(window.devicePixelRatio, 1.5);
    this.renderer.setPixelRatio(pr);
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.post.setSize(w, h, pr);
    this.env.setPixelRatio(pr, h);
  }

  applySettings() {
    const s = this.settings;
    Store.saveSettings(s);
    this.audio.setVolumes({ master: s.master, music: s.music, sfx: s.sfx, ambience: s.ambience });
    if (this.camera) {
      this.camera.fov = s.fov;
      this.camera.updateProjectionMatrix();
    }
    if (this.post) { this.post.setQuality(s.quality); this.onResize(); }
    if (!s.hints) this.ui.showHint(null);
  }

  // ---------------------------------------------------------------- derived stats
  get o2Max() { return UPGRADES.tank.levels[this.state.upgrades.tank]; }
  get suitRating() { return UPGRADES.suit.levels[this.state.upgrades.suit]; }
  get hullRating() { return UPGRADES.hull.levels[this.state.upgrades.hull]; }
  get batteryMax() { return UPGRADES.battery.levels[this.state.upgrades.battery]; }
  get swimMult() { return UPGRADES.fins.levels[this.state.upgrades.fins]; }
  get sonarRange() { return UPGRADES.sonar.levels[this.state.upgrades.sonar]; }

  count(type) { return this.state.inventory[type] || 0; }
  hasItem(type) { return this.count(type) > 0; }
  isDone(id) { return this.state.objectives[id] === 'done'; }
  lifeformCount() { return this.state.databank.filter((d) => LIFEFORMS.includes(d)).length; }
  inventoryUsed() { return Object.entries(this.state.inventory).reduce((a, [k, n]) => a + (ITEMS[k]?.story ? 0 : n), 0); }
  hasSave() { return Store.hasSave(); }

  // ---------------------------------------------------------------- flow
  toMenu() {
    if (this.renderer) this.hideClickHint();
    this.mode = 'menu';
    this.ui.only('menu');
    this.ui.updateMenu(Store.hasSave());
    this.ui.hide('hud');
    this.ui.closePDA();
    this.input.unlock();
  }

  resetWorldState() {
    this.state = freshState();
    this.stats = { moved: 0, collected: 0, pdaOpened: 0, pings: 0, lampToggles: 0, boarded: 0 };
    this.explored = new ExploredGrid(60);
    this.inSub = false;
    this.world.resources.restore([]);
    for (const it of this.world.structures.interactables) { it.active = true; if (it.mesh) it.mesh.visible = true; }
    this.world.structures.setPower(false);
    this.sub.place(this.world.structures.dockPoint, DOCK_YAW);
    this.sub.power = 0;
    this.sub.hull = 100;
    this.sub.setOnline(false);
    this.sub.setLights(false);
    this.player.place(SPAWN.pos, SPAWN.yaw);
    this.env.dayTime = 0.3;
    this.world.creatures.cantors.list.forEach((c) => { c.gather = null; });
    this.world.structures.gateFieldMat.uniforms.uOpen.value = 0;
    this.currentHint = null;
    this.ui.showHint(null);
    this.sonarMarks = [];
  }

  async newGame() {
    this.audio.init();
    Store.deleteSave();
    this.resetWorldState();
    this.mode = 'intro';
    this.ui.only(null);
    this.ui.hide('menu');
    await this.ui.intro([
      { text: 'SURVEY DIRECTORATE // RECOVERY ORDER 7-KAPPA', dim: true, pause: 500 },
      { text: 'Ocean world Maren. Surface coverage: 100% water. Mean depth: unknown.' },
      { text: 'Deepreach Expedition. Five crew. Meridian Station.' },
      { text: 'Last transmission received 214 days ago.', pause: 900 },
      { text: 'You are the recovery diver.', pause: 1100 },
      { text: 'Splashdown confirmed. Meridian moonpool located. Station on emergency power.', dim: true, pause: 900 },
    ]);
    this.startPlay(true);
  }

  continueGame() {
    this.audio.init();
    if (!this.loadGame()) { this.ui.notify('Save', 'No valid save found.', '', 'amber'); return; }
  }

  startPlay(fresh) {
    this.mode = 'play';
    this.ui.only(null);
    this.ui.show('hud');
    this.evaluate(true);
    if (fresh) {
      this.ui.discovery('Ocean world Maren', 'Meridian Station', 'Moonpool · 20 m');
      this.ui.subtitle('<b>Suit:</b> Life support nominal. Station main power: offline. Crew: not detected.', 7);
      this.state.discovered.push('station');
      this.explored.reveal(0, 0, 80);
    }
    this.input.lock();
  }

  resume() {
    if (this.mode !== 'pause') return;
    this.mode = 'play';
    this.ui.only(null);
    this.ui.show('hud');
    this.audio.suspend(false);
    this.input.lock();
  }

  pause() {
    if (this.mode !== 'play') return;
    this.hideClickHint();
    this.mode = 'pause';
    this.scan.active = false;
    this.ui.only('pause');
    this.ui.updatePauseFoot();
    this.audio.suspend(true);
    this.input.unlock();
  }

  onLockChange(locked) {
    if (locked) { this.everLocked = true; document.getElementById('clickToPlay').classList.add('hidden'); return; }
    // ignore the stale unlock event that can follow a quick unlock/relock
    if (performance.now() - this.input.lockRequestedAt < 600) return;
    if (this.mode === 'play' && !this.ui.pdaOpen && this.everLocked) this.pause();
  }

  hideClickHint() {
    this.showingClick = false;
    document.getElementById('clickToPlay').classList.add('hidden');
  }

  quitToTitle() {
    this.ui.hide('pause');
    this.ui.hide('ending');
    this.resetWorldState();
    this.toMenu();
  }

  // ---------------------------------------------------------------- PDA
  openPDA(tab = null, mode = null) {
    if (this.mode !== 'play') return;
    this.hideClickHint();
    const m = mode || (this.inSub ? 'sub' : 'field');
    this.mode = 'pda';
    this.scan.active = false;
    this.stats.pdaOpened++;
    this.ui.openPDA(tab, m);
    this.audio.uiOpen();
    this.input.unlock();
  }

  closePDA() {
    if (this.mode !== 'pda') return;
    this.ui.closePDA();
    this.mode = 'play';
    this.audio.uiClose();
    this.input.lock();
    this.evaluate();
  }

  // ---------------------------------------------------------------- inventory & crafting
  addItem(type, n = 1, force = false) {
    const it = ITEMS[type];
    if (!it.story && !force && this.inventoryUsed() + n > INVENTORY_CAPACITY) return false;
    this.state.inventory[type] = (this.state.inventory[type] || 0) + n;
    return true;
  }

  removeItem(type, n = 1) {
    this.state.inventory[type] = Math.max(0, (this.state.inventory[type] || 0) - n);
    if (!this.state.inventory[type]) delete this.state.inventory[type];
  }

  available(type, mode) {
    return this.count(type) + (mode === 'station' ? (this.state.storage[type] || 0) : 0);
  }

  canCraft(r, mode) {
    const s = this.state;
    if (r.where === 'station' && mode !== 'station') return { ok: false, reason: 'where', text: 'Requires Meridian Station' };
    if (!s.flags.power && mode === 'station' && !r.emergency) return { ok: false, reason: 'power', text: 'Requires main power' };
    if (r.gives.upgrade && s.upgrades[r.gives.upgrade] >= r.gives.level) return { ok: false, reason: 'installed', text: 'Installed' };
    if (r.requires) for (const [k, lvl] of Object.entries(r.requires)) if (s.upgrades[k] < lvl) return { ok: false, reason: 'requires', text: `Requires ${UPGRADES[k].name} Mk ${lvl + 1}` };
    if (r.gives.item === 'powerCell' && (s.flags.power || this.hasItem('powerCell'))) return { ok: false, reason: 'installed', text: s.flags.power ? 'Installed' : 'Already carried' };
    if (r.gives.item === 'resonanceKey' && (this.hasItem('resonanceKey') || s.flags.ending)) return { ok: false, reason: 'installed', text: 'Already fabricated' };
    for (const [k, n] of Object.entries(r.cost)) if (this.available(k, mode) < n) return { ok: false, reason: 'materials', text: 'Missing materials' };
    return { ok: true };
  }

  craft(id, mode) {
    const r = RECIPES.find((x) => x.id === id);
    if (!r) return false;
    const check = this.canCraft(r, mode);
    if (!check.ok) { this.audio.denied(); return false; }
    for (const [k, n] of Object.entries(r.cost)) {
      const fromInv = Math.min(n, this.count(k));
      this.removeItem(k, fromInv);
      const rest = n - fromInv;
      if (rest > 0) this.state.storage[k] -= rest;
    }
    if (r.gives.item) {
      this.addItem(r.gives.item, 1, true);
      if (r.gives.item === 'powerCell') this.state.flags.cellCrafted = true;
    }
    if (r.gives.upgrade) {
      this.state.upgrades[r.gives.upgrade] = r.gives.level;
      if (r.gives.upgrade === 'tank') this.state.o2 = this.o2Max;
      if (r.gives.upgrade === 'battery') this.state.battery = this.batteryMax;
      if (r.gives.upgrade === 'hull') this.sub.hull = 100;
    }
    this.audio.craft();
    this.ui.notify('Fabricated', r.name, r.desc, 'violet');
    this.evaluate();
    if (mode === 'station') this.saveGame(false);
    return true;
  }

  store(type) {
    const n = this.count(type);
    if (!n || ITEMS[type].story) return;
    this.state.storage[type] = (this.state.storage[type] || 0) + n;
    this.removeItem(type, n);
  }

  storeAll() {
    for (const k of Object.keys(this.state.inventory)) if (!ITEMS[k].story && !ITEMS[k].consumable) this.store(k);
    this.audio.pickup();
  }

  take(type) {
    const n = this.state.storage[type] || 0;
    const space = INVENTORY_CAPACITY - this.inventoryUsed();
    const t = Math.min(n, space);
    if (t <= 0) { this.audio.denied(); this.ui.notify('Inventory', 'Inventory full', '', 'amber'); return; }
    this.state.storage[type] -= t;
    this.addItem(type, t);
  }

  useMedkit() {
    if (!this.hasItem('medkit') || this.state.health >= 100) { this.audio.denied(); return; }
    this.removeItem('medkit');
    this.state.health = Math.min(100, this.state.health + 50);
    this.audio.craft();
    this.ui.notify('Medkit', 'Vitals restored', '+50');
  }

  recallSub() {
    if (!this.state.flags.power) return;
    if (this.inSub) return;
    this.sub.place(this.world.structures.dockPoint, DOCK_YAW);
    this.sub.vel.set(0, 0, 0);
    this.ui.notify('Kestrel', 'Autopilot recall complete', 'Docked beneath Meridian Station');
  }

  // ---------------------------------------------------------------- damage & death
  damage(amount, cause) {
    if (this.mode !== 'play' || this.cinematic) return;
    this.state.health -= amount;
    this.lastHurt = 0;
    this.hurtFlash = 1;
    this.deathCause = cause;
    this.audio.damage();
    this.ui.flash();
    if (this.state.health <= 0) this.die(cause);
  }

  die(cause) {
    this.hideClickHint();
    this.state.health = 0;
    this.mode = 'dead';
    this.state.stats.deaths++;
    this.input.unlock();
    this.scan.active = false;
    // lose a portion of carried materials
    const lost = [];
    for (const [k, n] of Object.entries(this.state.inventory)) {
      if (ITEMS[k].story) continue;
      const l = Math.floor(n * 0.3);
      if (l > 0) { this.removeItem(k, l); lost.push(`${l} ${ITEMS[k].name}`); }
    }
    this.ui.showDeath(`${cause || 'Vital signs lost.'} Meridian's emergency tether recovered your suit.${lost.length ? ` Lost in the dark: ${lost.join(', ')}.` : ''}`);
  }

  respawn() {
    this.ui.hide('death');
    if (this.inSub) this.exitSub(true);
    this.inSub = false;
    this.player.place(SPAWN.pos, SPAWN.yaw);
    this.state.health = 100;
    this.state.o2 = this.o2Max;
    this.state.battery = Math.max(this.state.battery, this.batteryMax * 0.5);
    this.mode = 'play';
    this.ui.show('hud');
    this.input.lock();
    this.ui.subtitle('<b>Suit:</b> Emergency recovery complete. You are back in the moonpool.', 5);
  }

  // ---------------------------------------------------------------- sub
  enterSub() {
    if (!this.state.flags.power) { this.ui.notify('Kestrel', 'Offline', 'Restore station power to charge her cells.', 'amber'); this.audio.denied(); return; }
    this.inSub = true;
    this.stats.boarded++;
    this.sub.setLights(true);
    this.state.lamp = false;
    this.audio.splash();
    this.audio.tone({ freq: 220, dur: 0.6, gain: 0.08, glide: 2 });
    this.ui.notify('Kestrel', 'Pilot aboard', 'W/S thrust · A/D strafe · Space/C rise/dive · Shift boost · E exit');
  }

  exitSub(force = false) {
    const depth = Math.max(0, -this.sub.pos.y);
    if (!force && depth > this.suitRating && !this.confirmExitDeep) {
      this.confirmExitDeep = 3;
      this.ui.notify('Warning', `Depth ${Math.round(depth)} m exceeds your suit rating (${this.suitRating} m)`, 'Press E again to exit anyway.', 'amber');
      this.audio.warn();
      return;
    }
    this.confirmExitDeep = 0;
    this.inSub = false;
    // place the diver beside the hatch, clear of geometry
    const side = _v.set(Math.cos(this.sub.yaw), 0, -Math.sin(this.sub.yaw)).multiplyScalar(-3.4);
    const p = this.sub.pos.clone().add(side).add(V(0, 0.8, 0));
    this.world.collision.resolve(p, 0.5, null);
    this.player.place(p, this.sub.yaw, this.sub.pitch * 0.5);
    this.audio.splash();
  }

  // ---------------------------------------------------------------- save/load
  canSaveHere() {
    if (this.state.flags.ending && this.cinematic) return { ok: false, reason: 'unavailable' };
    if (this.lastHurt < 5) return { ok: false, reason: 'in danger' };
    if (this.state.o2 <= 0) return { ok: false, reason: 'no oxygen' };
    return { ok: true };
  }

  serialize() {
    const p = this.player, s = this.sub;
    return {
      state: this.state,
      player: { pos: p.pos.toArray(), yaw: p.yaw, pitch: p.pitch },
      sub: { pos: s.pos.toArray(), yaw: s.yaw, power: s.power, hull: s.hull, inSub: this.inSub },
      resources: this.world.resources.serialize(),
      explored: this.explored.serialize(),
      dayTime: this.env.dayTime,
      stats: this.stats,
    };
  }

  saveGame(manual) {
    if (manual) {
      const c = this.canSaveHere();
      if (!c.ok) { this.ui.notify('Save', `Cannot save: ${c.reason}`, '', 'amber'); this.audio.denied(); return false; }
    }
    const ok = Store.writeSave(this.serialize());
    if (ok) {
      this.lastSaveTime = Date.now();
      this.ui.notify('Expedition saved', manual ? 'Progress recorded' : 'Autosave');
    } else this.ui.notify('Save failed', 'Browser storage unavailable', '', 'amber');
    return ok;
  }

  loadGame() {
    const data = Store.readSave();
    if (!data) return false;
    this.resetWorldState();
    const st = freshState();
    this.state = { ...st, ...data.state, flags: { ...st.flags, ...data.state.flags }, upgrades: { ...st.upgrades, ...data.state.upgrades }, stats: { ...st.stats, ...data.state.stats } };
    this.stats = { ...this.stats, ...(data.stats || {}) };
    this.world.resources.restore(data.resources);
    this.explored.restore(data.explored);
    this.env.dayTime = data.dayTime ?? 0.3;
    for (const it of this.world.structures.interactables) {
      const key = it.item || it.logId;
      if (key && this.state.picked.includes(key)) { it.active = false; if (it.mesh) it.mesh.visible = false; }
    }
    this.world.structures.setPower(this.state.flags.power);
    this.sub.setOnline(this.state.flags.power);
    this.sub.place(V(...data.sub.pos), data.sub.yaw);
    this.sub.power = data.sub.power;
    this.sub.hull = data.sub.hull;
    this.player.place(V(...data.player.pos), data.player.yaw, data.player.pitch);
    if (this.state.flags.ending) {
      this.world.creatures.cantors.gatherAt(this.world.structures.gateCenter.clone().add(V(0, 200, 0)));
      this.world.structures.gateFieldMat.uniforms.uOpen.value = 0.35;
    }
    this.ui.hide('pause');
    this.ui.hide('menu');
    if (data.sub.inSub) { this.inSub = false; this.state.flags.power && this.enterSub(); }
    this.lastSaveTime = data.savedAt;
    this.startPlay(false);
    this.ui.notify('Expedition loaded', `Saved ${new Date(data.savedAt).toLocaleString()}`);
    return true;
  }

  // ---------------------------------------------------------------- progression
  evaluate(silent = false) {
    const changes = evaluateObjectives(this);
    if (silent) return;
    for (const c of changes) {
      if (c.type === 'done') this.ui.notify('Objective complete', c.o.title, '', '');
      else this.ui.notify('New objective', c.o.title, '', 'amber');
    }
    if (changes.some((c) => c.type === 'new' && c.o.id === 'key')) this.unlockBlueprint('key');
  }

  unlockBlueprint(id) {
    if (this.state.blueprints.includes(id)) return;
    this.state.blueprints.push(id);
    const r = RECIPES.find((x) => x.blueprint === id);
    this.ui.notify('Blueprint acquired', r ? r.name : id, 'Available at the fabricator', 'violet');
  }

  addLog(id, quiet = false) {
    if (this.state.logs.includes(id)) return;
    this.state.logs.push(id);
    const log = LOGS[id];
    if (!quiet) {
      this.ui.notify(log.kind === 'audio' ? 'Audio log recovered' : 'Record recovered', log.title, `${log.author} · Tab → Logs`, 'violet');
      this.audio.tone({ freq: 523, dur: 0.4, gain: 0.07, reverb: 0.6 });
      this.audio.tone({ freq: 784, dur: 0.6, gain: 0.06, reverb: 0.6, delay: 0.12 });
      // a short excerpt plays immediately; the full transcript lives in the PDA
      const first = log.text.split(/(?<=[.!?\u2014])\s/)[0];
      this.ui.subtitle(`<b>${log.author}:</b> ${first.length > 160 ? `${first.slice(0, 157)}\u2026` : first}`, 7);
    }
    if (log.unlock) this.unlockBlueprint(log.unlock);
    this.evaluate();
  }

  addDatabank(id) {
    if (this.state.databank.includes(id)) return false;
    this.state.databank.push(id);
    const e = DATABANK[id];
    this.ui.notify(`Databank · ${e.cat}`, e.name, e.rare ? 'Rare species documented' : 'New entry', e.rare ? 'violet' : '');
    this.audio.scanComplete();
    if (e.unlock) this.unlockBlueprint(e.unlock);
    if (id === 'cantor' || id === 'veilRay' || id === 'monolith') this.audio.discovery();
    this.evaluate();
    return true;
  }

  installPower() {
    this.removeItem('powerCell');
    this.state.flags.power = true;
    this.world.structures.setPower(true);
    this.sub.power = 100;
    this.sub.setOnline(true);
    this.audio.powerOn();
    this.ui.discovery('Meridian Station', 'Main power restored', 'Logs recovered · Kestrel online');
    for (const id of STATION_LOGS) this.addLog(id, true);
    this.ui.notify('Station archive', `${STATION_LOGS.length} crew logs recovered`, 'Tab → Logs', 'violet');
    this.ui.subtitle('<b>Meridian:</b> Main bus online. Life support nominal. Beacon transmitting. Kestrel charging in dock.', 7);
    this.evaluate();
    this.saveGame(false);
  }

  // ---------------------------------------------------------------- ending
  startEnding() {
    if (this.cinematic) return;
    this.removeItem('resonanceKey');
    this.cinematic = { t: 0, stage: 0 };
    this.scan.active = false;
    const gate = this.world.structures.gateCenter.clone();
    this.world.creatures.cantors.gatherAt(gate.clone().add(V(0, 200, 0)));
    this.audio.endingSwell();
    this.ui.subtitle('<b>Kestrel:</b> Resonance key engaged. Broadcasting through hull transducers…', 6);
  }

  updateCinematic(dt) {
    const c = this.cinematic;
    c.t += dt;
    const field = this.world.structures.gateFieldMat.uniforms.uOpen;
    field.value = Math.min(1, c.t / 10);
    const gate = this.world.structures.gateCenter;
    // drift toward the ring, look at it
    _v.subVectors(gate, this.sub.pos);
    const targetYaw = Math.atan2(-_v.x, -_v.z);
    let dy = targetYaw - this.sub.yaw;
    dy = Math.atan2(Math.sin(dy), Math.cos(dy));
    this.sub.yaw += dy * dt * 0.8;
    const hd = Math.hypot(_v.x, _v.z);
    const targetPitch = Math.atan2(_v.y, hd);
    this.sub.pitch += (targetPitch - this.sub.pitch) * dt * 0.8;
    this.sub.vel.multiplyScalar(0.95);
    if (_v.length() > 40) this.sub.vel.addScaledVector(_v.normalize(), dt * 1.5);
    this.sub.integrate(dt);
    if (c.stage === 0 && c.t > 2) { c.stage = 1; this.env.ping(gate, 600); this.audio.ping(); }
    if (c.stage === 1 && c.t > 5) { c.stage = 2; this.ui.subtitle('<b>Dr. Varga (recording):</b> …tell her it’s beautiful.', 5); this.env.ping(gate, 900); }
    if (c.stage === 2 && c.t > 9) { c.stage = 3; this.env.ping(gate, 1200); }
    this.post.lens.uniforms.uWhite.value = smoothstep(9, 13, c.t);
    if (c.t > 13.5 && c.stage === 3) {
      c.stage = 4;
      this.finishEnding();
    }
  }

  async finishEnding() {
    this.state.flags.ending = true;
    this.evaluate(true);
    this.addLog('varga3', true);
    this.saveGame(false);
    this.mode = 'ending';
    this.hideClickHint();
    this.input.unlock();
    this.ui.hide('hud');
    const s = this.state;
    await this.ui.ending([
      'The chord resolves.',
      'For the first time in eleven thousand years, the Low Song falls silent.',
      'Above you, the Cantors turn as one — and rise toward the light.',
      'Meridian Station’s beacon reaches orbit: Deepreach Expedition, fate determined.',
      'Then, faint and impossibly far to the north, something answers.',
    ], [
      ['Time on Maren', formatTime(s.time)],
      ['Deepest dive', `${Math.round(s.stats.maxDepth)} m`],
      ['Databank', `${s.databank.length}/${Object.keys(DATABANK).length}`],
      ['Logs', `${s.logs.length}/${Object.keys(LOGS).length}`],
    ]);
    this.post.lens.uniforms.uWhite.value = 0;
  }

  keepExploring() {
    this.cinematic = null;
    this.post.lens.uniforms.uWhite.value = 0;
    this.world.structures.gateFieldMat.uniforms.uOpen.value = 0.35;
    this.ui.hide('ending');
    this.mode = 'play';
    this.ui.show('hud');
    this.evaluate();
    this.ui.discovery('Chapter II', 'The Other Half', 'A signal answers from beyond the survey line');
    this.input.lock();
  }

  // ---------------------------------------------------------------- interaction & scanning
  findInteraction() {
    const cam = this.camera;
    const origin = cam.position;
    const dir = cam.getWorldDirection(_d).clone();
    let best = null;
    let bestScore = Infinity;
    const consider = (score, obj) => { if (score < bestScore) { bestScore = score; best = obj; } };
    // structure interactables
    for (const it of this.world.structures.interactables) {
      if (!it.active) continue;
      const manip = this.inSub && (it.type === 'item' || it.type === 'log');
      if (this.inSub && !it.fromSub && !manip) continue;
      const dist = it.pos.distanceTo(origin);
      if (dist > (manip && !it.fromSub ? Math.max(7, it.radius) : it.radius)) continue;
      _v.subVectors(it.pos, origin).normalize();
      const dot = _v.dot(dir);
      if (dot < (it.radius > 10 ? 0.3 : 0.74)) continue;
      consider(dist * (2 - dot), { kind: 'struct', it });
    }
    // resources
    const reach = this.inSub ? 7 : 3.6;
    for (const n of this.world.resources.nodes) {
      if (n.collected) continue;
      const dx = n.pos.x - origin.x, dz = n.pos.z - origin.z;
      if (Math.abs(dx) > reach + 2 || Math.abs(dz) > reach + 2) continue;
      const c = _v.copy(n.pos).setY(n.pos.y + 0.3);
      const t = c.clone().sub(origin).dot(dir);
      if (t < 0 || t > reach) continue;
      const d2 = c.distanceToSquared(origin) - t * t;
      const rr = (n.radius || 0.6) * 1.6;
      if (d2 > rr * rr) continue;
      consider(t, { kind: 'resource', node: n });
    }
    // the Kestrel
    if (!this.inSub) {
      const t = _v.copy(this.sub.pos).sub(origin).dot(dir);
      if (t > 0 && t < 7) {
        const d2 = this.sub.pos.distanceToSquared(origin) - t * t;
        if (d2 < 3.2 * 3.2) consider(t, { kind: 'sub' });
      }
    }
    return best;
  }

  interactionPrompt(target) {
    if (this.inSub && !target) return { text: 'Exit the Kestrel', key: 'E' };
    if (!target) return null;
    if (target.kind === 'resource') {
      const full = this.inventoryUsed() >= INVENTORY_CAPACITY;
      return { text: full ? `Inventory full — ${ITEMS[target.node.type].name}` : `Collect ${ITEMS[target.node.type].name}`, key: 'E' };
    }
    if (target.kind === 'sub') return { text: this.state.flags.power ? 'Board the Kestrel' : 'Kestrel — offline (no station power)', key: 'E' };
    const it = target.it;
    switch (it.type) {
      case 'stationTerminal': return { text: this.state.flags.power ? 'Use Meridian terminal' : 'Use terminal (emergency power)', key: 'E' };
      case 'powerCore': return { text: this.state.flags.power ? 'Power core — online' : (this.hasItem('powerCell') ? 'Install Power Cell' : 'Power core — needs a Station Power Cell'), key: 'E' };
      case 'log': return { text: `Recover ${LOGS[it.logId].kind === 'audio' ? 'recorder' : 'datapad'}${this.inSub ? ' (manipulator)' : ''}`, key: 'E' };
      case 'item': return { text: `Take ${ITEMS[it.item].name}`, key: 'E' };
      case 'gate': return { text: this.hasItem('resonanceKey') ? (this.inSub ? 'Sing the Resonance Key' : 'Return to the Kestrel to sing the key') : 'The Threshold is silent — a Resonance Key is required', key: 'E' };
      default: return null;
    }
  }

  doInteract(target) {
    if (this.inSub && !target) { this.exitSub(); return; }
    if (!target) return;
    if (target.kind === 'resource') {
      const n = target.node;
      if (!this.addItem(n.type, 1)) { this.audio.denied(); this.ui.notify('Inventory full', 'Store materials at Meridian Station', '', 'amber'); return; }
      this.world.resources.collect(n, this.state.time);
      this.stats.collected++;
      this.audio.pickup();
      this.viewmodel.pickup();
      this.env.bubbles.spawn(n.pos.clone().setY(n.pos.y + 0.4), 6, 0.4, 0.06);
      this.ui.notify('Collected', `${ITEMS[n.type].name}`, `${this.count(n.type)} carried`);
      this.evaluate();
      return;
    }
    if (target.kind === 'sub') { this.enterSub(); return; }
    const it = target.it;
    switch (it.type) {
      case 'stationTerminal': this.openPDA(null, 'station'); break;
      case 'powerCore':
        if (this.state.flags.power) { this.ui.notify('Power core', 'Main bus stable', '108% nominal'); break; }
        if (this.hasItem('powerCell')) this.installPower();
        else { this.audio.denied(); this.ui.notify('Power core', 'Requires a Station Power Cell', 'Fabricate one at the station terminal', 'amber'); }
        break;
      case 'log':
        it.active = false;
        if (it.mesh) it.mesh.visible = false;
        this.state.picked.push(it.logId);
        this.addLog(it.logId);
        this.viewmodel.pickup();
        break;
      case 'item':
        it.active = false;
        if (it.mesh) it.mesh.visible = false;
        this.state.picked.push(it.item);
        this.addItem(it.item, 1, true);
        this.audio.discovery();
        this.ui.notify('Recovered', ITEMS[it.item].name, ITEMS[it.item].desc, 'violet');
        this.viewmodel.pickup();
        this.evaluate();
        break;
      case 'gate':
        if (this.hasItem('resonanceKey') && this.inSub) this.startEnding();
        else this.audio.denied();
        break;
      default: break;
    }
  }

  findScanTarget() {
    const origin = this.camera.position;
    const dir = this.camera.getWorldDirection(_d).clone();
    const range = this.inSub ? 45 : 22;
    let best = null, bt = range;
    const test = (c) => {
      const cy = c.offsetY ? _v.copy(c.pos).setY(c.pos.y + c.offsetY) : _v.copy(c.pos);
      if (cy.distanceToSquared(origin) < c.radius * c.radius) return; // inside it (e.g. a building)
      const t = cy.clone().sub(origin).dot(dir);
      if (t < 0 || t > bt + c.radius) return;
      const d2 = cy.distanceToSquared(origin) - t * t;
      if (d2 > c.radius * c.radius) return;
      bt = t;
      best = { id: c.id, pos: cy.clone(), radius: c.radius };
    };
    for (const c of this.world.structures.scannables) test(c);
    for (const c of this.world.creatures.scanTargets(origin)) test(c);
    const ci = Math.floor(origin.x / 20), cj = Math.floor(origin.z / 20);
    const cr = this.inSub ? 3 : 2;
    for (let j = cj - cr; j <= cj + cr; j++) {
      for (let i = ci - cr; i <= ci + cr; i++) {
        const arr = this.floraIndex.get(`${i},${j}`);
        if (arr) for (const c of arr) test(c);
      }
    }
    if (best) {
      const tHit = this.world.terrain.raycast(origin, dir, bt, 1.0);
      if (tHit >= 0 && tHit < bt - best.radius) return null;
    }
    return best;
  }

  sonarPing() {
    if (this.sonarCooldown > 0) return;
    const range = this.sonarRange * (this.inSub ? 1.25 : 1);
    if (this.inSub) {
      if (this.sub.power < 1) { this.audio.denied(); return; }
      this.sub.power -= 0.6;
    } else {
      if (this.state.battery < 3) { this.audio.denied(); this.ui.notify('Suit cell', 'Battery depleted', '', 'amber'); return; }
      this.state.battery -= 3;
    }
    this.sonarCooldown = 2.2;
    this.stats.pings++;
    const origin = this.camera.position.clone();
    this.env.ping(origin, range);
    this.audio.ping();
    this.sonarScare = { origin };
    if (this.explored.reveal(origin.x, origin.z, range * 0.75) && this.ui.pdaOpen) this.ui.drawMap();
    // mark deposits and unknown signals
    const resRange = this.state.upgrades.sonar ? range * 0.6 : 70;
    this.sonarMarks = [];
    for (const n of this.world.resources.nodes) {
      if (n.collected) continue;
      const d = n.pos.distanceTo(origin);
      if (d < resRange) this.sonarMarks.push({ pos: n.pos.clone().setY(n.pos.y + 0.5), label: `${ITEMS[n.type].name} ${Math.round(d)}m`, cls: 'res', t: 12, delay: d / this.env.sonar.speed });
    }
    for (const p of POIS) {
      if (this.state.discovered.includes(p.id)) continue;
      const pos = V(p.x, p.y ?? this.world.terrain.heightAt(p.x, p.z) + 4, p.z);
      const d = pos.distanceTo(origin);
      if (d < range * 1.6 && (!p.minDepth || this.player.depth > 150 || this.inSub)) {
        this.sonarMarks.push({ pos, label: `Unknown contact ${Math.round(d)}m`, cls: '', t: 14, delay: d / this.env.sonar.speed });
      }
    }
    const mono = this.world.structures.monolithPos;
    const dm = mono.distanceTo(origin);
    if (dm < range) {
      this.audio.echo(dm * 2 + 60);
      if (!this.state.seen.includes('monolithEcho')) {
        this.state.seen.push('monolithEcho');
        setTimeout(() => this.ui.subtitle('<b>Suit:</b> Delayed return from bearing of the monolith. It… answered the ping.', 6), 1800);
      }
    }
  }

  // ---------------------------------------------------------------- main loop
  tick() {
    this.clock.update();
    let dt = Math.min(0.05, this.clock.getDelta());
    if (this.timeScaleOverride) dt = this.timeScaleOverride;
    try {
      switch (this.mode) {
        case 'menu': this.updateMenuScene(dt); break;
        case 'play': this.updatePlay(dt); break;
        case 'pda': case 'pause': case 'dead': case 'ending': case 'intro': this.updateIdle(dt); break;
        default: break;
      }
      this.render(dt);
    } catch (err) {
      console.error(err);
      this.lastError = err;
    }
    this.input.endFrame();
  }

  updateMenuScene(dt) {
    this.menuT += dt;
    const t = this.menuT * 0.03;
    const cam = this.camera;
    cam.position.set(Math.cos(t) * 46 - 10, -17 + Math.sin(t * 2) * 3, Math.sin(t) * 46 + 6);
    cam.lookAt(0, -18, 0);
    this.updateWorld(dt, cam.position, { menu: true });
    this.viewmodel.update(dt, cam, { mouse: [0, 0], speed: 0, bob: 0, visible: false, time: this.menuT, ambient: 1 });
  }

  updateIdle(dt) {
    if (this.mode === 'ending' && this.cinematic && this.cinematic.stage < 4) this.updateCinematic(dt);
    // keep ambient life moving slowly behind menus
    this.updateWorld(dt * (this.mode === 'pause' ? 0 : 0.25), this.camera.position, {});
    this.viewmodel.update(dt, this.camera, {
      mouse: [0, 0], speed: 0, bob: this.player.bob, visible: !this.inSub && this.mode === 'pda', cockpit: this.inSub && this.mode !== 'ending', pdaOpen: this.mode === 'pda',
      lampOn: this.state.lamp, ambient: this.vmAmbient || 1, time: performance.now() * 0.001,
    });
    if (this.mode === 'pause' && this.input.hit('pause') && document.getElementById('settings').classList.contains('hidden')) { this.resume(); return; }
    if (this.mode === 'pda' && this.input.hit('pda')) this.closePDA();
    else if (this.mode === 'pda' && this.input.hit('pause')) this.closePDA();
    else if (this.mode === 'pda' && this.input.hit('map') && this.ui.pdaTab === 'map') this.closePDA();
    if (this.mode === 'pda' && this.ui.pdaTab === 'map' && (this.mapRedraw = (this.mapRedraw || 0) + dt) > 0.5) { this.mapRedraw = 0; this.ui.drawMap(); }
    this.audio.update(dt, { ...this.audioState(), paused: this.mode !== 'play' });
  }

  audioState() {
    const depth = Math.max(0, -this.camera.position.y);
    return {
      depth,
      underwater: !this.player.aboveSurface,
      inAir: this.player.inAirPocket && !this.inSub,
      aboveSurface: this.player.aboveSurface && !this.inSub,
      inSub: this.inSub,
      subThrust: this.sub.thrust,
      speed: this.inSub ? 0 : this.player.speed,
      song: this.song,
      scanning: this.scan.active,
      scanProgress: this.scan.progress,
    };
  }

  updateWorld(dt, camPos, opts) {
    const p = camPos;
    this.env.update(dt, this.camera, {
      inAirPocket: !this.inSub && this.player.inAirPocket && this.mode !== 'menu',
      aboveSurface: !this.inSub && this.player.aboveSurface && this.mode !== 'menu',
      lampOn: this.inSub ? this.sub.lightsOn : this.state.lamp,
    });
    this.world.flora.update(p, this.settings.quality === 'low' ? 0.6 : this.settings.quality === 'medium' ? 0.8 : 1);
    this.world.terrain.cull(p, this.player.aboveSurface && !this.inSub ? 120 : 340);
    const scare = this.sonarScare;
    this.sonarScare = null;
    this.world.creatures.update(dt, {
      playerPos: this.inSub ? this.sub.pos : p,
      playerDepth: Math.max(0, -p.y),
      playerFast: !this.inSub && this.player.speed > 6.5,
      inSub: this.inSub,
      lampOn: this.inSub ? this.sub.lightsOn : this.state.lamp,
      isNight: this.env.isNight,
      sonarScare: !!scare,
      sonarOrigin: scare ? scare.origin : V(0, 1e6, 0),
    });
    // Low Song intensity
    const da = Math.hypot(p.x - SITES.abyss.x, p.z - SITES.abyss.z);
    const dr = Math.hypot(p.x - SITES.ruins.x, p.z - SITES.ruins.z);
    const dm = this.world.structures.monolithPos.distanceTo(p);
    let song = Math.max(Math.exp(-Math.max(0, da - 150) / 260), Math.exp(-dr / 180) * 0.75, Math.exp(-dm / 60) * 0.45);
    song *= 0.6 + 0.4 * Math.sin(U.uTime.value * 0.11) ** 2;
    if (this.state.flags.ending && !this.cinematic) song *= 0.15;
    this.song = song;
    this.world.structures.update(dt, U.uTime.value, song);
    this.world.resources.update(this.state.time);
    // the headlamp
    this.lamp.intensity = !this.inSub && this.state.lamp && this.mode !== 'menu' ? 5.5 : 0;
  }

  updatePlay(dt) {
    const s = this.state;
    const input = this.input;
    s.time += dt;
    this.lastHurt += dt;
    this.hurtFlash = Math.max(0, this.hurtFlash - dt * 1.5);
    this.sonarCooldown -= dt;
    if (this.confirmExitDeep) this.confirmExitDeep = Math.max(0, this.confirmExitDeep - dt);

    if (input.hit('pause')) { this.pause(); return; }
    if (input.hit('pda')) { this.openPDA(); return; }
    if (input.hit('map')) { this.openPDA('map'); return; }
    if (this.cinematic) { this.updateCinematic(dt); this.sub.cameraTransform(this.camera); this.viewmodel.update(dt, this.camera, { mouse: [0, 0], speed: 0, bob: 0, visible: false, cockpit: true, ambient: 0.2, time: s.time }); this.updateWorld(dt, this.camera.position, {}); this.audio.update(dt, this.audioState()); this.ui.updateHUD(dt, this.hudFrame(null, null)); return; }

    const mouse = input.consumeMouse();
    const prevPos = this.player.pos.clone();
    if (this.inSub) {
      const impact = this.sub.pilot(dt, input, this.settings, mouse);
      if (impact > 5) {
        this.sub.hull = Math.max(0, this.sub.hull - (impact - 5) * 3);
        this.audio.damage();
        this.shake = 0.4;
      }
      this.sub.cameraTransform(this.camera);
      this.player.pos.copy(this.sub.pos);
      if (input.hit('lamp')) { this.sub.setLights(!this.sub.lightsOn); this.stats.lampToggles++; }
      // docking
      const dockD = this.sub.pos.distanceTo(this.world.structures.dockPoint);
      this.docked = dockD < 10 && this.state.flags.power;
      if (this.docked) {
        this.sub.power = Math.min(100, this.sub.power + dt * 8);
        this.sub.hull = Math.min(100, this.sub.hull + dt * 4);
      }
      if (this.sub.power <= 0 && this.sub.lightsOn) this.sub.setLights(true);
      this.dashTimer = (this.dashTimer || 0) - dt;
      if (this.dashTimer < 0) { this.dashTimer = 0.2; this.sub.drawDash(this.hullRating); }
    } else {
      this.player.look(mouse[0], mouse[1], this.settings);
      this.player.update(dt, input, this.settings, this.swimMult, this.events);
      this.sub.idle(dt);
      if (this.state.flags.power && this.sub.pos.distanceTo(this.world.structures.dockPoint) < 10) {
        this.sub.power = Math.min(100, this.sub.power + dt * 8);
        this.sub.hull = Math.min(100, this.sub.hull + dt * 4);
      }
      if (input.hit('lamp')) {
        if (s.battery > 0) { s.lamp = !s.lamp; this.audio.tone({ freq: s.lamp ? 1200 : 800, dur: 0.05, gain: 0.05, bus: 'ui' }); }
        this.stats.lampToggles++;
      }
    }
    this.stats.moved += this.player.pos.distanceTo(prevPos);
    const depth = this.inSub ? Math.max(0, -this.sub.pos.y) : this.player.depth;
    s.stats.maxDepth = Math.max(s.stats.maxDepth, depth);

    // ---- life support
    const breathing = this.inSub || this.player.surfaced;
    const inStation = !this.inSub && this.player.inAirPocket;
    if (breathing) s.o2 = Math.min(this.o2Max, s.o2 + dt * 28);
    else s.o2 = Math.max(0, s.o2 - dt * (this.player.sprinting ? 1.5 : 1));
    if (s.o2 <= 0 && !breathing) {
      s.health -= dt * 9;
      this.lastHurt = 0;
      this.deathCause = 'Drowned. Oxygen depleted.';
      if (s.health <= 0) { this.die('Drowned. Oxygen depleted.'); return; }
    }
    // battery
    if (this.inSub || inStation) s.battery = Math.min(this.batteryMax, s.battery + dt * 12);
    else if (s.lamp) s.battery = Math.max(0, s.battery - dt * 0.12);
    if (s.battery <= 0 && s.lamp) { s.lamp = false; this.ui.notify('Suit cell', 'Battery depleted — headlamp off', '', 'amber'); }
    // pressure
    let cracks = 0;
    let warning = '';
    let warningAmber = false;
    if (!this.inSub && depth > this.suitRating) {
      const over = depth - this.suitRating;
      s.health -= dt * (3 + over * 0.12);
      this.lastHurt = 0;
      cracks = Math.min(1, 0.2 + over / 40);
      warning = 'Suit pressure critical — ascend';
      if (s.health <= 0) { this.die(`Crushed at ${Math.round(depth)} m. The suit was rated to ${this.suitRating} m.`); return; }
      this.creakTimer = (this.creakTimer || 0) - dt;
      if (this.creakTimer < 0) { this.creakTimer = 2 + Math.random() * 2; this.audio.creak(); }
    }
    if (this.inSub && depth > this.hullRating) {
      const over = depth - this.hullRating;
      this.sub.hull -= dt * (1.5 + over * 0.06);
      cracks = Math.min(1, 0.15 + over / 60);
      warning = 'Hull stress — crush depth exceeded';
      this.creakTimer = (this.creakTimer || 0) - dt;
      if (this.creakTimer < 0) { this.creakTimer = 1.2 + Math.random() * 1.5; this.audio.creak(); }
    }
    if (this.inSub && this.sub.hull <= 0) {
      this.sub.hull = 0;
      this.exitSub(true);
      this.sub.place(this.world.structures.dockPoint, DOCK_YAW);
      this.sub.hull = 25;
      this.sub.power = Math.min(this.sub.power, 30);
      this.damage(25, 'Killed when the Kestrel’s hull failed.');
      this.ui.discovery('Hull breach', 'Kestrel lost', 'Emergency autopilot returning her to Meridian');
      if (this.mode !== 'play') return;
    }
    if (!warning) {
      if (s.o2 <= 0 && !breathing) warning = 'Oxygen depleted — surface now';
      else if (s.o2 < 15 && !breathing) { warning = 'Oxygen low'; warningAmber = s.o2 > 7; } else if (this.inSub && this.docked) { warning = this.sub.power < 99.5 || this.sub.hull < 99.5 ? 'Docked — charging & repairing' : 'Docked — systems nominal'; warningAmber = true; } else if (this.inSub && this.sub.power < 10) { warning = 'Kestrel power low — return to dock'; warningAmber = true; } else if (!this.inSub && depth > this.suitRating * 0.9) { warning = 'Approaching suit depth limit'; warningAmber = true; } else if (this.inSub && depth > this.hullRating * 0.9) { warning = 'Approaching crush depth'; warningAmber = true; }
    }
    this.warnTimer -= dt;
    if (warning && this.warnTimer < 0 && !(this.inSub && this.docked)) { this.warnTimer = warningAmber ? 3 : 1.4; this.audio.warn(); }
    if (s.o2 <= 0 && !breathing) {
      this.beatTimer = (this.beatTimer || 0) - dt;
      if (this.beatTimer < 0) { this.beatTimer = 0.9; this.audio.heartbeat(); }
    }
    // regeneration
    if (this.lastHurt > 6 && s.o2 > 0) s.health = Math.min(100, s.health + dt * (inStation ? 6 : 1.2));
    // breathing sounds & bubbles
    if (!this.inSub && !breathing) {
      this.breathTimer -= dt;
      if (this.breathTimer < 0) {
        this.breathTimer = s.o2 < 15 ? 2.2 : 4.2;
        this.audio.breathe(s.o2 < 15);
        this.env.bubbles.spawn(this.camera.position.clone().add(V(0, 0.25, 0)).addScaledVector(this.camera.getWorldDirection(_d), 0.9), 8, 0.15, 0.05);
      }
    }
    if (this.inSub && this.sub.thrust > 0.2 && Math.random() < dt * 20) {
      const back = this.sub.forward(_d).multiplyScalar(-3.6).add(this.sub.pos);
      this.env.bubbles.spawn(back, 2, 0.6, 0.08);
    }
    if (input.hit('medkit')) this.useMedkit();

    // ---- scanning
    const wantScan = input.held('scan');
    const target = this.findScanTarget();
    this.scan.target = target;
    if (wantScan && target && !s.databank.includes(target.id) && (this.inSub || s.battery > 0)) {
      if (this.scan.id !== target.id) { this.scan.id = target.id; this.scan.progress = 0; }
      this.scan.active = true;
      this.scan.progress += dt / (DATABANK[target.id]?.time || 2);
      if (!this.inSub) s.battery = Math.max(0, s.battery - dt * 1.2);
      if (this.scan.progress >= 1) {
        this.addDatabank(target.id);
        this.scan.progress = 0;
        this.scan.active = false;
        this.scan.id = null;
      }
    } else {
      this.scan.active = false;
      if (!wantScan) this.scan.progress = Math.max(0, this.scan.progress - dt * 2);
    }
    this.viewmodel.drawScreenThrottle = (this.viewmodel.drawScreenThrottle || 0) - dt;
    if (this.viewmodel.drawScreenThrottle < 0) {
      this.viewmodel.drawScreenThrottle = 0.1;
      const label = target ? (s.databank.includes(target.id) ? DATABANK[target.id].name : (this.scan.active ? 'SCANNING' : 'UNKNOWN')) : 'NO TARGET';
      this.viewmodel.drawScreen(label, target && s.databank.includes(target.id) ? 1 : this.scan.progress);
    }

    // ---- interaction
    const it = this.findInteraction();
    const prompt = this.interactionPrompt(it);
    if (input.hit('interact')) this.doInteract(it);
    if (input.hit('sonar')) this.sonarPing();

    // ---- discovery of places
    this.discoverTimer -= dt;
    if (this.discoverTimer < 0) {
      this.discoverTimer = 0.4;
      const p = this.camera.position;
      if (this.explored.reveal(p.x, p.z, 55) && this.mode === 'pda') this.ui.drawMap();
      for (const poi of POIS) {
        if (s.discovered.includes(poi.id)) continue;
        const d = Math.hypot(p.x - poi.x, p.z - poi.z);
        if (d > poi.radius) continue;
        if (poi.minDepth && depth < poi.minDepth) continue;
        s.discovered.push(poi.id);
        this.ui.discovery('Site discovered', poi.name, `${poi.sub} · ${Math.round(depth)} m`);
        this.audio.discovery();
        if (poi.id === 'abyss' && !this.state.flags.ending) setTimeout(() => this.ui.subtitle('<b>Suit:</b> Bathymetry returns no floor within sonar range. Recommend extreme caution.', 6), 2500);
        this.evaluate();
      }
      this.updateHints();
      this.evaluate();
    }

    // ---- ambient life sounds
    this.ambTimer = (this.ambTimer ?? 6) - dt;
    if (this.ambTimer < 0) {
      this.ambTimer = 5 + Math.random() * 9;
      const cp = this.camera.position;
      const school = this.world.creatures.fish.schools.find((sc) => sc.active && sc.center.distanceTo(cp) < 40);
      const caveD = this.world.structures.caveCurve ? this.world.structures.caveChamber.distanceTo(cp) : 999;
      const nearCave = caveD < 140 && depth > 40;
      if (nearCave) this.audio.crystalRing();
      else if (school) this.audio.shimmer(school.center.distanceTo(cp));
      else if (depth > 180 && Math.random() < 0.6) this.audio.deepGroan();
    }

    // ---- world + audio
    this.updateWorld(dt, this.camera.position, {});
    this.audio.update(dt, this.audioState());
    this.updateSonarMarks(dt);

    // ---- viewmodel
    const lightLevel = Math.exp(-depth * 0.02) * (0.2 + 0.8 * U.uDaylight.value);
    this.vmAmbient = 0.08 + lightLevel * 1.3 + (this.player.inAirPocket ? 0.8 : 0);
    this.viewmodel.update(dt, this.camera, {
      mouse, speed: this.player.speed, bob: this.player.bob, scanning: this.scan.active, scanTarget: target?.pos,
      visible: !this.inSub, cockpit: this.inSub, pdaOpen: false, lampOn: s.lamp || (this.inSub && this.sub.lightsOn), ambient: this.vmAmbient, time: s.time,
    });
    if (this.shake > 0) {
      this.shake = Math.max(0, this.shake - dt);
      this.camera.position.x += (Math.random() - 0.5) * this.shake * 0.15;
      this.camera.position.y += (Math.random() - 0.5) * this.shake * 0.15;
    }

    // ---- HUD
    const needClick = this.everLocked && !this.input.locked;
    if (needClick !== this.showingClick) {
      this.showingClick = needClick;
      document.getElementById('clickToPlay').classList.toggle('hidden', !needClick);
    }
    this.ui.updateHUD(dt, this.hudFrame({ prompt, warning, warningAmber, cracks }, target));
    this.updateMarkers();
  }

  hudFrame(extra, target) {
    const depth = this.inSub ? Math.max(0, -this.sub.pos.y) : this.player.depth;
    const lightLabel = depth < 40 ? 'SUNLIT ZONE' : depth < 200 ? 'TWILIGHT ZONE' : depth < 450 ? 'MIDNIGHT ZONE' : 'ABYSSAL ZONE';
    return {
      depth, inSub: this.inSub, camPos: this.camera.position, lightLabel,
      scanTarget: target, scanProgress: this.scan.progress, scanning: this.scan.active,
      prompt: extra?.prompt?.text, promptKey: extra?.prompt?.key,
      warning: extra?.warning, warningAmber: extra?.warningAmber,
      cracks: extra?.cracks || 0, hurt: this.hurtFlash * 0.5, boundary: this.player.boundaryWarning,
    };
  }

  updateSonarMarks(dt) {
    for (const m of this.sonarMarks) { m.t -= dt; m.delay -= dt; }
    this.sonarMarks = this.sonarMarks.filter((m) => m.t > 0);
  }

  updateMarkers() {
    const list = [];
    const cam = this.camera.position;
    const o = this.mainObjectiveTarget();
    const compass = [];
    if (o) {
      list.push({ pos: o.pos, label: `${o.title} · ${Math.round(o.pos.distanceTo(cam))} m`, cls: 'obj', clamp: true });
      compass.push({ deg: bearing(cam, o.pos), cls: 'obj' });
    }
    if (!this.inSub && this.state.flags.power) {
      const d = this.sub.pos.distanceTo(cam);
      if (d > 12 && d < 600) list.push({ pos: this.sub.pos.clone().add(V(0, 2, 0)), label: `Kestrel ${Math.round(d)} m`, cls: 'sub', opacity: 0.8 });
      compass.push({ deg: bearing(cam, this.sub.pos), cls: 'sub' });
    }
    for (const m of this.sonarMarks) if (m.delay <= 0) list.push({ pos: m.pos, label: m.label, cls: m.cls, opacity: Math.min(1, m.t / 3) });
    for (const p of POIS) {
      if (!this.state.discovered.includes(p.id)) continue;
      const d = Math.hypot(p.x - cam.x, p.z - cam.z);
      if (d < 500 && d > p.radius * 0.5) compass.push({ deg: bearing(cam, V(p.x, 0, p.z)), cls: '' });
    }
    this.ui.updateMarkers(this.camera, list);
    this.ui.updateCompass(this.inSub ? this.sub.yaw : this.player.yaw, compass);
  }

  mainObjectiveTarget() {
    const o = mainObjective(this);
    if (!o || !o.target) return null;
    const pos = o.target(this);
    return pos ? { pos, title: o.title } : null;
  }

  updateHints() {
    if (!this.settings.hints) return;
    const s = this.state;
    if (this.currentHint) {
      if (this.currentHint.done(this) || (this.currentHint.time && (this.hintTimer += 0.4) > this.currentHint.time)) {
        s.hintsDone.push(this.currentHint.id);
        this.currentHint = null;
        this.ui.showHint(null);
        this.hintCooldown = 2.5;
      }
      return;
    }
    this.hintCooldown = (this.hintCooldown || 0) - 0.4;
    if (this.hintCooldown > 0) return;
    for (const h of HINTS) {
      if (s.hintsDone.includes(h.id)) continue;
      if (h.done(this)) { s.hintsDone.push(h.id); continue; }
      if (h.when && !h.when(this)) continue;
      this.currentHint = h;
      this.hintTimer = 0;
      this.ui.showHint(h);
      break;
    }
  }

  /** Advance the simulation without rendering (used by automated tests). */
  simulate(seconds, dt = 1 / 30) {
    for (let t = 0; t < seconds; t += dt) {
      if (this.mode === 'play') this.updatePlay(dt);
      else if (this.mode !== 'menu') this.updateIdle(dt);
      this.input.endFrame();
    }
  }

  render(dt) {
    if (this.mode === 'loading') return;
    const above = !this.inSub && this.player.aboveSurface && this.mode !== 'menu';
    const inAir = !this.inSub && this.player.inAirPocket && this.mode !== 'menu';
    const depth = Math.max(0, -this.camera.position.y);
    // background = fog colour at the camera (or sky when above water)
    if (above) this.scene.background.setRGB(0.3, 0.42, 0.5);
    else {
      const d = depth;
      const day = 0.18 + 0.82 * U.uDaylight.value;
      const fc = U.uFogColor.value;
      const ab = U.uFogAbsorb.value;
      this.scene.background.setRGB(fc.r * Math.exp(-ab.x * d) * day + 0.001, fc.g * Math.exp(-ab.y * d) * day + 0.0015, fc.b * Math.exp(-ab.z * d) * day + 0.004);
      if (inAir) this.scene.background.multiplyScalar(0.3);
    }
    const lens = this.post.lens.uniforms;
    lens.uUnderwater.value = above || inAir ? 0 : 1;
    lens.uHurt.value = Math.max(this.hurtFlash * 0.6, this.mode === 'play' ? (1 - this.state.health / 100) * 0.4 : 0);
    lens.uLowO2.value = this.mode === 'play' && !this.inSub ? clamp(1 - this.state.o2 / 12, 0, 1) : 0;
    this.post.render(dt);
  }
}

function bearing(from, to) {
  const dx = to.x - from.x, dz = to.z - from.z;
  return ((Math.atan2(dx, -dz) * 180) / Math.PI + 360) % 360;
}

function frame() { return new Promise((r) => requestAnimationFrame(() => r())); }
