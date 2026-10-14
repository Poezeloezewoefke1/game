// High-detail Kestrel submersible model (nose toward +z, origin at the hull's
// centre of buoyancy). Dimensions match the gameplay collision volumes in
// kestrel.js: hull sphere r = 2.1 at the origin, nose sphere r = 1.2 at z = 1.8.
// The pilot camera sits at (0, 0.35, 1.6), inside the acrylic dome.

import * as THREE from 'three';
import { waterMat } from '../world/shading.js';
import { surface } from '../world/surfaces.js';
import { panelTexture, labelTexture } from '../world/textures.js';
import { lathe, duct, sweep, strut, roundedBox, place, Kit } from '../world/shapes.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);
const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

// main pressure hull: elliptical section, circular where it meets the dome ring
const HULL_Z0 = -2.9, HULL_Z1 = 2.05;
function hullSection(t) {
  const z = HULL_Z0 + (HULL_Z1 - HULL_Z0) * t;
  // radius: tail cone -> full body -> collar for the dome
  let r = 0.34 + 0.71 * smooth(-2.9, -0.8, z);
  r -= 0.06 * smooth(1.2, 2.05, z);
  const circ = smooth(1.0, 2.0, z); // 0 = elliptical body, 1 = circular collar
  return { r, hx: 1.2 + (1 - 1.2) * circ, hy: 1.0, y: -0.04 * (1 - circ) };
}

/** Point and outward normal on the hull surface at height y, length z, side sx. */
function hullPoint(z, y, sx) {
  const t = (z - HULL_Z0) / (HULL_Z1 - HULL_Z0);
  const s = hullSection(t);
  const rx = s.r * s.hx, ry = s.r * s.hy;
  const yy = (y - s.y) / ry;
  const x = sx * rx * Math.sqrt(Math.max(0, 1 - yy * yy));
  const n = new THREE.Vector3(x / (rx * rx), (y - s.y) / (ry * ry), 0).normalize();
  return { pos: new THREE.Vector3(x, y, z), normal: n };
}

function orientTo(geo, pos, normal, offset = 0) {
  // geometry authored facing +z; rotate to the normal and move onto the surface
  const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 0, 1), normal);
  geo.applyQuaternion(q);
  geo.translate(pos.x + normal.x * offset, pos.y + normal.y * offset, pos.z + normal.z * offset);
  return geo;
}

function propeller(blades, radius, mat) {
  const g = new THREE.Group();
  const parts = [];
  for (let i = 0; i < blades; i++) {
    const b = roundedBox(radius * 0.86, 0.02, radius * 0.34, 0.01, 1);
    b.translate(radius * 0.5, 0, 0);
    b.rotateX(0.55); // blade pitch
    b.rotateZ((i / blades) * Math.PI * 2);
    parts.push(b);
  }
  parts.push(new THREE.SphereGeometry(radius * 0.22, 12, 8).scale(1, 1, 1.6));
  const kit = new Kit();
  for (const p of parts) kit.add(mat, p);
  kit.build(g, 'propeller');
  return g;
}

export function buildKestrelModel() {
  const root = new THREE.Group();
  root.name = 'kestrel';

  // ---------------- materials (PBR, underwater-patched)
  const panel = panelTexture('#e8e5dc', 11, 0.22);
  panel.repeat.set(4, 3);
  const M = {
    hull: waterMat({ map: panel, roughness: 0.42, metalness: 0.0 }, { surface: surface('paint', { space: 'object', scale: 1.6, strength: 0.25 }), reflect: 1.1 }),
    frame: waterMat({ color: 0x2c3238, roughness: 0.34, metalness: 0.85, side: THREE.DoubleSide }, { surface: surface('paintScratched', { space: 'object', scale: 2.2 }), reflect: 1.2 }),
    orange: waterMat({ color: 0xd8692a, roughness: 0.45, metalness: 0.0 }, { surface: surface('paint', { space: 'object', scale: 1.8, strength: 0.3 }) }),
    chrome: waterMat({ color: 0xb8bec4, roughness: 0.22, metalness: 1.0 }, { reflect: 1.4 }),
    rubber: waterMat({ color: 0x15171a, roughness: 0.85, metalness: 0.0 }),
    glass: waterMat({ color: 0xbfe8f5, roughness: 0.02, metalness: 0.0, transparent: true, opacity: 0.24, depthWrite: false }, { reflect: 2.6 }),
    cabin: waterMat({ color: 0x23282e, roughness: 0.6, metalness: 0.3 }, { surface: surface('deck', { space: 'object', scale: 2.5, strength: 0.4 }) }),
    seat: waterMat({ color: 0x3a2f2a, roughness: 0.75 }, { surface: surface('hide', { scale: 6, strength: 0.5 }) }),
    screen: waterMat({ color: 0x000000, emissive: 0x58d8ff, emissiveIntensity: 1.1, roughness: 0.2 }),
    tint: waterMat({ color: 0x0d1a22, roughness: 0.08, metalness: 0.2 }, { reflect: 1.6 }),
    porthole: waterMat({ color: 0x0a1218, emissive: 0x9fdcff, emissiveIntensity: 0.25, roughness: 0.05 }, { reflect: 1.4 }),
    lamp: waterMat({ color: 0x111111, emissive: 0xd8f4ff, emissiveIntensity: 3 }),
    label: waterMat({ map: labelTexture('KESTREL  DR-02', '#2b3138'), transparent: true, roughness: 0.5 }),
  };
  const kit = new Kit();

  // ---------------- pressure hull + collar + dome
  const hull = lathe({ z0: HULL_Z0, z1: HULL_Z1, segs: 44, radial: 48, section: hullSection, capStart: true, capEnd: false, uvScale: [1, 1] });
  kit.add(M.hull, hull);
  // dark keel fairing under the hull
  kit.add(M.frame, lathe({ z0: -2.3, z1: 1.5, segs: 20, radial: 16, section: (t) => ({ r: 0.32 * Math.sin(Math.PI * Math.min(1, t * 1.15)) + 0.02, hx: 1.6, hy: 0.55, y: -0.98 }) }));
  // dome collar ring and seal
  kit.add(M.frame, place(new THREE.TorusGeometry(1.02, 0.08, 12, 64), [0, 0, 2.05]));
  kit.add(M.orange, place(new THREE.TorusGeometry(1.035, 0.035, 8, 64), [0, 0, 1.94]));
  // bolt ring on the collar
  for (let i = 0; i < 24; i++) {
    const a = (i / 24) * Math.PI * 2;
    kit.add(M.chrome, place(new THREE.CylinderGeometry(0.022, 0.022, 0.04, 6), [Math.cos(a) * 1.03, Math.sin(a) * 1.03, 2.13], [Math.PI / 2, 0, 0]));
  }
  const thetaMax = Math.acos(0.3 / 1.05);
  const dome = new THREE.SphereGeometry(1.05, 48, 28, 0, Math.PI * 2, 0, thetaMax);
  dome.rotateX(Math.PI / 2);
  dome.translate(0, 0, 1.75);
  kit.add(M.glass, dome);

  // ---------------- cockpit interior (seen through the dome; camera sits at z 1.6)
  kit.add(M.cabin, place(new THREE.CircleGeometry(0.98, 40), [0, 0, 0.85]));               // rear bulkhead
  kit.add(M.cabin, place(roundedBox(1.7, 0.08, 1.3, 0.03), [0, -0.62, 1.45]));             // deck plate
  kit.add(M.cabin, place(roundedBox(1.3, 0.34, 0.32, 0.06), [0, -0.38, 2.15], [-0.5, 0, 0])); // console
  for (const x of [-0.36, 0, 0.36]) kit.add(M.screen, place(new THREE.PlaneGeometry(0.28, 0.16), [x, -0.27, 2.25], [-0.5, 0, 0]));
  for (const sx of [-1, 1]) {
    kit.add(M.seat, place(roundedBox(0.46, 0.12, 0.48, 0.05), [sx * 0.42, -0.5, 1.15]));
    kit.add(M.seat, place(roundedBox(0.46, 0.62, 0.12, 0.05), [sx * 0.42, -0.18, 0.93], [-0.12, 0, 0]));
    kit.add(M.chrome, place(new THREE.CylinderGeometry(0.02, 0.025, 0.24, 8), [sx * 0.3, -0.42, 1.75], [-0.4, 0, 0])); // control sticks
  }

  // ---------------- dorsal fairing (sail) with hatch, mast and grab rails
  kit.add(M.hull, lathe({ z0: -1.9, z1: 1.0, segs: 24, radial: 24, section: (t) => ({ r: 0.42 * Math.sin(Math.PI * Math.pow(t, 0.8)) + 0.03, hx: 1.25, hy: 0.62, y: 0.9 }) }));
  kit.add(M.frame, place(new THREE.TorusGeometry(0.32, 0.05, 8, 32), [0, 1.17, -0.35], [Math.PI / 2, 0, 0]));
  kit.add(M.frame, place(new THREE.CylinderGeometry(0.3, 0.3, 0.06, 32), [0, 1.18, -0.35]));
  kit.add(M.chrome, place(new THREE.CylinderGeometry(0.04, 0.04, 0.32, 8), [0.22, 1.24, -0.35], [0, 0, Math.PI / 2]));
  kit.add(M.frame, strut(V(0, 1.15, -1.25), V(0, 1.85, -1.45), 0.035));
  kit.add(M.frame, place(new THREE.CylinderGeometry(0.06, 0.06, 0.14, 10), [0, 1.9, -1.46]));
  for (const sx of [-1, 1]) {
    kit.add(M.chrome, sweep([V(sx * 0.48, 1.0, 0.7), V(sx * 0.5, 1.12, 0.3), V(sx * 0.52, 1.12, -0.9), V(sx * 0.48, 0.98, -1.4)], 0.025, 0.025, 6, 24));
  }

  // ---------------- side sponsons (ballast/trim tanks) with safety stripes
  const sponson = lathe({ z0: -2.4, z1: 1.55, segs: 24, radial: 20, section: (t) => ({ r: 0.34 * Math.pow(Math.sin(Math.PI * t), 0.35) + 0.02, hx: 1.0, hy: 1.12 }) });
  for (const sx of [-1, 1]) {
    kit.add(M.hull, place(sponson.clone(), [sx * 1.24, -0.62, 0]));
    kit.add(M.orange, place(new THREE.TorusGeometry(0.355, 0.03, 8, 28), [sx * 1.24, -0.62, 0.95]));
    kit.add(M.orange, place(new THREE.TorusGeometry(0.36, 0.03, 8, 28), [sx * 1.24, -0.62, -1.7]));
    // struts joining sponson and hull
    for (const z of [1.0, -0.2, -1.5]) {
      const hp = hullPoint(z, -0.5, sx);
      kit.add(M.frame, strut(hp.pos.clone().addScaledVector(hp.normal, -0.05), V(sx * 1.08, -0.6, z), 0.055, 8));
    }
    // one forward observation viewport per side, flush on the curved hull
    {
      const hp = hullPoint(1.25, 0.18, sx);
      kit.add(M.frame, orientTo(new THREE.TorusGeometry(0.21, 0.04, 8, 32), hp.pos, hp.normal, 0.0));
      kit.add(M.porthole, orientTo(new THREE.CircleGeometry(0.2, 32), hp.pos, hp.normal, 0.01));
      for (let i = 0; i < 8; i++) {
        const a = (i / 8) * Math.PI * 2;
        const b = new THREE.SphereGeometry(0.018, 6, 4);
        b.translate(Math.cos(a) * 0.255, Math.sin(a) * 0.255, 0);
        kit.add(M.chrome, orientTo(b, hp.pos, hp.normal, 0.01));
      }
    }
    // service hatch panel outline on the flank
    {
      const hp = hullPoint(-0.9, 0.05, sx);
      kit.add(M.frame, orientTo(roundedBox(0.7, 0.42, 0.02, 0.06), hp.pos, hp.normal, 0.0));
      kit.add(M.hull, orientTo(roundedBox(0.64, 0.36, 0.02, 0.05), hp.pos, hp.normal, 0.008));
    }
  }

  // ---------------- landing skids
  for (const sx of [-1, 1]) {
    kit.add(M.frame, sweep([V(sx * 0.95, -1.38, -1.9), V(sx * 0.95, -1.42, -0.5), V(sx * 0.95, -1.4, 1.1), V(sx * 0.93, -1.2, 1.7)], 0.055, 0.05, 8, 24));
    kit.add(M.rubber, place(roundedBox(0.16, 0.06, 2.6, 0.025), [sx * 0.95, -1.46, -0.4]));
    for (const z of [-1.5, -0.2, 1.0]) kit.add(M.frame, strut(V(sx * 0.95, -1.38, z), V(sx * 0.62, -0.88, z + 0.1), 0.04));
  }

  // ---------------- light bar above the dome + chin lights + sonar
  kit.add(M.frame, sweep([V(-0.95, 0.72, 1.5), V(-0.5, 1.02, 1.62), V(0.5, 1.02, 1.62), V(0.95, 0.72, 1.5)], 0.04, 0.04, 8, 30));
  for (const x of [-0.62, -0.22, 0.22, 0.62]) {
    const y = 0.98 - Math.abs(x) * 0.18;
    kit.add(M.frame, place(new THREE.CylinderGeometry(0.11, 0.09, 0.16, 16), [x, y + 0.04, 1.74], [Math.PI / 2, 0, 0]));
    kit.add(M.lamp, place(new THREE.CircleGeometry(0.085, 16), [x, y + 0.04, 1.825]));
  }
  for (const sx of [-1, 1]) {
    kit.add(M.frame, place(new THREE.CylinderGeometry(0.13, 0.11, 0.2, 16), [sx * 0.62, -0.78, 1.82], [Math.PI / 2, 0, 0]));
    kit.add(M.lamp, place(new THREE.CircleGeometry(0.1, 16), [sx * 0.62, -0.78, 1.925]));
  }
  kit.add(M.tint, place(new THREE.SphereGeometry(0.2, 20, 12, 0, Math.PI * 2, 0, Math.PI / 2), [0, -0.98, 1.0], [Math.PI, 0, 0]));
  // instrument boom on the bow with a camera pod
  kit.add(M.frame, strut(V(0.75, 0.55, 1.6), V(1.05, 0.6, 2.05), 0.03));
  kit.add(M.frame, place(roundedBox(0.18, 0.16, 0.24, 0.04), [1.07, 0.6, 2.12]));
  kit.add(M.tint, place(new THREE.CircleGeometry(0.05, 16), [1.07, 0.6, 2.245]));

  // ---------------- aft thrusters: two main ducts on pylons + tail cap
  const props = [];
  const mainDuct = duct(0.42, 0.62, 0.075, 40);
  for (const sx of [-1, 1]) {
    const cx = sx * 0.95, cy = -0.12, cz = -2.75;
    kit.add(M.frame, place(mainDuct.clone(), [cx, cy, cz]));
    kit.add(M.orange, place(new THREE.TorusGeometry(0.47, 0.022, 6, 40), [cx, cy, cz - 0.18]));
    kit.add(M.frame, place(roundedBox(0.7, 0.1, 0.5, 0.04), [sx * 0.6, -0.1, -2.45], [0, 0, 0]));
    // stator vanes + motor pod
    kit.add(M.frame, lathe({ z0: cz - 0.05, z1: cz + 0.55, segs: 10, radial: 16, section: (t) => ({ r: 0.12 * Math.sin(Math.PI * (0.25 + t * 0.75)) + 0.02, x: cx, y: cy }) }));
    for (let i = 0; i < 3; i++) {
      const a = (i / 3) * Math.PI * 2 + 0.5;
      kit.add(M.frame, strut(V(cx, cy, cz + 0.12), V(cx + Math.cos(a) * 0.4, cy + Math.sin(a) * 0.4, cz + 0.12), 0.018, 6));
    }
    const p = propeller(5, 0.38, M.chrome);
    p.position.set(cx, cy, cz - 0.05);
    root.add(p);
    props.push({ obj: p, axis: 'z', kind: 'main', dir: sx });
  }
  kit.add(M.frame, place(new THREE.SphereGeometry(0.34, 20, 12), [0, -0.04, -2.9], [0, 0, 0], [1, 0.95, 0.5]));
  kit.add(M.lamp, place(new THREE.SphereGeometry(0.045, 8, 6), [0, 0.05, -3.07]));

  // ---------------- vertical thrusters: flush grilles in the sponson tops
  for (const sx of [-1, 1]) {
    for (const z of [0.6, -1.55]) {
      const x = sx * 1.24, y = -0.245;
      kit.add(M.frame, place(new THREE.TorusGeometry(0.17, 0.025, 6, 24), [x, y, z], [Math.PI / 2, 0, 0]));
      for (let b = -2; b <= 2; b++) kit.add(M.frame, place(roundedBox(0.3 - Math.abs(b) * 0.05, 0.012, 0.022, 0.005, 1), [x, y + 0.01, z + b * 0.06]));
      const p = propeller(4, 0.15, M.chrome);
      p.rotation.x = -Math.PI / 2;
      p.position.set(x, y - 0.06, z);
      root.add(p);
      props.push({ obj: p, axis: 'z', kind: 'vertical', dir: sx });
    }
  }

  // ---------------- name label conforming to the hull side
  for (const sx of [-1, 1]) {
    const lg = new THREE.PlaneGeometry(1.5, 0.22, 16, 1);
    const p = lg.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const z = -p.getX(i) * sx - 1.35, y = p.getY(i) + 0.55;
      const t = (z - HULL_Z0) / (HULL_Z1 - HULL_Z0);
      const s = hullSection(t);
      const rx = s.r * s.hx, ry = s.r * s.hy;
      const yy = (y - s.y) / ry;
      p.setXYZ(i, sx * (rx * Math.sqrt(Math.max(0, 1 - yy * yy)) + 0.012), y, z);
    }
    lg.computeVertexNormals();
    const lm = new THREE.Mesh(lg, M.label);
    root.add(lm);
  }

  // ---------------- manipulator arms (folded under the bow)
  const arms = [];
  for (const sx of [-1, 1]) {
    const shoulder = new THREE.Group();
    shoulder.position.set(sx * 0.5, -0.82, 1.45);
    const ak = new Kit();
    ak.add(M.frame, place(new THREE.SphereGeometry(0.1, 14, 10), [0, 0, 0]));
    ak.add(M.frame, place(roundedBox(0.1, 0.1, 0.62, 0.03), [0, 0, 0.3]));
    ak.add(M.orange, place(roundedBox(0.105, 0.03, 0.4, 0.012), [0, 0.06, 0.3]));
    ak.build(shoulder, 'arm');
    const elbow = new THREE.Group();
    elbow.position.set(0, 0, 0.62);
    const ek = new Kit();
    ek.add(M.chrome, place(new THREE.CylinderGeometry(0.075, 0.075, 0.14, 14), [0, 0, 0], [0, 0, Math.PI / 2]));
    ek.add(M.frame, place(roundedBox(0.08, 0.08, 0.5, 0.025), [0, 0, 0.25]));
    ek.add(M.chrome, place(new THREE.CylinderGeometry(0.05, 0.05, 0.08, 10), [0, 0, 0.52], [Math.PI / 2, 0, 0]));
    // two-finger claw
    for (const f of [-1, 1]) {
      ek.add(M.frame, sweep([V(f * 0.02, 0, 0.55), V(f * 0.07, 0, 0.64), V(f * 0.04, 0, 0.74)], 0.018, 0.012, 6, 8));
    }
    ek.build(elbow, 'arm');
    shoulder.add(elbow);
    root.add(shoulder);
    // folded rest pose: upper arm forward-down, forearm tucked back
    shoulder.rotation.set(0.55, sx * 0.08, 0);
    elbow.rotation.set(-2.3, 0, 0);
    arms.push({ shoulder, elbow, side: sx, rest: { s: 0.55, e: -2.3 } });
  }

  // status strobe on the mast (kept as a separate mesh: its colour changes with power)
  const statusLight = new THREE.Mesh(new THREE.SphereGeometry(0.06, 10, 8), waterMat({ color: 0x111111, emissive: 0xff3b2b, emissiveIntensity: 3 }));
  statusLight.position.set(0, 1.99, -1.46);
  root.add(statusLight);

  kit.build(root, 'kestrel_hull');
  return { group: root, props, arms, lampM: M.lamp, statusLight };
}
