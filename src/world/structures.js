// Hand-placed sites: Meridian Station, Echo Lab, the Corvid wreck, Veyru ruins,
// the Listening Stone, the Old Bones, Whisper Caves, Lindqvist's beacon and
// the Threshold. Each site registers colliders, scannables and interactables.

import * as THREE from 'three';
import { waterMat, U } from './shading.js';
import { SITES } from './layout.js';
import { panelTexture, glyphTextures, labelTexture, screenTexture, textScreenTexture, hazardTexture } from './textures.js';
import * as G from './geom.js';
import { mulberry32 } from '../core/noise.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);

/** Local-frame builder: places meshes and colliders relative to an origin + yaw. */
class Site {
  constructor(owner, name, origin, yaw = 0) {
    this.owner = owner;
    this.col = owner.collision;
    this.group = new THREE.Group();
    this.group.name = name;
    this.group.position.copy(origin);
    this.group.rotation.y = yaw;
    this.origin = origin.clone();
    this.yaw = yaw;
    owner.group.add(this.group);
  }

  w(x, y, z) { // local -> world
    const c = Math.cos(this.yaw), s = Math.sin(this.yaw);
    return V(this.origin.x + x * c + z * s, this.origin.y + y, this.origin.z - x * s + z * c);
  }

  mesh(geo, mat, x = 0, y = 0, z = 0, ry = 0) {
    const m = new THREE.Mesh(geo, mat);
    m.position.set(x, y, z);
    m.rotation.y = ry;
    this.group.add(m);
    return m;
  }

  box(w, h, d, x, y, z, mat, opts = {}) {
    const ry = opts.ry || 0;
    const m = this.mesh(new THREE.BoxGeometry(w, h, d), mat, x, y, z, ry);
    if (opts.collide !== false) this.col.box(this.w(x, y, z), V(w / 2, h / 2, d / 2), this.yaw + ry, opts.tag);
    return m;
  }

  capsule(a, b, r, mat, radial = 10) {
    const A = V(...a), B = V(...b);
    const len = A.distanceTo(B);
    const geo = new THREE.CylinderGeometry(r, r, len, radial, 1);
    const m = new THREE.Mesh(geo, mat);
    m.position.copy(A).add(B).multiplyScalar(0.5);
    m.quaternion.setFromUnitVectors(V(0, 1, 0), B.clone().sub(A).normalize());
    this.group.add(m);
    if (mat) this.col.capsule(this.w(...a), this.w(...b), r);
    return m;
  }

  scannable(id, x, y, z, radius = 2) {
    this.owner.scannables.push({ id, pos: this.w(x, y, z), radius });
  }

  interact(data, x, y, z, radius = 2.5) {
    const it = { ...data, pos: this.w(x, y, z), radius, active: true };
    this.owner.interactables.push(it);
    return it;
  }
}

export class Structures {
  constructor(scene, terrain, collision) {
    this.scene = scene;
    this.terrain = terrain;
    this.collision = collision;
    this.group = new THREE.Group();
    this.group.name = 'structures';
    scene.add(this.group);
    this.scannables = [];
    this.interactables = [];
    this.resourceSpots = []; // { type, pos }
    this.animated = [];
    this.powered = false;
  }

  build() {
    this.mats();
    this.buildStation();
    this.buildLanternTrail();
    this.buildMonolith();
    this.buildEchoLab();
    this.buildSkeleton();
    this.buildWreck();
    this.buildCaves();
    this.buildRuins();
    this.buildBeacon();
    this.buildGate();
    this.buildDebris();
  }

  mats() {
    const hullTex = panelTexture('#d9dcd6', 2, 0.4);
    hullTex.repeat.set(4, 2);
    const darkTex = panelTexture('#5b636b', 5, 0.5);
    darkTex.repeat.set(3, 3);
    const rustTex = panelTexture('#6b4a3c', 9, 0.9);
    rustTex.repeat.set(3, 1);
    const labTex = panelTexture('#a7aca6', 4, 0.9);
    labTex.repeat.set(3, 1);
    const glyph = glyphTextures(3);
    glyph.map.repeat.set(1, 3); glyph.emissive.repeat.set(1, 3);
    this.glyphTex = glyph;
    this.M = {
      hull: waterMat({ map: hullTex, roughness: 0.55, metalness: 0.15 }),
      hullDark: waterMat({ map: darkTex, roughness: 0.6, metalness: 0.2 }),
      interior: waterMat({ color: 0xc9c4b8, roughness: 0.7 }, { ambient: 0.6 }),
      deck: waterMat({ map: darkTex, color: 0x777f86, roughness: 0.8 }),
      orange: waterMat({ color: 0xd8692a, roughness: 0.5 }),
      lab: waterMat({ map: labTex, roughness: 0.75, metalness: 0.1 }, { detail: 0.25 }),
      labInner: waterMat({ color: 0x8c948f, roughness: 0.8 }, { detail: 0.4 }),
      rust: waterMat({ map: rustTex, roughness: 0.85, metalness: 0.2 }, { detail: 0.2 }),
      rustDark: waterMat({ color: 0x3d2f2a, roughness: 0.9 }, { detail: 0.3 }),
      containerA: waterMat({ color: 0xc0632e, roughness: 0.7 }, { detail: 0.3 }),
      containerB: waterMat({ color: 0x2f6f78, roughness: 0.7 }, { detail: 0.3 }),
      glass: waterMat({ color: 0x9fd9e8, roughness: 0.05, metalness: 0.0, transparent: true, opacity: 0.25, depthWrite: false }),
      warmLight: waterMat({ color: 0x222222, emissive: 0xffc98a, emissiveIntensity: 0.2 }),
      redLight: waterMat({ color: 0x220000, emissive: 0xff3b2b, emissiveIntensity: 2.5 }),
      cyanLight: waterMat({ color: 0x002222, emissive: 0x5fe8ff, emissiveIntensity: 2.5 }),
      stone: waterMat({ map: glyph.map, emissiveMap: glyph.emissive, emissive: 0x7a5cff, emissiveIntensity: 0.5, roughness: 0.6, metalness: 0.2 }),
      stonePlain: waterMat({ color: 0x2b3142, roughness: 0.7 }, { detail: 0.2 }),
      bone: waterMat({ color: 0xd6cfbf, roughness: 0.85 }, { detail: 0.5 }),
      rock: waterMat({ vertexColors: true, roughness: 0.95 }, { detail: 0.35 }),
      suit: waterMat({ color: 0xe5e2da, roughness: 0.6 }),
      visor: waterMat({ color: 0x0a0f14, roughness: 0.1, metalness: 0.6 }),
      shard: waterMat({ color: 0x302050, emissive: 0xb48cff, emissiveIntensity: 3, roughness: 0.2 }),
      screen: (seed, hue) => waterMat({ color: 0x000000, emissive: 0xffffff, emissiveMap: screenTexture(seed, hue), emissiveIntensity: 1.4 }),
    };
    this.windowMats = [];
  }

  // ------------------------------------------------------------------ STATION
  buildStation() {
    const M = this.M;
    const s = new Site(this, 'meridian', V(0, 0, 0), 0);
    this.stationSite = s;
    const R = 9, yB = -23, yT = -11;
    // hub shell
    s.mesh(new THREE.CylinderGeometry(R, R, yT - yB, 40, 1, true), M.hull, 0, (yB + yT) / 2, 0);
    const dome = new THREE.SphereGeometry(R, 40, 12, 0, Math.PI * 2, 0, Math.PI / 2);
    dome.scale(1, 0.35, 1);
    s.mesh(dome, M.hull, 0, yT, 0);
    const bottom = new THREE.RingGeometry(3.6, R, 40, 1);
    bottom.rotateX(Math.PI / 2);
    s.mesh(bottom, M.hullDark, 0, yB, 0);
    s.mesh(new THREE.CylinderGeometry(3.6, 3.6, 3.1, 32, 1, true), waterMat({ color: 0x5b636b, side: THREE.DoubleSide, roughness: 0.6 }), 0, yB + 1.55, 0);
    // orange stripe band
    s.mesh(new THREE.CylinderGeometry(R + 0.03, R + 0.03, 0.7, 40, 1, true), M.orange, 0, -21.6, 0);
    // label
    const label = new THREE.CylinderGeometry(R + 0.06, R + 0.06, 1.6, 24, 1, true, -0.55, 1.1);
    s.mesh(label, waterMat({ map: labelTexture('MERIDIAN'), transparent: true, roughness: 0.6 }), 0, -15, 0);
    // interior
    const inner = new THREE.CylinderGeometry(R - 0.2, R - 0.2, yT - (-19.9), 40, 1, true);
    const innerTex = panelTexture('#c9c6bc', 7, 0.25);
    innerTex.repeat.set(10, 2);
    s.mesh(inner, waterMat({ map: innerTex, side: THREE.BackSide, roughness: 0.7 }, { ambient: 0.7 }), 0, (yT + -19.9) / 2, 0);
    // emergency light strips around the wall at deck level
    this.stripMat = waterMat({ color: 0x220000, emissive: 0xff3b2b, emissiveIntensity: 1.6 });
    for (let i = 0; i < 12; i++) {
      const a = (i / 12) * Math.PI * 2 + 0.13;
      const st = s.mesh(new THREE.BoxGeometry(1.2, 0.07, 0.05), this.stripMat, Math.cos(a) * (R - 0.27), -19.3, Math.sin(a) * (R - 0.27));
      st.lookAt(0, -19.3, 0);
      const up = s.mesh(new THREE.BoxGeometry(1.2, 0.07, 0.05), this.stripMat, Math.cos(a) * (R - 0.27), yT - 1.2, Math.sin(a) * (R - 0.27));
      up.lookAt(0, yT - 1.2, 0);
    }
    // hazard edge around the pool
    const haz = new THREE.RingGeometry(3.6, 3.95, 48, 1);
    haz.rotateX(-Math.PI / 2);
    // remap UVs so stripes run around the ring
    const huv = haz.attributes.uv, hp = haz.attributes.position;
    for (let i = 0; i < huv.count; i++) {
      const ang = Math.atan2(hp.getZ(i), hp.getX(i));
      huv.setXY(i, ang / (Math.PI * 2) + 0.5, Math.hypot(hp.getX(i), hp.getZ(i)) > 3.8 ? 1 : 0);
    }
    s.mesh(haz, waterMat({ map: hazardTexture(), roughness: 0.6 }), 0, -19.88, 0);
    const ceiling = new THREE.CircleGeometry(R - 0.2, 40);
    ceiling.rotateX(Math.PI / 2);
    s.mesh(ceiling, M.interior, 0, yT - 0.3, 0);
    const deck = new THREE.RingGeometry(3.9, R - 0.2, 40, 1);
    deck.rotateX(-Math.PI / 2);
    s.mesh(deck, M.deck, 0, -19.9, 0);
    // pool water inside the moonpool
    const pool = new THREE.CircleGeometry(3.6, 32);
    pool.rotateX(-Math.PI / 2);
    this.poolMat = waterMat({ color: 0x0a4a5a, emissive: 0x0b3a4c, emissiveIntensity: 0.18, transparent: true, opacity: 0.78, roughness: 0.05, metalness: 0.2, side: THREE.DoubleSide, depthWrite: false });
    s.mesh(pool, this.poolMat, 0, -20.2, 0);
    // railing
    const rail = new THREE.TorusGeometry(3.75, 0.06, 6, 48);
    rail.rotateX(Math.PI / 2);
    s.mesh(rail, M.orange, 0, -19.0, 0);
    for (let i = 0; i < 12; i++) {
      const a = (i / 12) * Math.PI * 2;
      s.mesh(new THREE.CylinderGeometry(0.04, 0.04, 0.9, 5), M.hullDark, Math.cos(a) * 3.75, -19.45, Math.sin(a) * 3.75);
    }
    // ceiling light ring
    const ring = new THREE.TorusGeometry(4.5, 0.12, 6, 48);
    ring.rotateX(Math.PI / 2);
    this.ceilingLightMat = waterMat({ color: 0x111111, emissive: 0xff4030, emissiveIntensity: 0.6 });
    s.mesh(ring, this.ceilingLightMat, 0, yT - 0.5, 0);
    this.stationLight = new THREE.PointLight(0xff4a30, 2, 22, 1.2);
    this.stationLight.position.set(0, -13.5, 0);
    s.group.add(this.stationLight);

    // colliders
    this.collision.tube(V(0, 0, 0), 3.6, R + 0.2, yB - 0.4, -19.9, 'station');
    this.collision.tube(V(0, 0, 0), R - 0.25, R + 0.25, yB - 0.4, yT, 'station');
    this.collision.tube(V(0, 0, 0), 0, R + 0.25, yT - 0.4, yT + 3.2, 'station');
    this.collision.tube(V(0, 0, 0), 3.55, 3.95, -20.8, -18.9, 'station');
    this.collision.addAirPocket(V(-R, yB - 0.5, -R), V(R, yT, R), -20.2);

    // consoles on the deck (facing the pool)
    const consoleAt = (angle, w, h, mat, screenMat) => {
      const r = 5.0;
      const x = Math.cos(angle) * r, z = Math.sin(angle) * r;
      const body = s.mesh(new THREE.BoxGeometry(w, h, 0.9), mat, x, -19.9 + h / 2, z, -angle - Math.PI / 2);
      body.lookAt(0, body.position.y, 0);
      const scr = new THREE.Mesh(new THREE.PlaneGeometry(w * 0.8, w * 0.4), screenMat);
      scr.position.set(0, h / 2 - 0.45, 0.46);
      scr.rotation.x = -0.25;
      body.add(scr);
      return { x, z, body };
    };
    this.termTexOff = textScreenTexture(['EMERGENCY POWER', 'Fabricator: essential items', 'Main bus: OFFLINE', '[E] Access terminal'], '#ffb25a', '#140a02');
    this.termTexOn = textScreenTexture(['MERIDIAN ONLINE', 'Fabricator + upgrade bay', 'Storage \u00b7 Logs \u00b7 Save', '[E] Access terminal'], '#8fe3ea', '#02121a');
    this.termScreenMat = waterMat({ color: 0x000000, emissive: 0xffffff, emissiveMap: this.termTexOff, emissiveIntensity: 0.9 });
    const term = consoleAt(0, 2.2, 1.5, M.hullDark, this.termScreenMat);
    s.interact({ type: 'stationTerminal' }, term.x * 0.8, -19.4, term.z * 0.8, 3.2);
    // fabricator (beside terminal)
    const fabA = 0.75;
    const fab = s.mesh(new THREE.CylinderGeometry(0.8, 1.0, 1.9, 16), M.hullDark, Math.cos(fabA) * 5.4, -18.95, Math.sin(fabA) * 5.4);
    const fabGlow = new THREE.Mesh(new THREE.TorusGeometry(0.62, 0.05, 6, 24), M.cyanLight);
    fabGlow.rotation.x = Math.PI / 2;
    fabGlow.position.y = 0.4;
    fab.add(fabGlow);
    // power core (opposite side)
    this.coreMat = waterMat({ color: 0x111111, emissive: 0xff3b2b, emissiveIntensity: 0.8 });
    const coreA = Math.PI;
    const cx = Math.cos(coreA) * 5.2, cz = Math.sin(coreA) * 5.2;
    s.mesh(new THREE.CylinderGeometry(0.9, 1.1, 3.2, 16), M.hullDark, cx, -18.3, cz);
    const coreRings = [];
    for (let k = 0; k < 3; k++) {
      const ring = s.mesh(new THREE.TorusGeometry(0.98, 0.06, 8, 32), this.coreMat, cx, -18.9 + k * 0.55, cz);
      ring.rotation.x = Math.PI / 2;
      coreRings.push(ring);
    }
    const coreSlot = s.mesh(new THREE.BoxGeometry(0.5, 0.7, 0.2), M.hullDark, cx + 0.95, -18.6, cz);
    coreSlot.rotation.y = Math.PI / 2;
    this.animated.push((t) => { coreRings.forEach((r, k) => { r.scale.setScalar(1 + Math.sin(t * (this.powered ? 3 : 0.8) + k) * 0.02); }); });
    s.interact({ type: 'powerCore' }, cx * 0.8, -19.4, cz * 0.8, 3.2);
    const sign = (text, angle, color) => {
      const m = s.mesh(new THREE.PlaneGeometry(2.1, 0.39), waterMat({ map: labelTexture(text, color, 1024, 192, '600 96px "Space Grotesk", sans-serif'), transparent: true, emissive: 0xffffff, emissiveIntensity: 0.25 }),
        Math.cos(angle) * (R - 0.75), -14.6, Math.sin(angle) * (R - 0.75));
      m.lookAt(0, -14.6, 0);
    };
    sign('TERMINAL · FABRICATOR', 0.35, '#e8e2d2');
    sign('POWER CORE', Math.PI, '#e8742c');
    sign('MOONPOOL', Math.PI / 2, '#e8e2d2');
    // lockers & clutter
    for (let i = 0; i < 4; i++) {
      const a = -1.9 + i * 0.32;
      const lk = s.mesh(new THREE.BoxGeometry(0.9, 2.4, 0.6), i % 2 ? M.orange : M.hullDark, Math.cos(a) * 8.1, -18.7, Math.sin(a) * 8.1);
      lk.lookAt(0, lk.position.y, 0);
    }
    const crate = s.mesh(new THREE.BoxGeometry(1, 0.7, 0.8), M.hullDark, Math.cos(2.2) * 6.8, -19.55, Math.sin(2.2) * 6.8, 0.4);
    crate.rotation.y = 0.7;
    // a mug and a helmet on the terminal desk area (crew traces)
    const helmet = s.mesh(new THREE.SphereGeometry(0.28, 16, 12), M.suit, Math.cos(-0.5) * 6.3, -19.6, Math.sin(-0.5) * 6.3);
    const vis = new THREE.Mesh(new THREE.SphereGeometry(0.22, 16, 12, 0, Math.PI), M.visor);
    vis.position.z = 0.1; helmet.add(vis);
    // station log datapads are added to the station terminal when power returns

    // windows (exterior portholes)
    this.windowMat = waterMat({ color: 0x111111, emissive: 0xffb877, emissiveIntensity: 0.15 });
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * Math.PI * 2 + 0.3;
      const w = s.mesh(new THREE.CircleGeometry(0.55, 20), this.windowMat, Math.cos(a) * (R + 0.05), -15.5, Math.sin(a) * (R + 0.05));
      w.lookAt(Math.cos(a) * 30, -15.5, Math.sin(a) * 30);
      const frame = new THREE.Mesh(new THREE.TorusGeometry(0.58, 0.07, 6, 20), M.hullDark);
      w.add(frame);
    }
    // legs
    for (let i = 0; i < 4; i++) {
      const a = (i / 4) * Math.PI * 2 + Math.PI / 4;
      const top = [Math.cos(a) * 6.5, yB + 0.3, Math.sin(a) * 6.5];
      const bot = [Math.cos(a) * 11, -31.5, Math.sin(a) * 11];
      s.capsule(top, bot, 0.55, M.hullDark);
      s.mesh(new THREE.CylinderGeometry(1.2, 1.5, 0.6, 12), M.hullDark, bot[0], this.terrain.heightAt(bot[0], bot[2]) + 0.2, bot[2]);
    }
    // east module (quarters)
    const modA = s.mesh(new THREE.CylinderGeometry(3.2, 3.2, 14, 28, 1, true), M.hull, 16, -17, 0);
    modA.rotation.z = Math.PI / 2;
    const capA = new THREE.SphereGeometry(3.2, 24, 12, 0, Math.PI * 2, 0, Math.PI / 2);
    capA.scale(1, 0.45, 1);
    const capM = s.mesh(capA, M.hull, 23, -17, 0);
    capM.rotation.z = -Math.PI / 2;
    this.collision.capsule(V(9, -17, 0), V(23.5, -17, 0), 3.3, 'station');
    for (let i = 0; i < 5; i++) {
      for (const side of [-1, 1]) {
        const w = s.mesh(new THREE.PlaneGeometry(1.4, 0.6), this.windowMat, 11 + i * 2.6, -16.5, side * 3.22);
        w.rotation.y = side > 0 ? 0 : Math.PI;
      }
    }
    // north module (hangar) + dock cradle for the Kestrel
    const modB = s.mesh(new THREE.CylinderGeometry(3.6, 3.6, 13, 28, 1, true), M.hull, 0, -16.5, -16);
    modB.rotation.x = Math.PI / 2;
    const capB = s.mesh(capA.clone(), M.hull, 0, -16.5, -22.5);
    capB.rotation.x = -Math.PI / 2;
    this.collision.capsule(V(0, -16.5, -9), V(0, -16.5, -23), 3.7, 'station');
    s.mesh(new THREE.CylinderGeometry(3.65, 3.65, 0.6, 28, 1, true), M.orange, 0, -16.5, -19).rotation.x = Math.PI / 2;
    // cradle arms
    for (const sx of [-3.1, 3.1]) {
      s.capsule([sx * 0.8, -19.5, -12], [sx, -23.4, -13], 0.18, M.hullDark);
      s.capsule([sx * 0.8, -19.5, -21], [sx, -23.4, -20], 0.18, M.hullDark);
    }
    this.dockPoint = V(0, -25.2, -16.5);
    this.dockLightMat = waterMat({ color: 0x111111, emissive: 0xff3b2b, emissiveIntensity: 1.5 });
    for (const sx of [-3.1, 3.1]) for (const sz of [-12.8, -20.2]) {
      s.mesh(new THREE.SphereGeometry(0.18, 10, 8), this.dockLightMat, sx, -23.6, sz);
    }
    // storage tanks
    for (const [x, z] of [[-14, 6], [-13, -7]]) {
      const gh = this.terrain.heightAt(x, z);
      const h = -14 - gh;
      s.mesh(new THREE.CylinderGeometry(2.4, 2.4, h, 20), M.hull, x, gh + h / 2, z);
      const top = new THREE.SphereGeometry(2.4, 20, 8, 0, Math.PI * 2, 0, Math.PI / 2);
      top.scale(1, 0.4, 1);
      s.mesh(top, M.hull, x, -14, z);
      s.mesh(new THREE.CylinderGeometry(2.45, 2.45, 0.5, 20, 1, true), M.orange, x, -16, z);
      this.collision.tube(V(x, 0, z), 0, 2.5, gh - 1, -13, 'station');
      s.capsule([x * 0.9, -17, z * 0.9], [x * 0.55, -17, z * 0.55], 0.5, M.hullDark);
    }
    // antenna mast to the surface with beacon
    s.capsule([0, -8, 0], [0, -1.2, 0], 0.22, M.hullDark);
    this.beaconMat = waterMat({ color: 0x220000, emissive: 0xff3b2b, emissiveIntensity: 3 });
    s.mesh(new THREE.SphereGeometry(0.4, 12, 10), this.beaconMat, 0, -0.9, 0);
    const dish = new THREE.SphereGeometry(1.4, 20, 8, 0, Math.PI * 2, 0, Math.PI * 0.35);
    const dm = s.mesh(dish, M.hull, 0.9, -5, 0);
    dm.rotation.z = -1.1;
    // floodlights on the seabed
    this.floodMat = waterMat({ color: 0x111111, emissive: 0xffd9a0, emissiveIntensity: 0.0 });
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2 + 0.2;
      const x = Math.cos(a) * 19, z = Math.sin(a) * 19;
      const gh = this.terrain.heightAt(x, z);
      s.capsule([x, gh, z], [x, gh + 3.2, z], 0.12, M.hullDark);
      const head = s.mesh(new THREE.CylinderGeometry(0.35, 0.25, 0.5, 12), this.floodMat, x, gh + 3.3, z);
      head.lookAt(0, -20, 0);
      head.rotateX(Math.PI / 2);
    }
    this.scannables.push({ id: 'station', pos: V(9, -15, 0), radius: 9 });
    // supply crates around
    const rnd = mulberry32(17);
    for (let i = 0; i < 7; i++) {
      const a = rnd() * Math.PI * 2, d = 24 + rnd() * 16;
      const x = Math.cos(a) * d, z = Math.sin(a) * d;
      const gh = this.terrain.heightAt(x, z);
      s.box(1.6, 1.1, 1.1, x, gh + 0.45, z, rnd() < 0.5 ? M.containerA : M.containerB, { ry: rnd() * 3 });
    }
  }

  // Lanternblooms planted by the crew in a line from the station to Echo Lab.
  buildLanternTrail() {
    const geo = G.lanternPlantGeometry(21);
    const pole = G.prep(new THREE.CylinderGeometry(0.05, 0.05, 1.6, 6).translate(0, 0.8, 0), 0xd8692a);
    const tag = G.prep(new THREE.BoxGeometry(0.25, 0.15, 0.02).translate(0, 1.5, 0.05), 0xffffff, 0.8);
    const merged = G.merge([geo, G.prep(pole.clone().translate(0.6, 0, 0), 0xd8692a), tag.translate(0.6, 0, 0)]);
    const mat = waterMat({ vertexColors: true, roughness: 0.8 }, { glow: { color: 0x6ff3ff, intensity: 3.4, pulse: 0.6 } });
    const pts = [];
    const ctrl = new THREE.CatmullRomCurve3([V(14, 0, 22), V(30, 0, 90), V(28, 0, 170), V(60, 0, 250), V(84, 0, 312)]);
    const len = ctrl.getLength();
    for (let d = 0; d < len; d += 13) pts.push(ctrl.getPointAt(d / len));
    const im = new THREE.InstancedMesh(merged, mat, pts.length);
    const phases = new Float32Array(pts.length);
    const m = new THREE.Matrix4();
    pts.forEach((p, i) => {
      const y = this.terrain.heightAt(p.x, p.z);
      m.compose(V(p.x, y, p.z), new THREE.Quaternion().setFromAxisAngle(V(0, 1, 0), i * 1.3), V(1.2, 1.2, 1.2));
      im.setMatrixAt(i, m);
      phases[i] = i * 0.07;
    });
    im.geometry = merged.clone();
    im.geometry.setAttribute('aPhase', new THREE.InstancedBufferAttribute(phases, 1));
    im.computeBoundingSphere();
    this.group.add(im);
  }

  // ------------------------------------------------------------------ MONOLITH
  buildMonolith() {
    const { x, z } = SITES.monolith;
    const gh = this.terrain.heightAt(x, z);
    const s = new Site(this, 'monolith', V(x, gh, z), 0.4);
    const geo = new THREE.BoxGeometry(3.2, 15, 1.6, 1, 6, 1);
    // slight taper
    const p = geo.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const t = (p.getY(i) + 7.5) / 15;
      p.setX(i, p.getX(i) * (1 - t * 0.25));
      p.setZ(i, p.getZ(i) * (1 - t * 0.2));
    }
    geo.computeVertexNormals();
    this.monolithMat = this.M.stone.clone();
    this.monolithMat.onBeforeCompile = this.M.stone.onBeforeCompile;
    this.monolithMat.customProgramCacheKey = this.M.stone.customProgramCacheKey;
    s.mesh(geo, this.monolithMat, 0, 6.5, 0);
    this.collision.box(V(x, gh + 6.5, z), V(1.6, 7.5, 0.8), 0.4, 'monolith');
    const frag = s.mesh(new THREE.BoxGeometry(2, 1.2, 1.4), this.M.stonePlain, 4, 0.3, 2.5, 0.8);
    frag.rotation.z = 0.3;
    s.scannable('monolith', 0, 6, 0, 3.5);
    this.monolithPos = V(x, gh + 7, z);
    for (let i = 0; i < 4; i++) {
      const a = i * 1.7;
      this.resourceSpots.push({ type: 'lumen', pos: V(x + Math.cos(a) * 6, 0, z + Math.sin(a) * 6) });
    }
  }

  // ------------------------------------------------------------------ ECHO LAB
  buildEchoLab() {
    const M = this.M;
    const { x, z, floor } = SITES.echoLab;
    const s = new Site(this, 'echoLab', V(x, floor + 1.2, z), 0.35);
    this.echoSite = s;
    const H = 4.5, T = 0.35;
    // legs
    for (const lx of [-7, 0, 7]) for (const lz of [-3.5, 3.5]) s.mesh(new THREE.CylinderGeometry(0.3, 0.4, 2, 8), M.hullDark, lx, -1, lz);
    // floor & roof (roof breach between x 1..4.5)
    s.box(16, 0.4, 8, 0, -0.2, 0, M.lab);
    s.box(9, 0.4, 8, -3.5, H + 0.2, 0, M.lab);
    s.box(3.5, 0.4, 8, 6.25, H + 0.2, 0, M.lab);
    s.box(16, 0.06, 8, 0, H - 0.03, 0, M.labInner, { collide: false });
    // north & south walls
    s.box(16, H, T, 0, H / 2, -4, M.lab);
    s.box(16, H, T, 0, H / 2, 4, M.lab);
    // west wall with breach (z -1.5..1.5)
    s.box(T, H, 2.5, -8, H / 2, -2.75, M.lab);
    s.box(T, H, 2.5, -8, H / 2, 2.75, M.lab);
    s.box(T, 0.8, 3, -8, H - 0.4, 0, M.lab);
    // east wall with door to corridor (z -1..1, h 3)
    s.box(T, H, 3, 8, H / 2, -2.5, M.lab);
    s.box(T, H, 3, 8, H / 2, 2.5, M.lab);
    s.box(T, 1.5, 2, 8, H - 0.75, 0, M.lab);
    // corridor
    s.box(3, 0.3, 2.4, 9.5, -0.15, 0, M.lab);
    s.box(3, 0.3, 2.4, 9.5, 3.15, 0, M.lab);
    s.box(3, 3, 0.3, 9.5, 1.5, -1.2, M.lab);
    s.box(3, 3, 0.3, 9.5, 1.5, 1.2, M.lab);
    // workshop
    s.box(8, 0.4, 6, 15, -0.2, 0, M.lab);
    s.box(8, 0.4, 6, 15, 4.2, 0, M.lab);
    s.box(8, 4, T, 15, 2, -3, M.lab);
    s.box(8, 4, T, 15, 2, 3, M.lab);
    s.box(T, 4, 6, 19, 2, 0, M.lab);
    s.box(T, 4, 2, 11, 2, -2, M.lab);
    s.box(T, 4, 2, 11, 2, 2, M.lab);
    s.box(T, 1, 2, 11, 3.5, 0, M.lab);
    // windows on south wall
    const labWin = waterMat({ color: 0x111111, emissive: 0xbfe8ff, emissiveIntensity: 1.1 });
    for (let i = 0; i < 4; i++) {
      s.mesh(new THREE.PlaneGeometry(1.6, 0.8), labWin, -5 + i * 3.5, 2.6, 4.19);
      s.mesh(new THREE.PlaneGeometry(1.6, 0.8), labWin, -5 + i * 3.5, 2.6, -4.19).rotation.y = Math.PI;
    }
    // label
    const lbl = s.mesh(new THREE.PlaneGeometry(6, 1.1), waterMat({ map: labelTexture('ECHO LAB', '#e8742c'), transparent: true }), -2, 3.4, 4.2);
    lbl.rotation.y = 0;
    // bent antenna
    s.capsule([6, H + 0.4, -2], [7.5, H + 6, -3.5], 0.08, M.hullDark);
    s.capsule([7.5, H + 6, -3.5], [10, H + 7, -2], 0.06, M.hullDark);

    // ---- interior: specimen tank (breached outward)
    s.mesh(new THREE.CylinderGeometry(1.6, 1.7, 0.6, 20), M.hullDark, -4, 0.3, 0);
    s.mesh(new THREE.CylinderGeometry(1.6, 1.6, 0.5, 20), M.hullDark, -4, H - 0.4, 0);
    const tankLow = new THREE.CylinderGeometry(1.45, 1.45, 1.4, 24, 1, true);
    s.mesh(tankLow, M.glass, -4, 1.3, 0);
    // jagged shards still standing
    const rnd = mulberry32(5);
    for (let i = 0; i < 9; i++) {
      const a = (i / 9) * Math.PI * 2 + 0.3;
      if (a > 4.2 && a < 5.6) continue; // the blown-out side
      const h = 0.5 + rnd() * 1.6;
      const g = new THREE.CylinderGeometry(1.45, 1.45, h, 3, 1, true, a, 0.5);
      s.mesh(g, M.glass, -4, 2 + h / 2, 0);
    }
    this.collision.tube(s.w(-4, 0, 0), 1.3, 1.6, s.origin.y, s.origin.y + 2, 'lab');
    // glass debris on the floor
    for (let i = 0; i < 14; i++) {
      const g = s.mesh(new THREE.PlaneGeometry(0.3 + rnd() * 0.4, 0.2 + rnd() * 0.3), M.glass, -4 + 1.5 + rnd() * 3, 0.03, -2.5 + rnd() * 2);
      g.rotation.x = -Math.PI / 2; g.rotation.z = rnd() * 3;
    }
    // claw scoring on wall (dark grooves)
    for (let i = 0; i < 4; i++) s.mesh(new THREE.BoxGeometry(0.06, 1.4, 0.05), M.rustDark, -6 + i * 0.25, 2.2, -3.8).rotation.z = 0.3;
    s.scannable('specimenTank', -4, 1.5, 0, 1.8);
    // desks with screens along north wall
    s.box(3, 0.9, 1.2, 2, 0.45, -3.2, M.hullDark);
    s.box(3, 0.9, 1.2, 5.6, 0.45, -3.2, M.hullDark);
    for (const [dx, seed] of [[2, 7], [5.6, 8]]) {
      const scr = s.mesh(new THREE.PlaneGeometry(1.2, 0.7), M.screen(seed, '#7ff0c8'), dx, 1.4, -3.65);
      scr.rotation.x = -0.15;
    }
    // overturned chair
    const chair = s.mesh(new THREE.BoxGeometry(0.6, 0.1, 0.6), M.orange, 3.5, 0.3, -1.4);
    chair.rotation.z = 1.2;
    // datapads (logs)
    this.addDatapad(s, 'varga2', 2.4, 0.95, -3);
    this.addDatapad(s, 'mensah2', -6.5, 0.05, 3);
    // shard B on pedestal in a broken case
    s.box(0.8, 1.1, 0.8, 5.5, 0.55, 2.6, M.hullDark);
    const shardGeo = this.shardGeometry();
    const shardB = s.mesh(shardGeo, M.shard, 5.5, 1.5, 2.6);
    this.animated.push((t) => { shardB.rotation.y = t * 0.8; shardB.position.y = 1.5 + Math.sin(t * 1.3) * 0.06; });
    s.interact({ type: 'item', item: 'shardB', mesh: shardB }, 5.5, 1.5, 2.6, 2.4);
    // workshop contents
    s.box(4, 0.9, 1.2, 15, 0.45, -2.2, M.hullDark);
    const fin = new THREE.Shape();
    fin.moveTo(0, 0); fin.quadraticCurveTo(0.4, 0.3, 0.9, 0.05); fin.lineTo(0.9, -0.05); fin.quadraticCurveTo(0.4, -0.3, 0, 0);
    for (const fx of [14.2, 15.2]) {
      const fm = s.mesh(new THREE.ShapeGeometry(fin), waterMat({ color: 0x2a6a78, side: THREE.DoubleSide, emissive: 0x0a3040 }), fx, 0.95, -2.2);
      fm.rotation.x = -Math.PI / 2;
    }
    s.scannable('finsFragment', 14.7, 1, -2.2, 1.0);
    const board = s.mesh(new THREE.PlaneGeometry(2.4, 1.4), M.screen(12, '#ffd27a'), 15, 2.4, 2.8);
    board.rotation.y = Math.PI;
    s.scannable('suitFragment', 15, 2.4, 2.7, 1.2);
    this.addDatapad(s, 'hara1', 16.3, 0.95, -2.1);
    // interior lights
    this.labLightMat = waterMat({ color: 0x111111, emissive: 0xbfe8ff, emissiveIntensity: 1.6 });
    s.mesh(new THREE.BoxGeometry(5, 0.08, 0.3), this.labLightMat, -3, H - 0.1, -1.5);
    s.mesh(new THREE.BoxGeometry(3, 0.08, 0.3), this.labLightMat, 15, 3.9, 0);
    const redStrip = s.mesh(new THREE.BoxGeometry(10, 0.06, 0.06), waterMat({ color: 0x220000, emissive: 0xff3b2b, emissiveIntensity: 1 }), -1, 0.2, 3.75);
    this.labLight = new THREE.PointLight(0xbfe8ff, 2.5, 16, 1.2);
    this.labLight.position.set(0, 3.5, 0);
    s.group.add(this.labLight);
    this.animated.push((t) => {
      const f = Math.sin(t * 17) * Math.sin(t * 3.1) > 0.82 ? 0.15 : 1;
      this.labLight.intensity = 2.5 * f;
      this.labLightMat.emissiveIntensity = 1.6 * f;
      redStrip.material.emissiveIntensity = 0.9 + Math.sin(t * 2) * 0.5;
    });
    this.scannables.push({ id: 'echoLab', pos: s.w(0, 2, 0), radius: 8 });
    // silica + misc resources around the lab
    for (let i = 0; i < 6; i++) {
      const a = i * 1.1, d = 14 + (i % 3) * 5;
      this.resourceSpots.push({ type: 'silica', pos: V(x + Math.cos(a) * d, 0, z + Math.sin(a) * d) });
    }
    this.resourceSpots.push({ type: 'voidGlass', pos: s.w(-6.8, 0.25, -3), floorY: s.origin.y + 0.1 });
    this.resourceSpots.push({ type: 'voidGlass', pos: s.w(17.8, 0.25, 1.8), floorY: s.origin.y + 0.1 });
  }

  addDatapad(site, logId, x, y, z, kind = 'pad') {
    let mesh;
    if (kind === 'recorder') {
      mesh = site.mesh(new THREE.CylinderGeometry(0.12, 0.12, 0.32, 12), this.M.hullDark, x, y + 0.16, z);
      const l = new THREE.Mesh(new THREE.SphereGeometry(0.05, 8, 6), this.M.cyanLight);
      l.position.y = 0.18;
      mesh.add(l);
    } else {
      mesh = site.mesh(new THREE.BoxGeometry(0.34, 0.03, 0.24), this.M.hullDark, x, y + 0.02, z, 0.3);
      const scr = new THREE.Mesh(new THREE.PlaneGeometry(0.28, 0.18), this.M.screen(logId.length, '#5fe3ff'));
      scr.rotation.x = -Math.PI / 2;
      scr.position.y = 0.017;
      mesh.add(scr);
    }
    // beacon glint so pads are findable
    const glint = new THREE.Mesh(new THREE.SphereGeometry(0.05, 6, 4), this.M.cyanLight);
    glint.position.y = 0.12;
    mesh.add(glint);
    this.animated.push((t) => { glint.visible = mesh.visible && Math.sin(t * 3 + x) > 0; });
    const it = site.interact({ type: 'log', logId, mesh }, x, y + 0.1, z, 2.2);
    return it;
  }

  shardGeometry() {
    const g = new THREE.OctahedronGeometry(0.28, 0);
    g.scale(0.6, 1.6, 0.35);
    return g;
  }

  // ------------------------------------------------------------------ OLD BONES
  buildSkeleton() {
    const { x, z } = SITES.skeleton;
    const M = this.M;
    const curve = [];
    for (let i = 0; i <= 34; i++) {
      const t = i / 34;
      const px = x - 50 + t * 105, pz = z + Math.sin(t * 3.2) * 9;
      curve.push(V(px, this.terrain.heightAt(px, pz) + 1.2 + Math.sin(t * Math.PI) * 1.5, pz));
    }
    // vertebrae
    const vGeo = G.merge([
      G.prep(new THREE.SphereGeometry(1.3, 12, 8).scale(1, 0.9, 1.2), 0xd6cfbf),
      G.prep(new THREE.ConeGeometry(0.35, 2.4, 6).translate(0, 1.8, 0), 0xd6cfbf),
      G.prep(new THREE.CylinderGeometry(0.25, 0.4, 3.6, 6).rotateX(Math.PI / 2), 0xd6cfbf),
    ]);
    const im = new THREE.InstancedMesh(vGeo, waterMat({ vertexColors: true, roughness: 0.85 }, { detail: 0.6 }), curve.length);
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    curve.forEach((p, i) => {
      const t = i / 34;
      const s = 0.6 + Math.sin(t * Math.PI) * 0.7;
      const dir = (curve[Math.min(i + 1, 34)].clone().sub(curve[Math.max(i - 1, 0)])).normalize();
      q.setFromUnitVectors(V(1, 0, 0), dir);
      q.multiply(new THREE.Quaternion().setFromAxisAngle(V(0, 1, 0), Math.PI / 2));
      m.compose(p, q, V(s, s, s));
      im.setMatrixAt(i, m);
      this.collision.sphere(p, 1.3 * s, 'bone');
    });
    im.computeBoundingSphere();
    this.group.add(im);
    // ribs
    const ribs = [];
    for (let i = 8; i < 24; i += 2) {
      const p = curve[i];
      const s = 0.6 + Math.sin((i / 34) * Math.PI) * 0.7;
      for (const side of [-1, 1]) {
        const ground = this.terrain.heightAt(p.x, p.z + side * 12 * s);
        const pts = [
          V(p.x, p.y + 0.5, p.z),
          V(p.x + 1, p.y + 5 * s, p.z + side * 6 * s),
          V(p.x + 2, p.y + 3 * s, p.z + side * 11 * s),
          V(p.x + 2.5, ground - 0.5, p.z + side * 13 * s),
        ];
        ribs.push(G.tubeAlong(pts, 0.35 * s, 0.18 * s, 5, 0xd6cfbf, null, 8));
        this.collision.capsule(pts[1], pts[2], 0.4 * s, 'bone');
      }
    }
    const ribMesh = new THREE.Mesh(G.merge(ribs), waterMat({ vertexColors: true, roughness: 0.85 }, { detail: 0.6 }));
    this.group.add(ribMesh);
    // skull — opened
    const head = curve[34].clone().add(V(9, 1.5, 0));
    const skullGeo = new THREE.SphereGeometry(1, 28, 16, 0.6, Math.PI * 2 - 1.2, 0.25, Math.PI * 0.75);
    skullGeo.scale(11, 4.5, 5.5);
    const skull = new THREE.Mesh(skullGeo, waterMat({ color: 0xd6cfbf, side: THREE.DoubleSide, roughness: 0.85 }, { detail: 0.5 }));
    skull.position.copy(head);
    skull.rotation.z = 0.12;
    this.group.add(skull);
    const jaw = G.tubeAlong([head.clone().add(V(-6, -3, 3)), head.clone().add(V(4, -3.5, 3.5)), head.clone().add(V(11, -2.5, 1))], 0.6, 0.3, 6, 0xd6cfbf, null, 8);
    const jaw2 = G.tubeAlong([head.clone().add(V(-6, -3, -3)), head.clone().add(V(4, -3.5, -3.5)), head.clone().add(V(11, -2.5, -1))], 0.6, 0.3, 6, 0xd6cfbf, null, 8);
    this.group.add(new THREE.Mesh(G.merge([jaw, jaw2]), waterMat({ vertexColors: true, roughness: 0.85 })));
    this.collision.capsule(head.clone().add(V(-6, -3, 3)), head.clone().add(V(11, -2.5, 1)), 0.7, 'bone');
    this.collision.capsule(head.clone().add(V(-6, -3, -3)), head.clone().add(V(11, -2.5, -1)), 0.7, 'bone');
    // shell of the skull: keep players outside except via the cut
    this.scannables.push({ id: 'skeleton', pos: head, radius: 8 });
    this.skullPos = head;
  }

  // ------------------------------------------------------------------ CORVID
  buildWreck() {
    const M = this.M;
    const { x, z } = SITES.wreck;
    const gh = this.terrain.heightAt(x, z);
    const half = (name, lx, lz, yaw, sink, breach, bridge) => {
      const ox = x + lx, oz = z + lz;
      const s = new Site(this, name, V(ox, this.terrain.heightAt(ox, oz) - sink, oz), yaw);
      const L = 28, W = 11, Hh = 8;
      s.box(L, 0.6, W, 0, 0.3, 0, M.rust);
      // keel bulge
      const keel = s.mesh(new THREE.CylinderGeometry(W / 2, W / 2, L, 16, 1, true, Math.PI / 2, Math.PI), M.rustDark, 0, 0.6, 0);
      keel.rotation.z = Math.PI / 2;
      keel.scale.set(1, 1, 0.35);
      // side walls
      if (breach) {
        s.box(10, Hh, 0.5, -9, Hh / 2, W / 2, M.rust);
        s.box(10, Hh, 0.5, 9, Hh / 2, W / 2, M.rust);
        s.box(8, 2.4, 0.5, 0, Hh - 1.2, W / 2, M.rust);
      } else {
        s.box(L, Hh, 0.5, 0, Hh / 2, W / 2, M.rust);
      }
      s.box(L, Hh, 0.5, 0, Hh / 2, -W / 2, M.rust);
      // deck with a hatch hole
      s.box(12, 0.5, W, -8, Hh, 0, M.rust);
      s.box(10, 0.5, W, 9, Hh, 0, M.rust);
      s.box(4, 0.5, 4, 2, Hh, 3.5, M.rust);
      // far bulkhead (the break end stays open)
      const farX = lx < 0 ? -L / 2 : L / 2;
      s.box(0.5, Hh, W, farX, Hh / 2, 0, M.rust);
      // jagged break edge
      const nearX = -farX;
      const rnd = mulberry32(name.length);
      for (let i = 0; i < 6; i++) {
        const t = s.mesh(new THREE.ConeGeometry(0.6, 1.5 + rnd() * 2, 4), M.rustDark, nearX, rnd() * Hh, -W / 2 + rnd() * W);
        t.rotation.z = (lx < 0 ? -1 : 1) * Math.PI / 2;
      }
      // label
      if (!bridge) {
        const lbl = s.mesh(new THREE.PlaneGeometry(9, 1.8), waterMat({ map: labelTexture('CORVID', '#d9d4c4'), transparent: true }), 2, 5.5, -W / 2 - 0.27);
        lbl.rotation.y = Math.PI;
      }
      // cargo containers
      const cont = (cx, cz, mat, open) => {
        s.box(6, 2.6, 2.6, cx, 0.6 + 1.3, cz, mat);
        if (open) s.mesh(new THREE.PlaneGeometry(2.4, 2.4), M.rustDark, cx + 3.05, 1.9, cz).rotation.y = Math.PI / 2;
      };
      cont(-6, -2.5, M.containerA, false);
      cont(-6, 1.5, M.containerB, true);
      cont(6, -2.5, M.containerB, false);
      if (bridge) {
        s.box(7, 6, 8, -8, Hh + 3.25, 0, M.rust);
        for (let i = 0; i < 4; i++) {
          s.mesh(new THREE.PlaneGeometry(1.2, 0.8), this.windowMat, -11.55, Hh + 4.5, -2.7 + i * 1.8).rotation.y = -Math.PI / 2;
        }
        s.capsule([-8, Hh + 6.3, 0], [-8, Hh + 16, 0], 0.3, M.rustDark);
        const dish = new THREE.SphereGeometry(1.8, 20, 8, 0, Math.PI * 2, 0, Math.PI * 0.35);
        const dm = s.mesh(dish, M.hull, -8, Hh + 15, 0.4);
        dm.rotation.x = 1.2;
        s.scannable('sonarFragment', -8, Hh + 15, 0.4, 2.0);
        // corvid log console on deck
        s.box(1.2, 1.2, 0.8, -3.5, Hh + 0.85, 3, M.hullDark);
        const scr = s.mesh(new THREE.PlaneGeometry(0.9, 0.6), M.screen(31, '#ff9a5a'), -3.5, Hh + 1.2, 3.42);
        scr.rotation.x = -0.3;
        s.interact({ type: 'log', logId: 'corvid' }, -3.5, Hh + 1.2, 3.6, 2.6);
        // O2 cylinder rack
        for (let i = 0; i < 4; i++) {
          const c = s.mesh(new THREE.CylinderGeometry(0.3, 0.3, 2, 12), M.orange, 8 + i * 0.7, 1.6, -4.4);
          c.rotation.z = i === 3 ? 1.2 : 0;
        }
        s.scannable('tankFragment', 9, 1.6, -4.4, 1.6);
      }
      // titanite plates around and inside
      const spots = [[-6, 1.5, 0], [6, 1.4, 1.5], [-10, 0.7, 2.6], [10, 0.7, -0.5]];
      for (const [px, py, pz] of spots) {
        const wp = s.w(px, py, pz);
        this.resourceSpots.push({ type: 'titanite', pos: wp, floorY: wp.y - 0.4 });
      }
      return s;
    };
    half('corvidAft', -16, 0, 0.12, 0.8, false, true);
    half('corvidBow', 19, 3, 0.42, 2.0, true, false);
    this.scannables.push({ id: 'wreck', pos: V(x, gh + 5, z), radius: 12 });
    // scattered plates on the canyon floor
    for (let i = 0; i < 10; i++) {
      const a = i * 0.9, d = 22 + (i % 4) * 9;
      this.resourceSpots.push({ type: 'titanite', pos: V(x + Math.cos(a) * d, 0, z + Math.sin(a) * d) });
    }
  }

  // ------------------------------------------------------------------ CAVES
  buildCaves() {
    const path = SITES.caves.path.map(([px, pz]) => V(px, -57, pz));
    const curve = new THREE.CatmullRomCurve3(path);
    const len = curve.getLength();
    const rockGeo = G.rockGeometry(7, 2, 0.45);
    G.colorize(rockGeo, (x, y, z, c) => c.setRGB(0.30, 0.31, 0.34));
    const placements = [];
    const rnd = mulberry32(77);
    const up = V(0, 1, 0);
    for (let d = 0; d < len; d += 3.2) {
      const t = d / len;
      const p = curve.getPointAt(t);
      p.y = this.terrain.heightAt(p.x, p.z);
      const tan = curve.getTangentAt(t);
      const side = V(-tan.z, 0, tan.x).normalize();
      // radius: wide entrance, narrows in the middle, chamber at the end
      const R = t < 0.15 ? 8 : t < 0.55 ? 6.5 - Math.sin((t - 0.15) / 0.4 * Math.PI) * 1.8 : t < 0.8 ? 6.5 : 7;
      if (t > 0.88) break;
      const n = 9;
      for (let k = 0; k < n; k++) {
        const ang = -0.25 + (k / (n - 1)) * (Math.PI + 0.5);
        const rr = 2.6 + rnd() * 1.6;
        const off = side.clone().multiplyScalar(Math.cos(ang) * (R + rr * 0.55)).addScaledVector(up, Math.sin(ang) * (R + rr * 0.45) + 1.5);
        placements.push({ p: p.clone().add(off), r: rr });
      }
    }
    // end chamber: dome
    const end = curve.getPointAt(1);
    end.y = this.terrain.heightAt(end.x, end.z);
    this.caveChamber = end.clone().add(V(0, 4, 0));
    const tanEnd = curve.getTangentAt(0.95);
    for (let i = 0; i < 70; i++) {
      const u = rnd() * Math.PI * 2, v = rnd() * Math.PI * 0.5;
      const dir = V(Math.cos(u) * Math.cos(v), Math.sin(v), Math.sin(u) * Math.cos(v));
      if (dir.dot(tanEnd) < -0.55 && v < 0.9) continue; // leave the tunnel mouth open
      const rr = 3 + rnd() * 2.2;
      placements.push({ p: end.clone().addScaledVector(dir, 12 + rr * 0.5).add(V(0, 1, 0)), r: rr });
    }
    const mat = waterMat({ vertexColors: true, roughness: 0.95 }, { detail: 0.4 });
    const im = new THREE.InstancedMesh(rockGeo, mat, placements.length);
    const m = new THREE.Matrix4();
    placements.forEach((pl, i) => {
      const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(rnd() * 3, rnd() * 3, rnd() * 3));
      m.compose(pl.p, q, V(pl.r, pl.r * 1.2, pl.r));
      im.setMatrixAt(i, m);
      this.collision.sphere(pl.p, pl.r * 0.82, 'cave');
    });
    im.computeBoundingSphere();
    this.group.add(im);
    // crystals inside
    const crystalGeo = G.crystalClusterGeometry(14, 0x62e6ff);
    const cmat = waterMat({ vertexColors: true, roughness: 0.25 }, { glow: { color: 0x62e6ff, intensity: 2.8, pulse: 0.5 } });
    const cpos = [];
    for (let d = 10; d < len; d += 7) {
      const t = d / len;
      const p = curve.getPointAt(Math.min(t, 1));
      const tan = curve.getTangentAt(Math.min(t, 1));
      const side = V(-tan.z, 0, tan.x).normalize();
      const sgn = (cpos.length % 2) * 2 - 1;
      const q = p.clone().addScaledVector(side, sgn * 3.5);
      q.y = this.terrain.heightAt(q.x, q.z);
      cpos.push(q);
    }
    for (let i = 0; i < 10; i++) {
      const a = i * 0.63;
      const q = end.clone().add(V(Math.cos(a) * 8, 0, Math.sin(a) * 8));
      q.y = this.terrain.heightAt(q.x, q.z);
      cpos.push(q);
    }
    const cim = new THREE.InstancedMesh(crystalGeo, cmat, cpos.length);
    const phases = new Float32Array(cpos.length);
    cpos.forEach((p, i) => {
      m.compose(p, new THREE.Quaternion().setFromAxisAngle(up, i), V(1.4, 1.4, 1.4));
      cim.setMatrixAt(i, m);
      phases[i] = i * 0.13;
    });
    cim.geometry = crystalGeo.clone();
    cim.geometry.setAttribute('aPhase', new THREE.InstancedBufferAttribute(phases, 1));
    cim.computeBoundingSphere();
    this.group.add(cim);
    // lumen crystal deposits
    cpos.forEach((p, i) => { if (i % 2 === 0) this.resourceSpots.push({ type: 'lumen', pos: p.clone().add(V(1.2, 0, 0.8)) }); });
    // shard A on a carved pedestal in the chamber
    const s = new Site(this, 'caveShrine', end.clone(), 0);
    s.mesh(new THREE.CylinderGeometry(0.7, 1.1, 1.6, 7), this.M.stone, 0, 0.6, 0);
    this.collision.tube(end, 0, 1.1, end.y - 1, end.y + 1.4, 'cave');
    const shardA = s.mesh(this.shardGeometry(), this.M.shard, 0, 2.1, 0);
    this.animated.push((t) => { shardA.rotation.y = -t * 0.7; shardA.position.y = 2.1 + Math.sin(t * 1.1) * 0.08; });
    s.interact({ type: 'item', item: 'shardA', mesh: shardA }, 0, 2.1, 0, 2.6);
    // Hara's recorder near the entrance
    const ent = curve.getPointAt(0.06);
    const es = new Site(this, 'caveEntrance', V(ent.x, this.terrain.heightAt(ent.x, ent.z), ent.z), 0);
    this.addDatapad(es, 'hara2', 1.5, 0.05, 0, 'recorder');
    this.caveCurve = curve;
  }

  // ------------------------------------------------------------------ RUINS
  buildRuins() {
    const M = this.M;
    const { x, z, floor } = SITES.ruins;
    const s = new Site(this, 'ruins', V(x, floor, z), 0.2);
    this.ruinsSite = s;
    // stepped plaza
    for (let i = 0; i < 3; i++) {
      const r = 22 + (2 - i) * 4;
      s.mesh(new THREE.CylinderGeometry(r, r + 0.5, 1, 48), M.stonePlain, 0, 0.5 + i * 0.8, 0);
    }
    const plazaTop = floor + 2.6;
    this.collision.tube(V(x, 0, z), 0, 30.5, floor - 2, plazaTop, 'ruins');
    const ringTex = this.glyphTex;
    const disc = new THREE.CircleGeometry(21, 48);
    disc.rotateX(-Math.PI / 2);
    s.mesh(disc, waterMat({ map: ringTex.map, emissiveMap: ringTex.emissive, emissive: 0x6a4cff, emissiveIntensity: 0.8 }), 0, 2.62, 0);
    // altar
    const altarY = 2.6;
    s.mesh(new THREE.CylinderGeometry(2.0, 2.6, 1.8, 6), M.stone, 0, altarY + 0.9, 0);
    this.collision.tube(s.w(0, 0, 0), 0, 2.6, plazaTop, plazaTop + 1.8, 'ruins');
    for (let k = 0; k < 3; k++) {
      const a = (k / 3) * Math.PI * 2;
      const sock = s.mesh(new THREE.TorusGeometry(0.35, 0.08, 6, 16), M.cyanLight, Math.cos(a) * 1.1, altarY + 1.82, Math.sin(a) * 1.1);
      sock.rotation.x = Math.PI / 2;
    }
    const shardC = s.mesh(this.shardGeometry(), M.shard, 1.1, altarY + 2.5, 0);
    this.animated.push((t) => { shardC.rotation.y = t * 0.9; shardC.position.y = altarY + 2.5 + Math.sin(t * 1.4) * 0.08; });
    s.interact({ type: 'item', item: 'shardC', mesh: shardC }, 1.1, altarY + 2.5, 0, 2.6);
    this.addDatapad(s, 'mensah3', -2.6, altarY, 2.6, 'recorder');
    // pillars
    const pillarGeo = new THREE.CylinderGeometry(1.0, 1.6, 22, 6, 6);
    const rnd = mulberry32(23);
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * Math.PI * 2 + 0.15;
      const px = Math.cos(a) * 26, pz = Math.sin(a) * 26;
      const broken = i % 3 === 1;
      const h = broken ? 8 + rnd() * 5 : 22;
      const pg = broken ? new THREE.CylinderGeometry(1.25, 1.6, h, 6, 3) : pillarGeo;
      s.mesh(pg, M.stone, px, 2.6 + h / 2, pz, a);
      this.collision.capsule(s.w(px, 2.6, pz), s.w(px, 2.6 + h, pz), 1.5, 'ruins');
      if (broken) {
        // fallen section
        const fa = a + 1.2;
        const fx = Math.cos(a) * 34, fz = Math.sin(a) * 34;
        const fy = this.terrain.heightAt(...[s.w(fx, 0, fz)].map((v) => [v.x, v.z])[0]) - floor + 1.2;
        const fl = s.mesh(new THREE.CylinderGeometry(1.2, 1.25, 10, 6), M.stone, fx, fy, fz, fa);
        fl.rotation.z = Math.PI / 2;
        const dir = V(Math.cos(-fa), 0, Math.sin(-fa));
        this.collision.capsule(s.w(fx - dir.x * 5, fy, fz - dir.z * 5), s.w(fx + dir.x * 5, fy, fz + dir.z * 5), 1.2, 'ruins');
      }
      if (i === 0 || i === 5) s.scannable('ruinsGlyph', px, 8, pz, 2.2);
    }
    // great arch at the north entrance
    const arch = new THREE.TorusGeometry(14, 1.7, 10, 40, Math.PI);
    const am = s.mesh(arch, M.stone, 0, 2.6, -30);
    am.scale.set(1, 1.5, 1);
    for (let k = 0; k <= 24; k++) {
      const a = (k / 24) * Math.PI;
      this.collision.sphere(s.w(Math.cos(a) * 14, 2.6 + Math.sin(a) * 14 * 1.5, -30), 1.9, 'ruins');
    }
    // pressure lattice on the rift wall
    const lat = new Site(this, 'lattice', s.w(44, 0, 6), 0.2 - Math.PI / 2);
    const ly0 = this.terrain.heightAt(lat.origin.x, lat.origin.z) + 1;
    lat.origin.y = ly0; lat.group.position.y = ly0;
    for (let i = -3; i <= 3; i++) {
      lat.capsule([i * 3 - 6, 0, 0], [i * 3 + 6, 14, 0], 0.32, M.stone, 6);
      lat.capsule([i * 3 + 6, 0, 0], [i * 3 - 6, 14, 0], 0.32, M.stone, 6);
    }
    lat.capsule([-15, 14, 0], [15, 14, 0], 0.5, M.stone, 6);
    lat.scannable('veyruLattice', 0, 7, 0, 5);
    this.scannables.push({ id: 'crystal', pos: s.w(0, 3, -30), radius: 0.1 }); // placeholder anchor (unused)
    // alloy & void glass around the plaza
    for (let i = 0; i < 8; i++) {
      const a = i * 0.8 + 0.3, d = 33 + (i % 3) * 6;
      this.resourceSpots.push({ type: 'veyruAlloy', pos: s.w(Math.cos(a) * d, 0, Math.sin(a) * d) });
    }
    for (let i = 0; i < 6; i++) {
      const a = i * 1.05 + 0.6, d = 18 + (i % 2) * 3;
      this.resourceSpots.push({ type: 'voidGlass', pos: s.w(Math.cos(a) * d, 2.65, Math.sin(a) * d), floorY: plazaTop });
    }
    this.scannables = this.scannables.filter((sc) => sc.radius > 0.2);
  }

  // ------------------------------------------------------------------ BEACON
  buildBeacon() {
    const M = this.M;
    const { x, z } = SITES.beacon;
    const gh = this.terrain.heightAt(x, z);
    const s = new Site(this, 'beacon', V(x, gh, z), 0.8);
    // boulder she rests against
    const rock = s.mesh(G.rockGeometry(31), M.rock, -1.6, 0.6, 0);
    rock.scale.set(2.2, 1.8, 2.6);
    this.collision.sphere(s.w(-1.6, 0.9, 0), 1.9);
    // the suit, slumped
    s.capsule([0, 0.6, 0], [-0.6, 1.4, 0], 0.32, M.suit);
    const helm = s.mesh(new THREE.SphereGeometry(0.3, 16, 12), M.suit, -0.85, 1.75, 0);
    const vis = new THREE.Mesh(new THREE.SphereGeometry(0.24, 16, 12, -0.6, 1.8, 0.6, 1.4), M.visor);
    vis.position.x = 0.1; vis.rotation.y = -Math.PI / 2;
    helm.add(vis);
    s.capsule([0.1, 0.35, 0.2], [1.2, 0.2, 0.35], 0.13, M.suit);
    s.capsule([0.1, 0.35, -0.2], [1.1, 0.2, -0.5], 0.13, M.suit);
    s.capsule([-0.4, 1.2, 0.3], [0.2, 0.6, 0.7], 0.1, M.suit);
    s.mesh(new THREE.BoxGeometry(0.5, 0.7, 0.45), M.orange, -0.7, 1.0, 0);
    this.beaconLight = s.mesh(new THREE.SphereGeometry(0.12, 10, 8), M.redLight.clone(), -0.9, 1.5, 0.3);
    this.beaconLight.material.onBeforeCompile = M.redLight.onBeforeCompile;
    this.beaconLight.material.customProgramCacheKey = M.redLight.customProgramCacheKey;
    this.animated.push((t) => { this.beaconLight.material.emissiveIntensity = Math.sin(t * 4) > 0.6 ? 5 : 0.2; });
    s.scannable('lindqvistSuit', -0.3, 1.0, 0, 1.4);
    this.addDatapad(s, 'lindqvist3', 0.9, 0.05, 0.9, 'recorder');
    // flares toward the abyss
    const dir = V(SITES.abyss.x - x, 0, SITES.abyss.z - z).normalize();
    for (let i = 1; i <= 6; i++) {
      const fx = x + dir.x * i * 7, fz = z + dir.z * i * 7;
      const fy = this.terrain.heightAt(fx, fz);
      const fl = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.4, 6), M.redLight);
      fl.position.set(fx, fy + 0.1, fz);
      fl.rotation.z = Math.PI / 2;
      fl.rotation.y = i;
      this.group.add(fl);
    }
  }

  // ------------------------------------------------------------------ THRESHOLD
  buildGate() {
    const M = this.M;
    const { x, z } = SITES.abyss;
    const gh = this.terrain.heightAt(x, z);
    const s = new Site(this, 'threshold', V(x, gh, z), 0.6);
    this.gateSite = s;
    s.mesh(new THREE.CylinderGeometry(16, 19, 6, 8), M.stonePlain, 0, 2, 0);
    this.collision.tube(V(x, 0, z), 0, 19, gh - 3, gh + 5, 'gate');
    s.mesh(new THREE.CylinderGeometry(12, 16, 1.2, 8), M.stone, 0, 5.6, 0);
    const baseTop = gh + 6.2;
    const ringR = 30, tube = 3.2;
    const cy = 6.2 + ringR + 2;
    const ring = s.mesh(new THREE.TorusGeometry(ringR, tube, 16, 120), this.gateRingMat = waterMat({ map: this.glyphTex.map, emissiveMap: this.glyphTex.emissive, emissive: 0x8a6cff, emissiveIntensity: 1.2, roughness: 0.5, metalness: 0.3 }), 0, cy, 0);
    this.gateRing = ring;
    for (let k = 0; k < 64; k++) {
      const a = (k / 64) * Math.PI * 2;
      this.collision.sphere(s.w(Math.cos(a) * ringR, cy + Math.sin(a) * ringR, 0), tube + 0.3, 'gate');
    }
    // the membrane (resonance field)
    this.gateFieldMat = new THREE.ShaderMaterial({
      uniforms: { uTime: U.uTime, uOpen: { value: 0 } },
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
      blending: THREE.AdditiveBlending,
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: /* glsl */`
        uniform float uTime; uniform float uOpen; varying vec2 vUv;
        void main() {
          vec2 p = vUv - 0.5;
          float r = length(p) * 2.0;
          float a = atan(p.y, p.x);
          float swirl = sin(a * 6.0 + r * 18.0 - uTime * (0.6 + uOpen * 3.0)) * 0.5 + 0.5;
          float rings = sin(r * 40.0 - uTime * 2.0) * 0.5 + 0.5;
          float core = smoothstep(1.0, 0.0, r);
          vec3 col = mix(vec3(0.35, 0.2, 0.9), vec3(0.4, 0.95, 1.0), swirl) * (0.08 + uOpen * 1.8);
          float alpha = core * (0.25 + swirl * 0.35 + rings * 0.15) * smoothstep(1.0, 0.92, r);
          gl_FragColor = vec4(col * alpha + vec3(1.0) * pow(core, 6.0) * uOpen * 2.0, 1.0);
        }`,
    });
    s.mesh(new THREE.CircleGeometry(ringR - tube, 64), this.gateFieldMat, 0, cy, 0);
    // flanking pylons
    for (const sx of [-1, 1]) {
      s.capsule([sx * 44, -2, 0], [sx * 44, 52, 0], 3, M.stone, 8);
      s.mesh(new THREE.ConeGeometry(3, 8, 8), M.stone, sx * 44, 56, 0);
    }
    this.gateCenter = s.w(0, cy, 0);
    s.interact({ type: 'gate', fromSub: true }, 0, cy, 0, 48);
    s.scannable('gate', 0, cy + ringR, 0, 6);
    // last logs on the plinth (retrievable with the Kestrel's manipulator)
    this.addDatapad(s, 'varga3', 8, 6.2, 6, 'recorder');
    this.addDatapad(s, 'hara3', -8, 6.2, 6);
    for (const it of this.interactables) if (it.logId === 'varga3' || it.logId === 'hara3') { it.fromSub = true; it.radius = 16; }
    // a few deep void glass deposits around the base
    for (let i = 0; i < 6; i++) {
      const a = i * 1.04;
      this.resourceSpots.push({ type: 'voidGlass', pos: V(x + Math.cos(a) * 30, 0, z + Math.sin(a) * 30) });
    }
    this.baseTop = baseTop;
  }

  buildDebris() {
    // survey drone crashed near the monolith (environmental)
    const M = this.M;
    const x = SITES.monolith.x + 16, z = SITES.monolith.z + 9;
    const s = new Site(this, 'drone', V(x, this.terrain.heightAt(x, z) + 0.4, z), 1.1);
    const body = s.mesh(new THREE.SphereGeometry(0.8, 16, 10), M.hull, 0, 0, 0);
    body.scale.set(1.6, 0.6, 1);
    body.rotation.z = 0.4;
    s.mesh(new THREE.BoxGeometry(2.6, 0.08, 0.5), M.hullDark, 0.3, 0.1, 0.9).rotation.z = 0.4;
    this.collision.sphere(s.origin, 1.1);
  }

  setPower(on) {
    this.powered = on;
    this.ceilingLightMat.emissive.set(on ? 0xffe2b8 : 0xff4030);
    this.ceilingLightMat.emissiveIntensity = on ? 2.4 : 0.6;
    this.stationLight.color.set(on ? 0xffe0c0 : 0xff4a30);
    this.stationLight.intensity = on ? 7 : 2;
    this.windowMat.emissiveIntensity = on ? 2.2 : 0.15;
    this.floodMat.emissiveIntensity = on ? 3 : 0;
    this.coreMat.emissive.set(on ? 0x6ff3ff : 0xff3b2b);
    this.coreMat.emissiveIntensity = on ? 2.5 : 0.8;
    this.termScreenMat.emissiveMap = on ? this.termTexOn : this.termTexOff;
    this.termScreenMat.needsUpdate = true;
    this.stripMat.emissive.set(on ? 0xffe2b8 : 0xff3b2b);
    this.stripMat.emissiveIntensity = on ? 1.4 : 1.6;
    this.beaconMat.emissive.set(on ? 0x6ff3ff : 0xff3b2b);
    this.dockLightMat.emissive.set(on ? 0x6ff3ff : 0xff3b2b);
  }

  update(dt, t, song = 0) {
    for (const f of this.animated) f(t);
    // beacon blink
    this.beaconMat.emissiveIntensity = Math.sin(t * (this.powered ? 2 : 5)) > 0.3 ? 4 : 0.3;
    if (!this.powered) {
      this.stationLight.intensity = 1.8 + Math.sin(t * 9) * Math.sin(t * 2.3) * 0.8;
    }
    // glyph pulse follows the Low Song
    const pulse = 0.25 + song * 0.7 + Math.sin(t * 0.7) * 0.1;
    this.M.stone.emissiveIntensity = pulse;
    this.monolithMat.emissiveIntensity = pulse * 0.8;
    if (this.gateRingMat) this.gateRingMat.emissiveIntensity = pulse * 1.2;
  }
}
