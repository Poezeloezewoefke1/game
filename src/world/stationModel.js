// Detailed exterior for Meridian Station. Visual only, except for a few
// small colliders added for new protrusions (airlock, module saddles). All
// original collision volumes, the air pocket, the dock point and the
// interactables stay in structures.js unchanged.
//
// Coordinate frame: station origin (0, 0, 0); hub radius 9 from y -23 to -11;
// east module along +x (x 9..23.5, y -17, r 3.2); north hangar along -z
// (z -9..-23, y -16.5, r 3.6); tanks at (-14, 6) and (-13, -7).

import * as THREE from 'three';
import { waterMat } from './shading.js';
import { surface } from './surfaces.js';
import { panelTexture } from './textures.js';
import { sweep, strut, roundedBox, place, Kit } from './shapes.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);

/** Revolve a (radius, height) polyline around the y axis, with UVs scaled to metres/tile. */
function revolve(profile, radial, tileU, tileV) {
  const pts = profile.map(([r, y]) => new THREE.Vector2(Math.max(r, 0.0001), y));
  const g = new THREE.LatheGeometry(pts, radial);
  // uv: u around, v along the profile length -> scale to real metres
  let len = 0;
  for (let i = 1; i < pts.length; i++) len += pts[i].distanceTo(pts[i - 1]);
  const maxR = Math.max(...profile.map((p) => p[0]));
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * (Math.PI * 2 * maxR) / tileU, uv.getY(i) * len / tileV);
  return g;
}

/** Quarter-ellipse arc points from (r0,y0) to (r1,y1) bulging outward. */
function arc(r0, y0, r1, y1, n = 6, convexOut = true) {
  const out = [];
  for (let i = 1; i <= n; i++) {
    const a = (i / n) * Math.PI / 2;
    const s = Math.sin(a), c = Math.cos(a);
    out.push(convexOut ? [r0 + (r1 - r0) * s, y0 + (y1 - y0) * (1 - c)] : [r0 + (r1 - r0) * (1 - c), y0 + (y1 - y0) * s]);
  }
  return out;
}

/** Rounded-rectangle window frame (extruded ring) facing +z, centred at origin. */
function windowFrame(w, h, r, border, depth) {
  const rr = (shape, x, y, ww, hh, rad, hole) => {
    const p = hole ? new THREE.Path() : shape;
    p.moveTo(x - ww / 2 + rad, y - hh / 2);
    p.lineTo(x + ww / 2 - rad, y - hh / 2);
    p.quadraticCurveTo(x + ww / 2, y - hh / 2, x + ww / 2, y - hh / 2 + rad);
    p.lineTo(x + ww / 2, y + hh / 2 - rad);
    p.quadraticCurveTo(x + ww / 2, y + hh / 2, x + ww / 2 - rad, y + hh / 2);
    p.lineTo(x - ww / 2 + rad, y + hh / 2);
    p.quadraticCurveTo(x - ww / 2, y + hh / 2, x - ww / 2, y + hh / 2 - rad);
    p.lineTo(x - ww / 2, y - hh / 2 + rad);
    p.quadraticCurveTo(x - ww / 2, y - hh / 2, x - ww / 2 + rad, y - hh / 2);
    return p;
  };
  const shape = new THREE.Shape();
  rr(shape, 0, 0, w + border * 2, h + border * 2, r + border, false);
  shape.holes.push(rr(null, 0, 0, w, h, r, true));
  const g = new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: true, bevelThickness: depth * 0.4, bevelSize: border * 0.25, bevelSegments: 2, curveSegments: 6 });
  g.translate(0, 0, -depth / 2);
  return g;
}

/** Place a geometry authored facing +z onto a vertical cylinder wall at angle a. */
function onWall(geo, a, radius, y, out = 0) {
  geo.rotateY(Math.PI / 2 - a);
  geo.translate(Math.cos(a) * (radius + out), y, Math.sin(a) * (radius + out));
  return geo;
}

/** Hatch wheel + door facing +z. */
function hatch(kit, M, radius) {
  kit.add(M.dark, new THREE.CylinderGeometry(radius, radius, 0.12, 32).rotateX(Math.PI / 2));
  kit.add(M.metal, new THREE.TorusGeometry(radius * 1.02, 0.05, 8, 40));
  const wheel = new THREE.TorusGeometry(radius * 0.38, 0.035, 8, 28);
  wheel.translate(0, 0, 0.14);
  kit.add(M.orange, wheel);
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * Math.PI * 2;
    kit.add(M.orange, strut(V(0, 0, 0.14), V(Math.cos(a) * radius * 0.38, Math.sin(a) * radius * 0.38, 0.14), 0.025, 6));
  }
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2;
    kit.add(M.metal, new THREE.CylinderGeometry(0.03, 0.03, 0.06, 6).rotateX(Math.PI / 2).translate(Math.cos(a) * radius * 0.88, Math.sin(a) * radius * 0.88, 0.07));
  }
}

export function buildStationExterior(site, base, terrain, collision) {
  const g = site.group;
  const tex = panelTexture('#dcded8', 21, 0.45);
  const M = {
    hull: waterMat({ map: tex, roughness: 0.5, metalness: 0.05 }, { detail: 0.06, surface: surface('paint', { strength: 0.3 }), reflect: 1.0 }),
    dark: waterMat({ color: 0x3a4148, roughness: 0.42, metalness: 0.75 }, { surface: surface('paintScratched', { scale: 1.2 }), reflect: 1.1 }),
    metal: waterMat({ color: 0x9aa2a8, roughness: 0.3, metalness: 1.0 }, { surface: surface('paintScratched', { scale: 2, strength: 0.3 }), reflect: 1.3 }),
    orange: base.orange,
    glass: waterMat({ color: 0x1a2a33, roughness: 0.05, metalness: 0.1, transparent: true, opacity: 0.55 }, { reflect: 1.8 }),
    rubber: waterMat({ color: 0x16181b, roughness: 0.9 }),
    concrete: waterMat({ color: 0x6d7175, roughness: 0.9 }, { detail: 0.3, surface: surface('rock', { strength: 0.6 }) }),
    window: base.window,
    flood: base.flood,
    beacon: base.beacon,
    dockLight: base.dockLight,
    navRed: waterMat({ color: 0x220000, emissive: 0xff2a1a, emissiveIntensity: 2.5 }),
    navGreen: waterMat({ color: 0x002200, emissive: 0x2aff6a, emissiveIntensity: 2.5 }),
  };
  const kit = new Kit();

  // ---------------------------------------------------------------- hub shell
  const R = 9.05;
  const prof = [[3.6, -19.9], [3.6, -23.0], ...arc(3.6, -23.0, 3.95, -23.4, 3, false), [7.4, -23.4],
    ...arc(7.4, -23.4, R, -22.1, 6, true), [R, -12.6], ...arc(R, -12.6, 8.2, -11.1, 6, false)];
  // dome: shallow ellipsoid from the shoulder to the apex (stays under the roof collider top, y -7.8)
  for (let i = 1; i <= 10; i++) {
    const a = (i / 10) * Math.PI / 2;
    prof.push([8.2 * Math.cos(a), -11.1 + 3.25 * Math.sin(a)]);
  }
  kit.add(M.hull, revolve(prof, 72, 10, 10));
  // hoop bands and the safety band
  for (const y of [-22.2, -17.6, -12.7]) kit.add(M.dark, place(new THREE.TorusGeometry(R + 0.06, 0.11, 8, 96), [0, y, 0], [Math.PI / 2, 0, 0]));
  kit.add(M.orange, place(new THREE.CylinderGeometry(R + 0.04, R + 0.04, 0.55, 96, 1, true), [0, -21.5, 0]));
  // vertical ribs between the hoops
  const ribCount = 20;
  for (let i = 0; i < ribCount; i++) {
    const a = (i / ribCount) * Math.PI * 2 + 0.16;
    kit.add(M.hull, onWall(roundedBox(0.3, 9.6, 0.18, 0.07), a, R, -17.4, 0.05)); // painted stiffener
  }
  // dome segments: radial seams + top hatch ring
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2;
    const pts = [];
    for (let k = 0; k <= 8; k++) {
      const t = (k / 8) * Math.PI / 2 * 0.86;
      pts.push(V(Math.cos(a) * 8.25 * Math.cos(t), -11.05 + 3.3 * Math.sin(t), Math.sin(a) * 8.25 * Math.cos(t)));
    }
    kit.add(M.dark, sweep(pts, 0.07, 0.07, 6, 16));
  }
  kit.add(M.dark, place(new THREE.TorusGeometry(1.6, 0.14, 8, 40), [0, -7.95, 0], [Math.PI / 2, 0, 0]));
  kit.add(M.metal, place(new THREE.CylinderGeometry(1.5, 1.5, 0.12, 40), [0, -7.9, 0]));

  // ---------------------------------------------------------------- observation windows (reinforced)
  const winFrame = windowFrame(1.5, 1.05, 0.28, 0.16, 0.22);
  const winGlass = new THREE.PlaneGeometry(1.5, 1.05);
  const windowAngles = [];
  for (let i = 0; i < ribCount; i++) if (i % 2 === 0 && i !== 6) windowAngles.push(((i + 0.5) / ribCount) * Math.PI * 2 + 0.16);
  for (const a of windowAngles) {
    kit.add(M.dark, onWall(winFrame.clone(), a, R, -15.4, 0.06));
    kit.add(M.window, onWall(winGlass.clone(), a, R, -15.4, 0.04));
    kit.add(M.metal, onWall(roundedBox(0.06, 1.05, 0.05, 0.02, 1), a, R, -15.4, 0.1)); // mullion
    // exterior lamp above each window, aimed down the wall
    kit.add(M.dark, onWall(roundedBox(0.36, 0.14, 0.28, 0.05), a, R, -14.45, 0.18));
    kit.add(M.flood, onWall(new THREE.PlaneGeometry(0.28, 0.08).rotateX(Math.PI / 2), a, R, -14.53, 0.2));
  }

  // ---------------------------------------------------------------- airlock (south-west)
  const airA = 2.45;
  const al = new THREE.Group();
  al.position.set(Math.cos(airA) * R, -20.6, Math.sin(airA) * R);
  al.rotation.y = Math.PI / 2 - airA;
  g.add(al);
  const ak = new Kit();
  ak.add(M.hull, revolve([[0.001, 0], [1.25, 0], [1.25, 2.0], ...arc(1.25, 2.0, 1.35, 2.15, 3, true), [1.35, 2.35], [0.001, 2.35]], 40, 6, 6).rotateX(Math.PI / 2));
  ak.add(M.dark, new THREE.TorusGeometry(1.32, 0.09, 8, 48).translate(0, 0, 0.35));
  ak.add(M.orange, new THREE.TorusGeometry(1.36, 0.05, 8, 48).translate(0, 0, 2.3));
  const hatchGroup = new THREE.Group();
  hatchGroup.position.z = 2.42;
  al.add(hatchGroup);
  const hk = new Kit();
  hatch(hk, M, 0.95);
  hk.build(hatchGroup, 'airlock_hatch');
  ak.add(M.navRed, new THREE.SphereGeometry(0.09, 10, 8).translate(-1.15, 1.0, 2.2));
  ak.add(M.navGreen, new THREE.SphereGeometry(0.09, 10, 8).translate(1.15, 1.0, 2.2));
  ak.build(al, 'airlock');
  collision.capsule(site.w(Math.cos(airA) * R, -20.6, Math.sin(airA) * R), site.w(Math.cos(airA) * (R + 2.3), -20.6, Math.sin(airA) * (R + 2.3)), 1.35, 'station');

  // ---------------------------------------------------------------- legs: trussed columns with braced pads
  const legs = [];
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * Math.PI * 2 + Math.PI / 4;
    const top = V(Math.cos(a) * 6.5, -22.7, Math.sin(a) * 6.5);
    const bot = V(Math.cos(a) * 11, -31.5, Math.sin(a) * 11);
    const gy = terrain.heightAt(bot.x, bot.z);
    bot.y = gy + 0.6;
    legs.push({ a, top, bot });
    kit.add(M.dark, strut(top, bot, 0.42, 16));
    // bracket at the hub
    kit.add(M.dark, place(roundedBox(1.4, 0.5, 0.9, 0.12), [top.x, -23.1, top.z], [0, -a, 0]));
    // hydraulic sleeve near the foot + collar
    const lowSleeve = top.clone().lerp(bot, 0.72);
    kit.add(M.metal, strut(lowSleeve, bot.clone().lerp(top, 0.05), 0.5, 16));
    kit.add(M.orange, strut(lowSleeve.clone().lerp(bot, -0.02), lowSleeve.clone().lerp(bot, 0.06), 0.53, 16));
    // foot pad
    kit.add(M.dark, place(new THREE.CylinderGeometry(1.15, 1.45, 0.45, 24), [bot.x, gy + 0.2, bot.z]));
    kit.add(M.concrete, place(new THREE.CylinderGeometry(1.7, 1.9, 0.35, 24), [bot.x, gy - 0.05, bot.z]));
    for (let k = 0; k < 8; k++) {
      const b = (k / 8) * Math.PI * 2;
      kit.add(M.metal, place(new THREE.CylinderGeometry(0.06, 0.06, 0.12, 6), [bot.x + Math.cos(b) * 1.25, gy + 0.46, bot.z + Math.sin(b) * 1.25]));
    }
    // gusset struts from pad to column
    for (const s of [-1, 1]) {
      const side = V(-Math.sin(a), 0, Math.cos(a)).multiplyScalar(s * 0.95);
      kit.add(M.dark, strut(V(bot.x + side.x, gy + 0.4, bot.z + side.z), bot.clone().lerp(top, 0.2), 0.08, 8));
    }
  }
  // x-bracing between neighbouring legs
  for (let i = 0; i < 4; i++) {
    const A = legs[i], B = legs[(i + 1) % 4];
    const a0 = A.top.clone().lerp(A.bot, 0.3), a1 = A.top.clone().lerp(A.bot, 0.75);
    const b0 = B.top.clone().lerp(B.bot, 0.3), b1 = B.top.clone().lerp(B.bot, 0.75);
    kit.add(M.dark, strut(a0, b1, 0.09, 8));
    kit.add(M.dark, strut(b0, a1, 0.09, 8));
  }

  // ---------------------------------------------------------------- east module (quarters) along +x
  const modProfile = (len, r) => {
    const p = [[0.001, 0], ...arc(0.001, 0, r * 0.82, 0.22, 3, false), [r, 0.55], [r, len - r * 0.55]];
    for (let i = 1; i <= 8; i++) { const t = (i / 8) * Math.PI / 2; p.push([r * Math.cos(t), len - r * 0.55 + r * 0.55 * Math.sin(t)]); }
    return p;
  };
  const eastLen = 14.4;
  const east = revolve(modProfile(eastLen, 3.2), 48, 10, 10);
  east.rotateZ(-Math.PI / 2); // y axis -> +x
  east.translate(9.1, -17, 0);
  kit.add(M.hull, east);
  kit.add(M.dark, place(new THREE.TorusGeometry(3.42, 0.22, 10, 64), [9.6, -17, 0], [0, Math.PI / 2, 0]));
  for (const x of [12.6, 15.2, 17.8, 20.4]) kit.add(M.dark, place(new THREE.TorusGeometry(3.26, 0.1, 8, 64), [x, -17, 0], [0, Math.PI / 2, 0]));
  kit.add(M.orange, place(new THREE.CylinderGeometry(3.23, 3.23, 0.4, 64, 1, true), [10.6, -17, 0], [0, 0, Math.PI / 2]));
  // quarters windows: framed, set into the curved flank
  const qFrame = windowFrame(1.25, 0.5, 0.2, 0.1, 0.16);
  const qGlass = new THREE.PlaneGeometry(1.25, 0.5);
  for (let i = 0; i < 4; i++) {
    for (const side of [-1, 1]) {
      const x = 11.3 + i * 2.6;
      const f = qFrame.clone(); const gl = qGlass.clone();
      for (const geo of [f, gl]) { if (side < 0) geo.rotateY(Math.PI); geo.translate(x, -16.5, side * (3.2 + (geo === gl ? 0.07 : 0.1))); }
      kit.add(M.dark, f);
      kit.add(M.window, gl);
    }
  }
  // saddle supports down to the seabed
  for (const x of [13.5, 20.5]) {
    const gy = terrain.heightAt(x, 0);
    for (const s of [-1, 1]) {
      kit.add(M.dark, strut(V(x, -19.4, s * 1.9), V(x, gy + 0.4, s * 3.2), 0.22, 10));
      kit.add(M.dark, place(new THREE.CylinderGeometry(0.7, 0.85, 0.35, 16), [x, gy + 0.15, s * 3.2]));
      collision.capsule(site.w(x, -19.4, s * 1.9), site.w(x, gy + 0.4, s * 3.2), 0.25, 'station');
    }
    kit.add(M.dark, place(new THREE.TorusGeometry(3.3, 0.16, 8, 32, Math.PI), [x, -17, 0], [Math.PI, Math.PI / 2, 0]));
  }

  // ---------------------------------------------------------------- north hangar module along -z
  const north = revolve(modProfile(14.2, 3.6), 48, 10, 10);
  north.rotateX(-Math.PI / 2); // y axis -> -z
  north.translate(0, -16.5, -8.9);
  kit.add(M.hull, north);
  kit.add(M.dark, place(new THREE.TorusGeometry(3.82, 0.24, 10, 64), [0, -16.5, -9.4]));
  for (const z of [-12.4, -15.6, -21.2]) kit.add(M.dark, place(new THREE.TorusGeometry(3.66, 0.1, 8, 64), [0, -16.5, z]));
  kit.add(M.orange, place(new THREE.CylinderGeometry(3.64, 3.64, 0.6, 64, 1, true), [0, -16.5, -19], [Math.PI / 2, 0, 0]));
  // hangar end door outline
  kit.add(M.dark, place(new THREE.TorusGeometry(2.0, 0.12, 8, 48), [0, -16.5, -22.95]));
  kit.add(M.orange, place(new THREE.CircleGeometry(1.9, 40), [0, -16.5, -22.9], [Math.PI, 0, 0]));
  // crane rail under the hangar and the dock cradle (cradle colliders live in structures.js)
  for (const sx of [-1, 1]) kit.add(M.metal, place(roundedBox(0.16, 0.2, 11, 0.04), [sx * 1.3, -20.0, -16]));
  for (const sx of [-3.1, 3.1]) {
    for (const [z0, z1] of [[-12, -13], [-21, -20]]) {
      kit.add(M.dark, strut(V(sx * 0.8, -19.5, z0), V(sx, -23.4, z1), 0.18, 12));
      kit.add(M.rubber, place(roundedBox(0.5, 0.18, 1.2, 0.06), [sx, -23.55, z1 + (z1 < -16 ? -0.2 : 0.2)]));
    }
    kit.add(M.dark, strut(V(sx, -23.4, -13), V(sx, -23.4, -20), 0.12, 10));
  }
  for (const sx of [-3.1, 3.1]) for (const sz of [-12.8, -20.2]) kit.add(M.dockLight, place(new THREE.SphereGeometry(0.18, 12, 10), [sx, -23.6, sz]));

  // ---------------------------------------------------------------- storage tanks
  for (const [x, z] of [[-14, 6], [-13, -7]]) {
    const gy = terrain.heightAt(x, z);
    const tprof = [[0.001, gy - 0.2], [2.7, gy - 0.2], [2.7, gy + 0.5], [2.4, gy + 0.7], [2.4, -14.6]];
    for (let i = 1; i <= 8; i++) { const t = (i / 8) * Math.PI / 2; tprof.push([2.4 * Math.cos(t), -14.6 + 1.1 * Math.sin(t)]); }
    kit.add(M.hull, revolve(tprof, 40, 10, 10).translate(x, 0, z));
    for (const y of [-16, gy + 3.2]) kit.add(M.orange, place(new THREE.CylinderGeometry(2.43, 2.43, 0.4, 40, 1, true), [x, y, z]));
    for (const y of [-14.9, (gy - 14) / 2 - 7]) kit.add(M.dark, place(new THREE.TorusGeometry(2.45, 0.08, 6, 48), [x, y, z], [Math.PI / 2, 0, 0]));
    // ladder on the outside
    const la = Math.atan2(-z, -x) + 0.9;
    const lx = x + Math.cos(la) * 2.55, lz = z + Math.sin(la) * 2.55;
    const side = V(-Math.sin(la), 0, Math.cos(la)).multiplyScalar(0.25);
    kit.add(M.metal, strut(V(lx + side.x, gy + 0.7, lz + side.z), V(lx + side.x, -14.5, lz + side.z), 0.03, 6));
    kit.add(M.metal, strut(V(lx - side.x, gy + 0.7, lz - side.z), V(lx - side.x, -14.5, lz - side.z), 0.03, 6));
    for (let y = gy + 1.1; y < -14.6; y += 0.4) kit.add(M.metal, strut(V(lx + side.x, y, lz + side.z), V(lx - side.x, y, lz - side.z), 0.02, 5));
    // pipe to the hub with flanges and a valve wheel (pipe collider lives in structures.js)
    const p0 = V(x * 0.9, -17, z * 0.9), p1 = V(x * 0.55, -17, z * 0.55);
    kit.add(M.dark, strut(p0, p1, 0.45, 16));
    for (const t of [0.1, 0.9]) kit.add(M.metal, strut(p0.clone().lerp(p1, t - 0.02), p0.clone().lerp(p1, t + 0.02), 0.58, 16));
    const mid = p0.clone().lerp(p1, 0.5);
    kit.add(M.orange, place(new THREE.TorusGeometry(0.32, 0.04, 6, 20), [mid.x, mid.y + 0.75, mid.z], [Math.PI / 2, 0, 0]));
    kit.add(M.metal, strut(V(mid.x, mid.y + 0.4, mid.z), V(mid.x, mid.y + 0.75, mid.z), 0.05, 6));
  }

  // ---------------------------------------------------------------- mast, dish and beacon
  kit.add(M.dark, strut(V(0, -8.0, 0), V(0, -1.6, 0), 0.24, 12));
  kit.add(M.metal, place(new THREE.CylinderGeometry(0.75, 0.75, 0.1, 24), [0, -4.2, 0]));
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * Math.PI * 2;
    kit.add(M.dark, strut(V(Math.cos(a) * 1.4, -8.05, Math.sin(a) * 1.4), V(Math.cos(a) * 0.2, -5.6, Math.sin(a) * 0.2), 0.05, 6));
  }
  // parabolic dish with feed horn
  const dishPts = [];
  for (let i = 0; i <= 10; i++) { const r = (i / 10) * 1.5; dishPts.push(new THREE.Vector2(r, r * r * 0.22)); }
  const dish = new THREE.LatheGeometry(dishPts, 32);
  dish.rotateZ(-1.1);
  dish.translate(0.55, -5.0, 0);
  kit.add(M.hull, dish);
  kit.add(M.dark, strut(V(0.05, -4.9, 0), V(0.55, -5.0, 0), 0.07, 8));
  kit.add(M.dark, strut(V(0.55, -5.0, 0), V(1.3, -4.55, 0), 0.03, 6));
  kit.add(M.beacon, place(new THREE.SphereGeometry(0.32, 16, 12), [0, -1.25, 0]));
  kit.add(M.metal, place(new THREE.CylinderGeometry(0.36, 0.3, 0.2, 16), [0, -1.6, 0]));

  // ---------------------------------------------------------------- cable runs (hub -> seabed, hub -> modules)
  const cables = [
    [V(7.2, -22.9, 3.6), V(8.6, -26.5, 5.5), V(10.5, -30.4, 6.0), V(16, -30.8, 7.5)],
    [V(-7.6, -22.9, -2.0), V(-9.5, -26, -3.5), V(-11.5, -29.5, -5.2), V(-12.6, -29.8, -6.4)],
    [V(4.0, -23.3, -6.8), V(3.6, -24.6, -9.2), V(3.4, -24.4, -12.5), V(3.4, -20.2, -13.5)],
  ];
  for (const c of cables) {
    for (const p of c) { const gy = terrain.heightAt(p.x, p.z); if (p.y < gy + 0.25) p.y = gy + 0.25; }
    kit.add(M.rubber, sweep(c, 0.09, 0.09, 6, 30));
    kit.add(M.rubber, sweep(c.map((p) => p.clone().add(V(0.22, 0.05, 0.1))), 0.06, 0.06, 6, 30));
  }

  // ---------------------------------------------------------------- floodlight posts
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2 + 0.2;
    const x = Math.cos(a) * 19, z = Math.sin(a) * 19;
    const gy = terrain.heightAt(x, z);
    for (let k = 0; k < 3; k++) {
      const b = (k / 3) * Math.PI * 2 + a;
      kit.add(M.dark, strut(V(x + Math.cos(b) * 0.7, gy, z + Math.sin(b) * 0.7), V(x, gy + 1.0, z), 0.05, 6));
    }
    kit.add(M.dark, strut(V(x, gy, z), V(x, gy + 3.2, z), 0.1, 8));
    const head = new THREE.Group();
    head.position.set(x, gy + 3.35, z);
    head.lookAt(0, -20, 0);
    g.add(head);
    const hk2 = new Kit();
    hk2.add(M.dark, roundedBox(0.7, 0.42, 0.5, 0.08));
    hk2.add(M.flood, new THREE.PlaneGeometry(0.58, 0.3).translate(0, 0, 0.26));
    hk2.add(M.metal, new THREE.TorusGeometry(0.42, 0.03, 6, 20, Math.PI).rotateY(Math.PI / 2).translate(0, -0.05, 0));
    hk2.build(head, 'floodlight');
  }

  // name plate on the hub (curved sign plate between the hoop bands)
  const plate = new THREE.CylinderGeometry(R + 0.22, R + 0.22, 1.5, 32, 1, true, -0.42, 0.84);
  kit.add(M.dark, plate.translate(0, -19.85, 0));
  kit.build(g, 'meridian_exterior');
  return { labelRadius: R + 0.25, labelY: -19.85 };
}
