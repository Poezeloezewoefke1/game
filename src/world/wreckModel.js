// Detailed visuals for one half of the Corvid wreck (expedition support
// ship broken in two). Visual only: Structures.buildWreck keeps every
// original collider, interactable and scannable. Local frame: x along the
// ship (farX = the intact end, -farX = the break), y up, z across.

import * as THREE from 'three';
import { Kit, strut, roundedBox, place, sweep } from './shapes.js';
import { waterMat } from './shading.js';
import { surface } from './surfaces.js';
import { mulberry32 } from '../core/noise.js';
import { fbm3 } from './rocks.js';
import { panelTexture } from './textures.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);

let SHARED = null;
function materials(M) {
  if (SHARED) return SHARED;
  // weathered dark-grey hull paint over rust-streaked plating
  const hullTex = panelTexture('#7d776e', 21, 1.0);
  hullTex.repeat.set(1, 1);
  void M;
  SHARED = {
    plate: waterMat({ map: hullTex, roughness: 0.8, metalness: 0.3 }, { detail: 0.25, surface: surface('rust', { strength: 0.8 }) }),
    paint: waterMat({ color: 0x8c948f, roughness: 0.7, metalness: 0.25 }, { detail: 0.3, surface: surface('rust', { strength: 0.7 }) }),
    red: waterMat({ color: 0x8a3a2c, roughness: 0.8, metalness: 0.2 }, { detail: 0.3, surface: surface('rust') }),
    dark: M.rustDark,
    inner: waterMat({ color: 0x5a4a40, roughness: 0.9, metalness: 0.3 }, { detail: 0.4, surface: surface('rust') }),
    growth: waterMat({ color: 0x5d5a3c, roughness: 0.95 }, { detail: 0.6, surface: surface('coral', { strength: 0.8 }) }),
  };
  return SHARED;
}

/** Hull section: superellipse U from keel (u=0) to deck edge (u=1) on side `sd`. */
function section(u, a, depth, deckY, sd) {
  const th = (u - 1) * Math.PI / 2; // 0 at deck edge, -PI/2 at keel
  const n = 4.2;
  const c = Math.cos(th), s = Math.sin(th);
  const z = a * Math.pow(Math.abs(c), 2 / n);
  const y = deckY - depth * Math.pow(Math.abs(s), 2 / n);
  return [sd * z, y];
}

export function buildWreckHalf(group, M, { L = 28, W = 11, Hh = 8, farX, breach = false, bridge = false, seed = 1, windowMat }) {
  const T = materials(M);
  const rnd = mulberry32(seed * 97 + 3);
  const kit = new Kit();
  const nearX = -farX;
  const dirF = Math.sign(farX); // toward the intact end
  const isBow = farX > 0 && !bridge;
  const halfW = (t) => {
    // t: 0 break .. 1 far end. Bow narrows to a raked stem, stern stays full.
    if (!isBow) return W / 2 * (1 - 0.06 * THREE.MathUtils.smoothstep(t, 0.85, 1));
    return W / 2 * (1 - 0.3 * Math.pow(THREE.MathUtils.smoothstep(t, 0.72, 1), 1.4));
  };
  const deckAt = (t) => Hh + (isBow ? 0.9 * THREE.MathUtils.smoothstep(t, 0.6, 1) : 0);
  const depthAt = (t) => Hh + 0.3 - (isBow ? 2.0 * Math.pow(THREE.MathUtils.smoothstep(t, 0.8, 1), 2) : 0);
  const tear = (s) => 1.0 + 1.4 * (fbm3(s * 5 + seed, seed, 0, 3) * 0.5 + 0.5);

  // ------------------------------------------------ hull shell (one double-sided plate surface)
  const NX = 60, NS = 34;
  const pos = [], uv = [], idx = [];
  const holeAt = (x, y, z) => breach && z > 0 && ((x / 4.2) ** 2 + ((y - 2.9) / 3.2) ** 2) < 1 + 0.8 * fbm3(x * 1.1, y * 1.1, 7, 3);
  const grid = [];
  for (let i = 0; i <= NX; i++) {
    const t = i / NX;
    for (let j = 0; j <= NS; j++) {
      const sj = j / NS; // 0 port deck edge .. 1 starboard deck edge
      const sd = sj < 0.5 ? -1 : 1;
      const u = sj < 0.5 ? 1 - sj * 2 : (sj - 0.5) * 2;
      const [z, y] = section(u, halfW(t), depthAt(t), deckAt(t), sd);
      // torn plating at the break: ragged edge + outward curl
      const tx = tear(sj) * (1 - t) ** 6;
      let x = THREE.MathUtils.lerp(nearX, farX, t) + dirF * tx;
      const curl = Math.max(0, 1 - t * 14) * 0.5;
      const nz = z * (1 + curl * 0.08), ny = y - curl * 0.3 * (u < 0.3 ? 1 : 0);
      // dents and buckles
      const dent = fbm3(x * 0.25, y * 0.3, z * 0.25 + seed, 3) * 0.18;
      let px = x, pz = nz + Math.sign(nz || 1) * dent * (u > 0.15 ? 1 : 0.3);
      // breach: plates pushed inward around the hole
      if (breach && pz > 0) {
        const r = Math.sqrt((px / 4.2) ** 2 + ((ny - 2.6) / 3.1) ** 2);
        if (r < 1.7) pz -= Math.max(0, 1.7 - r) * 0.9;
      }
      grid.push({ x: px, y: ny, z: pz });
      pos.push(px, ny, pz);
      uv.push(px / 4, sj * 6);
    }
  }
  const cols = NS + 1;
  for (let i = 0; i < NX; i++) {
    for (let j = 0; j < NS; j++) {
      const a = i * cols + j, b = a + 1, c = a + cols, d = c + 1;
      const g0 = grid[a], g1 = grid[d];
      if (holeAt((g0.x + g1.x) / 2, (g0.y + g1.y) / 2, (g0.z + g1.z) / 2 + 0.5)) continue;
      if (dirF > 0) idx.push(a, d, b, a, c, d); else idx.push(a, b, d, a, d, c);
    }
  }
  const hull = new THREE.BufferGeometry();
  hull.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  hull.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  hull.setIndex(idx);
  hull.computeVertexNormals();
  kit.add(T.plate, hull);
  // inner skin (visible through the break and the breach), inset along the normal
  {
    const inner = hull.clone();
    const ip = inner.attributes.position, inn = inner.attributes.normal;
    for (let k = 0; k < ip.count; k++) {
      ip.setXYZ(k, ip.getX(k) - inn.getX(k) * 0.12, ip.getY(k) - inn.getY(k) * 0.12, ip.getZ(k) - inn.getZ(k) * 0.12);
    }
    const ix = inner.index.array.slice();
    for (let k = 0; k < ix.length; k += 3) { const t = ix[k + 1]; ix[k + 1] = ix[k + 2]; ix[k + 2] = t; }
    inner.setIndex(Array.from(ix));
    inner.computeVertexNormals();
    kit.add(T.inner, inner);
  }
  // anti-fouling red below the waterline: a second skin just outside the lower hull
  {
    const p2 = [], u2 = [], i2 = [];
    const NS2 = 16;
    for (let i = 0; i <= NX; i++) {
      const t = i / NX;
      for (let j = 0; j <= NS2; j++) {
        const sj = j / NS2; const sd = sj < 0.5 ? -1 : 1;
        const u = (sj < 0.5 ? 1 - sj * 2 : (sj - 0.5) * 2) * 0.55;
        const [z, y] = section(u, halfW(t) + 0.03, depthAt(t) + 0.03, deckAt(t), sd);
        const x = THREE.MathUtils.lerp(nearX, farX, t) + dirF * (tear(0.5 - (0.5 - sj) * 0.55) + 0.3) * (1 - t) ** 6;
        p2.push(x, y, z); u2.push(x / 4, sj * 3);
      }
    }
    const c2 = NS2 + 1;
    for (let i = 0; i < NX; i++) for (let j = 0; j < NS2; j++) {
      const a = i * c2 + j, b = a + 1, c = a + c2, d = c + 1;
      const zMid = (p2[a * 3 + 2] + p2[d * 3 + 2]) / 2, xMid = (p2[a * 3] + p2[d * 3]) / 2, yMid = (p2[a * 3 + 1] + p2[d * 3 + 1]) / 2;
      if (holeAt(xMid, yMid, zMid + 0.5)) continue;
      if (dirF > 0) i2.push(a, d, b, a, c, d); else i2.push(a, b, d, a, d, c);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(p2, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(u2, 2));
    g.setIndex(i2);
    g.computeVertexNormals();
    kit.add(T.red, g);
  }
  // stern transom / bow stem cap at the intact end
  {
    const shape = new THREE.Shape();
    const steps = 20;
    for (let k = 0; k <= steps; k++) {
      const sj = k / steps; const sd = sj < 0.5 ? -1 : 1;
      const u = sj < 0.5 ? 1 - sj * 2 : (sj - 0.5) * 2;
      const [z, y] = section(u, halfW(1), depthAt(1), deckAt(1), sd);
      if (k === 0) shape.moveTo(z, y); else shape.lineTo(z, y);
    }
    const cap = new THREE.ShapeGeometry(shape, 4);
    cap.rotateY(dirF > 0 ? Math.PI / 2 : -Math.PI / 2);
    cap.translate(farX, 0, 0);
    kit.add(T.plate, cap);
  }
  // exposed frames (ribs) at the break, some snapped off
  for (let k = 0; k < 5; k++) {
    const x = nearX + dirF * (0.4 + k * 0.7);
    const t = (x - nearX) / (farX - nearX);
    for (const sd of [-1, 1]) {
      const u0 = rnd() * 0.25, u1 = 0.55 + rnd() * 0.45;
      const pts = [];
      for (let m = 0; m <= 8; m++) {
        const u = u0 + (u1 - u0) * (m / 8);
        const [z, y] = section(u, halfW(t) - 0.15, depthAt(t) - 0.15, deckAt(t), sd);
        pts.push(V(x, y, z));
      }
      kit.add(T.dark, sweep(pts, 0.1, 0.07, 5, 16));
    }
  }
  // bilge keels and a rubbing strake
  for (const sd of [-1, 1]) {
    const pts = [], strake = [];
    for (let m = 0; m <= 12; m++) {
      const t = 0.08 + 0.84 * (m / 12);
      const x = THREE.MathUtils.lerp(nearX, farX, t);
      const [z, y] = section(0.42, halfW(t) + 0.12, depthAt(t) + 0.12, deckAt(t), sd);
      pts.push(V(x, y, z));
      const [z2, y2] = section(0.93, halfW(t) + 0.1, depthAt(t), deckAt(t), sd);
      strake.push(V(x, y2, z2));
    }
    kit.add(T.dark, sweep(pts, 0.12, 0.12, 5, 30));
    kit.add(T.dark, sweep(strake, 0.13, 0.13, 6, 30));
  }

  // interior tank-top floor at the floor collider height, ragged at the break
  kit.add(T.paint, place(roundedBox(L - 3.2, 0.12, W - 1.8, 0.04), [dirF * 1.4, 0.55, 0]));

  // ------------------------------------------------ deck slab with hatch opening (matches the deck colliders)
  const deckY = Hh;
  kit.add(T.paint, place(roundedBox(12, 0.5, W - 0.1, 0.08), [-8, deckY, 0]));
  kit.add(T.paint, place(roundedBox(10, 0.5, W - 0.1, 0.08), [9, deckY, 0]));
  kit.add(T.paint, place(roundedBox(4, 0.5, 4, 0.08), [2, deckY, 3.5]));
  // hatch coaming around the opening
  for (const [w, d, x, z] of [[6.2, 0.25, 1, -5.4], [0.25, 7, -2.05, -2], [0.25, 3, 4.05, -4], [2.3, 0.25, -0.9, 1.5]]) {
    kit.add(T.dark, place(roundedBox(w, 0.6, d, 0.05), [x, deckY + 0.5, z]));
  }
  // bulwark railing (posts + two rails), a few bent or missing
  for (const sd of [-1, 1]) {
    const zr = sd * (W / 2 - 0.2);
    const posts = [];
    for (let x = -13.2; x <= 13.2; x += 1.6) {
      if (rnd() < 0.15) continue;
      const lean = rnd() < 0.2 ? (rnd() - 0.5) * 0.8 : 0;
      kit.add(T.dark, strut(V(x, deckY + 0.25, zr), V(x + lean * 0.3, deckY + 1.3, zr + sd * lean * 0.4), 0.04, 5));
      posts.push(x);
    }
    for (const h of [0.75, 1.25]) {
      for (let k = 0; k < posts.length - 1; k++) {
        if (posts[k + 1] - posts[k] > 2 || rnd() < 0.1) continue;
        kit.add(T.dark, strut(V(posts[k], deckY + h, zr), V(posts[k + 1], deckY + h, zr), 0.03, 4));
      }
    }
  }
  // bollards and mushroom vents
  for (const [bx, bz] of [[-12, 3.8], [-12, -3.8], [12, 3.8], [12, -3.8], [6.5, -4.2]]) {
    for (const o of [-0.35, 0.35]) kit.add(T.dark, place(new THREE.CylinderGeometry(0.17, 0.2, 0.55, 10), [bx + o, deckY + 0.5, bz]));
    kit.add(T.dark, place(roundedBox(1.2, 0.12, 0.5, 0.04), [bx, deckY + 0.3, bz]));
  }
  for (const [vx, vz] of [[-4, 4.4], [7.5, 4.4], [11, -1]]) {
    kit.add(T.paint, place(new THREE.CylinderGeometry(0.18, 0.18, 1.0, 10), [vx, deckY + 0.75, vz]));
    kit.add(T.paint, place(new THREE.SphereGeometry(0.42, 12, 6, 0, Math.PI * 2, 0, Math.PI / 2).scale(1, 0.6, 1), [vx, deckY + 1.2, vz]));
  }

  // ------------------------------------------------ rusticles hanging under the hull edges and the break
  for (let k = 0; k < 46; k++) {
    const t = rnd();
    const sd = rnd() < 0.5 ? -1 : 1;
    const u = 0.25 + rnd() * 0.5;
    const nearBreak = k < 16;
    const tt = nearBreak ? rnd() * 0.06 : t;
    const x = THREE.MathUtils.lerp(nearX, farX, tt) + (nearBreak ? dirF * tear(0.5 + sd * (0.5 - u / 2)) * 0.8 : 0);
    const [z, y] = section(u, halfW(tt) * 0.98, depthAt(tt) * 0.98, deckAt(tt), sd);
    const len = 0.3 + rnd() * 0.8;
    const g = new THREE.ConeGeometry(0.06 + rnd() * 0.08, len, 5).rotateX(Math.PI).translate(x, y - len / 2, z);
    kit.add(T.dark, g);
  }
  // marine growth patches on the deck and hull
  for (let k = 0; k < 18; k++) {
    const x = (rnd() - 0.5) * 24, z = (rnd() - 0.5) * (W - 1.5);
    if (x > -2.2 && x < 4.2 && z < 1.6) continue; // keep the hatch open
    const r = 0.3 + rnd() * 0.7;
    kit.add(T.growth, place(new THREE.SphereGeometry(r, 9, 5, 0, Math.PI * 2, 0, Math.PI / 2).scale(1, 0.35, 1), [x, deckY + 0.24, z]));
  }

  // ------------------------------------------------ bridge deckhouse (aft half)
  if (bridge) {
    const bx = -8, by = Hh + 3.25;
    kit.add(T.paint, place(roundedBox(7, 6, 8, 0.35, 3), [bx, by, 0]));
    kit.add(T.dark, place(roundedBox(8, 0.3, 9.2, 0.1), [bx, by + 3.1, 0])); // roof overhang
    kit.add(T.dark, place(roundedBox(0.4, 0.5, 8.4, 0.1), [bx - 3.7, by + 1.85, 0])); // window visor
    // bridge wings with railings
    for (const sd of [-1, 1]) {
      kit.add(T.paint, place(roundedBox(2.6, 0.25, 1.6, 0.06), [bx - 2, by + 1.4, sd * 4.75]));
      for (let k = 0; k <= 3; k++) kit.add(T.dark, strut(V(bx - 3.2 + k * 0.8, by + 1.5, sd * 5.5), V(bx - 3.2 + k * 0.8, by + 2.5, sd * 5.5), 0.035, 4));
      kit.add(T.dark, strut(V(bx - 3.2, by + 2.5, sd * 5.5), V(bx - 0.8, by + 2.5, sd * 5.5), 0.03, 4));
      // door and porthole row on the side
      kit.add(T.dark, place(roundedBox(1.0, 2.1, 0.12, 0.08), [bx + 1.6, Hh + 1.3, sd * 4.02]));
      for (let k = 0; k < 3; k++) kit.add(T.dark, place(new THREE.TorusGeometry(0.28, 0.06, 6, 14), [bx - 1.8 + k * 1.3, by + 0.2, sd * 4.03]));
    }
    // aft funnel with a soot band
    kit.add(T.paint, place(roundedBox(2.2, 4.2, 3.0, 0.5, 3), [bx + 5.0, Hh + 2.4, 0], [0, 0, -0.08]));
    kit.add(T.dark, place(roundedBox(2.3, 0.7, 3.1, 0.3, 2), [bx + 5.15, Hh + 4.1, 0], [0, 0, -0.08]));
    // ladder up the deckhouse side
    for (let k = 0; k < 9; k++) kit.add(T.dark, strut(V(bx + 3.55, Hh + 0.6 + k * 0.6, 1.0), V(bx + 3.55, Hh + 0.6 + k * 0.6, 1.6), 0.025, 4));
    for (const z of [1.0, 1.6]) kit.add(T.dark, strut(V(bx + 3.55, Hh + 0.3, z), V(bx + 3.55, Hh + 6, z), 0.035, 4));
    // empty lifeboat davits
    for (const sd of [-1, 1]) {
      kit.add(T.dark, sweep([V(bx + 2.5, Hh + 0.3, sd * 4.6), V(bx + 2.5, Hh + 2.4, sd * 4.9), V(bx + 2.5, Hh + 3.0, sd * 5.8)], 0.09, 0.07, 6, 10));
      kit.add(T.dark, sweep([V(bx - 1.5, Hh + 0.3, sd * 4.6), V(bx - 1.5, Hh + 2.4, sd * 4.9), V(bx - 1.5, Hh + 2.8, sd * 5.6)], 0.09, 0.07, 6, 10));
    }
    // mast yard and lights (the mast pole itself stays the collider capsule)
    kit.add(T.dark, strut(V(-8, Hh + 12.5, -2.2), V(-8, Hh + 12.5, 2.2), 0.08, 6));
    if (windowMat) {
      const wm = [];
      for (let i = 0; i < 4; i++) wm.push(place(new THREE.PlaneGeometry(1.2, 0.8), [-11.53, Hh + 4.5, -2.7 + i * 1.8], [0, -Math.PI / 2, 0]));
      for (const g of wm) kit.add(windowMat, g);
    }
  } else {
    // bow: deck crane on a pedestal, boom folded over the hatch
    kit.add(T.paint, place(new THREE.CylinderGeometry(0.6, 0.75, 2.4, 14), [6.5, Hh + 1.4, -1.5]));
    kit.add(T.paint, place(roundedBox(1.6, 1.0, 1.4, 0.15), [6.5, Hh + 3.0, -1.5]));
    kit.add(T.dark, strut(V(6.2, Hh + 3.3, -1.5), V(0.5, Hh + 5.3, -1.0), 0.18, 8));
    kit.add(T.dark, sweep([V(0.5, Hh + 5.3, -1.0), V(0.4, Hh + 3.5, -1.0), V(0.9, Hh + 1.6, -0.6)], 0.025, 0.025, 4, 8)); // hanging cable
    // anchor hawse pipes near the stem
    for (const sd of [-1, 1]) {
      const [z, y] = section(0.85, halfW(0.93) + 0.05, depthAt(0.93), deckAt(0.93), sd);
      kit.add(T.dark, place(new THREE.TorusGeometry(0.35, 0.1, 6, 14), [farX - 2.0, y - 0.5, z], [0, Math.PI / 2, 0]));
    }
  }
  return kit.build(group, bridge ? 'corvidAft' : 'corvidBow');
}

/** Corrugated 20 ft-style container (6 x 2.6 x 2.6) centred at the origin, doors at +x. */
export function containerGeometry(open = false) {
  const kit = new Kit();
  const tmp = new THREE.MeshBasicMaterial();
  const L = 6, H = 2.6, D = 2.6;
  for (const sd of [-1, 1]) {
    const g = new THREE.PlaneGeometry(L - 0.2, H - 0.2, 48, 1);
    const p = g.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i);
      const k = ((x + 10) * 4) % 1;
      p.setZ(i, (k < 0.5 ? k : 1 - k) * 0.12);
    }
    g.computeVertexNormals();
    if (sd < 0) g.rotateY(Math.PI);
    g.translate(0, 0, sd * (D / 2 - 0.06));
    kit.add(tmp, g);
  }
  kit.add(tmp, place(roundedBox(L, 0.12, D, 0.03), [0, H / 2 - 0.06, 0]));
  kit.add(tmp, place(roundedBox(L, 0.15, D, 0.03), [0, -H / 2 + 0.07, 0]));
  kit.add(tmp, place(roundedBox(0.1, H, D, 0.03), [-L / 2 + 0.05, 0, 0]));
  if (!open) {
    kit.add(tmp, place(roundedBox(0.08, H - 0.2, D - 0.2, 0.02), [L / 2 - 0.05, 0, 0]));
    for (const z of [-0.65, -0.25, 0.25, 0.65]) kit.add(tmp, strut(V(L / 2 + 0.03, -H / 2 + 0.2, z), V(L / 2 + 0.03, H / 2 - 0.2, z), 0.025, 5));
  }
  // corner posts
  for (const x of [-L / 2 + 0.08, L / 2 - 0.08]) for (const z of [-D / 2 + 0.08, D / 2 - 0.08]) kit.add(tmp, place(roundedBox(0.16, H, 0.16, 0.03), [x, 0, z]));
  const grp = new THREE.Group();
  kit.build(grp, 'container');
  return grp.children[0].geometry;
}
