// Vegetation, coral, rocks and crystals scattered over the seafloor using
// instanced meshes split into spatial tiles (so they frustum/distance cull).

import * as THREE from 'three';
import { waterMat } from './shading.js';
import { surface } from './surfaces.js';
import { biomeWeights, SITES } from './layout.js';
import { mulberry32, smoothstep } from '../core/noise.js';
import * as G from './geom.js';
import { boulderGeometry } from './rocks.js';
import * as P from './plants.js';

const TILE = 150;
const _m = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _s = new THREE.Vector3();
const _p = new THREE.Vector3();
const _up = new THREE.Vector3(0, 1, 0);
const _e = new THREE.Euler();

export class Scatter {
  /** opts.lod = { geometry, dist }: tiles farther than `dist` draw the light geometry. opts.tile: tile size. */
  constructor(name, geometry, material, maxDist = 260, opts = {}) {
    this.name = name;
    this.geometry = geometry;
    this.material = material;
    this.maxDist = maxDist;
    this.lod = opts.lod || null;
    this.tile = opts.tile || TILE;
    this.lodMeshes = [];
    this.tiles = new Map();
    this.meshes = [];
    this.points = []; // world positions for scanning/queries
  }

  add(matrix, phase, pos) {
    const key = `${Math.floor(pos.x / this.tile)},${Math.floor(pos.z / this.tile)}`;
    let t = this.tiles.get(key);
    if (!t) { t = { matrices: [], phases: [] }; this.tiles.set(key, t); }
    t.matrices.push(matrix.clone());
    t.phases.push(phase);
    this.points.push(pos.clone());
  }

  build(parent) {
    for (const [, t] of this.tiles) {
      const mesh = new THREE.InstancedMesh(this.geometry, this.material, t.matrices.length);
      const phases = new Float32Array(t.matrices.length);
      t.matrices.forEach((m, i) => { mesh.setMatrixAt(i, m); phases[i] = t.phases[i]; });
      mesh.geometry = this.geometry.clone();
      mesh.geometry.setAttribute('aPhase', new THREE.InstancedBufferAttribute(phases, 1));
      mesh.instanceMatrix.needsUpdate = true;
      mesh.computeBoundingSphere();
      mesh.name = this.name;
      mesh.matrixAutoUpdate = false;
      this.meshes.push(mesh);
      parent.add(mesh);
      if (this.lod) {
        // far version shares the instance data
        const lo = new THREE.InstancedMesh(this.lod.geometry.clone(), this.material, t.matrices.length);
        lo.instanceMatrix = mesh.instanceMatrix;
        lo.geometry.setAttribute('aPhase', mesh.geometry.attributes.aPhase);
        lo.boundingSphere = mesh.boundingSphere;
        lo.name = this.name;
        lo.matrixAutoUpdate = false;
        lo.visible = false;
        this.lodMeshes.push(lo);
        parent.add(lo);
      } else this.lodMeshes.push(null);
    }
  }

  cull(cam, distScale = 1) {
    const max = this.maxDist * distScale;
    const near = this.lod ? this.lod.dist * Math.min(1, distScale) : Infinity;
    this.meshes.forEach((m, i) => {
      const bs = m.boundingSphere;
      const d = bs.center.distanceTo(cam) - bs.radius;
      const lo = this.lodMeshes[i];
      m.visible = d < Math.min(max, lo ? near : max);
      if (lo) lo.visible = !m.visible && d < max;
    });
  }
}

export class Flora {
  constructor(scene, terrain, collision, quality = 'high', { classic = false } = {}) {
    this.scene = scene;
    this.classic = classic;
    this.terrain = terrain;
    this.collision = collision;
    this.group = new THREE.Group();
    this.group.name = 'flora';
    scene.add(this.group);
    this.sets = [];
    this.density = quality === 'low' ? 0.55 : quality === 'medium' ? 0.8 : 1;
    this.exclusions = [
      { x: SITES.station.x, z: SITES.station.z, r: 30 },
      { x: SITES.echoLab.x, z: SITES.echoLab.z, r: 30 },
      { x: SITES.ruins.x, z: SITES.ruins.z, r: 46 },
      { x: SITES.wreck.x, z: SITES.wreck.z, r: 40 },
      { x: SITES.monolith.x, z: SITES.monolith.z, r: 12 },
    ];
  }

  excluded(x, z) {
    for (const e of this.exclusions) if ((x - e.x) ** 2 + (z - e.z) ** 2 < e.r * e.r) return true;
    return false;
  }

  makeSet(name, geo, mat, maxDist, opts) {
    const s = new Scatter(name, geo, mat, maxDist, opts);
    this.sets.push(s);
    return s;
  }

  /**
   * Scatter `count` attempts inside a rectangle; accept by weightFn(x,z,h,normal) (0..1).
   * place(x, y, z, normal, rnd) -> { scale: Vector3|number, tiltToNormal, yaw }
   */
  scatter(sets, count, area, weightFn, opts = {}) {
    const rnd = mulberry32(opts.seed ?? 1);
    const n = Math.floor(count * this.density);
    const nrm = new THREE.Vector3();
    let placed = 0;
    for (let i = 0; i < n * 4 && placed < n; i++) {
      const x = area.x0 + rnd() * (area.x1 - area.x0);
      const z = area.z0 + rnd() * (area.z1 - area.z0);
      if (this.excluded(x, z)) continue;
      const h = this.terrain.heightAt(x, z);
      this.terrain.normalAt(x, z, nrm);
      if (opts.maxSlope !== undefined && nrm.y < opts.maxSlope) continue;
      if (opts.minDepth !== undefined && h > -opts.minDepth) continue;
      if (opts.maxDepth !== undefined && h < -opts.maxDepth) continue;
      const w = weightFn(x, z, h, nrm, rnd);
      if (rnd() > w) continue;
      const set = sets[Math.floor(rnd() * sets.length)];
      const sc = opts.scale ? opts.scale(rnd, x, z) : 1;
      const scale = typeof sc === 'number' ? _s.set(sc, sc, sc) : _s.copy(sc);
      _p.set(x, h - (opts.sink ?? 0.05) * scale.y, z);
      if (opts.tilt) {
        _q.setFromUnitVectors(_up, nrm.clone().lerp(_up, 1 - opts.tilt).normalize());
        const yawQ = new THREE.Quaternion().setFromAxisAngle(_up, rnd() * Math.PI * 2);
        _q.multiply(yawQ);
      } else {
        _e.set((rnd() - 0.5) * (opts.wobble ?? 0.15), rnd() * Math.PI * 2, (rnd() - 0.5) * (opts.wobble ?? 0.15));
        _q.setFromEuler(_e);
      }
      _m.compose(_p, _q, scale);
      set.add(_m, rnd(), _p);
      if (opts.collide) opts.collide(_p, scale);
      placed++;
    }
    return placed;
  }

  build() {
    const B = (x, z) => biomeWeights(x, z);
    const world = { x0: -760, x1: 760, z0: -760, z1: 760 };

    // ---------- materials
    const plantMat = (swim, glow, extra = {}) => waterMat({ vertexColors: true, side: THREE.DoubleSide, roughness: 0.8, ...extra }, { swim, glow });
    const grassMat = plantMat({ mode: 4, amp: 0.18, speed: 1.4, freq: 2, len: 1.6 }, { color: 0x77ffd8, intensity: 1.2, pulse: 1 });
    const kelpMat = plantMat({ mode: 4, amp: 0.06, speed: 0.55, freq: 5, len: 1 }, { color: 0x6fd8ef, intensity: 1.1, pulse: 0.8 });
    const coralMat = waterMat({ vertexColors: true, roughness: 0.75 }, { glow: { color: 0xff9a7a, intensity: 0.9, pulse: 0.6 }, detail: 0.9, surface: surface('coral') });
    const fanMat = plantMat({ mode: 4, amp: 0.05, speed: 0.9, freq: 1, len: 1 }, { color: 0xd7a0ff, intensity: 0.9, pulse: 0.5 });
    const spongeMat = waterMat({ vertexColors: true, roughness: 0.9, side: THREE.DoubleSide }, { glow: { color: 0x66f0ff, intensity: 2.4, pulse: 0.9 } });
    const anemoneMat = plantMat({ mode: 4, amp: 0.12, speed: 1.6, freq: 6, len: 0.8 }, { color: 0xb07bff, intensity: 2.2, pulse: 1.4 });
    const lanternMat = plantMat({ mode: 4, amp: 0.12, speed: 0.8, freq: 1.2, len: 2 }, { color: 0x6ff3ff, intensity: 2.2, pulse: 0.7 });
    const crystalMat = waterMat({ vertexColors: true, roughness: 0.25, metalness: 0.1 }, { glow: { color: 0x9a7bff, intensity: 2.6, pulse: 0.4 } });
    const crystalCyanMat = waterMat({ vertexColors: true, roughness: 0.25, metalness: 0.1 }, { glow: { color: 0x5ff0ff, intensity: 2.4, pulse: 0.5 } });
    const wormMat = plantMat({ mode: 4, amp: 0.05, speed: 1.2, freq: 3, len: 2 }, { color: 0xff5040, intensity: 1.6, pulse: 1.1 });
    const rockMat = waterMat({ vertexColors: true, roughness: 0.9 }, { detail: 0.35, surface: surface('rock'), reflect: 0.7 });

    // ---------- geometry variants
    const grass = this.makeSet('seagrass', G.merge([G.seagrassGeometry(1), G.seagrassGeometry(2).translate(0.5, 0, 0.3)]), grassMat, 85);
    const C = this.classic;
    const kelpSet = (seed) => (C ? this.makeSet('kelp', G.kelpGeometry(seed), kelpMat, 210)
      : this.makeSet('kelp', P.kelpGeometry(seed), kelpMat, 210, { tile: 50, lod: { geometry: P.kelpGeometry(seed, { lod: 1 }), dist: 18 } }));
    const coralSet = (seed, color) => (C ? this.makeSet('branchCoral', G.branchCoralGeometry(seed, color), coralMat, 200)
      : this.makeSet('branchCoral', P.branchCoralGeometry(seed, color), coralMat, 200, { tile: 60, lod: { geometry: P.branchCoralGeometry(seed, color, { lod: 1 }), dist: 25 } }));
    const kelp = kelpSet(3);
    const kelp2 = kelpSet(7);
    const coralA = coralSet(4, 0xd8644a);
    const coralB = coralSet(9, 0xe0a040);
    const coralC = coralSet(15, 0xb04a8a);
    const fanA = this.makeSet('fanCoral', G.fanCoralGeometry(2, 0x9a4fc0), fanMat, 200);
    const fanB = this.makeSet('fanCoral', G.fanCoralGeometry(5, 0xc0506a), fanMat, 200);
    const brain = this.makeSet('brainCoral', G.brainCoralGeometry(3, 0xb8a46c), coralMat, 200);
    const brain2 = this.makeSet('brainCoral', G.brainCoralGeometry(8, 0x7fa070), coralMat, 200);
    const sponge = this.makeSet('tubeSponge', G.tubeSpongeGeometry(3, 0xc48b3a), spongeMat, 220);
    const sponge2 = this.makeSet('tubeSponge', G.tubeSpongeGeometry(11, 0x6a7fb0), spongeMat, 220);
    const anemone = this.makeSet('anemone', G.anemoneGeometry(2, 0x5a3a7a), anemoneMat, 140);
    const lantern = this.makeSet('lanternPlant', G.lanternPlantGeometry(4), lanternMat, 200);
    const lantern2 = this.makeSet('lanternPlant', G.lanternPlantGeometry(12), lanternMat, 200);
    const crystal = this.makeSet('crystal', G.crystalClusterGeometry(5, 0x8a6cff), crystalMat, 300);
    const crystalC = this.makeSet('crystal', G.crystalClusterGeometry(9, 0x50d8f0), crystalCyanMat, 300);
    const worms = this.makeSet('tubeWorm', G.tubeWormGeometry(6), wormMat, 200);
    let rocks;
    if (this.classic) {
      const rockGeos = [G.rockGeometry(1), G.rockGeometry(2), G.rockGeometry(3, 2, 0.5)];
      rocks = rockGeos.map((g) => this.makeSet('rock', g, rockMat, 320));
      rockGeos.forEach((g) => G.colorize(g, (x, y, z, c) => c.setRGB(0.42, 0.43, 0.45).multiplyScalar(0.8 + y * 0.2)));
    } else {
      // fractured boulders: detailed near, light far (same silhouette family)
      const variants = [{ seed: 1 }, { seed: 2, strata: 0.7 }, { seed: 3, cuts: 9 }, { seed: 4, strata: 0.5, cuts: 5 }];
      rocks = variants.map((o) => this.makeSet('rock', boulderGeometry(o.seed, { ...o, detail: 9 }), rockMat, 320,
        { tile: 100, lod: { geometry: boulderGeometry(o.seed, { ...o, detail: 3 }), dist: 35 } }));
    }

    const col = this.collision;
    const rockCollide = (p, s) => {
      if (s.x > 1.6) col.sphere(new THREE.Vector3(p.x, p.y + s.y * 0.3, p.z), Math.min(s.x, s.z) * 0.85, 'rock');
    };

    // ---------- shelf
    this.scatter([grass], 3300, { x0: -320, x1: 320, z0: -320, z1: 260 }, (x, z, h) => {
      const b = B(x, z);
      return (0.15 + b.shelf * 0.85) * (1 - b.coral) * smoothstep(-90, -40, h);
    }, { seed: 11, maxSlope: 0.75, scale: (r) => 0.8 + r() * 0.9 });
    this.scatter([lantern, lantern2], 380, { x0: -330, x1: 330, z0: -330, z1: 240 }, (x, z, h) => {
      const b = B(x, z);
      return 0.25 + b.shelf * 0.5 + b.kelp * 0.4;
    }, { seed: 12, maxSlope: 0.7, scale: (r) => 0.9 + r() * 1.1 });
    this.scatter([anemone], 420, { x0: -300, x1: 300, z0: -300, z1: 420 }, (x, z, h) => {
      const b = B(x, z);
      return 0.2 + b.shelf * 0.4 + b.coral * 0.6;
    }, { seed: 13, maxSlope: 0.65, scale: (r) => 0.8 + r() * 1.4 });

    // ---------- kelp forest
    this.scatter([kelp, kelp2], 1300, { x0: -460, x1: -60, z0: -170, z1: 210 }, (x, z, h) => {
      const b = B(x, z);
      return b.kelp * b.kelp;
    }, { seed: 21, maxSlope: 0.7, sink: 0.0, scale: (r, x, z) => {
      const h = this.terrain.heightAt(x, z);
      const maxH = Math.min(-h - 6, 22 + r() * 22);
      return new THREE.Vector3(1.3 + r() * 0.8, Math.max(6, maxH), 1.3 + r() * 0.8);
    } });
    this.scatter([grass], 1100, { x0: -460, x1: -60, z0: -170, z1: 210 }, (x, z) => B(x, z).kelp, { seed: 22, maxSlope: 0.7, scale: (r) => 1 + r() });

    // ---------- coral terraces
    const coralArea = { x0: -230, x1: 280, z0: 120, z1: 520 };
    const coralW = (x, z) => B(x, z).coral;
    this.scatter([coralA, coralB, coralC], 1100, coralArea, coralW, { seed: 31, maxSlope: 0.6, scale: (r) => 1.2 + r() * 2.6 });
    this.scatter([fanA, fanB], 700, coralArea, coralW, { seed: 32, maxSlope: 0.55, scale: (r) => 1 + r() * 1.8, wobble: 0.3 });
    this.scatter([brain, brain2], 420, coralArea, coralW, { seed: 33, maxSlope: 0.6, scale: (r) => 0.6 + r() * 1.6 });
    this.scatter([sponge, sponge2], 620, coralArea, coralW, { seed: 34, maxSlope: 0.55, scale: (r) => 1 + r() * 1.5 });

    // ---------- canyon + plains (deep sponges & crystals)
    this.scatter([sponge, sponge2], 700, world, (x, z, h) => {
      const b = B(x, z);
      return b.canyon * 0.9 + smoothstep(-80, -140, h) * 0.12 * (1 - b.abyss);
    }, { seed: 41, maxSlope: 0.5, scale: (r) => 1.2 + r() * 1.8 });
    this.scatter([crystal, crystalC], 260, { x0: 120, x1: 620, z0: -150, z1: 120 }, (x, z) => B(x, z).canyon, { seed: 42, scale: (r) => 0.8 + r() * 1.6, tilt: 0.6 });

    // ---------- rift & abyss
    this.scatter([crystal, crystalC], 650, { x0: -520, x1: 80, z0: 300, z1: 800 }, (x, z, h) => B(x, z).rift * smoothstep(-160, -240, h), { seed: 51, scale: (r) => 1 + r() * 2.5, tilt: 0.7 });
    this.scatter([worms], 700, { x0: -520, x1: 80, z0: 300, z1: 800 }, (x, z, h) => B(x, z).rift * smoothstep(-200, -250, h), { seed: 52, maxSlope: 0.6, scale: (r) => 0.8 + r() * 1.4 });
    this.scatter([crystal], 300, { x0: 140, x1: 620, z0: 300, z1: 780 }, (x, z, h) => B(x, z).abyss * smoothstep(-300, -500, h), { seed: 53, scale: (r) => 1.5 + r() * 3.5, tilt: 0.8 });

    // ---------- rocks everywhere
    this.scatter(rocks, 2600, world, (x, z, h, n) => {
      const b = B(x, z);
      return 0.12 + (1 - n.y) * 1.5 + b.canyon * 0.4 + b.rift * 0.3;
    }, { seed: 61, tilt: 0.7, sink: 0.35, scale: (r) => {
      const s = 0.6 + Math.pow(r(), 3) * 7;
      return new THREE.Vector3(s * (0.8 + r() * 0.6), s * (0.6 + r() * 0.6), s * (0.8 + r() * 0.6));
    }, collide: rockCollide });

    for (const s of this.sets) s.build(this.group);
  }

  /** Scatter an extra instanced set (e.g. an external model) using the same culling. */
  addScatter(name, geo, mat, count, area, weightFn, opts = {}, maxDist = 80) {
    const set = this.makeSet(name, geo, mat, maxDist);
    this.scatter([set], count, area, weightFn, opts);
    set.build(this.group);
    return set;
  }

  update(camPos, distScale = 1) {
    for (const s of this.sets) s.cull(camPos, distScale);
  }

  pointsOf(name) {
    const out = [];
    for (const s of this.sets) if (s.name === name) out.push(...s.points);
    return out;
  }
}
