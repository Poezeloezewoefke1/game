// Anatomy toolkit for the creature rebuild: shaped trunks, membrane fins with
// real thickness and interior vertices (so the swim shader can bend them),
// eyes set in sockets, teeth, and tapered limbs. Every part is finished with
// the same attributes (position, normal, color, aGlow, aFin) so a whole
// creature merges into one geometry / one draw call.
// Convention: head toward +z, tail toward -z, back toward +y.

import * as THREE from 'three';
import * as G from '../world/geom.js';

const _c = new THREE.Color();
export const V3 = (x, y, z) => new THREE.Vector3(x, y, z);
export const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
export const mix = (a, b, t) => a + (b - a) * t;

// cheap deterministic value noise for mottling (no allocation)
function hash3(x, y, z) {
  const s = Math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453;
  return s - Math.floor(s);
}
export function mottle(x, y, z, f = 6) {
  const ix = Math.floor(x * f), iy = Math.floor(y * f), iz = Math.floor(z * f);
  const fx = x * f - ix, fy = y * f - iy, fz = z * f - iz;
  const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy), uz = fz * fz * (3 - 2 * fz);
  const l = (a, b, t) => a + (b - a) * t;
  const c00 = l(hash3(ix, iy, iz), hash3(ix + 1, iy, iz), ux);
  const c10 = l(hash3(ix, iy + 1, iz), hash3(ix + 1, iy + 1, iz), ux);
  const c01 = l(hash3(ix, iy, iz + 1), hash3(ix + 1, iy, iz + 1), ux);
  const c11 = l(hash3(ix, iy + 1, iz + 1), hash3(ix + 1, iy + 1, iz + 1), ux);
  return l(l(c00, c10, uy), l(c01, c11, uy), uz);
}

/**
 * Give a geometry the shared creature attributes.
 * color: hex | fn(x,y,z,c:Color)  glow: number | fn(x,y,z)  fin: number | fn(x,y,z)
 */
export function finish(geo, { color = 0xffffff, glow = 0, fin = 0 } = {}) {
  const g = G.prep(geo, typeof color === 'function' ? 0xffffff : color, glow);
  if (typeof color === 'function') G.colorize(g, color);
  const p = g.attributes.position;
  const arr = new Float32Array(p.count);
  for (let i = 0; i < p.count; i++) arr[i] = typeof fin === 'function' ? fin(p.getX(i), p.getY(i), p.getZ(i)) : fin;
  g.setAttribute('aFin', new THREE.BufferAttribute(arr, 1));
  return g;
}

/** Indexed grid from a point function pt(u, v) -> Vector3, u,v in [0,1]. */
function grid(pt, nu, nv, closedU = false) {
  const pos = [], idx = [];
  const cols = nu + 1;
  for (let j = 0; j <= nv; j++) {
    for (let i = 0; i <= nu; i++) {
      const p = pt(closedU && i === nu ? 0 : i / nu, j / nv);
      pos.push(p.x, p.y, p.z);
    }
  }
  for (let j = 0; j < nv; j++) {
    for (let i = 0; i < nu; i++) {
      const a = j * cols + i, b = a + 1, c = a + cols, d = c + 1;
      idx.push(a, c, d, a, d, b);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  return g;
}

/**
 * Trunk: body of revolution along z with a shaped section.
 * section(t, a) -> [x, y] offset of the surface at length fraction t (0 tail .. 1 head)
 * and angle a (0 = +x, PI/2 = back). Optional helper `ellipse` builds the common case.
 */
export function trunk({ z0, z1, segs = 40, radial = 20, section }) {
  const g = grid((u, v) => {
    const a = u * Math.PI * 2;
    const t = v;
    const [x, y] = section(t, a);
    return V3(x, y, z0 + (z1 - z0) * t);
  }, radial, segs, true);
  // close both ends with a fan to the centre of the end rings
  const pos = Array.from(g.attributes.position.array);
  const idx = Array.from(g.index.array);
  const cols = radial + 1;
  for (const [row, flip] of [[0, true], [segs, false]]) {
    let cx = 0, cy = 0, cz = 0;
    for (let k = 0; k < radial; k++) { const j = (row * cols + k) * 3; cx += pos[j]; cy += pos[j + 1]; cz += pos[j + 2]; }
    const c = pos.length / 3;
    pos.push(cx / radial, cy / radial, cz / radial);
    for (let k = 0; k < radial; k++) {
      const a = row * cols + k, b = a + 1;
      if (flip) idx.push(c, a, b); else idx.push(c, b, a);
    }
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  out.setIndex(idx);
  out.computeVertexNormals();
  return out;
}

/**
 * Elliptical section with a flatter belly and an optional dorsal keel.
 * r: radius, hx/hy: axis scales, belly: 0..1 flattening of the underside,
 * keel: 0..1 pinch of the back into a ridge, yo: vertical offset.
 */
export function ellipse(r, { hx = 1, hy = 1, belly = 0, keel = 0, yo = 0, xo = 0 } = {}) {
  return (a) => {
    const c = Math.cos(a), s = Math.sin(a);
    let x = c * r * hx, y = s * r * hy;
    if (s < 0) y *= 1 - belly * (1 - Math.abs(c) ** 2) * 0.55;
    if (s > 0 && keel > 0) { const k = s ** 6; x *= 1 - keel * k * 0.6; y *= 1 + keel * k * 0.25; }
    return [x + xo, y + yo];
  };
}

/**
 * Membrane fin: a double-sided sheet with lens-shaped thickness.
 * pt(u, v) -> Vector3 mid-surface (u along the root, v from root to edge).
 * thick(u, v) -> half-thickness (should reach ~0 at free edges).
 */
export function membrane(pt, { nu = 10, nv = 6, thick = (u, v) => 0.01 * (1 - v) } = {}) {
  const mid = [];
  for (let j = 0; j <= nv; j++) for (let i = 0; i <= nu; i++) mid.push(pt(i / nu, j / nv));
  const cols = nu + 1;
  const at = (i, j) => mid[Math.min(nv, Math.max(0, j)) * cols + Math.min(nu, Math.max(0, i))];
  const pos = [], idx = [];
  for (const side of [1, -1]) {
    const base = pos.length / 3;
    for (let j = 0; j <= nv; j++) {
      for (let i = 0; i <= nu; i++) {
        const du = at(i + 1, j).clone().sub(at(i - 1, j));
        const dv = at(i, j + 1).clone().sub(at(i, j - 1));
        const n = du.cross(dv).normalize();
        const p = at(i, j).clone().addScaledVector(n, side * thick(i / nu, j / nv));
        pos.push(p.x, p.y, p.z);
      }
    }
    for (let j = 0; j < nv; j++) {
      for (let i = 0; i < nu; i++) {
        const a = base + j * cols + i, b = a + 1, c = a + cols, d = c + 1;
        if (side > 0) idx.push(a, b, d, a, d, c); else idx.push(a, d, b, a, c, d);
      }
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

/** Fin colour: darker rays running root->edge, lighter translucent-looking margin. */
export function finColor(base, rayCount = 9, edge = 0.25, rays = 0.25) {
  const b = new THREE.Color(base);
  return (u, v, c) => {
    const ray = 1 - rays * (Math.abs(Math.sin(u * Math.PI * rayCount)) > 0.85 ? 1 : 0) * (0.4 + v * 0.6);
    const m = 1 + edge * smooth(0.65, 1, v);
    c.setRGB(b.r * ray * m, b.g * ray * m, b.b * ray * m);
  };
}

/**
 * Membrane with per-vertex colour in (u, v) space. Returns a finished geometry.
 * opts: nu, nv, thick, color(u,v,c), glow(u,v)->n, fin(u,v)->n
 */
export function fin(pt, { nu = 10, nv = 6, thick, color, glow, fin: flex } = {}) {
  const g = membrane(pt, { nu, nv, thick });
  const n = g.attributes.position.count;
  const half = n / 2;
  const cols = nu + 1;
  const uv = (i) => { const k = i % half; return [(k % cols) / nu, Math.floor(k / cols) / nv]; };
  const colArr = new Float32Array(n * 3), glowArr = new Float32Array(n), finArr = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const [u, v] = uv(i);
    if (color) { color(u, v, _c); colArr[i * 3] = _c.r; colArr[i * 3 + 1] = _c.g; colArr[i * 3 + 2] = _c.b; } else colArr.fill(1, i * 3, i * 3 + 3);
    glowArr[i] = glow ? glow(u, v) : 0;
    finArr[i] = flex ? flex(u, v) : 0;
  }
  g.setAttribute('color', new THREE.BufferAttribute(colArr, 3));
  g.setAttribute('aGlow', new THREE.BufferAttribute(glowArr, 1));
  g.setAttribute('aFin', new THREE.BufferAttribute(finArr, 1));
  const out = g.toNonIndexed();
  return out;
}

/** Eye: glossy ball with iris and pupil, set into a rim, looking along `dir`. */
export function eye(pos, r, dir, { iris = 0x8a6a20, rim = 0x222222, glow = 0, pupil = 0.45, detail = 1 } = {}) {
  const parts = [];
  const q = new THREE.Quaternion().setFromUnitVectors(V3(0, 0, 1), dir.clone().normalize());
  const ball = new THREE.SphereGeometry(r, Math.max(6, Math.round(14 * detail)), Math.max(4, Math.round(10 * detail)));
  parts.push(finish(ball, {
    color: (x, y, z, c) => {
      const f = z / r; // facing component
      if (f > 0.93 - pupil * 0.1) c.setRGB(0.01, 0.01, 0.012); // pupil
      else if (f > 0.6) { c.set(iris); c.multiplyScalar(0.7 + 0.5 * (f - 0.6) / 0.35); } // iris
      else c.setRGB(0.06, 0.06, 0.06);
    },
    glow: (x, y, z) => (z / r > 0.6 && z / r < 0.93 ? glow : 0),
  }));
  const ring = new THREE.TorusGeometry(r * 1.02, r * 0.22, Math.max(3, Math.round(6 * detail)), Math.max(8, Math.round(18 * detail))).translate(0, 0, r * 0.25);
  parts.push(finish(ring, { color: rim }));
  for (const p of parts) { p.applyQuaternion(q); p.translate(pos.x, pos.y, pos.z); }
  return parts;
}

/** A row of conical teeth along a curve, pointing along tipDir(t). */
export function teeth(curve, n, len, r, tipDir, color = 0xd8d2c0) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const t = (i + 0.5) / n;
    const p = curve(t);
    const d = tipDir(t).normalize();
    const l = typeof len === 'function' ? len(t) : len;
    const g = new THREE.ConeGeometry(r, l, 5, 1);
    g.translate(0, l / 2, 0);
    g.applyQuaternion(new THREE.Quaternion().setFromUnitVectors(V3(0, 1, 0), d));
    g.translate(p.x, p.y, p.z);
    out.push(finish(g, { color: (x, y, z, c) => c.set(color) }));
  }
  return out;
}

/** Tapered limb / tentacle along points with radius r0 -> r1. */
export function limb(points, r0, r1, { radial = 6, segs = 0, color = 0xffffff, glow = 0, fin: flex = 0 } = {}) {
  const pts = points.map((p) => (p.isVector3 ? p : V3(...p)));
  const curve = new THREE.CatmullRomCurve3(pts);
  const n = segs || Math.max(4, pts.length * 4);
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
  return finish(g, { color, glow, fin: flex });
}

export function sphere(pos, r, { sx = 1, sy = 1, sz = 1, w = 10, h = 8, color = 0xffffff, glow = 0, fin: flex = 0 } = {}) {
  const g = new THREE.SphereGeometry(r, w, h).scale(sx, sy, sz).translate(pos.x, pos.y, pos.z);
  return finish(g, { color, glow, fin: flex });
}

export function mergeParts(parts) { return G.merge(parts); }
