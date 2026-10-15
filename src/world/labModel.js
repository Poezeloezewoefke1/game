// Exterior detail for Echo Lab. The walkable interior and every collider stay
// in Structures.buildEchoLab; these parts sit on the outside of the walls
// (<= 0.25 m proud) or below the floor, so play space is unchanged.
// Local frame: main module x -8..8, z -4..4, floor y 0, roof y 4.5..4.9.

import * as THREE from 'three';
import { Kit, strut, roundedBox, place, sweep } from './shapes.js';
import { waterMat } from './shading.js';
import { surface } from './surfaces.js';
import { mulberry32 } from '../core/noise.js';
import { fbm3 } from './rocks.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);

export function buildEchoLabExterior(group, M, H = 4.5, groundAt = () => -2.6) {
  const rnd = mulberry32(17);
  const kit = new Kit();
  const silt = waterMat({ color: 0xc4c0b0, roughness: 1 }, { detail: 0.8, surface: surface('seabed') });
  const growth = waterMat({ color: 0x55603e, roughness: 0.95 }, { detail: 0.6, surface: surface('coral', { strength: 0.7 }) });
  const edge = (a, b, r = 0.26) => kit.add(M.lab, strut(a, b, r, 12));

  // ---- rounded edge fairings on the three volumes
  const box = (x0, x1, y0, y1, z0, z1, skipTop = null) => {
    for (const x of [x0, x1]) for (const z of [z0, z1]) edge(V(x, y0, z), V(x, y1, z));
    for (const z of [z0, z1]) {
      if (!skipTop) edge(V(x0, y1, z), V(x1, y1, z));
      else { edge(V(x0, y1, z), V(skipTop[0], y1, z)); edge(V(skipTop[1], y1, z), V(x1, y1, z)); }
      edge(V(x0, y0, z), V(x1, y0, z));
    }
    for (const x of [x0, x1]) { edge(V(x, y1, z0), V(x, y1, z1)); edge(V(x, y0, z0), V(x, y0, z1)); }
  };
  box(-8, 8, -0.4, H + 0.4, -4, 4, [1, 4.5]);
  box(11, 19, -0.4, 4.4, -3, 3);
  // corridor: ribbed pressure tube look
  for (const x of [8.4, 9.5, 10.6]) {
    for (const [y, z0, z1] of [[-0.3, -1.35, 1.35], [3.3, -1.35, 1.35]]) kit.add(M.hullDark, strut(V(x, y, z0), V(x, y, z1), 0.12, 8));
    for (const z of [-1.35, 1.35]) kit.add(M.hullDark, strut(V(x, -0.3, z), V(x, 3.3, z), 0.12, 8));
  }

  // ---- external frames (U-channels over the walls and roof)
  for (let x = -6; x <= 6; x += 2) {
    const overBreach = x > 0.8 && x < 4.7;
    for (const z of [-4.12, 4.12]) {
      if (Math.abs(x + 5) < 1 || Math.abs(x + 1.5) < 1 || Math.abs(x - 2) < 1 || Math.abs(x - 5.5) < 1) continue; // keep windows clear
      kit.add(M.hullDark, place(roundedBox(0.28, H + 0.6, 0.16, 0.05), [x, H / 2, z]));
    }
    if (!overBreach) kit.add(M.hullDark, place(roundedBox(0.28, 0.16, 8.3, 0.05), [x, H + 0.48, 0]));
  }
  for (let x = 12.5; x <= 17.5; x += 2.5) {
    for (const z of [-3.12, 3.12]) kit.add(M.hullDark, place(roundedBox(0.28, 4.6, 0.16, 0.05), [x, 2, z]));
    kit.add(M.hullDark, place(roundedBox(0.28, 0.16, 6.3, 0.05), [x, 4.48, 0]));
  }

  // ---- window frames (4 per long side)
  for (let i = 0; i < 4; i++) {
    const x = -5 + i * 3.5;
    for (const sz of [-1, 1]) {
      const z = sz * 4.24;
      kit.add(M.hullDark, place(roundedBox(2.0, 0.14, 0.12, 0.04), [x, 3.07, z]));
      kit.add(M.hullDark, place(roundedBox(2.0, 0.14, 0.12, 0.04), [x, 2.13, z]));
      for (const dx of [-0.93, 0.93]) kit.add(M.hullDark, place(roundedBox(0.14, 1.08, 0.12, 0.04), [x + dx, 2.6, z]));
      if (sz < 0) kit.add(M.orange, place(roundedBox(0.4, 0.12, 0.2, 0.04), [x, 3.3, z])); // eyebrow lamp housing (south side carries the name board)
    }
  }

  // ---- conduits along the north wall with brackets and drops
  for (const y of [0.7, 3.85]) {
    kit.add(M.orange, sweep([V(-7.6, y, -4.32), V(0, y, -4.32), V(7.6, y, -4.32)], 0.09, 0.09, 8, 24));
    for (let x = -7; x <= 7; x += 1.75) kit.add(M.hullDark, place(roundedBox(0.12, 0.28, 0.22, 0.03), [x, y, -4.2]));
  }
  kit.add(M.orange, sweep([V(7.6, 3.85, -4.32), V(8.2, 3.6, -4.4), V(8.3, 1.0, -4.4), V(8.6, -0.6, -4.2)], 0.09, 0.09, 8, 16));
  kit.add(M.hullDark, sweep([V(-7.8, 2.0, 4.3), V(-8.6, 1.0, 4.5), V(-9.5, -1.0, 4.8), V(-11, -1.6, 5.6)], 0.11, 0.11, 8, 16)); // umbilical to the seabed

  // ---- braced legs and foot pads under the main module and workshop
  for (const [lx, lz] of [[-7, -3.5], [-7, 3.5], [0, -3.5], [0, 3.5], [7, -3.5], [7, 3.5], [12, -2.5], [12, 2.5], [18, -2.5], [18, 2.5]]) {
    const gy = Math.min(-0.8, groundAt(lx, lz));
    kit.add(M.hullDark, strut(V(lx, -0.4, lz), V(lx, gy, lz), 0.22, 10));
    kit.add(M.hullDark, place(new THREE.CylinderGeometry(0.75, 0.9, 0.3, 14), [lx, gy + 0.05, lz]));
    kit.add(M.orange, place(new THREE.CylinderGeometry(0.28, 0.28, 0.18, 12), [lx, -0.9, lz]));
  }
  for (const lz of [-3.5, 3.5]) for (const [a, b] of [[-7, 0], [0, 7]]) {
    const ga = Math.min(-0.8, groundAt(a, lz)) + 0.3, gb = Math.min(-0.8, groundAt(b, lz)) + 0.3;
    kit.add(M.hullDark, strut(V(a, -0.5, lz), V(b, gb, lz), 0.07, 6));
    kit.add(M.hullDark, strut(V(b, -0.5, lz), V(a, ga, lz), 0.07, 6));
  }

  // ---- roof plant: HVAC unit with fan, reel, hatch, tilted floodlight
  kit.add(M.lab, place(roundedBox(2.2, 0.9, 1.6, 0.12), [-5.4, H + 0.85, -1.8]));
  kit.add(M.hullDark, place(new THREE.TorusGeometry(0.55, 0.06, 6, 20), [-5.4, H + 1.31, -1.8], [Math.PI / 2, 0, 0]));
  for (let k = 0; k < 5; k++) kit.add(M.hullDark, place(roundedBox(0.95, 0.03, 0.12, 0.01), [-5.4, H + 1.3, -1.8], [0, (k / 5) * Math.PI, 0]));
  kit.add(M.orange, place(new THREE.CylinderGeometry(0.5, 0.5, 0.7, 16), [-2.3, H + 0.95, 2.4], [0, 0, Math.PI / 2]));
  kit.add(M.hullDark, place(new THREE.CylinderGeometry(0.75, 0.75, 0.12, 20), [15, 4.47, 1.2]));
  kit.add(M.hullDark, strut(V(6.6, H + 0.4, 2.8), V(6.6, H + 1.6, 2.8), 0.06, 6));
  kit.add(M.hullDark, place(roundedBox(0.5, 0.35, 0.4, 0.06), [6.6, H + 1.7, 2.8], [0.5, 0.4, 0]));

  // ---- torn plating around the roof breach and the west wall breach
  for (let k = 0; k < 12; k++) {
    const x = 1 + rnd() * 3.5, z = (rnd() - 0.5) * 7.4;
    const edgeX = rnd() < 0.5 ? 1 : 4.5;
    const g = new THREE.PlaneGeometry(0.5 + rnd() * 0.6, 0.6 + rnd() * 0.9, 2, 2);
    place(g, [edgeX + (edgeX === 1 ? 0.2 : -0.2), H + 0.3 + rnd() * 0.3, z], [-Math.PI / 2 + (edgeX === 1 ? 0.6 : -0.6) + (rnd() - 0.5) * 0.4, 0, (rnd() - 0.5) * 0.6]);
    void x;
    kit.add(M.rustDark, g);
  }
  for (let k = 0; k < 9; k++) {
    const z = (rnd() < 0.5 ? -1.5 : 1.5) + (rnd() - 0.5) * 0.3, y = 0.4 + rnd() * (H - 1.4);
    const g = new THREE.PlaneGeometry(0.4 + rnd() * 0.5, 0.5 + rnd() * 0.7, 2, 2);
    place(g, [-8.25, y, z], [0, Math.PI / 2 + (z > 0 ? 0.7 : -0.7), (rnd() - 0.5) * 0.8]);
    kit.add(M.rustDark, g);
  }

  // ---- silt drifts against the walls and growth on the roof
  for (let k = 0; k < 16; k++) {
    const side = k % 4;
    const t = (rnd() - 0.5) * 2;
    const [x, z] = side === 0 ? [t * 7, -4.6] : side === 1 ? [t * 7, 4.6] : side === 2 ? [-8.6, t * 3] : [15 + t * 3.5, 3.6];
    const g = new THREE.SphereGeometry(1, 12, 6, 0, Math.PI * 2, 0, Math.PI / 2).scale(1.6 + rnd() * 1.4, 0.28 + rnd() * 0.25, 1.0 + rnd() * 0.6);
    kit.add(silt, place(g, [x, groundAt(x, z) - 0.1, z], [0, rnd() * 3, 0]));
  }
  for (let k = 0; k < 10; k++) {
    const x = -7 + rnd() * 14, z = (rnd() - 0.5) * 7;
    if (x > 0.6 && x < 4.9) continue;
    const r = 0.3 + rnd() * 0.5;
    const g = new THREE.SphereGeometry(r, 9, 5, 0, Math.PI * 2, 0, Math.PI / 2).scale(1, 0.35 + fbm3(x, z, 1, 2) * 0.2, 1);
    kit.add(growth, place(g, [x, H + 0.4, z]));
  }
  return kit.build(group, 'echoLabExterior');
}
