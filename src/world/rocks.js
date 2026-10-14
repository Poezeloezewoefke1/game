// Fractured boulders for the graphics rebuild. A dense icosphere is lumped
// with 3D noise, then sliced by random fracture planes (the flat faces and
// crisp edges of broken rock), roughened, optionally stepped into strata,
// and painted with cavity darkening, silt on top faces and algae patches.
// Output matches geom.js (non-indexed, normal, color, aGlow) so it drops
// into the existing instanced scatter and cave builders.

import * as THREE from 'three';
import { mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';
import { mulberry32 } from '../core/noise.js';
import * as G from './geom.js';

function hash3(x, y, z) {
  const s = Math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453;
  return s - Math.floor(s);
}
function vnoise(x, y, z) {
  const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
  const fx = x - ix, fy = y - iy, fz = z - iz;
  const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy), uz = fz * fz * (3 - 2 * fz);
  const l = (a, b, t) => a + (b - a) * t;
  return l(
    l(l(hash3(ix, iy, iz), hash3(ix + 1, iy, iz), ux), l(hash3(ix, iy + 1, iz), hash3(ix + 1, iy + 1, iz), ux), uy),
    l(l(hash3(ix, iy, iz + 1), hash3(ix + 1, iy, iz + 1), ux), l(hash3(ix, iy + 1, iz + 1), hash3(ix + 1, iy + 1, iz + 1), ux), uy),
    uz) * 2 - 1;
}
export function fbm3(x, y, z, oct = 4) {
  let a = 0.5, f = 1, s = 0;
  for (let i = 0; i < oct; i++) { s += vnoise(x * f, y * f, z * f) * a; f *= 2.03; a *= 0.5; }
  return s;
}

/**
 * opts: detail (icosphere subdivisions), cuts (fracture planes), strata (0..1 ledge strength),
 *       tone ([r,g,b] base colour), flat (0..1 underside flattening), moss (0..1)
 */
export function boulderGeometry(seed = 1, { detail = 8, cuts = 7, strata = 0, tone = null, flat = 0.5, moss = 1 } = {}) {
  const rnd = mulberry32(seed * 7919 + 13);
  let g = new THREE.IcosahedronGeometry(1, detail);
  g.deleteAttribute('normal');
  g.deleteAttribute('uv');
  g = mergeVertices(g, 1e-5);
  const p = g.attributes.position;
  const sx = 0.85 + rnd() * 0.4, sy = 0.6 + rnd() * 0.35, sz = 0.85 + rnd() * 0.4;
  const ox = rnd() * 50, oy = rnd() * 50, oz = rnd() * 50;
  const planes = [];
  for (let i = 0; i < cuts; i++) {
    const th = rnd() * Math.PI * 2, el = (rnd() - 0.35) * 1.5;
    const n = new THREE.Vector3(Math.cos(th) * Math.cos(el), Math.sin(el), Math.sin(th) * Math.cos(el)).normalize();
    planes.push({ n, o: 0.62 + rnd() * 0.3 });
  }
  const v = new THREE.Vector3(), q = new THREE.Vector3();
  const strataF = 4 + rnd() * 3, strataTilt = (rnd() - 0.5) * 0.5;
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i); // unit sphere direction
    q.copy(v).multiplyScalar(1 + 0.28 * fbm3(v.x * 1.4 + ox, v.y * 1.4 + oy, v.z * 1.4 + oz, 3));
    q.set(q.x * sx, q.y * sy, q.z * sz);
    for (const pl of planes) {
      const d = q.dot(pl.n) - pl.o;
      if (d > 0) q.addScaledVector(pl.n, -d * 0.93);
    }
    if (q.y < -0.25) q.y = -0.25 + (q.y + 0.25) * (1 - flat); // seated underside
    // surface roughness along the original direction (keeps the cuts mostly flat)
    const r1 = fbm3(v.x * 5 + ox, v.y * 5 + oy, v.z * 5 + oz, 3);
    const r2 = vnoise(v.x * 16 + oy, v.y * 16 + oz, v.z * 16 + ox);
    q.addScaledVector(v, r1 * 0.045 + r2 * 0.012);
    if (strata > 0) {
      // sedimentary ledges: step the height on steep sides
      const side = 1 - Math.abs(v.y);
      const layer = (q.y + q.x * strataTilt) * strataF;
      const step = Math.floor(layer) + Math.min(1, (layer - Math.floor(layer)) * 2.5);
      q.y += ((step / strataF - q.x * strataTilt) - q.y) * strata * side * 0.6;
    }
    p.setXYZ(i, q.x, q.y, q.z);
  }
  g.computeVertexNormals();
  const out = G.prep(g.toNonIndexed(), 0xffffff, 0);
  const pos = out.attributes.position, nor = out.attributes.normal, col = out.attributes.color;
  const base = new THREE.Color(...(tone || [0.4 + rnd() * 0.06, 0.4 + rnd() * 0.05, 0.42 + rnd() * 0.05]));
  const silt = new THREE.Color(0.58, 0.55, 0.48), algae = new THREE.Color(0.28, 0.36, 0.22);
  const c = new THREE.Color();
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i), ny = nor.getY(i);
    const cav = fbm3(x * 6 + ox, y * 6 + oy, z * 6 + oz, 3); // pits and cracks
    const mot = fbm3(x * 2.2 + oz, y * 2.2 + ox, z * 2.2 + oy, 2);
    c.copy(base).multiplyScalar(0.82 + mot * 0.35 + Math.min(0, cav) * 0.9);
    if (strata > 0 && Math.abs(((y * strataF) % 1 + 1) % 1 - 0.5) < 0.06) c.multiplyScalar(0.7);
    const top = THREE.MathUtils.smoothstep(ny, 0.45, 0.85);
    c.lerp(silt, top * (0.45 + 0.3 * mot));
    if (moss > 0) {
      const m = THREE.MathUtils.smoothstep(fbm3(x * 3.1 + 7, y * 3.1, z * 3.1 - 3, 2), 0.05, 0.35) * THREE.MathUtils.smoothstep(ny, 0.1, 0.6);
      c.lerp(algae, m * 0.7 * moss);
    }
    if (y < -0.15) c.multiplyScalar(0.75 + 0.25 * THREE.MathUtils.smoothstep(y, -0.3, -0.15));
    col.setXYZ(i, c.r, c.g, c.b);
  }
  return out;
}
