// First-person equipment: gloved hand holding the scanner, the wrist PDA,
// and the scan beam. Rendered in a separate scene over the world.

import * as THREE from 'three';
import { normalTexture } from '../world/surfaces.js';
import { roundedBox } from '../world/shapes.js';
import { makeGearMaterials, buildScanner, buildGlove, buildSleeve, applyLook } from './gear.js';
import { DEFAULT_LOOK } from './look.js';

export class ViewModel {
  constructor() {
    this.scene = new THREE.Scene();
    this.root = new THREE.Group();
    this.scene.add(this.root);
    this.hemi = new THREE.HemisphereLight(0x9fd8e8, 0x0a1a24, 1.2);
    this.scene.add(this.hemi);
    this.lamp = new THREE.PointLight(0xe8f6ff, 1.5, 3, 1.5);
    this.lamp.position.set(0.1, 0.25, 0.1);
    this.root.add(this.lamp);
    this.sway = new THREE.Vector2();
    this.reach = 0;
    this.pdaRaise = 0;
    this.scanPulse = 0;
    this.build();
  }

  build() {
    const M = makeGearMaterials();
    this.M = M;
    this.detailMats = [[M.suit, '0018', 3, 0.6], [M.glove, '0018', 5, 0.9], [M.accent, '0022', 2, 0.4], [M.scanBody, '0022', 1.5, 0.6], [M.rubber, '0018', 6, 1.0]];
    this.emitMat = M.emit;

    // ---- right arm: sleeve, glove and the Mk III scanner
    const hand = new THREE.Group();
    hand.position.set(0.24, -0.23, -0.44);
    hand.rotation.set(0.05, -0.18, 0.04);
    this.hand = hand;
    this.handBase = hand.position.clone();
    this.root.add(hand);
    this.sleeveR = buildSleeve(M, hand, [0.07, -0.36, 0.4], [0.03, -0.088, 0.012], 0.078, 0.05, 'bands');
    const scanner = buildScanner(M);
    scanner.group.position.set(-0.004, 0, 0);
    hand.add(scanner.group);
    this.scanner = scanner;
    const glove = buildGlove(M);
    glove.group.position.set(-0.004, 0, 0);
    hand.add(glove.group);
    this.glove = glove;
    // screen on top of the scanner
    this.screenCanvas = document.createElement('canvas');
    this.screenCanvas.width = 128; this.screenCanvas.height = 80;
    this.screenTex = new THREE.CanvasTexture(this.screenCanvas);
    this.screenTex.colorSpace = THREE.SRGBColorSpace;
    const scr = new THREE.Mesh(new THREE.PlaneGeometry(0.05, 0.031), new THREE.MeshBasicMaterial({ map: this.screenTex, toneMapped: false }));
    scr.rotation.x = -Math.PI / 2;
    scr.position.set(0, 0.0046, 0);
    scanner.screenMount.add(scr);
    this.emitter = scanner.emitter;

    // ---- scan beam (cone attached to the emitter)
    const beamGeo = new THREE.CylinderGeometry(0.004, 0.25, 1, 20, 1, true);
    beamGeo.translate(0, -0.5, 0);
    beamGeo.rotateX(Math.PI / 2); // extends along -z
    this.beamMat = new THREE.ShaderMaterial({
      uniforms: { uTime: { value: 0 }, uStrength: { value: 0 }, uColor: { value: new THREE.Color(0x5fe8ff) } },
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
      fragmentShader: `uniform float uTime; uniform float uStrength; uniform vec3 uColor; varying vec2 vUv;
        void main(){
          float lines = smoothstep(0.6, 1.0, sin(vUv.y * 60.0 - uTime * 18.0) * 0.5 + 0.5);
          float edge = pow(abs(sin(vUv.x * 3.14159)), 0.5);
          float a = (0.12 + lines * 0.5) * edge * uStrength * (1.0 - vUv.y * 0.2);
          gl_FragColor = vec4(uColor * 0.85 * a, 1.0);
        }`,
    });
    this.beam = new THREE.Mesh(beamGeo, this.beamMat);
    this.beam.visible = false;
    this.emitter.add(this.beam);

    // ---- left arm with the wrist computer
    const left = new THREE.Group();
    left.position.set(-0.32, -0.75, -0.5);
    this.left = left;
    this.root.add(left);
    this.sleeveL = buildSleeve(M, left, [0.02, -0.3, 0.42], [0, 0.0, 0.02], 0.074, 0.054, 'bands');
    const pda = new THREE.Group();
    pda.position.set(0, 0.035, -0.02);
    pda.rotation.x = 0.6;
    left.add(pda);
    pda.add(new THREE.Mesh(roundedBox(0.12, 0.034, 0.13, 0.012, 3), M.scanBody));
    const bezel = new THREE.Mesh(roundedBox(0.1, 0.006, 0.1, 0.006, 2), M.rubber);
    bezel.position.y = 0.018;
    pda.add(bezel);
    const pdaScreen = new THREE.Mesh(new THREE.PlaneGeometry(0.084, 0.084), this.emitMat);
    pdaScreen.rotation.x = -Math.PI / 2;
    pdaScreen.position.set(0, 0.0215, 0);
    pda.add(pdaScreen);
    for (let k = 0; k < 3; k++) {
      const b = new THREE.Mesh(new THREE.CylinderGeometry(0.006, 0.006, 0.006, 10), M.scanAccent);
      b.rotation.z = Math.PI / 2;
      b.position.set(0.062, 0.004, -0.03 + k * 0.03);
      pda.add(b);
    }
    for (const z of [-0.07, 0.07]) {
      const strap = new THREE.Mesh(roundedBox(0.13, 0.02, 0.026, 0.008, 2), M.rubber);
      strap.position.set(0, -0.01, z);
      pda.add(strap);
    }
    const lglove = new THREE.Mesh(roundedBox(0.08, 0.055, 0.1, 0.02, 3), M.glove);
    lglove.position.set(0, -0.01, -0.12);
    lglove.rotation.x = 0.6;
    left.add(lglove);
    this.applyLook(DEFAULT_LOOK);
  }

  /** Recolour the arms and scanner from a diver look; rebuilds sleeves for the pattern. */
  applyLook(look) {
    const c = applyLook(this.M, look);
    this.look = look;
    this.beamMat.uniforms.uColor.value.setHex(c.beam);
    this.beamHex = `#${c.beam.toString(16).padStart(6, '0')}`;
    if (this.sleevePattern !== look.pattern) {
      this.sleevePattern = look.pattern;
      for (const [k, parent, a, b, rA, rB] of [['sleeveR', this.hand, [0.07, -0.36, 0.4], [0.03, -0.088, 0.012], 0.078, 0.05], ['sleeveL', this.left, [0.02, -0.3, 0.42], [0, 0.0, 0.02], 0.074, 0.054]]) {
        parent.remove(this[k]);
        this[k] = buildSleeve(this.M, parent, a, b, rA, rB, look.pattern);
      }
    }
  }

  drawScreen(text, progress, color = this.beamHex || '#5fe8ff') {
    const c = this.screenCanvas.getContext('2d');
    c.fillStyle = '#031016';
    c.fillRect(0, 0, 128, 80);
    c.globalAlpha = 0.5;
    c.fillStyle = color;
    c.font = '600 10px "IBM Plex Mono", monospace';
    c.fillText(`MK III  ${(this.look?.name || '').slice(0, 10)}`, 6, 14);
    c.fillRect(6, 19, 116, 1);
    c.globalAlpha = 1;
    c.font = '600 14px "IBM Plex Mono", monospace';
    c.fillText(text.slice(0, 14), 6, 40);
    c.globalAlpha = 0.25;
    c.fillRect(6, 54, 116, 10);
    c.globalAlpha = 1;
    c.fillRect(6, 54, 116 * Math.max(0, Math.min(1, progress)), 10);
    this.screenTex.needsUpdate = true;
  }

  pickup() { this.reach = 1; }

  /** Enable photoreal detail: normal maps and reflections (skipped in classic mode). */
  enhance(envMap) {
    for (const [m, id, rep, k] of this.detailMats) {
      const t = normalTexture(id).clone();
      t.repeat.set(rep, rep);
      t.needsUpdate = true;
      m.normalMap = t;
      m.normalScale.set(k, k);
      m.needsUpdate = true;
    }
    this.scene.environment = envMap;
    this.enhanced = true;
  }

  attachCockpit(group) {
    this.cockpit = group;
    this.root.add(group);
  }

  update(dt, camera, opts) {
    const { mouse, speed, bob, scanning, scanTarget, visible, pdaOpen, lampOn, ambient, time, cockpit } = opts;
    this.root.visible = visible || !!cockpit;
    this.hand.visible = visible;
    if (this.cockpit) this.cockpit.visible = !!cockpit;
    this.root.position.copy(camera.position);
    this.root.quaternion.copy(camera.quaternion);
    this.root.updateMatrixWorld(true);
    // sway lags behind look motion
    this.sway.x = THREE.MathUtils.lerp(this.sway.x, -mouse[0] * 0.0006, 1 - Math.exp(-dt * 8));
    this.sway.y = THREE.MathUtils.lerp(this.sway.y, mouse[1] * 0.0006, 1 - Math.exp(-dt * 8));
    this.reach = Math.max(0, this.reach - dt * 3);
    const r = Math.sin(this.reach * Math.PI);
    this.scanPulse = THREE.MathUtils.lerp(this.scanPulse, scanning ? 1 : 0, 1 - Math.exp(-dt * 10));
    const bobA = Math.min(1, speed / 6);
    this.hand.position.set(
      this.handBase.x + this.sway.x + Math.cos(bob) * 0.008 * bobA - r * 0.06,
      this.handBase.y + this.sway.y + Math.sin(bob * 2) * 0.01 * bobA + this.scanPulse * 0.03 + Math.sin(time * 1.3) * 0.004,
      this.handBase.z - r * 0.15 - this.scanPulse * 0.06,
    );
    this.hand.rotation.y = -0.12 - this.scanPulse * 0.1 + this.sway.x;
    this.pdaRaise = THREE.MathUtils.lerp(this.pdaRaise, pdaOpen ? 1 : 0, 1 - Math.exp(-dt * 9));
    this.left.position.set(-0.32 + this.pdaRaise * 0.18, -0.75 + this.pdaRaise * 0.42, -0.5);
    this.left.visible = visible && this.pdaRaise > 0.02;
    this.emitMat.emissiveIntensity = 1.2 + this.scanPulse * 2 + Math.sin(time * 4) * 0.2;
    // trigger pull, finned collar spin-up, status LED and battery gauge
    const sc = this.scanner;
    sc.trigger.rotation.x = this.scanPulse * 0.35;
    this.glove.index.rotation.z = -this.scanPulse * 0.25;
    this.rotorSpeed = THREE.MathUtils.lerp(this.rotorSpeed || 0.3, scanning ? 14 : 0.3, 1 - Math.exp(-dt * 3));
    sc.rotor.rotation.z += dt * this.rotorSpeed;
    sc.led.material.emissiveIntensity = scanning ? (Math.sin(time * 22) > 0 ? 3 : 0.3) : 1.2 + Math.sin(time * 2) * 0.8;
    const bat = opts.battery ?? 1;
    sc.cells.forEach((cell, k) => { cell.material.emissiveIntensity = bat > (k + 0.5) / 4 ? 1.4 : 0.05; cell.material.emissive.copy(this.M.emit.emissive); });
    this.M.lens.emissiveIntensity = 0.5 + this.scanPulse * 2.5;
    this.hemi.intensity = ambient * (this.enhanced ? 0.8 : 1);
    if (this.enhanced) this.scene.environmentIntensity = Math.min(1, ambient * 0.5) + (lampOn ? 0.05 : 0);
    this.lamp.intensity = lampOn ? 1.6 : 0.05;
    // beam
    if (scanning && scanTarget) {
      this.beam.visible = true;
      const wp = new THREE.Vector3();
      this.emitter.getWorldPosition(wp);
      const dist = wp.distanceTo(scanTarget);
      this.emitter.lookAt(scanTarget);
      this.emitter.rotateY(Math.PI); // cone extends along -z
      this.beam.scale.set(1 + dist * 0.15, 1 + dist * 0.15, dist);
      this.beamMat.uniforms.uStrength.value = this.scanPulse;
    } else {
      this.beam.visible = false;
      this.emitter.rotation.set(0, 0, 0);
    }
    this.beamMat.uniforms.uTime.value = time;
  }
}
