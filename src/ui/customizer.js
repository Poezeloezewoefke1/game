// Diver customisation screen: swatch rows for every look option, a callsign
// field and a live, drag-to-rotate 3D preview of the full diver model.

import * as THREE from 'three';
import { LOOK_OPTIONS, DEFAULT_LOOK, sanitizeLook, randomLook } from '../player/look.js';
import { DiverModel } from '../player/diverModel.js';

const hex = (n) => `#${n.toString(16).padStart(6, '0')}`;

export class Customizer {
  /** onChange(look) is called on every edit (the game applies and saves it). */
  constructor(getLook, onChange) {
    this.getLook = getLook;
    this.onChange = onChange;
    this.canvas = document.getElementById('diverCanvas');
    this.optionsEl = document.getElementById('diverOptions');
    this.running = false;
    this.yaw = -0.5;
    this.drag = null;
    this.buildOptions();
    const c = this.canvas;
    c.addEventListener('pointerdown', (e) => { this.drag = { x: e.clientX, yaw: this.yaw }; c.setPointerCapture(e.pointerId); });
    c.addEventListener('pointermove', (e) => { if (this.drag) this.yaw = this.drag.yaw + (e.clientX - this.drag.x) * 0.012; });
    c.addEventListener('pointerup', () => { this.drag = null; });
  }

  buildOptions() {
    const el = this.optionsEl;
    el.innerHTML = '';
    const nameRow = document.createElement('div');
    nameRow.className = 'look-row';
    nameRow.innerHTML = '<label for="lookName">Callsign</label><input id="lookName" maxlength="14" spellcheck="false" autocomplete="off">';
    el.appendChild(nameRow);
    this.nameInput = nameRow.querySelector('input');
    this.nameInput.addEventListener('input', () => this.set({ name: this.nameInput.value }));
    this.nameInput.addEventListener('keydown', (e) => e.stopPropagation()); // typing never steers the diver
    for (const [k, def] of Object.entries(LOOK_OPTIONS)) {
      const row = document.createElement('div');
      row.className = 'look-row';
      const text = k === 'pattern';
      row.innerHTML = `<label>${def.label}<span data-name="${k}"></span></label><div class="look-swatches${text ? ' text' : ''}"></div>`;
      const box = row.querySelector('.look-swatches');
      for (const [v, opt] of Object.entries(def.options)) {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = text ? 'look-chip' : 'look-swatch';
        b.dataset.k = k; b.dataset.v = v;
        b.title = opt[0];
        if (text) b.textContent = opt[0];
        else if (k === 'scanner') b.style.background = `linear-gradient(135deg, ${hex(opt[1])} 55%, ${hex(opt[2])} 55%)`;
        else b.style.background = hex(opt[1]);
        b.addEventListener('click', () => this.set({ [k]: v }));
        box.appendChild(b);
      }
      el.appendChild(row);
    }
  }

  set(patch) {
    const look = sanitizeLook({ ...this.getLook(), ...patch });
    this.onChange(look);
    this.refresh(look);
  }

  randomize() { this.set({ ...randomLook(), name: this.getLook().name }); }
  reset() { this.set({ ...DEFAULT_LOOK }); }

  refresh(look = this.getLook()) {
    if (document.activeElement !== this.nameInput) this.nameInput.value = look.name;
    this.optionsEl.querySelectorAll('[data-k]').forEach((b) => b.classList.toggle('on', look[b.dataset.k] === b.dataset.v));
    this.optionsEl.querySelectorAll('[data-name]').forEach((s) => { s.textContent = LOOK_OPTIONS[s.dataset.name].options[look[s.dataset.name]][0]; });
    if (this.diver) this.diver.setLook(look);
  }

  ensureScene() {
    if (this.renderer) return;
    this.renderer = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: true, alpha: true });
    this.renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(30, 1, 0.05, 20);
    this.camera.position.set(0, -0.85, 5.6);
    this.camera.lookAt(0, -1.02, 0);
    this.scene.add(new THREE.HemisphereLight(0xbfe8f0, 0x0c1a22, 1.4));
    const key = new THREE.DirectionalLight(0xffffff, 2.4);
    key.position.set(2, 3, 3);
    this.scene.add(key);
    const rim = new THREE.DirectionalLight(0x6fd8ef, 1.6);
    rim.position.set(-3, 1, -2);
    this.scene.add(rim);
    // a simple studio environment so the visor and metal read
    const pm = new THREE.PMREMGenerator(this.renderer);
    const envScene = new THREE.Scene();
    envScene.background = new THREE.Color(0x14303c);
    const panel = new THREE.Mesh(new THREE.PlaneGeometry(6, 3), new THREE.MeshBasicMaterial({ color: 0xcfe8ee }));
    panel.position.set(0, 3, 2); panel.lookAt(0, 0, 0);
    envScene.add(panel);
    this.scene.environment = pm.fromScene(envScene, 0.04).texture;
    const floor = new THREE.Mesh(new THREE.CircleGeometry(0.9, 48), new THREE.MeshStandardMaterial({ color: 0x0e2430, roughness: 0.9, transparent: true, opacity: 0.8 }));
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = -2.42;
    this.scene.add(floor);
    this.diver = new DiverModel(this.getLook());
    this.scene.add(this.diver.root);
  }

  open() {
    this.ensureScene();
    this.refresh();
    if (this.running) return;
    this.running = true;
    let last = performance.now();
    const loop = (now) => {
      if (!this.running) return;
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
      if (w && h && (this.canvas.width !== Math.round(w * this.renderer.getPixelRatio()) || this.canvas.height !== Math.round(h * this.renderer.getPixelRatio()))) {
        this.renderer.setSize(w, h, false);
        this.camera.aspect = w / h;
        this.camera.updateProjectionMatrix();
      }
      if (!this.drag) this.yaw += dt * 0.35;
      this.diver.root.rotation.y = this.yaw;
      this.diver.update(dt, { speed: 0, t: now * 0.001 });
      this.renderer.render(this.scene, this.camera);
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }

  close() { this.running = false; }
}
