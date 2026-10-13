// Procedural creature geometry. Bodies run along +z (head) / -z (tail).

import * as THREE from 'three';
import * as G from '../world/geom.js';

/**
 * Body of revolution with elliptical cross-section.
 * profile(t) -> radius, t: 0 tail .. 1 head. hx/hy scale the ellipse.
 */
export function bodyGeometry({ length = 1, segs = 24, radial = 12, profile, hx = 1, hy = 1, color = 0xffffff, colorFn, glowFn, yOffset }) {
  const pos = [];
  const idx = [];
  for (let i = 0; i <= segs; i++) {
    const t = i / segs;
    const z = -length / 2 + t * length;
    const r = profile(t);
    const yo = yOffset ? yOffset(t) : 0;
    for (let k = 0; k <= radial; k++) {
      const a = (k / radial) * Math.PI * 2;
      pos.push(Math.cos(a) * r * hx, Math.sin(a) * r * hy + yo, z);
    }
  }
  for (let i = 0; i < segs; i++) {
    for (let k = 0; k < radial; k++) {
      const a = i * (radial + 1) + k, b = a + 1, c = a + radial + 1, d = c + 1;
      idx.push(a, b, d, a, d, c);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  g.computeVertexNormals();
  const out = G.prep(g, color, glowFn || 0);
  if (colorFn) G.colorize(out, colorFn);
  return out;
}

/** Flat fin from a list of 2D points in the (a, b) plane, placed by a transform function. */
export function finGeometry(points, color, glow = 0, plane = 'yz') {
  const shape = new THREE.Shape(points.map(([a, b]) => new THREE.Vector2(a, b)));
  const g = new THREE.ShapeGeometry(shape);
  if (plane === 'yz') g.rotateY(-Math.PI / 2); // shape (x, y) -> (0, y, x): x runs along the body
  if (plane === 'xz') g.rotateX(Math.PI / 2); // shape (x, y) -> (x, 0, y)
  return G.prep(g, color, glow);
}

export function glimmerfinGeometry() {
  const body = bodyGeometry({
    length: 1, segs: 14, radial: 8, hx: 0.42, hy: 0.85,
    profile: (t) => Math.sin(Math.pow(t, 0.75) * Math.PI) * 0.16 + 0.004,
    color: 0x9fb8c8,
    colorFn: (x, y, z, c) => {
      const belly = y < 0 ? 1.25 : 0.75;
      c.setRGB(0.55 * belly, 0.68 * belly, 0.78 * belly);
    },
    glowFn: (x, y, z) => (Math.abs(y) < 0.02 && z > -0.35 && z < 0.4 ? 1 : 0),
  });
  const tail = finGeometry([[0, 0], [-0.22, 0.17], [-0.17, 0], [-0.22, -0.17]], 0x7fa0b8, 0.25);
  tail.translate(0, 0, -0.46);
  const dorsal = finGeometry([[0.1, 0.1], [-0.05, 0.22], [-0.15, 0.1]], 0x7fa0b8);
  const eyeL = G.prep(new THREE.SphereGeometry(0.03, 6, 4).translate(0.055, 0.03, 0.32), 0x111111);
  const eyeR = G.prep(new THREE.SphereGeometry(0.03, 6, 4).translate(-0.055, 0.03, 0.32), 0x111111);
  return G.merge([body, tail, dorsal, eyeL, eyeR]);
}

export function drifterGeometry() {
  const parts = [];
  const bell = new THREE.SphereGeometry(1, 16, 7, 0, Math.PI * 2, 0, Math.PI * 0.5);
  bell.scale(1, 0.75, 1);
  parts.push(G.prep(bell, 0x6a4fa0, (x, y) => (y < 0.12 ? 0.9 : 0.25)));
  const inner = new THREE.SphereGeometry(0.45, 12, 8).scale(1, 0.8, 1).translate(0, 0.25, 0);
  parts.push(G.prep(inner, 0xa0f0ff, 1));
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * Math.PI * 2;
    const r = 0.75;
    const len = 2.2 + (i % 3) * 0.8;
    const pts = [];
    for (let k = 0; k <= 5; k++) pts.push(new THREE.Vector3(Math.cos(a) * r * (1 - k * 0.08), -k * (len / 5), Math.sin(a) * r * (1 - k * 0.08)));
    parts.push(G.tubeAlong(pts, 0.022, 0.006, 3, 0xd7c8ff, (x, y) => (y < -len * 0.8 ? 0.7 : 0.05), 8));
  }
  // oral arms
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * Math.PI * 2 + 0.4;
    const pts = [new THREE.Vector3(0, 0, 0), new THREE.Vector3(Math.cos(a) * 0.2, -0.8, Math.sin(a) * 0.2), new THREE.Vector3(Math.cos(a) * 0.1, -1.6, Math.sin(a) * 0.1)];
    parts.push(G.tubeAlong(pts, 0.07, 0.02, 4, 0xb090e0, () => 0.25, 6));
  }
  return G.merge(parts);
}

export function shellbackGeometry() {
  const parts = [];
  const shell = new THREE.SphereGeometry(1, 20, 12, 0, Math.PI * 2, 0, Math.PI * 0.55);
  shell.scale(0.85, 0.55, 1.2);
  const s = G.prep(shell, 0x8a7a60);
  G.colorize(s, (x, y, z, c) => {
    const band = Math.abs(Math.sin(z * 9)) > 0.8 ? 0.55 : 1;
    const ridge = Math.abs(x) < 0.08 ? 1.25 : 1;
    c.setRGB(0.55 * band * ridge, 0.47 * band * ridge, 0.36 * band * ridge);
  });
  parts.push(s);
  const under = new THREE.CylinderGeometry(0.82, 0.82, 0.15, 16).scale(1, 1, 1.4).translate(0, 0.02, 0);
  parts.push(G.prep(under, 0x4a4036));
  // glowing dorsal pores
  for (let i = 0; i < 5; i++) parts.push(G.prep(new THREE.SphereGeometry(0.05, 6, 4).translate(0, 0.52, -0.6 + i * 0.3), 0x66ffd0, 1));
  return G.merge(parts);
}

export function razormawGeometry() {
  const body = bodyGeometry({
    length: 4, segs: 30, radial: 10, hx: 0.75, hy: 1,
    profile: (t) => {
      const head = t > 0.86 ? 1 - (t - 0.86) / 0.14 * 0.55 : 1;
      return (0.06 + Math.pow(t, 0.6) * 0.32) * head;
    },
    color: 0x3a4a44,
    colorFn: (x, y, z, c) => {
      const stripe = Math.sin(z * 6) > 0.6 && y > 0 ? 0.55 : 1;
      const belly = y < -0.05 ? 1.6 : 1;
      c.setRGB(0.24 * stripe * belly, 0.30 * stripe * belly, 0.27 * stripe * belly);
    },
    glowFn: (x, y, z) => (Math.abs(y) < 0.04 && z < 1.5 && Math.sin(z * 10) > 0.3 ? 0.9 : 0),
  });
  const parts = [body];
  // jaws
  const jaw = new THREE.ConeGeometry(0.18, 0.7, 6).rotateX(Math.PI / 2).translate(0, -0.08, 2.15);
  parts.push(G.prep(jaw, 0x2a2420));
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * Math.PI * 2;
    parts.push(G.prep(new THREE.ConeGeometry(0.025, 0.14, 4).rotateX(Math.PI / 2 + 0.6).translate(Math.cos(a) * 0.14, Math.sin(a) * 0.12, 2.0), 0xe0e0d0));
  }
  // dorsal ridge fins
  for (let i = 0; i < 6; i++) {
    const fin = finGeometry([[0, 0], [-0.25, 0.35], [-0.45, 0]], 0x5a3a2a, 0.15);
    fin.translate(0, 0.25, 1.2 - i * 0.5);
    parts.push(fin);
  }
  const tail = finGeometry([[0, 0], [-0.6, 0.55], [-0.4, 0], [-0.6, -0.55]], 0x5a3a2a, 0.3);
  tail.translate(0, 0, -1.95);
  parts.push(tail);
  for (const sx of [-1, 1]) {
    const pec = finGeometry([[0, 0], [sx * 0.6, -0.35], [sx * 0.15, -0.5]], 0x5a3a2a, 0, 'xz');
    pec.translate(sx * 0.2, -0.1, 1.4);
    parts.push(pec);
    parts.push(G.prep(new THREE.SphereGeometry(0.05, 6, 4).translate(sx * 0.17, 0.08, 1.8), 0xffc040, 1));
  }
  return G.merge(parts);
}

export function cantorGeometry() {
  const L = 100;
  const body = bodyGeometry({
    length: L, segs: 60, radial: 18, hx: 0.85, hy: 0.7,
    profile: (t) => {
      const base = Math.sin(Math.pow(t, 0.55) * Math.PI) * 8.5 + 0.3;
      return base * (t > 0.92 ? 1 - (t - 0.92) * 4 : 1);
    },
    color: 0x2a3a4a,
    colorFn: (x, y, z, c) => {
      const belly = y < 0 ? 1.5 : 1;
      c.setRGB(0.16 * belly, 0.21 * belly, 0.27 * belly);
    },
    glowFn: (x, y, z) => {
      const row = Math.abs(y) < 1.5 && Math.abs(x) > 3;
      const spot = Math.sin(z * 0.9) > 0.85;
      const top = y > 4 && Math.sin(z * 0.5 + x) > 0.92;
      return (row && spot) || top ? 1 : 0;
    },
  });
  const parts = [body];
  for (const sx of [-1, 1]) {
    const fin = finGeometry([[0, 0], [sx * 26, -14], [sx * 30, -24], [sx * 8, -20]], 0x22303c, (x) => (Math.abs(x) > 24 ? 0.6 : 0), 'xz');
    fin.translate(sx * 6, -2, 30);
    parts.push(fin);
  }
  const fluke = finGeometry([[0, 0], [-12, 18], [-8, 0], [-12, -18]], 0x22303c, 0.2);
  // tail fluke horizontal: rotate to xz plane
  fluke.rotateZ(Math.PI / 2);
  fluke.translate(0, 0, -L / 2 + 2);
  parts.push(fluke);
  // head crest lanterns
  for (let i = 0; i < 6; i++) parts.push(G.prep(new THREE.SphereGeometry(0.9, 8, 6).translate(0, 5.5 - i * 0.3, 40 - i * 4), 0x9ff4ff, 1));
  return G.merge(parts);
}

export function veilRayGeometry() {
  const parts = [];
  const shape = new THREE.Shape();
  shape.moveTo(0, 0.9);
  shape.quadraticCurveTo(0.6, 0.6, 1.6, -0.1);
  shape.quadraticCurveTo(0.6, -0.15, 0, -0.7);
  shape.quadraticCurveTo(-0.6, -0.15, -1.6, -0.1);
  shape.quadraticCurveTo(-0.6, 0.6, 0, 0.9);
  const wing = new THREE.ShapeGeometry(shape, 10);
  wing.rotateX(-Math.PI / 2); // shape y -> -z ; flip so nose is +z
  wing.rotateY(Math.PI);
  const w = G.prep(wing, 0x8fb8e8, (x, y, z) => {
    const vein = Math.abs(Math.sin(Math.atan2(z, x) * 9)) > 0.93 ? 1 : 0;
    return Math.max(vein, Math.hypot(x, z) > 1.3 ? 0.6 : 0);
  });
  parts.push(w);
  const bodyG = bodyGeometry({ length: 1.4, segs: 10, radial: 8, hx: 1, hy: 0.4, profile: (t) => Math.sin(t * Math.PI) * 0.25 + 0.01, color: 0x6a8ab0, glowFn: () => 0.3 });
  parts.push(bodyG);
  const tail = G.tubeAlong([new THREE.Vector3(0, 0, -0.6), new THREE.Vector3(0, 0, -1.6), new THREE.Vector3(0, 0.05, -2.6)], 0.04, 0.01, 4, 0x8fb8e8, () => 0.8, 6);
  parts.push(tail);
  return G.merge(parts);
}

export function stalkerGeometry() {
  const body = bodyGeometry({
    length: 8, segs: 36, radial: 12, hx: 0.8, hy: 1,
    profile: (t) => {
      if (t > 0.78) return 0.9 * Math.sin(((t - 0.78) / 0.22) * Math.PI * 0.9 + 0.3) + 0.05; // skull bulb
      return 0.08 + Math.pow(t / 0.78, 0.8) * 0.55;
    },
    color: 0x1a1c22,
    colorFn: (x, y, z, c) => {
      const plate = Math.sin(z * 4) > 0.7 ? 0.6 : 1;
      c.setRGB(0.11 * plate, 0.11 * plate, 0.14 * plate);
    },
    glowFn: (x, y, z) => (z > 2.6 && Math.abs(Math.sin(x * 9) * Math.sin(y * 9)) > 0.6 ? 1 : (z < 2 && Math.abs(y) < 0.08 ? 0.4 : 0)),
  });
  const parts = [body];
  // inner lantern
  parts.push(G.prep(new THREE.SphereGeometry(0.45, 12, 8).translate(0, 0, 3.2), 0xff6040, 1));
  // jaw spikes
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * Math.PI * 2;
    parts.push(G.prep(new THREE.ConeGeometry(0.06, 0.6, 4).rotateX(Math.PI / 2 + 0.4).translate(Math.cos(a) * 0.55, Math.sin(a) * 0.55, 3.95), 0xcfc8b8));
  }
  // long whisker lures
  for (const sx of [-1, 1]) {
    parts.push(G.tubeAlong([new THREE.Vector3(sx * 0.5, 0.6, 3.4), new THREE.Vector3(sx * 1.4, 1.4, 4.4), new THREE.Vector3(sx * 1.8, 0.8, 5.6)], 0.04, 0.015, 4, 0x222222, (x, y, z) => (z > 5.3 ? 1 : 0), 6));
    const pec = finGeometry([[0, 0], [sx * 1.4, -0.8], [sx * 0.3, -1.2]], 0x16181c, 0, 'xz');
    pec.translate(sx * 0.5, -0.3, 1.8);
    parts.push(pec);
  }
  const tail = finGeometry([[0, 0], [-1.2, 0.9], [-0.8, 0], [-1.2, -0.9]], 0x16181c, 0.2);
  tail.translate(0, 0, -3.9);
  parts.push(tail);
  return G.merge(parts);
}
