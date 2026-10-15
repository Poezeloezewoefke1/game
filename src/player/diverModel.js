// Full diver model for the third-person view and the customisation preview.
// Origin at the eye (helmet centre), upright +y, facing -z. ~1.85 m with fins.

import * as THREE from 'three';
import { roundedBox, lathe, sweep } from '../world/shapes.js';
import { buildScanner, buildSleeve, applyLook, makeGearMaterials } from './gear.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);

function add(parent, geo, mat, pos, rot) {
  const m = new THREE.Mesh(geo, mat);
  if (pos) m.position.set(...pos);
  if (rot) m.rotation.set(...rot);
  m.castShadow = false;
  parent.add(m);
  return m;
}

function tube(len, r0, r1, pad = 0.05) {
  return lathe({ z0: 0, z1: len, segs: 14, radial: 16, section: (t) => ({ r: (r0 + (r1 - r0) * t) * (1 + pad * Math.max(0, Math.sin(t * Math.PI * 4))) }) });
}

function nameTexture(name, accent) {
  const c = document.createElement('canvas');
  c.width = 256; c.height = 64;
  const g = c.getContext('2d');
  g.fillStyle = '#1a1d20'; g.fillRect(0, 0, 256, 64);
  g.fillStyle = `#${accent.toString(16).padStart(6, '0')}`; g.fillRect(0, 0, 14, 64);
  g.fillStyle = '#e8e6de';
  g.font = '600 30px "Space Grotesk", sans-serif';
  g.textBaseline = 'middle';
  g.fillText((name || '').slice(0, 14), 26, 34);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

export class DiverModel {
  constructor(look) {
    this.M = makeGearMaterials();
    this.root = new THREE.Group();
    this.root.name = 'diver';
    this.body = new THREE.Group(); // tilts between upright and prone
    this.root.add(this.body);
    this.kick = 0;
    this.setLook(look, true);
  }

  setLook(look, force = false) {
    const c = applyLook(this.M, look);
    const rebuild = force || !this.look || this.look.pattern !== look.pattern || this.look.name !== look.name || this.look.accent !== look.accent;
    this.look = { ...look };
    this.colors = c;
    if (rebuild) this.build();
  }

  build() {
    const M = this.M, P = this.look.pattern;
    this.body.clear();
    const b = this.body;
    // ---------------- helmet
    const head = new THREE.Group();
    b.add(head);
    this.head = head;
    add(head, new THREE.SphereGeometry(0.175, 28, 20), M.suit);
    // wide faceplate on the front (-z): sphere segment centred on phi = -PI/2
    add(head, new THREE.SphereGeometry(0.179, 32, 18, -Math.PI / 2 - Math.PI * 0.33, Math.PI * 0.66, Math.PI * 0.27, Math.PI * 0.36), M.visor);
    add(head, new THREE.TorusGeometry(0.168, 0.009, 6, 40, Math.PI * 0.66), M.suitDark, [0, 0.012, 0], [Math.PI / 2, 0, Math.PI + Math.PI * 0.17]);
    for (const s of [-1, 1]) {
      const lamp = add(head, new THREE.CylinderGeometry(0.03, 0.034, 0.08, 14), M.scanBody, [s * 0.17, 0.05, -0.02], [Math.PI / 2, 0, 0]);
      add(lamp, new THREE.CircleGeometry(0.026, 14), M.emit, [0, 0.041, 0], [-Math.PI / 2, 0, 0]);
    }
    add(head, new THREE.CylinderGeometry(0.004, 0.004, 0.16, 6), M.metal, [0.08, 0.2, 0.06], [0.2, 0, -0.2]);
    add(head, new THREE.TorusGeometry(0.13, 0.025, 10, 30), M.metal, [0, -0.17, 0], [Math.PI / 2, 0, 0]); // neck ring
    // ---------------- torso
    const torso = lathe({ z0: 0, z1: 0.58, segs: 18, radial: 22, section: (t) => {
      const chest = 1 + 0.12 * Math.sin(Math.min(1, t * 1.4) * Math.PI);
      return { r: 0.16 * chest * (1 - 0.18 * t), hx: 1.32, hy: 0.85 };
    } });
    torso.rotateX(Math.PI / 2); // z -> -y
    add(b, torso, M.suit, [0, -0.2, 0.01]);
    add(b, roundedBox(0.3, 0.2, 0.06, 0.03, 3), P === 'panels' ? M.accent : M.suitDark, [0, -0.36, -0.13]); // chest plate
    add(b, new THREE.PlaneGeometry(0.15, 0.038), new THREE.MeshStandardMaterial({ map: nameTexture(this.look.name, this.colors.accent), roughness: 0.6 }), [0, -0.31, -0.162]);
    for (const s of [-1, 1]) add(b, roundedBox(0.045, 0.5, 0.02, 0.01, 2), M.rubber, [s * 0.09, -0.42, -0.14], [0, 0, s * 0.12]); // harness straps
    add(b, roundedBox(0.4, 0.06, 0.3, 0.025, 2), M.rubber, [0, -0.74, 0.0]); // belt
    for (const s of [-1, 1]) add(b, roundedBox(0.08, 0.09, 0.05, 0.015, 2), M.suitDark, [s * 0.15, -0.76, -0.14]);
    add(b, roundedBox(0.06, 0.04, 0.03, 0.01, 2), M.metal, [0, -0.74, -0.155]);
    // hips / pelvis
    add(b, new THREE.SphereGeometry(0.17, 18, 12).scale(1.2, 0.7, 0.9), M.suit, [0, -0.82, 0.01]);
    // ---------------- backpack: twin tanks, manifold and hoses
    add(b, roundedBox(0.36, 0.48, 0.07, 0.03, 3), M.suitDark, [0, -0.42, 0.17]);
    for (const s of [-1, 1]) {
      const tank = lathe({ z0: 0, z1: 0.58, segs: 12, radial: 18, section: (t) => ({ r: 0.085 * Math.min(1, Math.sin(Math.min(1, t * 6) * Math.PI / 2) ** 0.4, Math.sin(Math.min(1, (1 - t) * 6) * Math.PI / 2) ** 0.4) + 0.01 }) });
      tank.rotateX(Math.PI / 2);
      add(b, tank, P === 'hazard' ? M.hazard : M.accent, [s * 0.095, -0.12, 0.27]);
      add(b, new THREE.CylinderGeometry(0.022, 0.022, 0.05, 10), M.metal, [s * 0.095, -0.1, 0.27]);
      add(b, new THREE.TorusGeometry(0.087, 0.006, 6, 20), M.rubber, [s * 0.095, -0.5, 0.27], [Math.PI / 2, 0, 0]);
      add(b, sweep([V(s * 0.095, -0.08, 0.27), V(s * 0.16, -0.02, 0.18), V(s * 0.17, -0.12, 0.02), V(s * 0.12, -0.16, -0.05)], 0.012, 0.012, 6, 14), M.rubber);
    }
    add(b, new THREE.CylinderGeometry(0.018, 0.018, 0.2, 10), M.metal, [0, -0.08, 0.27], [0, 0, Math.PI / 2]);
    // ---------------- arms (shoulder -> elbow -> wrist), right hand holds the scanner
    this.arms = [];
    for (const s of [-1, 1]) {
      const sh = new THREE.Group();
      sh.position.set(s * 0.25, -0.3, 0.0);
      b.add(sh);
      add(sh, new THREE.SphereGeometry(0.075, 14, 10), P === 'panels' ? M.accent : M.suit);
      if (P === 'panels') add(sh, new THREE.SphereGeometry(0.09, 14, 8, 0, Math.PI * 2, 0, Math.PI / 2).scale(1, 0.6, 1), M.accent, [s * 0.01, 0.02, 0]);
      const upper = tube(0.27, 0.078, 0.066);
      upper.rotateX(Math.PI / 2);
      add(sh, upper, M.suit);
      if (P === 'bands') add(sh, new THREE.CylinderGeometry(0.071, 0.071, 0.04, 16, 1, true), M.accent, [0, -0.12, 0]);
      const el = new THREE.Group();
      el.position.set(0, -0.28, 0);
      sh.add(el);
      add(el, new THREE.SphereGeometry(0.06, 12, 8), M.suitDark);
      buildSleeve(M, el, V(0, 0, 0), V(0, -0.25, 0), 0.066, 0.052, P);
      const hand = new THREE.Group();
      hand.position.set(0, -0.3, 0);
      el.add(hand);
      add(hand, roundedBox(0.075, 0.1, 0.06, 0.025, 3), M.glove, [0, -0.02, 0]);
      for (let k = 0; k < 4; k++) add(hand, new THREE.CapsuleGeometry(0.011, 0.04, 4, 6), M.glove, [-0.026 + k * 0.017, -0.085, -0.012], [0.5, 0, 0]);
      add(hand, new THREE.CapsuleGeometry(0.012, 0.035, 4, 6), M.glove, [s * -0.04, -0.03, -0.02], [0.4, 0, s * 0.6]);
      if (s < 0) {
        // wrist computer on the left forearm
        const wc = add(el, roundedBox(0.03, 0.09, 0.075, 0.01, 2), M.scanBody, [-0.05, -0.18, 0]);
        add(wc, new THREE.PlaneGeometry(0.06, 0.055), M.emit, [-0.0155, 0, 0], [0, -Math.PI / 2, 0]);
      } else {
        const sc = buildScanner(M);
        sc.group.scale.setScalar(1.05);
        sc.group.position.set(0, -0.05, -0.02);
        sc.group.rotation.set(-Math.PI / 2, 0, 0);
        hand.add(sc.group);
        this.scanner = sc;
      }
      this.arms.push({ sh, el, s });
    }
    // ---------------- legs (hip -> knee -> ankle) with boots and fins
    this.legs = [];
    for (const s of [-1, 1]) {
      const hip = new THREE.Group();
      hip.position.set(s * 0.1, -0.86, 0.01);
      b.add(hip);
      const thigh = tube(0.4, 0.1, 0.08);
      thigh.rotateX(Math.PI / 2);
      add(hip, thigh, M.suit);
      if (P === 'bands') add(hip, new THREE.CylinderGeometry(0.084, 0.084, 0.05, 16, 1, true), M.accent, [0, -0.15, 0]);
      add(hip, roundedBox(0.04, 0.12, 0.06, 0.01, 2), M.suitDark, [s * 0.085, -0.2, 0]); // thigh pocket
      const knee = new THREE.Group();
      knee.position.set(0, -0.41, 0);
      hip.add(knee);
      add(knee, new THREE.SphereGeometry(0.068, 12, 8), M.suitDark);
      add(knee, roundedBox(0.09, 0.1, 0.04, 0.02, 2), M.rubber, [0, -0.01, -0.055]); // knee pad
      buildSleeve(M, knee, V(0, 0, 0), V(0, -0.36, 0), 0.076, 0.058, P);
      const ankle = new THREE.Group();
      ankle.position.set(0, -0.4, 0);
      knee.add(ankle);
      add(ankle, roundedBox(0.1, 0.12, 0.2, 0.04, 3), M.glove, [0, -0.04, -0.03]); // boot
      // fin blade: tapered, ribbed, pointing along the foot
      const fin = new THREE.Shape();
      fin.moveTo(-0.055, 0); fin.lineTo(0.055, 0); fin.quadraticCurveTo(0.13, 0.32, 0.12, 0.55); fin.lineTo(0.0, 0.5); fin.lineTo(-0.12, 0.55); fin.quadraticCurveTo(-0.13, 0.32, -0.055, 0);
      const fg = new THREE.ExtrudeGeometry(fin, { depth: 0.012, bevelEnabled: true, bevelThickness: 0.004, bevelSize: 0.004, bevelSegments: 1, curveSegments: 8 });
      const finM = add(ankle, fg, M.glove, [0, -0.1, -0.05], [Math.PI / 2 + 0.25, 0, 0]);
      finM.rotation.x = Math.PI - 0.15;
      for (const x of [-0.07, 0.07]) add(ankle, roundedBox(0.012, 0.42, 0.014, 0.004, 1), M.accent, [x, -0.36, -0.08], [-0.15, 0, 0]);
      this.legs.push({ hip, knee, ankle, s });
    }
    this.body.traverse((o) => { if (o.isMesh) o.frustumCulled = true; });
  }

  /** opts: { speed, scanning, t, pitch } — swims prone when moving, hangs upright at rest. */
  update(dt, { speed = 0, scanning = false, t = 0, pitch = 0, surfaced = false } = {}) {
    const k = THREE.MathUtils.smoothstep(speed, 0.4, 2.2);
    this.prone = THREE.MathUtils.lerp(this.prone ?? 0, k, 1 - Math.exp(-dt * 3));
    this.body.rotation.x = this.prone * (pitch - Math.PI / 2) * (surfaced ? 0.7 : 1);
    // flutter kick: rate and amplitude follow speed
    this.kick += dt * (1.6 + speed * 1.4);
    const amp = 0.12 + 0.3 * k;
    this.legs.forEach((l, i) => {
      const ph = this.kick + i * Math.PI;
      l.hip.rotation.x = Math.sin(ph) * amp - 0.05;
      l.knee.rotation.x = Math.max(0, Math.sin(ph + 0.9)) * amp * 1.3 + 0.08;
      l.ankle.rotation.x = Math.sin(ph - 0.6) * amp * 0.6 + 0.55 * (1 - k) - 0.2 * k;
      l.hip.rotation.z = l.s * 0.05;
    });
    // arms: tucked along the body while swimming, slow sculling at rest, right arm aims while scanning
    const idle = Math.sin(t * 1.2) * 0.12 * (1 - k);
    this.aim = THREE.MathUtils.lerp(this.aim ?? 0, scanning ? 1 : 0, 1 - Math.exp(-dt * 8));
    for (const a of this.arms) {
      const right = a.s > 0;
      const tuck = k * 0.25;
      a.sh.rotation.x = right ? THREE.MathUtils.lerp(0.25 + idle - tuck, -1.35, this.aim) : 0.2 - idle - tuck;
      a.sh.rotation.z = a.s * (0.18 + (1 - k) * 0.15);
      a.el.rotation.x = right ? THREE.MathUtils.lerp(-0.7, -0.15, this.aim) : -0.9 + idle;
    }
    this.head.rotation.x = -this.prone * (pitch - Math.PI / 2) * 0.35 * 0;
    if (this.scanner) this.scanner.rotor.rotation.z += dt * (scanning ? 14 : 0.3);
  }
}
