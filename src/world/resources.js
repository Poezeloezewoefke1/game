// Collectable resource deposits. Deterministic placement (stable ids for saves),
// instanced per type, with slow respawn for common materials.

import * as THREE from 'three';
import { waterMat } from './shading.js';
import { biomeWeights, SITES } from './layout.js';
import { mulberry32, smoothstep } from '../core/noise.js';
import * as G from './geom.js';

const RESPAWN = 900; // seconds of game time

function nodeGeometry(type) {
  switch (type) {
    case 'ferrite': {
      const g = G.rockGeometry(5, 1, 0.5);
      G.colorize(g, (x, y, z, c) => c.setRGB(0.35, 0.33, 0.32).multiplyScalar(0.8 + Math.abs(Math.sin(x * 9 + z * 7)) * 0.5));
      const glow = g.attributes.aGlow;
      const p = g.attributes.position;
      for (let i = 0; i < p.count; i++) glow.setX(i, Math.sin(p.getX(i) * 13) * Math.cos(p.getZ(i) * 11) > 0.75 ? 0.9 : 0);
      g.scale(0.55, 0.5, 0.55);
      return { geo: g, glow: 0xff9a4a, intensity: 1.6, radius: 0.6 };
    }
    case 'lumen':
      return { geo: G.crystalClusterGeometry(41, 0x62e6ff).scale(0.45, 0.45, 0.45), glow: 0x62e6ff, intensity: 3.2, radius: 0.6 };
    case 'kelpFiber': {
      const parts = [];
      for (let i = 0; i < 5; i++) {
        const s = new THREE.SphereGeometry(0.14, 8, 6).scale(1, 1.8, 1);
        const a = i * 1.26;
        s.rotateZ(0.4 * Math.cos(a)).translate(Math.cos(a) * 0.16, 0.22, Math.sin(a) * 0.16);
        parts.push(G.prep(s, 0x8fb04a, (x, y) => (y > 0.3 ? 0.8 : 0.1)));
      }
      parts.push(G.prep(new THREE.CylinderGeometry(0.05, 0.08, 0.2, 6).translate(0, 0.1, 0), 0x4f6b2e));
      return { geo: G.merge(parts), glow: 0xd7ff7a, intensity: 2, radius: 0.5 };
    }
    case 'silica': {
      const parts = [];
      const rnd = mulberry32(8);
      for (let i = 0; i < 6; i++) {
        const s = new THREE.BoxGeometry(0.3 + rnd() * 0.2, 0.04, 0.2 + rnd() * 0.15);
        s.rotateX((rnd() - 0.5) * 1.2).rotateZ((rnd() - 0.5) * 1.2).translate((rnd() - 0.5) * 0.4, 0.08 + rnd() * 0.15, (rnd() - 0.5) * 0.4);
        parts.push(G.prep(s, 0xf3d6c8, 0.35));
      }
      return { geo: G.merge(parts), glow: 0xffc0b0, intensity: 1.4, radius: 0.5 };
    }
    case 'titanite': {
      const plate = new THREE.BoxGeometry(0.9, 0.08, 0.6);
      plate.rotateZ(0.25);
      const plate2 = new THREE.BoxGeometry(0.7, 0.08, 0.5).rotateZ(-0.4).rotateY(0.7).translate(0.1, 0.12, 0.1);
      const g = G.merge([G.prep(plate, 0xb87a4a, (x) => (Math.abs(x) > 0.4 ? 0.6 : 0)), G.prep(plate2, 0xa0a8ae, 0.2)]);
      g.translate(0, 0.12, 0);
      return { geo: g, glow: 0xffb070, intensity: 1.5, radius: 0.6 };
    }
    case 'voidGlass':
      return { geo: G.crystalClusterGeometry(57, 0x241a3a).scale(0.5, 0.6, 0.5), glow: 0xa387ff, intensity: 2.8, radius: 0.6 };
    case 'veyruAlloy': {
      const g = new THREE.TorusGeometry(0.35, 0.09, 8, 20, Math.PI * 1.2);
      g.rotateX(Math.PI / 2.4).translate(0, 0.15, 0);
      return { geo: G.prep(g, 0x3a4a52, (x, y, z) => (Math.abs(Math.sin(Math.atan2(z, x) * 6)) > 0.8 ? 1 : 0)), glow: 0x9ef5e0, intensity: 2.6, radius: 0.55 };
    }
    default:
      return { geo: G.prep(new THREE.SphereGeometry(0.3)), glow: 0xffffff, intensity: 1, radius: 0.5 };
  }
}

export class Resources {
  constructor(scene, terrain) {
    this.scene = scene;
    this.terrain = terrain;
    this.nodes = [];
    this.byType = {};
    this.group = new THREE.Group();
    this.group.name = 'resources';
    scene.add(this.group);
  }

  add(type, x, z, yOverride) {
    const y = yOverride ?? this.terrain.heightAt(x, z);
    const node = { id: this.nodes.length, type, pos: new THREE.Vector3(x, y, z), collected: false, collectedAt: 0, rot: (this.nodes.length * 2.39) % (Math.PI * 2) };
    this.nodes.push(node);
    return node;
  }

  scatterBy(type, count, area, weight, seed, opts = {}) {
    const rnd = mulberry32(seed);
    let placed = 0;
    for (let i = 0; i < count * 30 && placed < count; i++) {
      const x = area.x0 + rnd() * (area.x1 - area.x0);
      const z = area.z0 + rnd() * (area.z1 - area.z0);
      const h = this.terrain.heightAt(x, z);
      if (opts.maxDepth && h < -opts.maxDepth) continue;
      if (opts.minDepth && h > -opts.minDepth) continue;
      if (Math.hypot(x, z) < 26) continue; // not under the station
      if (rnd() > weight(x, z, h)) continue;
      this.add(type, x, z);
      placed++;
    }
  }

  build(structureSpots) {
    const B = biomeWeights;
    // order matters: ids must be stable across sessions
    this.scatterBy('ferrite', 34, { x0: -280, x1: 280, z0: -280, z1: 200 }, (x, z) => B(x, z).shelf * 0.8 + 0.1, 101, { maxDepth: 62 });
    this.scatterBy('ferrite', 8, { x0: -430, x1: -80, z0: -150, z1: 200 }, (x, z) => B(x, z).kelp, 102);
    this.scatterBy('lumen', 12, { x0: -250, x1: 250, z0: -250, z1: 200 }, (x, z) => B(x, z).shelf * 0.7 + 0.1, 103, { maxDepth: 60 });
    this.scatterBy('lumen', 8, { x0: -430, x1: -80, z0: -150, z1: 200 }, (x, z) => B(x, z).kelp, 104);
    this.scatterBy('lumen', 6, { x0: -200, x1: 250, z0: 150, z1: 500 }, (x, z) => B(x, z).coral, 105);
    this.scatterBy('kelpFiber', 28, { x0: -440, x1: -70, z0: -160, z1: 200 }, (x, z) => B(x, z).kelp ** 2, 106);
    this.scatterBy('kelpFiber', 6, { x0: -200, x1: 200, z0: -200, z1: 150 }, (x, z) => B(x, z).shelf * 0.5, 107, { maxDepth: 50 });
    this.scatterBy('silica', 24, { x0: -220, x1: 270, z0: 130, z1: 520 }, (x, z) => B(x, z).coral, 108);
    this.scatterBy('voidGlass', 7, { x0: 470, x1: 600, z0: -40, z1: 60 }, (x, z) => B(x, z).canyon, 109);
    this.scatterBy('voidGlass', 10, { x0: -500, x1: 60, z0: 320, z1: 780 }, (x, z, h) => B(x, z).rift * smoothstep(-200, -250, h), 110);
    this.scatterBy('veyruAlloy', 4, { x0: -500, x1: 60, z0: 320, z1: 780 }, (x, z, h) => B(x, z).rift * smoothstep(-200, -250, h), 111);
    this.scatterBy('titanite', 4, { x0: 250, x1: 560, z0: -80, z1: 80 }, (x, z) => B(x, z).canyon, 112);
    for (const s of structureSpots) {
      const node = this.add(s.type, s.pos.x, s.pos.z, s.floorY !== undefined ? s.floorY : undefined);
      node.fixed = true;
    }
    // meshes
    const types = [...new Set(this.nodes.map((n) => n.type))];
    for (const type of types) {
      const list = this.nodes.filter((n) => n.type === type);
      const def = nodeGeometry(type);
      const mat = waterMat({ vertexColors: true, roughness: type === 'titanite' ? 0.45 : 0.4, metalness: type === 'titanite' || type === 'ferrite' ? 0.4 : 0.1 },
        { glow: { color: def.glow, intensity: def.intensity, pulse: 1.8 } });
      const geo = def.geo.clone();
      const phases = new Float32Array(list.length);
      list.forEach((n, i) => { phases[i] = i * 0.17; n.index = i; n.radius = def.radius; });
      geo.setAttribute('aPhase', new THREE.InstancedBufferAttribute(phases, 1));
      const mesh = new THREE.InstancedMesh(geo, mat, list.length);
      mesh.name = `res_${type}`;
      this.byType[type] = { mesh, list };
      this.group.add(mesh);
      list.forEach((n) => this.updateMatrix(n));
      mesh.computeBoundingSphere();
      mesh.frustumCulled = false;
    }
  }

  updateMatrix(n) {
    const entry = this.byType[n.type];
    if (!entry) return;
    const m = new THREE.Matrix4();
    if (n.collected) m.makeScale(0, 0, 0);
    else {
      const q = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), n.rot);
      m.compose(n.pos, q, new THREE.Vector3(1.4, 1.4, 1.4));
    }
    entry.mesh.setMatrixAt(n.index, m);
    entry.mesh.instanceMatrix.needsUpdate = true;
  }

  collect(n, time) {
    n.collected = true;
    n.collectedAt = time;
    this.updateMatrix(n);
  }

  update(time) {
    // respawn common nodes slowly (never story/structure-specific ones)
    for (const n of this.nodes) {
      if (n.collected && !n.fixed && time - n.collectedAt > RESPAWN) {
        n.collected = false;
        this.updateMatrix(n);
      }
    }
  }

  nearest(p, maxDist, filter) {
    let best = null, bd = maxDist;
    for (const n of this.nodes) {
      if (n.collected) continue;
      if (filter && !filter(n)) continue;
      const d = n.pos.distanceTo(p);
      if (d < bd) { bd = d; best = n; }
    }
    return best;
  }

  serialize() {
    return this.nodes.filter((n) => n.collected).map((n) => [n.id, Math.round(n.collectedAt)]);
  }

  restore(list) {
    for (const n of this.nodes) { n.collected = false; }
    for (const [id, at] of list || []) {
      const n = this.nodes[id];
      if (n) { n.collected = true; n.collectedAt = at; }
    }
    for (const n of this.nodes) this.updateMatrix(n);
  }
}

export const RESOURCE_SITES = SITES;
