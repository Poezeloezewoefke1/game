// DOM user interface: HUD, wrist PDA, menus, intro, death and ending screens.

import * as THREE from 'three';
import { ITEMS, RECIPES, UPGRADES, INVENTORY_CAPACITY } from '../data/items.js';
import { DATABANK, LOGS } from '../data/lore.js';
import { POIS, WORLD_HALF, SITES } from '../world/layout.js';
import { OBJECTIVES, mainObjective } from '../systems/story.js';
import { icon, iconPath } from './icons.js';

const $ = (id) => document.getElementById(id);
const _p = new THREE.Vector3();

function esc(s) { return String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c])); }

export class UI {
  constructor(game) {
    this.game = game;
    this.screens = ['loading', 'menu', 'pause', 'settings', 'controls', 'credits', 'intro', 'death', 'ending', 'confirm'];
    this.screenStack = [];
    this.pdaOpen = false;
    this.pdaTab = 'objectives';
    this.selected = {};
    this.discoveryTimer = 0;
    this.subtitleTimer = 0;
    this.hintVisible = false;
    this.mapBase = null;
    this.typeTimer = null;
    this.bindMenus();
    this.buildSettings();
    this.buildCompass();
    this.cache = {};
  }

  // ---------------------------------------------------------------- screens
  show(id) { $(id).classList.remove('hidden'); }
  hide(id) { $(id).classList.add('hidden'); }
  only(id) {
    for (const s of this.screens) if (s !== id) this.hide(s);
    if (id) this.show(id);
  }

  setLoading(f, text) {
    $('loadFill').style.width = `${Math.round(f * 100)}%`;
    if (text) $('loadText').textContent = text;
  }

  bindMenus() {
    document.body.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-act]');
      if (!b) return;
      this.game.audio.ui();
      const act = b.dataset.act;
      const g = this.game;
      switch (act) {
        case 'continue': g.continueGame(); break;
        case 'new':
          if (g.hasSave()) this.confirm('New expedition', 'This will overwrite your saved expedition. Continue?', () => g.newGame());
          else g.newGame();
          break;
        case 'settings': this.openSub('settings'); break;
        case 'controls': this.openSub('controls'); break;
        case 'credits': this.openSub('credits'); break;
        case 'back': this.closeSub(); break;
        case 'resume': g.resume(); break;
        case 'save': g.saveGame(true); this.updatePauseFoot(); break;
        case 'load': this.confirm('Load last save', 'Unsaved progress since your last save will be lost.', () => g.loadGame()); break;
        case 'quit': this.confirm('Quit to title', 'Unsaved progress will be lost. Your last save is kept.', () => g.quitToTitle()); break;
        case 'respawn': g.respawn(); break;
        case 'keepExploring': g.keepExploring(); break;
        case 'yes': { const f = this.confirmYes; this.hide('confirm'); this.confirmYes = null; f?.(); break; }
        case 'no': this.hide('confirm'); this.confirmYes = null; break;
        default: break;
      }
    });
    $('pdaClose').addEventListener('click', () => this.game.closePDA());
  }

  confirm(title, text, yes) {
    $('confirmTitle').textContent = title;
    $('confirmText').textContent = text;
    this.confirmYes = yes;
    this.show('confirm');
  }

  openSub(id) {
    const visible = this.screens.find((s) => s !== id && !$(s).classList.contains('hidden') && s !== 'confirm');
    this.subReturn = visible;
    if (visible) this.hide(visible);
    this.show(id);
  }

  closeSub() {
    for (const s of ['settings', 'controls', 'credits']) this.hide(s);
    if (this.subReturn) this.show(this.subReturn);
    this.subReturn = null;
  }

  updateMenu(hasSave) {
    $('btnContinue').disabled = !hasSave;
    $('btnContinue').style.display = hasSave ? '' : 'none';
  }

  updatePauseFoot() {
    const s = this.game.lastSaveTime;
    $('pauseFoot').textContent = s ? `Last saved ${new Date(s).toLocaleTimeString()}` : 'Not yet saved this session';
    const atStation = this.game.canSaveHere();
    $('btnLoad').disabled = !this.game.hasSave();
    $('btnSave').disabled = !atStation.ok;
    $('btnSave').title = atStation.ok ? '' : atStation.reason;
    $('btnSave').textContent = atStation.ok ? 'Save Expedition' : `Save Expedition — ${atStation.reason}`;
  }

  // ---------------------------------------------------------------- settings
  buildSettings() {
    const grid = $('settingsGrid');
    const defs = [
      { k: 'sensitivity', label: 'Mouse sensitivity', type: 'range', min: 0.2, max: 3, step: 0.05, fmt: (v) => v.toFixed(2) },
      { k: 'fov', label: 'Field of view', type: 'range', min: 60, max: 100, step: 1, fmt: (v) => `${v}°` },
      { k: 'master', label: 'Master volume', type: 'range', min: 0, max: 1, step: 0.01, fmt: (v) => `${Math.round(v * 100)}%` },
      { k: 'music', label: 'Music', type: 'range', min: 0, max: 1, step: 0.01, fmt: (v) => `${Math.round(v * 100)}%` },
      { k: 'sfx', label: 'Effects', type: 'range', min: 0, max: 1, step: 0.01, fmt: (v) => `${Math.round(v * 100)}%` },
      { k: 'ambience', label: 'Ambience', type: 'range', min: 0, max: 1, step: 0.01, fmt: (v) => `${Math.round(v * 100)}%` },
      { k: 'quality', label: 'Graphics quality', type: 'select', options: [['low', 'Low'], ['medium', 'Medium'], ['high', 'High']] },
      { k: 'invertY', label: 'Invert vertical look', type: 'check' },
      { k: 'headBob', label: 'Head bob', type: 'check' },
      { k: 'subtitles', label: 'Subtitles for logs & radio', type: 'check' },
      { k: 'hints', label: 'Tutorial hints', type: 'check' },
    ];
    grid.innerHTML = '';
    for (const d of defs) {
      const el = document.createElement('div');
      el.className = `setting${d.type === 'check' ? ' check' : ''}`;
      const id = `set_${d.k}`;
      if (d.type === 'range') {
        el.innerHTML = `<label for="${id}">${d.label}<span id="${id}_v"></span></label><input type="range" id="${id}" min="${d.min}" max="${d.max}" step="${d.step}">`;
      } else if (d.type === 'select') {
        el.innerHTML = `<label for="${id}">${d.label}</label><select id="${id}">${d.options.map(([v, l]) => `<option value="${v}">${l}</option>`).join('')}</select>`;
      } else {
        el.innerHTML = `<input type="checkbox" id="${id}"><label for="${id}">${d.label}</label>`;
      }
      grid.appendChild(el);
      const input = el.querySelector('input,select');
      input.addEventListener('input', () => {
        const s = this.game.settings;
        if (d.type === 'range') s[d.k] = parseFloat(input.value);
        else if (d.type === 'select') s[d.k] = input.value;
        else s[d.k] = input.checked;
        if (d.fmt) $(`${id}_v`).textContent = d.fmt(s[d.k]);
        this.game.applySettings();
      });
      d.input = input;
    }
    this.settingDefs = defs;
  }

  syncSettings() {
    const s = this.game.settings;
    for (const d of this.settingDefs) {
      if (d.type === 'range') { d.input.value = s[d.k]; $(`set_${d.k}_v`).textContent = d.fmt(s[d.k]); } else if (d.type === 'select') d.input.value = s[d.k];
      else d.input.checked = !!s[d.k];
    }
  }

  // ---------------------------------------------------------------- HUD bits
  buildCompass() {
    const strip = $('compassStrip');
    strip.innerHTML = '';
    this.compassEls = [];
    const cards = { 0: 'N', 45: 'NE', 90: 'E', 135: 'SE', 180: 'S', 225: 'SW', 270: 'W', 315: 'NW' };
    for (let d = 0; d < 360; d += 15) {
      const t = document.createElement('div');
      t.className = `tick${d % 45 === 0 ? ' major' : ''}`;
      strip.appendChild(t);
      this.compassEls.push({ el: t, deg: d });
      if (cards[d] !== undefined) {
        const c = document.createElement('div');
        c.className = `card${d === 0 ? ' n' : ''}`;
        c.textContent = cards[d];
        strip.appendChild(c);
        this.compassEls.push({ el: c, deg: d });
      }
    }
    this.compassMarks = [];
  }

  updateCompass(yaw, marks) {
    const w = $('compass').clientWidth || 560;
    const heading = ((-yaw * 180) / Math.PI + 360) % 360; // 0 = north (-z)
    const span = 150;
    const place = (el, deg) => {
      let d = ((deg - heading + 540) % 360) - 180;
      const vis = Math.abs(d) < span / 2;
      el.style.display = vis ? '' : 'none';
      if (vis) el.style.left = `${w / 2 + (d / span) * w}px`;
    };
    for (const c of this.compassEls) place(c.el, c.deg);
    const strip = $('compassStrip');
    while (this.compassMarks.length < marks.length) {
      const m = document.createElement('div');
      strip.appendChild(m);
      this.compassMarks.push(m);
    }
    this.compassMarks.forEach((m, i) => {
      const mk = marks[i];
      if (!mk) { m.style.display = 'none'; return; }
      m.className = `cmark ${mk.cls || ''}`;
      place(m, mk.deg);
    });
  }

  vital(id, frac, text, warnAt = 0.35, critAt = 0.15) {
    const el = $(id);
    el.querySelector('.v-fill').style.transform = `scaleX(${Math.max(0, Math.min(1, frac))})`;
    el.querySelector('.v-val').textContent = text;
    el.classList.toggle('warn', frac < warnAt && frac >= critAt);
    el.classList.toggle('crit', frac < critAt);
  }

  setText(id, text) {
    if (this.cache[id] === text) return;
    this.cache[id] = text;
    $(id).textContent = text;
  }

  setHTML(id, html) {
    if (this.cache[id] === html) return;
    this.cache[id] = html;
    $(id).innerHTML = html;
  }

  notify(kind, title, text = '', cls = '') {
    const box = $('notifications');
    const n = document.createElement('div');
    n.className = `note ${cls}`;
    n.innerHTML = `<span class="n-k">${esc(kind)}</span>${esc(title)}${text ? `<div style="color:var(--ink-dim);font-size:12px;margin-top:2px">${esc(text)}</div>` : ''}`;
    box.prepend(n);
    while (box.children.length > 5) box.lastChild.remove();
    setTimeout(() => { n.classList.add('out'); setTimeout(() => n.remove(), 600); }, 5200);
  }

  discovery(eyebrow, title, sub) {
    $('dEyebrow').textContent = eyebrow;
    $('dTitle').textContent = title;
    $('dSub').textContent = sub || '';
    $('discovery').classList.add('show');
    this.discoveryTimer = 5;
  }

  subtitle(html, seconds = 5) {
    if (!this.game.settings.subtitles) return;
    $('subtitle').innerHTML = html;
    $('subtitle').classList.add('show');
    this.subtitleTimer = seconds;
  }

  showHint(h) {
    if (!h) { $('hint').classList.remove('show'); this.hintVisible = false; return; }
    $('hintKey').textContent = h.key;
    $('hintText').textContent = h.text;
    $('hint').classList.add('show');
    this.hintVisible = true;
  }

  flash() {
    const f = $('flash');
    f.style.transition = 'none';
    f.style.opacity = '1';
    requestAnimationFrame(() => { f.style.transition = 'opacity 0.6s'; f.style.opacity = '0'; });
  }

  drawCracks(level) {
    const c = $('cracks');
    if (!this.crackSeed) {
      this.crackSeed = [];
      for (let i = 0; i < 9; i++) {
        const side = i % 4;
        const x = side === 0 ? 0 : side === 1 ? 1024 : Math.random() * 1024;
        const y = side === 2 ? 0 : side === 3 ? 1024 : Math.random() * 1024;
        this.crackSeed.push({ x, y, a: Math.atan2(512 - y, 512 - x) + (Math.random() - 0.5) * 0.8 });
      }
      const g = c.getContext('2d');
      g.clearRect(0, 0, 1024, 1024);
      g.strokeStyle = 'rgba(220,240,255,0.55)';
      g.lineWidth = 1.3;
      for (const s of this.crackSeed) {
        let x = s.x, y = s.y, a = s.a;
        g.beginPath();
        g.moveTo(x, y);
        for (let k = 0; k < 18; k++) {
          a += (Math.random() - 0.5) * 0.7;
          x += Math.cos(a) * 18; y += Math.sin(a) * 18;
          g.lineTo(x, y);
          if (Math.random() < 0.2) { g.moveTo(x, y); g.lineTo(x + Math.cos(a + 1) * 30, y + Math.sin(a + 1) * 30); g.moveTo(x, y); }
        }
        g.stroke();
      }
    }
    c.style.opacity = String(Math.min(0.9, level));
  }

  /** Per-frame HUD refresh. */
  updateHUD(dt, f) {
    const g = this.game;
    const s = g.state;
    // vitals
    this.vital('vO2', s.o2 / g.o2Max, `${Math.ceil(s.o2)}s`, 0.3, 0.15);
    this.vital('vHealth', s.health / 100, `${Math.ceil(s.health)}`, 0.4, 0.2);
    this.vital('vBattery', s.battery / g.batteryMax, `${Math.round((s.battery / g.batteryMax) * 100)}%`, 0.25, 0.1);
    // depth
    const depth = f.depth;
    const rating = f.inSub ? g.hullRating : g.suitRating;
    this.setText('depthNum', depth.toFixed(0));
    this.setText('depthLabel', f.inSub ? 'Kestrel depth' : 'Depth');
    const over = depth > rating;
    this.setText('depthRating', over ? `EXCEEDS ${f.inSub ? 'HULL' : 'SUIT'} RATING ${rating} m` : `${f.inSub ? 'Hull' : 'Suit'} rated to ${rating} m`);
    $('depthRating').classList.toggle('danger', over);
    const gaugeMax = Math.max(rating * 1.25, depth + 10);
    $('dgFill').style.width = `${Math.min(100, (depth / gaugeMax) * 100)}%`;
    $('dgLimit').style.left = `${(rating / gaugeMax) * 100}%`;
    const atm = 1 + depth / 10;
    const temp = Math.max(2, 19 - depth * 0.035 - (depth > 300 ? 2 : 0));
    this.setText('depthMeta', `${atm.toFixed(1)} ATM · ${temp.toFixed(1)}°C · ${f.lightLabel}`);
    // sub HUD
    $('subhud').classList.toggle('hidden', !f.inSub);
    $('vitals').style.opacity = f.inSub ? '0.55' : '1';
    if (f.inSub) {
      this.setText('shHull', `${Math.round(g.sub.hull)}%`);
      this.setText('shPower', `${Math.round(g.sub.power)}%`);
      this.setText('shSpeed', `${g.sub.vel.length().toFixed(1)} m/s`);
      $('shHull').style.color = g.sub.hull < 35 ? 'var(--red)' : '';
      $('shPower').style.color = g.sub.power < 20 ? 'var(--amber)' : '';
    }
    // objective
    const o = mainObjective(g);
    if (o) {
      this.setText('objTitle', o.title);
      this.setText('objText', o.text(g));
      const t = o.target ? o.target(g) : null;
      this.setText('objDist', t ? `${Math.round(t.distanceTo(f.camPos))} m · ${t.y < -1 ? `${Math.round(-t.y)} m deep` : 'surface'}` : '');
      $('objective').style.display = '';
    } else $('objective').style.display = 'none';
    // scanning
    const ring = $('scanring');
    ring.classList.toggle('on', !!f.scanTarget);
    $('scanArc').style.strokeDashoffset = String(251.3 * (1 - (f.scanProgress || 0)));
    if (f.scanTarget) {
      const entry = DATABANK[f.scanTarget.id];
      const known = s.databank.includes(f.scanTarget.id);
      this.setHTML('targetLabel', known ? `<span class="known">${esc(entry?.name || f.scanTarget.id)} · in databank</span>` : (f.scanning ? `Scanning… ${Math.round(f.scanProgress * 100)}%` : 'Unknown — hold to scan'));
    } else this.setHTML('targetLabel', '');
    this.setHTML('prompt', f.prompt ? `<kbd>${esc(f.promptKey || 'E')}</kbd>${esc(f.prompt)}` : '');
    // warnings
    const warn = f.warning || '';
    this.setText('warning', warn);
    $('warning').classList.toggle('amber', !!f.warningAmber);
    $('boundary').style.opacity = String(Math.min(1, f.boundary || 0));
    // vignette / damage
    const danger = Math.max(1 - s.health / 100, s.o2 <= 0 ? 0.8 : 0);
    $('vignette').style.opacity = String(Math.min(0.9, danger * 0.9 + (f.hurt || 0)));
    this.drawCracks(f.cracks || 0);
    // discovery & subtitle timers
    if (this.discoveryTimer > 0) {
      this.discoveryTimer -= dt;
      if (this.discoveryTimer <= 0) $('discovery').classList.remove('show');
    }
    if (this.subtitleTimer > 0) {
      this.subtitleTimer -= dt;
      if (this.subtitleTimer <= 0) $('subtitle').classList.remove('show');
    }
  }

  /** Project world-space markers onto the screen. */
  updateMarkers(camera, list) {
    const box = $('markers');
    const w = window.innerWidth, h = window.innerHeight;
    while (box.children.length < list.length) box.appendChild(document.createElement('div'));
    for (let i = 0; i < box.children.length; i++) {
      const el = box.children[i];
      const m = list[i];
      if (!m) { el.style.display = 'none'; continue; }
      _p.copy(m.pos).project(camera);
      const behind = _p.z > 1;
      if (behind && !m.clamp) { el.style.display = 'none'; continue; }
      let x = (_p.x * 0.5 + 0.5) * w, y = (-_p.y * 0.5 + 0.5) * h;
      if (m.clamp) {
        if (behind) { x = w - x; y = h - 40; }
        x = Math.max(40, Math.min(w - 40, x));
        y = Math.max(60, Math.min(h - 60, y));
      } else if (x < 0 || x > w || y < 0 || y > h) { el.style.display = 'none'; continue; }
      el.style.display = '';
      el.className = `marker ${m.cls || ''}`;
      el.style.left = `${x}px`;
      el.style.top = `${y}px`;
      const label = m.label || '';
      if (el.dataset.l !== label) { el.textContent = label; el.dataset.l = label; }
      el.style.opacity = m.opacity ?? 1;
    }
  }

  // ---------------------------------------------------------------- PDA
  openPDA(tab, mode) {
    this.pdaOpen = true;
    this.pdaMode = mode;
    if (tab) this.pdaTab = tab;
    if (mode !== 'field' && !tab) this.pdaTab = 'fabricator';
    $('pdaMode').textContent = mode === 'station' ? 'MERIDIAN TERMINAL' : mode === 'sub' ? 'KESTREL CONSOLE' : 'FIELD PDA';
    this.show('pda');
    this.renderPDA();
  }

  closePDA() {
    this.pdaOpen = false;
    this.hide('pda');
    this.stopTyping();
  }

  tabs() {
    const g = this.game;
    const s = g.state;
    const t = [
      ['objectives', 'Objectives'],
      ['map', 'Map'],
      ['databank', 'Databank', s.databank.filter((d) => !s.seen.includes(`d:${d}`)).length],
      ['logs', 'Logs', s.logs.filter((l) => !s.seen.includes(`l:${l}`)).length],
      ['inventory', 'Inventory'],
    ];
    if (this.pdaMode === 'station' || this.pdaMode === 'sub') t.push(['fabricator', 'Fabricator']);
    t.push(['status', 'Equipment']);
    return t;
  }

  renderPDA() {
    const nav = $('pdaTabs');
    const tabs = this.tabs();
    if (!tabs.find((t) => t[0] === this.pdaTab)) this.pdaTab = 'objectives';
    nav.innerHTML = tabs.map(([id, label, badge]) => `<button data-tab="${id}" class="${id === this.pdaTab ? 'active' : ''}">${label}${badge ? `<span class="badge">${badge}</span>` : ''}</button>`).join('');
    nav.querySelectorAll('button').forEach((b) => b.addEventListener('click', () => { this.game.audio.ui(); this.pdaTab = b.dataset.tab; this.stopTyping(); this.renderPDA(); }));
    const body = $('pdaBody');
    switch (this.pdaTab) {
      case 'objectives': body.innerHTML = this.renderObjectives(); break;
      case 'map': body.innerHTML = this.renderMapPane(); this.drawMap(); break;
      case 'databank': this.renderDatabank(body); break;
      case 'logs': this.renderLogs(body); break;
      case 'inventory': this.renderInventory(body); break;
      case 'fabricator': this.renderFabricator(body); break;
      case 'status': body.innerHTML = this.renderStatus(); break;
      default: break;
    }
  }

  renderObjectives() {
    const g = this.game;
    const main = mainObjective(g);
    const cards = OBJECTIVES.filter((o) => g.state.objectives[o.id]).map((o) => {
      const st = g.state.objectives[o.id];
      return `<div class="obj-card ${st === 'done' ? 'done' : ''} ${o === main ? 'main' : ''}"><h3>${esc(o.title)}<span class="state">${st === 'done' ? 'COMPLETE' : o === main ? 'CURRENT' : 'ACTIVE'}</span></h3><p>${esc(o.text(g))}</p></div>`;
    }).reverse();
    const st = g.stats;
    const scanned = g.state.databank.length;
    const totalEntries = Object.keys(DATABANK).length;
    return `<div class="pane"><div class="eyebrow">Expedition record</div>
      <div class="obj-list" style="margin-top:14px">${cards.join('')}</div>
      <div class="stats-row">
        <div><b>${Math.round(g.state.stats.maxDepth)} m</b>Deepest dive</div>
        <div><b>${scanned}/${totalEntries}</b>Databank</div>
        <div><b>${g.state.discovered.length}/${POIS.length}</b>Sites found</div>
        <div><b>${g.state.logs.length}/${Object.keys(LOGS).length}</b>Logs recovered</div>
        <div><b>${formatTime(g.state.time)}</b>Time on Maren</div>
      </div></div>`;
  }

  renderMapPane() {
    const g = this.game;
    const pois = POIS.filter((p) => g.state.discovered.includes(p.id));
    return `<div class="map-wrap"><div class="map-canvas-wrap"><canvas id="mapCanvas" width="760" height="760"></canvas></div>
      <div class="map-side"><div class="eyebrow">Charted sites</div>
      <div class="legend" style="margin-top:12px">${pois.length ? pois.map((p) => `<div>${icon(p.icon, '#8fe3ea', 16)} ${esc(p.name)}</div>`).join('') : '<div>Nothing charted yet. Explore to reveal the map; sonar pings chart terrain further out.</div>'}</div>
      <div class="section-h">Legend</div>
      <div class="legend">
        <div><span class="sw" style="background:#fff;border-radius:50%"></span>You</div>
        <div><span class="sw" style="background:#ffd08a;border-radius:50%"></span>Kestrel</div>
        <div><span class="sw" style="background:#ffb25a;transform:rotate(45deg)"></span>Objective</div>
        <div><span class="sw" style="background:linear-gradient(90deg,#9fc8b8,#2d6f86,#123a63,#140a2a)"></span>Shallow → deep</div>
      </div></div></div>`;
  }

  buildMapBase() {
    const terrain = this.game.world.terrain;
    const N = 380;
    const c = document.createElement('canvas');
    c.width = N; c.height = N;
    const ctx = c.getContext('2d');
    const img = ctx.createImageData(N, N);
    const stops = [[-20, [178, 214, 196]], [-50, [104, 168, 168]], [-100, [45, 111, 134]], [-180, [26, 72, 108]], [-300, [18, 44, 82]], [-450, [20, 16, 52]], [-650, [10, 4, 22]]];
    const col = (h) => {
      for (let i = 0; i < stops.length - 1; i++) {
        const [h0, c0] = stops[i], [h1, c1] = stops[i + 1];
        if (h >= h1) {
          const t = Math.max(0, Math.min(1, (h0 - h) / (h0 - h1)));
          return c0.map((v, k) => v + (c1[k] - v) * t);
        }
      }
      return stops[stops.length - 1][1];
    };
    for (let j = 0; j < N; j++) {
      for (let i = 0; i < N; i++) {
        const x = -WORLD_HALF + (i / N) * WORLD_HALF * 2, z = -WORLD_HALF + (j / N) * WORLD_HALF * 2;
        const h = terrain.heightAt(x, z);
        const hx = terrain.heightAt(x + 5, z), hz = terrain.heightAt(x, z + 5);
        const shade = Math.max(0.55, Math.min(1.35, 1 + ((h - hx) + (h - hz)) * 0.04));
        const contour = Math.abs(((h % 25) + 25) % 25) < 0.9 ? 0.82 : 1;
        const cc = col(h);
        const k = (j * N + i) * 4;
        img.data[k] = cc[0] * shade * contour;
        img.data[k + 1] = cc[1] * shade * contour;
        img.data[k + 2] = cc[2] * shade * contour;
        img.data[k + 3] = 255;
      }
    }
    ctx.putImageData(img, 0, 0);
    this.mapBase = c;
  }

  drawMap() {
    const canvas = $('mapCanvas');
    if (!canvas) return;
    if (!this.mapBase) this.buildMapBase();
    const g = this.game;
    const ctx = canvas.getContext('2d');
    const S = canvas.width;
    const toMap = (x, z) => [((x + WORLD_HALF) / (WORLD_HALF * 2)) * S, ((z + WORLD_HALF) / (WORLD_HALF * 2)) * S];
    ctx.fillStyle = '#020a10';
    ctx.fillRect(0, 0, S, S);
    // reveal explored cells
    ctx.save();
    ctx.beginPath();
    const ex = g.explored;
    const cells = ex.size;
    const cs = S / cells;
    for (let j = 0; j < cells; j++) for (let i = 0; i < cells; i++) if (ex.get(i, j)) ctx.rect(i * cs - 0.5, j * cs - 0.5, cs + 1, cs + 1);
    ctx.clip();
    ctx.imageSmoothingEnabled = true;
    ctx.drawImage(this.mapBase, 0, 0, S, S);
    ctx.restore();
    // grid
    ctx.strokeStyle = 'rgba(143,227,234,0.07)';
    ctx.lineWidth = 1;
    for (let k = 0; k <= 9; k++) {
      ctx.beginPath(); ctx.moveTo((k / 9) * S, 0); ctx.lineTo((k / 9) * S, S); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(0, (k / 9) * S); ctx.lineTo(S, (k / 9) * S); ctx.stroke();
    }
    // survey boundary
    const [b0] = toMap(-820, 0); const [b1] = toMap(820, 0);
    ctx.strokeStyle = 'rgba(255,178,90,0.25)';
    ctx.setLineDash([6, 6]);
    ctx.strokeRect(b0, b0, b1 - b0, b1 - b0);
    ctx.setLineDash([]);
    // POIs
    ctx.font = '600 12px "IBM Plex Mono", monospace';
    for (const p of POIS) {
      if (!g.state.discovered.includes(p.id) || p.id === 'gate') continue;
      const [x, y] = toMap(p.x, p.z);
      const path = new Path2D(iconPath(p.icon));
      ctx.save();
      ctx.translate(x - 9, y - 9);
      ctx.scale(0.75, 0.75);
      ctx.strokeStyle = '#d8eef0';
      ctx.lineWidth = 1.8;
      ctx.stroke(path);
      ctx.restore();
      ctx.fillStyle = 'rgba(216,238,240,0.85)';
      ctx.fillText(p.name, x + 12, y + 4);
    }
    // objective
    const o = mainObjective(g);
    const t = o?.target?.(g);
    if (t) {
      const [x, y] = toMap(t.x, t.z);
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(Math.PI / 4);
      ctx.fillStyle = 'rgba(255,178,90,0.5)';
      ctx.strokeStyle = '#ffb25a';
      ctx.lineWidth = 2;
      ctx.fillRect(-6, -6, 12, 12);
      ctx.strokeRect(-6, -6, 12, 12);
      ctx.restore();
    }
    // kestrel
    if (g.state.flags.power) {
      const [x, y] = toMap(g.sub.pos.x, g.sub.pos.z);
      ctx.fillStyle = '#ffd08a';
      ctx.beginPath(); ctx.arc(x, y, 4.5, 0, 7); ctx.fill();
    }
    // player arrow
    const pp = g.inSub ? g.sub.pos : g.player.pos;
    const yaw = g.inSub ? g.sub.yaw : g.player.yaw;
    const [px, py] = toMap(pp.x, pp.z);
    ctx.save();
    ctx.translate(px, py);
    ctx.rotate(-yaw);
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.moveTo(0, -9); ctx.lineTo(6, 7); ctx.lineTo(0, 3); ctx.lineTo(-6, 7); ctx.closePath(); ctx.fill();
    ctx.restore();
    // compass rose
    ctx.fillStyle = 'rgba(143,227,234,0.8)';
    ctx.fillText('N', S / 2 - 4, 16);
    // scale bar
    ctx.strokeStyle = 'rgba(216,238,240,0.6)';
    const [s0] = toMap(0, 0); const [s1] = toMap(200, 0);
    ctx.beginPath(); ctx.moveTo(16, S - 18); ctx.lineTo(16 + (s1 - s0), S - 18); ctx.stroke();
    ctx.fillStyle = 'rgba(216,238,240,0.7)';
    ctx.fillText('200 m', 16, S - 26);
  }

  renderDatabank(body) {
    const s = this.game.state;
    const groups = {};
    for (const id of s.databank) {
      const e = DATABANK[id];
      if (!e) continue;
      (groups[e.cat] = groups[e.cat] || []).push(id);
    }
    const total = Object.keys(DATABANK).length;
    const sel = this.selected.databank && s.databank.includes(this.selected.databank) ? this.selected.databank : s.databank[s.databank.length - 1];
    let list = '';
    for (const cat of ['Fauna', 'Flora', 'Geology', 'Sites', 'Veyru', 'Blueprints']) {
      if (!groups[cat]) continue;
      list += `<div class="group-h">${cat}</div>`;
      list += groups[cat].map((id) => `<button data-id="${id}" class="${id === sel ? 'active' : ''}">${esc(DATABANK[id].name)}${!s.seen.includes(`d:${id}`) ? '<span class="new"></span>' : ''}</button>`).join('');
    }
    if (!list) list = '<div class="empty">No entries yet. Hold right mouse (or F) on lifeforms, plants and structures to scan them.</div>';
    let detail = '<div class="empty">Select an entry.</div>';
    if (sel) {
      const e = DATABANK[sel];
      if (!s.seen.includes(`d:${sel}`)) s.seen.push(`d:${sel}`);
      detail = `<div class="meta">${esc(e.cat)} · Entry ${s.databank.indexOf(sel) + 1} of ${total}</div><h2>${esc(e.name)}</h2>
        <div>${e.danger ? '<span class="tag danger">DANGEROUS</span>' : ''}${e.rare ? '<span class="tag rare">RARE</span>' : ''}</div>
        <div class="body">${esc(e.text)}</div>`;
    }
    body.innerHTML = `<div class="split"><div class="list">${list}</div><div class="detail">${detail}</div></div>`;
    body.querySelectorAll('.list button').forEach((b) => b.addEventListener('click', () => { this.game.audio.ui(); this.selected.databank = b.dataset.id; this.renderPDA(); }));
  }

  renderLogs(body) {
    const s = this.game.state;
    const sel = this.selected.log && s.logs.includes(this.selected.log) ? this.selected.log : s.logs[s.logs.length - 1];
    const list = s.logs.length
      ? s.logs.map((id) => `<button data-id="${id}" class="${id === sel ? 'active' : ''}">${esc(LOGS[id].title)}${!s.seen.includes(`l:${id}`) ? '<span class="new"></span>' : ''}</button>`).join('')
      : '<div class="empty">No logs recovered.</div>';
    body.innerHTML = `<div class="split"><div class="list"><div class="group-h">Recovered logs</div>${list}</div><div class="detail" id="logDetail"></div></div>`;
    body.querySelectorAll('.list button').forEach((b) => b.addEventListener('click', () => { this.game.audio.ui(); this.selected.log = b.dataset.id; this.stopTyping(); this.renderPDA(); }));
    if (sel) this.showLog(sel);
  }

  showLog(id) {
    const s = this.game.state;
    const log = LOGS[id];
    const firstTime = !s.seen.includes(`l:${id}`);
    if (firstTime) s.seen.push(`l:${id}`);
    const d = $('logDetail');
    const audio = log.kind === 'audio';
    const bars = Array.from({ length: 48 }, (_, i) => `<i style="height:${6 + Math.abs(Math.sin(i * 1.7) * Math.cos(i * 0.6)) * 20}px;animation-delay:${(i % 7) * 0.08}s"></i>`).join('');
    d.innerHTML = `<div class="meta">${audio ? 'Audio recording · transcript' : 'Text record'} · ${esc(log.where)}</div>
      <h2>${esc(log.title)}</h2><div class="meta" style="margin-top:2px">${esc(log.author)}</div>
      ${audio ? `<div class="wave playing" id="logWave">${bars}</div>` : ''}
      <div class="body ${audio ? 'audio' : ''}" id="logBody"></div>`;
    const el = $('logBody');
    if (audio && firstTime) {
      let i = 0;
      const text = log.text;
      this.game.audio.voiceLog(true);
      this.typeTimer = setInterval(() => {
        i += 2;
        el.textContent = text.slice(0, i);
        if (i >= text.length) this.stopTyping();
      }, 22);
    } else {
      el.textContent = log.text;
      $('logWave')?.classList.remove('playing');
    }
  }

  stopTyping() {
    if (this.typeTimer) { clearInterval(this.typeTimer); this.typeTimer = null; }
    this.game.audio.voiceLog(false);
    $('logWave')?.classList.remove('playing');
    const lb = $('logBody');
    const id = this.selected.log || this.game.state.logs[this.game.state.logs.length - 1];
    if (lb && id && LOGS[id]) lb.textContent = LOGS[id].text;
  }

  itemCard(type, count, actions = '') {
    const it = ITEMS[type];
    return `<div class="inv-item ${it.story ? 'story' : ''}">${icon(it.icon, it.color)}<div class="nm">${esc(it.name)}</div><div class="ct">${count}</div>${actions}</div>`;
  }

  renderInventory(body) {
    const g = this.game;
    const s = g.state;
    const items = Object.entries(s.inventory).filter(([, n]) => n > 0);
    const used = g.inventoryUsed();
    const atStation = this.pdaMode === 'station';
    const cards = items.map(([type, n]) => {
      let act = '';
      if (type === 'medkit') act = `<button data-use="medkit">Use (H)</button>`;
      else if (atStation && !ITEMS[type].story) act = `<button data-store="${type}">Store</button>`;
      return this.itemCard(type, n, act);
    }).join('');
    let storage = '';
    if (atStation) {
      const st = Object.entries(s.storage).filter(([, n]) => n > 0);
      storage = `<div class="section-h">Station storage locker (used by the fabricator)</div>
        <div class="station-actions"><button data-act2="storeAll">Store all materials</button></div>
        <div class="inv-grid">${st.length ? st.map(([type, n]) => this.itemCard(type, n, `<button data-take="${type}">Take</button>`)).join('') : '<div class="empty">Locker is empty.</div>'}</div>`;
    }
    const hover = items.length ? '' : '<div class="empty">Your pockets are empty. Collect deposits with E.</div>';
    body.innerHTML = `<div class="pane"><div class="inv-head"><div class="eyebrow">Carried</div><div class="cap">${used} / ${INVENTORY_CAPACITY} units</div></div>
      <div class="inv-grid">${cards}</div>${hover}${storage}
      <div class="section-h">Materials</div><div class="panel-note" style="font-size:13px">${Object.entries(ITEMS).filter(([, v]) => !v.story && !v.consumable).map(([, v]) => `<b style="color:${v.color}">${esc(v.name)}</b> — ${esc(v.desc)}`).join('<br>')}</div></div>`;
    body.querySelectorAll('[data-use]').forEach((b) => b.addEventListener('click', () => { g.useMedkit(); this.renderPDA(); }));
    body.querySelectorAll('[data-store]').forEach((b) => b.addEventListener('click', () => { g.store(b.dataset.store); this.renderPDA(); }));
    body.querySelectorAll('[data-take]').forEach((b) => b.addEventListener('click', () => { g.take(b.dataset.take); this.renderPDA(); }));
    body.querySelectorAll('[data-act2=storeAll]').forEach((b) => b.addEventListener('click', () => { g.storeAll(); this.renderPDA(); }));
  }

  renderFabricator(body) {
    const g = this.game;
    const mode = this.pdaMode;
    const s = g.state;
    const rows = RECIPES.filter((r) => r.known || s.blueprints.includes(r.blueprint)).map((r) => {
      const check = g.canCraft(r, mode);
      const cost = Object.entries(r.cost).map(([k, n]) => {
        const have = g.available(k, mode);
        return `<span class="${have >= n ? 'ok' : 'no'}">${esc(ITEMS[k].name)} ${Math.min(have, n)}/${n}</span>`;
      }).join('');
      return `<div class="recipe ${check.ok || check.reason === 'materials' ? '' : 'locked'}">
        <div class="r-name">${esc(r.name)}</div>
        <div class="r-desc">${esc(r.desc)}${!check.ok && check.reason !== 'materials' ? ` <span style="color:var(--amber)">— ${esc(check.text)}</span>` : ''}</div>
        <div class="r-cost">${cost}</div>
        <button data-craft="${r.id}" ${check.ok ? '' : 'disabled'}>Fabricate</button></div>`;
    }).join('');
    const unknown = RECIPES.filter((r) => !r.known && !s.blueprints.includes(r.blueprint)).length;
    let header = '';
    if (mode === 'station') {
      header = `<div class="station-actions">
        <button data-st="save">Save expedition</button>
        <button data-st="storeAll">Store all materials</button>
        <span class="panel-note" style="margin:0;align-self:center;font-size:12px">${s.flags.power ? 'Main power online. Upgrade bay and fabricator available.' : 'EMERGENCY POWER — fabricator limited to essential items.'}</span></div>`;
    } else {
      header = '<div class="panel-note" style="margin-top:0;font-size:13px">Kestrel field fabricator: consumables only. Upgrades require Meridian Station’s upgrade bay.</div>';
    }
    body.innerHTML = `<div class="pane">${header}<div class="recipes">${rows}</div>
      ${unknown ? `<div class="section-h">${unknown} blueprint${unknown > 1 ? 's' : ''} not yet acquired — scan fragments and read crew logs</div>` : ''}</div>`;
    body.querySelectorAll('[data-craft]').forEach((b) => b.addEventListener('click', () => { g.craft(b.dataset.craft, mode); this.renderPDA(); }));
    body.querySelectorAll('[data-st=save]').forEach((b) => b.addEventListener('click', () => { g.saveGame(true); }));
    body.querySelectorAll('[data-st=storeAll]').forEach((b) => b.addEventListener('click', () => { g.storeAll(); this.renderPDA(); }));
  }

  renderStatus() {
    const g = this.game;
    const s = g.state;
    const ups = Object.entries(UPGRADES).map(([k, u]) => {
      const lvl = s.upgrades[k];
      const val = u.levels[lvl];
      return `<div class="upgrade"><div class="eyebrow">${esc(u.label)}</div><div class="u-name">${esc(u.name)}${lvl ? ` Mk ${lvl + 1}` : ''}</div><div class="u-val">${val}${u.unit === '×' ? '×' : ` ${u.unit}`}</div><div class="pips">${u.levels.map((_, i) => `<i class="${i <= lvl ? 'on' : ''}"></i>`).join('')}</div></div>`;
    }).join('');
    return `<div class="pane"><div class="eyebrow">Equipment &amp; upgrades</div><div class="upgrade-list" style="margin-top:14px">${ups}</div>
      <div class="section-h">Kestrel</div>
      <div class="stats-row" style="margin-top:0"><div><b>${s.flags.power ? (g.sub.online ? 'Online' : 'Offline') : 'No power'}</b>Status</div><div><b>${Math.round(g.sub.hull)}%</b>Hull</div><div><b>${Math.round(g.sub.power)}%</b>Power</div><div><b>${g.hullRating} m</b>Crush depth</div></div>
      <div class="section-h">Suit</div>
      <div class="stats-row" style="margin-top:0"><div><b>${Math.round(s.health)}</b>Vitals</div><div><b>${Math.round(g.o2Max)} s</b>O₂ capacity</div><div><b>${g.suitRating} m</b>Depth rating</div><div><b>${s.inventory.medkit || 0}</b>Medkits</div></div></div>`;
  }

  // ---------------------------------------------------------------- sequences
  async intro(lines) {
    this.only('intro');
    const el = $('introText');
    el.innerHTML = '';
    let skip = false;
    const onKey = (e) => { if (e.code === 'Space' || e.code === 'Enter' || e.code === 'Escape') skip = true; };
    const onClick = () => { skip = true; };
    window.addEventListener('keydown', onKey);
    $('intro').addEventListener('click', onClick);
    for (const line of lines) {
      if (skip) break;
      const p = document.createElement('div');
      if (line.dim) p.className = 'dim';
      el.appendChild(p);
      for (let i = 0; i <= line.text.length; i++) {
        if (skip) { p.textContent = line.text; break; }
        p.textContent = line.text.slice(0, i);
        if (i % 3 === 0) this.game.audio.tone({ freq: 1800 + Math.random() * 300, dur: 0.012, gain: 0.012, bus: 'ui', reverb: 0 });
        await wait(18);
      }
      await wait(line.pause ?? 600);
    }
    window.removeEventListener('keydown', onKey);
    $('intro').removeEventListener('click', onClick);
    if (!skip) await wait(600);
    this.hide('intro');
  }

  showDeath(text) {
    $('deathText').textContent = text;
    this.only('death');
  }

  async ending(lines, stats) {
    this.only('ending');
    $('endingCard').classList.add('hidden');
    const box = $('endingLines');
    box.innerHTML = '';
    box.style.display = '';
    for (const l of lines) {
      const p = document.createElement('p');
      p.textContent = l;
      box.appendChild(p);
      await wait(3600);
    }
    await wait(1500);
    box.style.display = 'none';
    $('endingStats').innerHTML = stats.map(([k, v]) => `<div><b>${esc(v)}</b>${esc(k)}</div>`).join('');
    $('endingCard').classList.remove('hidden');
  }
}

function wait(ms) { return new Promise((r) => setTimeout(r, ms)); }

export function formatTime(sec) {
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
  return h ? `${h}h ${m}m` : `${m}m`;
}

export { SITES };
