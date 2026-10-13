// The Kestrel: a two-seat research submersible. Pilotable in first person
// with a cockpit overlay; has power, hull integrity and a depth rating.

import * as THREE from 'three';
import { waterMat } from '../world/shading.js';
import { panelTexture, labelTexture } from '../world/textures.js';
import { clamp } from '../core/noise.js';

const _v = new THREE.Vector3();
const _f = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _e = new THREE.Euler(0, 0, 0, 'YXZ');

export const SUB_RADIUS = 2.1;

export class Kestrel {
  constructor(scene, collision) {
    this.collision = collision;
    this.pos = new THREE.Vector3();
    this.vel = new THREE.Vector3();
    this.yaw = 0;
    this.pitch = 0;
    this.roll = 0;
    this.power = 0;
    this.hull = 100;
    this.thrust = 0;
    this.lightsOn = true;
    this.online = false;
    this.docked = true;
    this.group = this.buildModel();
    scene.add(this.group);
    this.light = new THREE.SpotLight(0xd8f4ff, 0, 95, 0.55, 0.55, 1.0);
    this.light.position.set(0, 0.2, 2.6);
    this.light.target.position.set(0, -0.6, 20);
    this.group.add(this.light);
    this.group.add(this.light.target);
  }

  buildModel() {
    const g = new THREE.Group();
    const tex = panelTexture('#e4e1d8', 11, 0.3);
    tex.repeat.set(2, 1);
    const hullM = waterMat({ map: tex, roughness: 0.45, metalness: 0.2 });
    const darkM = waterMat({ color: 0x3b4148, roughness: 0.6, metalness: 0.3 });
    const orangeM = waterMat({ color: 0xd8692a, roughness: 0.5 });
    const glassM = waterMat({ color: 0x8fd8ff, roughness: 0.05, metalness: 0.1, transparent: true, opacity: 0.35, depthWrite: false });
    this.lampM = waterMat({ color: 0x111111, emissive: 0xd8f4ff, emissiveIntensity: 3 });
    const body = new THREE.Mesh(new THREE.SphereGeometry(1, 32, 20), hullM);
    body.scale.set(1.5, 1.25, 2.9);
    g.add(body);
    const stripe = new THREE.Mesh(new THREE.TorusGeometry(1.42, 0.06, 6, 40), orangeM);
    stripe.scale.set(1, 0.86, 1);
    stripe.position.z = -0.6;
    g.add(stripe);
    const canopy = new THREE.Mesh(new THREE.SphereGeometry(1.05, 28, 16, 0, Math.PI * 2, 0, Math.PI * 0.55), glassM);
    canopy.rotation.x = Math.PI / 2;
    canopy.position.set(0, 0.15, 1.9);
    g.add(canopy);
    for (const sx of [-1, 1]) {
      const pod = new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.42, 2.4, 16), darkM);
      pod.rotation.x = Math.PI / 2;
      pod.position.set(sx * 1.75, -0.3, -1.2);
      g.add(pod);
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.46, 0.06, 6, 20), orangeM);
      ring.position.set(sx * 1.75, -0.3, -2.4);
      g.add(ring);
      const lamp = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.22, 0.25, 12), this.lampM);
      lamp.rotation.x = Math.PI / 2;
      lamp.position.set(sx * 1.05, -0.55, 2.2);
      g.add(lamp);
      const fin = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.9, 1.0), darkM);
      fin.position.set(sx * 0.6, 1.1, -2.3);
      fin.rotation.z = sx * 0.3;
      g.add(fin);
    }
    const tail = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.25, 0.8, 16), darkM);
    tail.rotation.x = Math.PI / 2;
    tail.position.z = -3.1;
    g.add(tail);
    this.prop = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.12, 0.05), darkM);
    this.prop.position.z = -3.55;
    g.add(this.prop);
    // manipulator arm
    const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.07, 1.2, 8), darkM);
    arm.rotation.x = 1.0;
    arm.position.set(0.7, -1.1, 1.8);
    g.add(arm);
    const lbl = new THREE.Mesh(new THREE.PlaneGeometry(1.8, 0.35), waterMat({ map: labelTexture('KESTREL', '#2b3138'), transparent: true }));
    lbl.position.set(1.49, 0.25, -0.3);
    lbl.rotation.y = Math.PI / 2;
    g.add(lbl);
    const lbl2 = lbl.clone();
    lbl2.position.x = -1.49;
    lbl2.rotation.y = -Math.PI / 2;
    g.add(lbl2);
    this.statusLight = new THREE.Mesh(new THREE.SphereGeometry(0.08, 8, 6), waterMat({ color: 0x111111, emissive: 0xff3b2b, emissiveIntensity: 3 }));
    this.statusLight.position.set(0, 1.25, -0.6);
    g.add(this.statusLight);
    return g;
  }

  /** Cockpit frame shown in first person when piloting (added to the viewmodel scene). */
  buildCockpit() {
    const g = new THREE.Group();
    const frameM = new THREE.MeshStandardMaterial({ color: 0x1a1f25, roughness: 0.7, metalness: 0.4 });
    const accentM = new THREE.MeshStandardMaterial({ color: 0x2a3138, roughness: 0.6, metalness: 0.4 });
    // canopy struts
    for (const sx of [-1, 1]) {
      const strut = new THREE.Mesh(new THREE.BoxGeometry(0.06, 1.4, 0.06), frameM);
      strut.position.set(sx * 0.62, 0.1, -0.85);
      strut.rotation.z = sx * -0.45;
      strut.rotation.x = 0.35;
      g.add(strut);
    }
    const top = new THREE.Mesh(new THREE.TorusGeometry(0.95, 0.04, 6, 32, Math.PI), frameM);
    top.position.set(0, -0.15, -0.95);
    top.rotation.x = -0.25;
    g.add(top);
    // dashboard
    const dash = new THREE.Mesh(new THREE.BoxGeometry(1.7, 0.32, 0.55), accentM);
    dash.position.set(0, -0.56, -0.72);
    dash.rotation.x = 0.4;
    g.add(dash);
    this.dashCanvas = document.createElement('canvas');
    this.dashCanvas.width = 512; this.dashCanvas.height = 128;
    this.dashTex = new THREE.CanvasTexture(this.dashCanvas);
    this.dashTex.colorSpace = THREE.SRGBColorSpace;
    const scr = new THREE.Mesh(new THREE.PlaneGeometry(1.2, 0.3), new THREE.MeshBasicMaterial({ map: this.dashTex, toneMapped: false }));
    scr.position.set(0, -0.4, -0.58);
    scr.rotation.x = -0.75;
    g.add(scr);
    // control sticks
    for (const sx of [-1, 1]) {
      const stick = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.03, 0.25, 8), frameM);
      stick.position.set(sx * 0.35, -0.62, -0.45);
      stick.rotation.x = -0.4;
      g.add(stick);
    }
    this.cockpit = g;
    g.visible = false;
    return g;
  }

  drawDash(depthRating) {
    if (!this.dashCanvas) return;
    const c = this.dashCanvas.getContext('2d');
    c.fillStyle = '#04121a';
    c.fillRect(0, 0, 512, 128);
    c.font = '600 22px "IBM Plex Mono", monospace';
    const depth = Math.max(0, -this.pos.y);
    const warn = depth > depthRating * 0.9;
    const cols = [
      ['DEPTH', `${depth.toFixed(0)} m`, warn ? '#ff6a5a' : '#8ff4ff'],
      ['HULL', `${this.hull.toFixed(0)}%`, this.hull < 35 ? '#ff6a5a' : '#8ff4ff'],
      ['POWER', `${this.power.toFixed(0)}%`, this.power < 20 ? '#ffb25a' : '#8ff4ff'],
      ['SPEED', `${this.vel.length().toFixed(1)}`, '#8ff4ff'],
    ];
    cols.forEach(([k, v, col], i) => {
      c.fillStyle = 'rgba(143,244,255,0.55)';
      c.fillText(k, 18 + i * 124, 42);
      c.fillStyle = col;
      c.font = '600 30px "IBM Plex Mono", monospace';
      c.fillText(v, 18 + i * 124, 86);
      c.font = '600 22px "IBM Plex Mono", monospace';
    });
    c.fillStyle = 'rgba(143,244,255,0.25)';
    c.fillRect(18, 104, 476, 6);
    c.fillStyle = warn ? '#ff6a5a' : '#8ff4ff';
    c.fillRect(18, 104, 476 * clamp(depth / depthRating, 0, 1), 6);
    this.dashTex.needsUpdate = true;
  }

  place(p, yaw) {
    this.pos.copy(p);
    this.vel.set(0, 0, 0);
    this.yaw = yaw;
    this.pitch = 0;
    this.syncModel();
  }

  syncModel() {
    this.group.position.copy(this.pos);
    _e.set(-this.pitch, this.yaw + Math.PI, -this.roll); // model nose is +z, so mirror pitch/roll
    this.group.quaternion.setFromEuler(_e);
  }

  forward(out = _f) {
    const cp = Math.cos(this.pitch);
    return out.set(-Math.sin(this.yaw) * cp, Math.sin(this.pitch), -Math.cos(this.yaw) * cp);
  }

  /** Pilot update. Returns collision impact speed (for damage). */
  pilot(dt, input, settings, mouse) {
    const s = 0.0018 * settings.sensitivity;
    this.yaw -= mouse[0] * s;
    this.pitch = clamp(this.pitch - mouse[1] * s * (settings.invertY ? -1 : 1), -1.1, 1.1);
    const f = this.forward();
    const r = _v.set(Math.cos(this.yaw), 0, -Math.sin(this.yaw));
    const acc = new THREE.Vector3();
    let thrust = 0;
    if (this.power > 0) {
      if (input.held('forward')) { acc.add(f); thrust += 1; }
      if (input.held('back')) { acc.addScaledVector(f, -0.6); thrust += 0.6; }
      if (input.held('right')) { acc.addScaledVector(r, 0.6); thrust += 0.4; }
      if (input.held('left')) { acc.addScaledVector(r, -0.6); thrust += 0.4; }
      if (input.held('up')) { acc.y += 0.7; thrust += 0.4; }
      if (input.held('down')) { acc.y -= 0.7; thrust += 0.4; }
    }
    const boost = input.held('sprint') && this.power > 5 ? 1.5 : 1;
    const maxSpeed = 11 * boost;
    acc.multiplyScalar(maxSpeed * 1.4);
    this.vel.add(acc.multiplyScalar(dt));
    this.vel.multiplyScalar(Math.exp(-1.4 * dt));
    if (this.power <= 0) this.vel.y -= 0.6 * dt; // sinks slowly without power
    this.thrust = THREE.MathUtils.lerp(this.thrust, Math.min(1, thrust) * boost, 1 - Math.exp(-dt * 4));
    this.power = Math.max(0, this.power - dt * (0.06 + this.thrust * 0.22 * boost + (this.lightsOn ? 0.02 : 0)));
    this.roll = THREE.MathUtils.lerp(this.roll, -this.vel.dot(r) * 0.03, 1 - Math.exp(-dt * 3));
    return this.integrate(dt);
  }

  idle(dt) {
    this.thrust = THREE.MathUtils.lerp(this.thrust, 0, 1 - Math.exp(-dt * 3));
    this.vel.multiplyScalar(Math.exp(-2 * dt));
    this.roll = THREE.MathUtils.lerp(this.roll, 0, 1 - Math.exp(-dt * 2));
    return this.integrate(dt);
  }

  integrate(dt) {
    const before = this.vel.length();
    this.pos.addScaledVector(this.vel, dt);
    if (this.pos.y > -1.4) { this.pos.y = -1.4; if (this.vel.y > 0) this.vel.y = 0; }
    const hit = this.collision.resolve(this.pos, SUB_RADIUS, this.vel);
    // nose sphere
    const nose = this.forward(_v).multiplyScalar(1.8).add(this.pos);
    const nhit = this.collision.resolve(nose, 1.2, this.vel);
    if (nhit) this.pos.copy(nose).sub(this.forward(_v).multiplyScalar(1.8));
    const after = this.vel.length();
    this.prop.rotation.z += this.thrust * dt * 30;
    this.syncModel();
    return (hit || nhit) ? Math.max(0, before - after) : 0;
  }

  cameraTransform(camera) {
    const f = this.forward(_v);
    camera.position.copy(this.pos).addScaledVector(f, 1.6);
    camera.position.y += 0.35;
    camera.rotation.order = 'YXZ';
    camera.rotation.set(this.pitch, this.yaw, this.roll);
  }

  setLights(on) {
    this.lightsOn = on;
    this.light.intensity = on && this.power > 0 ? 14 : 0;
    this.lampM.emissiveIntensity = on && this.power > 0 ? 3 : 0.1;
  }

  setOnline(on) {
    this.online = on;
    this.statusLight.material.emissive.set(on ? 0x6ff3ff : 0xff3b2b);
  }
}
