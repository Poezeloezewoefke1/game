// Shape library for hero assets (Kestrel, Meridian Station, creatures).
// Everything keeps position/normal/uv so parts can share UV-mapped PBR
// materials and be merged into one draw call per material.

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

const _m = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _e = new THREE.Euler();

/**
 * Smooth body of revolution along +z with a per-station elliptical section.
 * section(t) -> { r, hx = 1, hy = 1, y = 0, x = 0 }, t: 0 at z0 .. 1 at z1.
 * Optional `squareness` (0..1) pushes the section toward a rounded square.
 */
export function lathe({ z0 = -1, z1 = 1, segs = 32, radial = 32, section, squareness = 0, capStart = true, capEnd = true, uvScale = [1, 1] }) {
  const pos = [], uv = [], idx = [];
  const rows = segs + 1, cols = radial + 1;
  for (let i = 0; i <= segs; i++) {
    const t = i / segs;
    const z = z0 + (z1 - z0) * t;
    const s = section(t);
    const r = Math.max(s.r, 0);
    for (let k = 0; k <= radial; k++) {
      const a = (k / radial) * Math.PI * 2;
      let cx = Math.cos(a), cy = Math.sin(a);
      if (squareness > 0) {
        // superellipse-ish: blend toward a rounded square
        const p = 2 + squareness * 4;
        const sx = Math.sign(cx) * Math.pow(Math.abs(cx), 2 / p);
        const sy = Math.sign(cy) * Math.pow(Math.abs(cy), 2 / p);
        cx = sx; cy = sy;
      }
      pos.push((s.x || 0) + cx * r * (s.hx ?? 1), (s.y || 0) + cy * r * (s.hy ?? 1), z);
      uv.push((k / radial) * uvScale[0], t * uvScale[1]);
    }
  }
  for (let i = 0; i < segs; i++) {
    for (let k = 0; k < radial; k++) {
      const a = i * cols + k, b = a + 1, c = a + cols, d = c + 1;
      idx.push(a, b, d, a, d, c);
    }
  }
  const addCap = (row, flip) => {
    const center = pos.length / 3;
    let sx = 0, sy = 0, sz = 0;
    for (let k = 0; k < radial; k++) { const j = (row * cols + k) * 3; sx += pos[j]; sy += pos[j + 1]; sz += pos[j + 2]; }
    pos.push(sx / radial, sy / radial, sz / radial);
    uv.push(0.5, row ? 1 : 0);
    for (let k = 0; k < radial; k++) {
      const a = row * cols + k, b = a + 1;
      if (flip) idx.push(center, b, a); else idx.push(center, a, b);
    }
  };
  if (capStart && section(0).r > 1e-4) addCap(0, true);
  if (capEnd && section(1).r > 1e-4) addCap(segs, false);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

/** Ducted thruster shroud: an airfoil-section ring around the z axis (open both ends). */
export function duct(radius = 0.4, length = 0.5, thickness = 0.07, radial = 32) {
  const pts = [];
  const n = 14;
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const a = t * Math.PI * 2;
    // teardrop section: rounded leading edge at -z, thin trailing edge at +z
    const zz = -Math.cos(a) * length * 0.5;
    const thick = thickness * (0.55 + 0.45 * Math.cos(a * 0.5) ** 2) * Math.sin(a);
    pts.push(new THREE.Vector2(radius + thick, zz));
  }
  const g = new THREE.LatheGeometry(pts, radial);
  g.rotateX(Math.PI / 2); // lathe axis y -> z
  return g;
}

/** Tube through points with a radius function r(t). */
export function sweep(points, r0 = 0.05, r1 = r0, radial = 10, segs = 0) {
  const curve = new THREE.CatmullRomCurve3(points.map((p) => (p.isVector3 ? p : new THREE.Vector3(...p))));
  const n = segs || Math.max(4, points.length * 6);
  const g = new THREE.TubeGeometry(curve, n, 1, radial, false);
  const p = g.attributes.position;
  const c = new THREE.Vector3(), v = new THREE.Vector3();
  for (let s = 0; s <= n; s++) {
    const t = s / n;
    curve.getPointAt(t, c);
    const r = r0 + (r1 - r0) * t;
    for (let k = 0; k <= radial; k++) {
      const i = s * (radial + 1) + k;
      v.fromBufferAttribute(p, i).sub(c).multiplyScalar(r).add(c);
      p.setXYZ(i, v.x, v.y, v.z);
    }
  }
  g.computeVertexNormals();
  return g;
}

/** Straight strut between two points (capsule-ish cylinder). */
export function strut(a, b, r = 0.05, radial = 8) {
  const A = a.isVector3 ? a : new THREE.Vector3(...a), B = b.isVector3 ? b : new THREE.Vector3(...b);
  const len = A.distanceTo(B);
  const g = new THREE.CylinderGeometry(r, r, len, radial, 1);
  _q.setFromUnitVectors(new THREE.Vector3(0, 1, 0), B.clone().sub(A).normalize());
  _m.compose(A.clone().add(B).multiplyScalar(0.5), _q, new THREE.Vector3(1, 1, 1));
  g.applyMatrix4(_m);
  return g;
}

export function roundedBox(w, h, d, r = 0.05, seg = 2) {
  return new RoundedBoxGeometry(w, h, d, seg, Math.min(r, w / 2, h / 2, d / 2));
}

/** Apply position / euler rotation / scale to a geometry (returns it). */
export function place(geo, [x = 0, y = 0, z = 0] = [], [rx = 0, ry = 0, rz = 0] = [], scale = 1) {
  _e.set(rx, ry, rz);
  _q.setFromEuler(_e);
  const s = typeof scale === 'number' ? new THREE.Vector3(scale, scale, scale) : new THREE.Vector3(...scale);
  _m.compose(new THREE.Vector3(x, y, z), _q, s);
  geo.applyMatrix4(_m);
  return geo;
}

/** Mirror a geometry across the x = 0 plane (fixes winding). */
export function mirrorX(geo) {
  const g = geo.clone();
  g.scale(-1, 1, 1);
  const idx = g.index;
  if (idx) {
    for (let i = 0; i < idx.count; i += 3) { const a = idx.getX(i + 1); idx.setX(i + 1, idx.getX(i + 2)); idx.setX(i + 2, a); }
  } else {
    // non-indexed: swap vertex order in each triangle for every attribute
    for (const name of Object.keys(g.attributes)) {
      const at = g.attributes[name];
      for (let i = 0; i < at.count; i += 3) {
        for (let c = 0; c < at.itemSize; c++) {
          const v1 = at.getComponent(i + 1, c);
          at.setComponent(i + 1, c, at.getComponent(i + 2, c));
          at.setComponent(i + 2, c, v1);
        }
      }
    }
  }
  g.computeVertexNormals();
  return g;
}

function normalizeAttributes(g) {
  let geo = g;
  for (const name of Object.keys(geo.attributes)) if (!['position', 'normal', 'uv'].includes(name)) geo.deleteAttribute(name);
  if (!geo.attributes.normal) geo.computeVertexNormals();
  if (!geo.attributes.uv) {
    const n = geo.attributes.position.count;
    geo.setAttribute('uv', new THREE.Float32BufferAttribute(new Float32Array(n * 2), 2));
  }
  if (!geo.index) {
    const n = geo.attributes.position.count;
    const ids = new Uint32Array(n);
    for (let i = 0; i < n; i++) ids[i] = i;
    geo.setIndex(new THREE.BufferAttribute(ids, 1));
  }
  return geo;
}

/**
 * Collects parts by material and merges them: one mesh per material.
 * kit.add(material, geometry) ... kit.build(parent)
 */
export class Kit {
  constructor() { this.parts = new Map(); }

  add(material, geo) {
    if (!this.parts.has(material)) this.parts.set(material, []);
    this.parts.get(material).push(normalizeAttributes(geo));
    return geo;
  }

  build(parent, name = 'kit') {
    const meshes = [];
    for (const [mat, list] of this.parts) {
      const g = mergeGeometries(list, false);
      g.computeBoundingSphere();
      const m = new THREE.Mesh(g, mat);
      m.name = name;
      parent.add(m);
      meshes.push(m);
    }
    return meshes;
  }
}
