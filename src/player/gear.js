// Diver gear shared by the first-person view and the full diver model:
// the Mk III field scanner, an articulated glove and suit sleeves.
// Materials are recoloured from a Look (see look.js).

import * as THREE from 'three';
import { roundedBox, lathe, place } from '../world/shapes.js';
import { lookColors } from './look.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);

export function makeGearMaterials() {
  const std = (c, r, m = 0) => new THREE.MeshStandardMaterial({ color: c, roughness: r, metalness: m });
  return {
    suit: std(0xd9d6cc, 0.72),
    suitDark: std(0x2a2e33, 0.8),
    accent: std(0xd8692a, 0.55),
    glove: std(0x3a3f45, 0.85),
    rubber: std(0x15171a, 0.92),
    metal: std(0x9aa1a8, 0.3, 1),
    scanBody: std(0x23292f, 0.38, 0.55),
    scanAccent: std(0xd8692a, 0.5, 0.1),
    visor: new THREE.MeshStandardMaterial({ color: 0xc8963c, roughness: 0.08, metalness: 1 }),
    emit: new THREE.MeshStandardMaterial({ color: 0x062028, emissive: 0x5fe8ff, emissiveIntensity: 1.5 }),
    lens: new THREE.MeshStandardMaterial({ color: 0x0a1418, emissive: 0x5fe8ff, emissiveIntensity: 0.6, roughness: 0.05, metalness: 0.2 }),
    hazard: new THREE.MeshStandardMaterial({ map: hazardTex(), roughness: 0.6 }),
  };
}

let _hz = null;
function hazardTex() {
  if (_hz) return _hz;
  const c = document.createElement('canvas');
  c.width = 128; c.height = 32;
  const g = c.getContext('2d');
  g.fillStyle = '#e0b030'; g.fillRect(0, 0, 128, 32);
  g.fillStyle = '#16181a';
  for (let x = -32; x < 160; x += 24) { g.beginPath(); g.moveTo(x, 32); g.lineTo(x + 12, 32); g.lineTo(x + 24, 0); g.lineTo(x + 12, 0); g.fill(); }
  _hz = new THREE.CanvasTexture(c);
  _hz.colorSpace = THREE.SRGBColorSpace;
  _hz.wrapS = THREE.RepeatWrapping;
  _hz.repeat.set(3, 1);
  return _hz;
}

export function applyLook(mats, look) {
  const c = lookColors(look);
  mats.suit.color.setHex(c.suit);
  mats.accent.color.setHex(c.accent);
  mats.glove.color.setHex(c.glove);
  mats.visor.color.setHex(c.visor);
  mats.scanBody.color.setHex(c.scanBody);
  mats.scanAccent.color.setHex(c.scanAccent);
  mats.emit.emissive.setHex(c.beam);
  mats.lens.emissive.setHex(c.beam);
  return c;
}

const mesh = (geo, mat, parent, pos, rot, scale) => {
  const m = new THREE.Mesh(geo, mat);
  if (pos) m.position.set(...pos);
  if (rot) m.rotation.set(...rot);
  if (scale) m.scale.set(...scale);
  parent.add(m);
  return m;
};

/**
 * Mk III field scanner. Local frame: hand grip point at the origin, the
 * emitter points along -z, the screen faces +y. Length ~0.24 m.
 */
export function buildScanner(M) {
  const g = new THREE.Group();
  // main housing with a raised spine and inset side panels
  mesh(roundedBox(0.064, 0.054, 0.16, 0.014, 3), M.scanBody, g, [0, 0.028, -0.072]);
  mesh(roundedBox(0.03, 0.012, 0.085, 0.005, 2), M.scanAccent, g, [0, 0.058, -0.098]);
  for (const s of [-1, 1]) {
    mesh(roundedBox(0.004, 0.03, 0.09, 0.0015, 1), M.scanAccent, g, [s * 0.0325, 0.03, -0.07]);
    for (const z of [-0.028, -0.112]) mesh(new THREE.CylinderGeometry(0.0028, 0.0028, 0.003, 8), M.metal, g, [s * 0.0335, 0.044, z], [0, 0, Math.PI / 2]);
  }
  // ergonomic grip with finger grooves, raked back
  const grip = new THREE.Group();
  grip.position.set(0, 0.004, -0.03);
  grip.rotation.x = 0.28;
  g.add(grip);
  const gripGeo = lathe({ z0: 0, z1: 0.1, segs: 20, radial: 16, squareness: 0.55, capStart: true, capEnd: true, section: (t) => {
    const groove = t > 0.25 && t < 0.85 ? 1 - 0.07 * Math.max(0, Math.sin((t - 0.25) / 0.6 * Math.PI * 3)) : 1;
    return { r: 0.019 * groove * (1 + 0.15 * Math.sin(t * Math.PI)), hx: 0.85, hy: 1.1 };
  } });
  gripGeo.rotateX(Math.PI / 2); // z -> -y : grip hangs down
  mesh(gripGeo, M.rubber, grip);
  mesh(roundedBox(0.04, 0.012, 0.05, 0.005, 2), M.scanBody, grip, [0, -0.1, 0.004]); // butt plate
  // trigger and guard
  const trigger = new THREE.Group();
  trigger.position.set(0, -0.004, -0.058);
  g.add(trigger);
  mesh(new THREE.TorusGeometry(0.012, 0.0035, 6, 12, Math.PI * 0.7), M.scanAccent, trigger, [0, -0.01, 0], [0, Math.PI / 2, -0.3]);
  mesh(new THREE.TorusGeometry(0.024, 0.0028, 6, 16, Math.PI), M.scanBody, g, [0, -0.004, -0.05], [0, Math.PI / 2, Math.PI]);
  // emitter head: shroud, rotating finned collar, recessed lens and sensor dots
  const headZ = -0.168;
  mesh(new THREE.CylinderGeometry(0.036, 0.031, 0.05, 28, 1, true), M.scanBody, g, [0, 0.028, headZ], [Math.PI / 2, 0, 0]);
  mesh(new THREE.CylinderGeometry(0.031, 0.031, 0.05, 28, 1, true), M.shroudIn || (M.shroudIn = new THREE.MeshStandardMaterial({ color: 0x0c0e10, roughness: 0.9, side: THREE.BackSide })), g, [0, 0.028, headZ], [Math.PI / 2, 0, 0]);
  const rotor = new THREE.Group();
  rotor.position.set(0, 0.028, headZ + 0.012);
  g.add(rotor);
  for (let k = 0; k < 10; k++) {
    const a = (k / 10) * Math.PI * 2;
    mesh(roundedBox(0.004, 0.012, 0.018, 0.0015, 1), M.metal, rotor, [Math.cos(a) * 0.04, Math.sin(a) * 0.04, 0], [0, 0, a]);
  }
  mesh(new THREE.TorusGeometry(0.04, 0.003, 6, 32), M.metal, rotor);
  mesh(new THREE.TorusGeometry(0.0335, 0.004, 8, 32), M.scanAccent, g, [0, 0.028, headZ - 0.026]);
  mesh(new THREE.CircleGeometry(0.024, 24), M.lens, g, [0, 0.028, headZ - 0.012], [0, Math.PI, 0]);
  mesh(new THREE.TorusGeometry(0.016, 0.0018, 6, 24), M.emit, g, [0, 0.028, headZ - 0.0135]);
  for (let k = 0; k < 3; k++) {
    const a = Math.PI / 2 + (k - 1) * 0.8;
    mesh(new THREE.SphereGeometry(0.0028, 6, 4), M.emit, g, [Math.cos(a) * 0.028, 0.028 + Math.sin(a) * 0.028, headZ - 0.024]);
  }
  // battery pack under the housing, with a 4-segment charge gauge
  mesh(roundedBox(0.05, 0.026, 0.06, 0.008, 2), M.scanBody, g, [0, -0.008, -0.118]);
  const cells = [];
  for (let k = 0; k < 4; k++) {
    const m = new THREE.MeshStandardMaterial({ color: 0x041014, emissive: 0x5fe8ff, emissiveIntensity: 1 });
    cells.push(mesh(new THREE.PlaneGeometry(0.008, 0.005), m, g, [0.0255, -0.008, -0.135 + k * 0.011], [0, Math.PI / 2, 0]));
  }
  // rear heat sink and lanyard loop
  // vent slots along the rear flanks
  for (const s of [-1, 1]) for (let k = 0; k < 4; k++) mesh(roundedBox(0.002, 0.026, 0.004, 0.001, 1), M.rubber, g, [s * 0.0325, 0.028, -0.004 - k * 0.008]);
  mesh(new THREE.TorusGeometry(0.008, 0.002, 6, 12), M.metal, g, [0, -0.004, 0.022], [Math.PI / 2, 0, 0]);
  // screen hood and bezel on top, angled toward the user
  const scr = new THREE.Group();
  scr.position.set(0, 0.061, -0.03);
  scr.rotation.x = 0.45; // tilted back toward the user
  g.add(scr);
  mesh(roundedBox(0.058, 0.008, 0.042, 0.003, 2), M.rubber, scr);
  // status LED on the side
  const led = mesh(new THREE.SphereGeometry(0.003, 6, 4), new THREE.MeshStandardMaterial({ color: 0x041014, emissive: 0x6cff9c, emissiveIntensity: 2 }), g, [-0.0335, 0.046, -0.135]);
  const emitter = new THREE.Object3D();
  emitter.position.set(0, 0.028, headZ - 0.03);
  g.add(emitter);
  return { group: g, trigger, rotor, emitter, screenMount: scr, cells, led };
}

/**
 * Right glove closed around the scanner grip. Local frame matches buildScanner
 * (grip at the origin). Returns the index finger joints for the trigger pull.
 */
export function buildGlove(M) {
  const g = new THREE.Group();
  // palm and padded back of the hand
  mesh(roundedBox(0.062, 0.082, 0.074, 0.02, 3), M.glove, g, [0.026, -0.04, -0.012], [0.28, 0, 0]);
  mesh(roundedBox(0.012, 0.06, 0.052, 0.006, 2), M.accent, g, [0.058, -0.04, -0.012], [0.28, 0, 0]);
  // four fingers wrapping the grip from the right side (+x) around the front
  const fingers = [];
  const seg = (parent, len, r, pos) => {
    const j = new THREE.Group();
    j.position.set(...pos);
    parent.add(j);
    mesh(new THREE.CapsuleGeometry(r, len, 4, 8), M.glove, j, [-len / 2, 0, 0], [0, 0, Math.PI / 2]);
    return j;
  };
  for (let i = 0; i < 4; i++) {
    const root = new THREE.Group();
    const y = -0.018 - i * 0.02;
    root.position.set(0.024, y, -0.046 + i * 0.006);
    root.rotation.set(0, 0.35, 0);
    g.add(root);
    const r = i === 3 ? 0.0085 : 0.0105;
    const s1 = seg(root, 0.022, r, [0, 0, 0]);
    const s2 = seg(s1, 0.018, r * 0.95, [-0.026, 0, 0]);
    s2.rotation.y = 1.2;
    const s3 = seg(s2, 0.014, r * 0.9, [-0.022, 0, 0]);
    s3.rotation.y = 0.9;
    fingers.push({ root, s2, s3 });
    if (i === 0) root.position.y += 0.004;
  }
  // index finger forward on the trigger
  const index = new THREE.Group();
  index.position.set(0.02, -0.004, -0.04);
  index.rotation.set(0, 0.55, 0);
  g.add(index);
  const i1 = seg(index, 0.024, 0.01, [0, 0, 0]);
  const i2 = seg(i1, 0.018, 0.0095, [-0.028, 0, 0]);
  i2.rotation.y = 0.5;
  // thumb over the top of the grip
  const thumb = new THREE.Group();
  thumb.position.set(-0.004, 0.006, -0.008);
  thumb.rotation.set(0.5, -0.4, 0.3);
  g.add(thumb);
  const t1 = seg(thumb, 0.026, 0.012, [0.02, 0, 0]);
  seg(t1, 0.02, 0.011, [-0.03, 0, 0]).rotation.y = 0.4;
  fingers[0].root.visible = false; // index is its own chain
  return { group: g, index, i2 };
}

/**
 * Suit sleeve from elbow (a) to wrist (b): tapered padded tube, accent bands
 * per pattern, a metal cuff seal ring at the wrist. Returns the meshes added.
 */
export function buildSleeve(M, parent, a, b, rA, rB, pattern = 'bands') {
  const A = a.isVector3 ? a : V(...a), B = b.isVector3 ? b : V(...b);
  const len = A.distanceTo(B);
  const grp = new THREE.Group();
  grp.position.copy(A);
  grp.quaternion.setFromUnitVectors(V(0, 0, 1), B.clone().sub(A).normalize());
  parent.add(grp);
  const geo = lathe({ z0: 0, z1: len, segs: 24, radial: 18, capStart: false, capEnd: false, section: (t) => {
    const pad = 1 + 0.06 * Math.max(0, Math.sin(t * Math.PI * 5)) * (t < 0.8 ? 1 : 0);
    return { r: (rA + (rB - rA) * t) * pad };
  } });
  mesh(geo, M.suit, grp);
  const ring = (t, w, mat, k = 1.03) => mesh(new THREE.CylinderGeometry((rA + (rB - rA) * t) * k, (rA + (rB - rA) * t) * k, w, 18, 1, true), mat, grp, [0, 0, t * len], [Math.PI / 2, 0, 0]);
  if (pattern === 'bands') { ring(0.35, len * 0.08, M.accent); ring(0.5, len * 0.04, M.accent); }
  if (pattern === 'panels') mesh(roundedBox(rA * 0.9, rA * 0.5, len * 0.5, rA * 0.2, 2), M.accent, grp, [0, rA * 0.82, len * 0.4]);
  if (pattern === 'hazard') ring(0.82, len * 0.12, M.hazard, 1.035);
  // cuff seal: dark gasket + metal ring
  ring(0.94, len * 0.06, M.suitDark, 1.06);
  mesh(new THREE.TorusGeometry(rB * 1.1, rB * 0.14, 8, 22), M.metal, grp, [0, 0, len * 0.98]);
  return grp;
}
