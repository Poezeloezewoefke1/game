// The ecosystem: schooling glimmerfin, drifting lanterns, grazing shellbacks,
// hunting razormaws, distant cantor leviathans, rare veil rays and the
// hollow stalkers of the deep. Each species exposes scan targets.

import * as THREE from 'three';
import { waterMat, patchMaterial } from '../world/shading.js';
import { fit } from '../world/assets.js';
import { surface } from '../world/surfaces.js';
import { SITES } from '../world/layout.js';
import { mulberry32, clamp } from '../core/noise.js';
import * as B from './bodies.js';
import * as S from './species.js';

const _v = new THREE.Vector3();
const _w = new THREE.Vector3();
const _m = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _s = new THREE.Vector3();
const UP = new THREE.Vector3(0, 1, 0);
const V = (x, y, z) => new THREE.Vector3(x, y, z);

function orientMatrix(out, pos, dir, scale) {
  _v.copy(pos).add(dir);
  out.lookAt(_v, pos, UP); // +z faces along dir
  out.scale(_s.set(scale, scale, scale));
  out.setPosition(pos);
  return out;
}

function keepInWater(terrain, p, v, clearance, dt, strength = 4) {
  const ahead = _w.copy(p).addScaledVector(v, 1.2);
  const gh = terrain.heightAt(ahead.x, ahead.z);
  const gh2 = terrain.heightAt(p.x, p.z);
  const floor = Math.max(gh, gh2) + clearance;
  if (ahead.y < floor) v.y += (floor - ahead.y) * strength * dt + 0.5 * dt;
  if (p.y < gh2 + 0.6) p.y = gh2 + 0.6;
  if (p.y > -2.5) v.y -= (p.y + 2.5) * 2 * dt;
}

// smooth heading with banking into turns (replaces snapping lookAt)
const _fq = new THREE.Quaternion();
const _rq = new THREE.Quaternion();
const _fm = new THREE.Matrix4();
const ZERO = new THREE.Vector3();
const ZAXIS = new THREE.Vector3(0, 0, 1);
function faceAlong(obj, st, vel, dt, rate = 5, bank = 0.3) {
  if (vel.lengthSq() < 1e-4 || dt <= 0) return;
  _fm.lookAt(vel, ZERO, UP); // +z along vel
  _fq.setFromRotationMatrix(_fm);
  const yaw = Math.atan2(vel.x, vel.z);
  if (st.yawPrev === undefined) { st.yawPrev = yaw; st.roll = 0; obj.quaternion.copy(_fq); }
  let dy = yaw - st.yawPrev;
  dy = Math.atan2(Math.sin(dy), Math.cos(dy));
  st.yawPrev = yaw;
  st.roll += (clamp((-dy / dt) * bank, -0.7, 0.7) - st.roll) * (1 - Math.exp(-dt * 3));
  _fq.multiply(_rq.setFromAxisAngle(ZAXIS, st.roll));
  obj.quaternion.slerp(_fq, 1 - Math.exp(-dt * rate));
}

/** Two-level LOD for a single creature: detailed close up, light far away. */
function lodMesh(hi, lo, mat, dist) {
  if (!lo) return new THREE.Mesh(hi, mat);
  const lod = new THREE.LOD();
  lod.addLevel(new THREE.Mesh(hi, mat), 0);
  lod.addLevel(new THREE.Mesh(lo, mat), dist);
  return lod;
}

function steerTo(v, desired, maxAccel, dt) {
  _w.subVectors(desired, v);
  const l = _w.length();
  const max = maxAccel * dt;
  if (l > max) _w.multiplyScalar(max / l);
  v.add(_w);
}

// ---------------------------------------------------------------- GLIMMERFIN
class FishSchools {
  constructor(scene, terrain, assets, classic = false) {
    this.terrain = terrain;
    const homes = [
      [40, -60, 70], [-90, 40, 70], [120, 90, 60], // shelf
      [-230, -20, 80], [-300, 90, 60], // kelp
      [10, 230, 90], [130, 300, 70], [-110, 330, 80], // coral
      [360, -40, 60], // canyon
    ];
    this.perSchool = 34;
    this.schools = homes.map(([x, z, r], i) => {
      const gh = terrain.heightAt(x, z);
      const center = V(x, Math.min(-6, gh + 8), z);
      const rnd = mulberry32(300 + i);
      const fish = [];
      for (let k = 0; k < this.perSchool; k++) {
        fish.push({ p: center.clone().add(V((rnd() - 0.5) * 8, (rnd() - 0.5) * 4, (rnd() - 0.5) * 8)), v: V(rnd() - 0.5, 0, rnd() - 0.5).multiplyScalar(2), s: 0.38 + rnd() * 0.18, ph: rnd() * 6.28 });
      }
      return { home: V(x, 0, z), radius: r, center, target: center.clone(), fish, rnd, active: true };
    });
    const total = this.schools.length * this.perSchool;
    const swim = { mode: 1, amp: 0.05, speed: 16, freq: 7, len: 1, head: 0.5 };
    const glow = { color: 0x7ff6ff, intensity: 2.4, pulse: 5 };
    let geo, mat;
    const ext = assets?.meshData('glimmerfin');
    if (ext) {
      // external photoreal fish, normalised to the procedural contract:
      // head toward +z, centred, 1 unit long (instances scale it to 0.38-0.56 m)
      geo = fit(ext.geometry, { forward: '+z', length: 1, pivot: 'center' });
      const pos = geo.attributes.position, nor = geo.attributes.normal;
      const glowArr = new Float32Array(pos.count);
      for (let i = 0; i < pos.count; i++) {
        // keep the species' bioluminescent lateral line
        const y = pos.getY(i), z = pos.getZ(i), side = Math.abs(nor.getX(i));
        glowArr[i] = side > 0.5 && z > -0.3 && z < 0.3 ? Math.max(0, 1 - Math.abs(y - 0.015) / 0.012) * 0.8 : 0;
      }
      geo.setAttribute('aGlow', new THREE.BufferAttribute(glowArr, 1));
      mat = ext.material.clone();
      mat.color.multiply(new THREE.Color(1.0, 1.12, 1.25)); // cooler, alien sheen
      mat.metalness = 0.3; // scales the model's metalness map: wet scales, not chrome
      mat.roughness = 0.5;
      mat.side = THREE.DoubleSide;
      patchMaterial(mat, { swim, glow: { ...glow, intensity: 1.4 }, reflect: 1.3 });
      this.external = true;
    } else {
      mat = waterMat({ vertexColors: true, roughness: 0.35, metalness: classic ? 0.5 : 0.3, side: THREE.DoubleSide }, { swim, glow, reflect: 1.3 });
      geo = classic ? B.glimmerfinGeometry() : S.glimmerfin();
    }
    this.total = total;
    const instanced = (g, m) => {
      g.setAttribute('aPhase', new THREE.InstancedBufferAttribute(new Float32Array(total), 1).setUsage(THREE.DynamicDrawUsage));
      const mesh = new THREE.InstancedMesh(g, m, total);
      mesh.frustumCulled = false;
      mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
      mesh.count = 0;
      scene.add(mesh);
      return mesh;
    };
    // near: the detailed fish; far (past NEAR_LOD m): a light procedural fish
    this.mesh = instanced(geo, mat);
    this.far = null;
    if (!classic) {
      const farMat = waterMat({ vertexColors: true, roughness: 0.4, metalness: 0.3, side: THREE.DoubleSide }, { swim, glow, reflect: 1.3 });
      this.far = instanced(S.glimmerfin({ lod: 1 }), farMat);
    }
  }

  update(dt, ctx) {
    const { playerPos, predators, isNight } = ctx;
    const NEAR_LOD = 18;
    const near = this.mesh, far = this.far;
    const nearPh = near.geometry.attributes.aPhase.array;
    const farPh = far ? far.geometry.attributes.aPhase.array : null;
    let ni = 0, fi = 0;
    for (const s of this.schools) {
      const dist = s.center.distanceTo(playerPos);
      s.active = dist < 230;
      if (!s.active) continue;
      // school target wanders around home; at night they all face the Abyss
      if (s.center.distanceTo(s.target) < 6 || Math.random() < 0.002) {
        const a = s.rnd() * Math.PI * 2, r = s.rnd() * s.radius;
        const tx = s.home.x + Math.cos(a) * r, tz = s.home.z + Math.sin(a) * r;
        const gh = this.terrain.heightAt(tx, tz);
        s.target.set(tx, clamp(gh + 4 + s.rnd() * 10, gh + 3, -5), tz);
      }
      // compute center & avg velocity
      const c = s.center.set(0, 0, 0);
      const avgV = new THREE.Vector3();
      for (const f of s.fish) { c.add(f.p); avgV.add(f.v); }
      c.divideScalar(s.fish.length);
      avgV.divideScalar(s.fish.length);
      const toTarget = s.target.clone().sub(c).normalize().multiplyScalar(2.6);
      const abyssDir = isNight ? V(SITES.abyss.x - c.x, 0, SITES.abyss.z - c.z).normalize() : null;
      for (const f of s.fish) {
        const desired = new THREE.Vector3().copy(toTarget);
        // cohesion
        desired.addScaledVector(_w.subVectors(c, f.p), 0.25);
        // alignment
        desired.addScaledVector(avgV, 0.4);
        // separation
        for (const o of s.fish) {
          if (o === f) continue;
          const dx = f.p.x - o.p.x, dy = f.p.y - o.p.y, dz = f.p.z - o.p.z;
          const d2 = dx * dx + dy * dy + dz * dz;
          if (d2 < 1.2 && d2 > 1e-4) {
            const k = (1.2 - d2) * 2.5;
            desired.x += dx * k; desired.y += dy * k; desired.z += dz * k;
          }
        }
        let speed = 3.2;
        // flee the diver
        const pd = f.p.distanceTo(playerPos);
        const fleeR = ctx.playerFast ? 11 : 6.5;
        if (pd < fleeR) {
          desired.addScaledVector(_w.subVectors(f.p, playerPos).normalize(), (fleeR - pd) * 2.2);
          speed = 7;
        }
        // flee predators
        for (const pr of predators) {
          const d = f.p.distanceTo(pr.p);
          if (d < 14) {
            desired.addScaledVector(_w.subVectors(f.p, pr.p).normalize(), (14 - d) * 1.5);
            speed = 8.5;
          }
        }
        if (abyssDir) desired.lerp(abyssDir.clone().multiplyScalar(2.2), 0.65);
        desired.clampLength(0, speed);
        steerTo(f.v, desired, 9, dt);
        keepInWater(this.terrain, f.p, f.v, 1.5, dt, 6);
        if (f.v.lengthSq() < 0.3) f.v.addScaledVector(toTarget, 0.1);
        f.p.addScaledVector(f.v, dt);
        orientMatrix(_m, f.p, f.v, f.s);
        if (!far || f.p.distanceTo(playerPos) < NEAR_LOD) { near.setMatrixAt(ni, _m); nearPh[ni++] = f.ph; } else { far.setMatrixAt(fi, _m); farPh[fi++] = f.ph; }
      }
    }
    near.count = ni;
    near.instanceMatrix.needsUpdate = true;
    near.geometry.attributes.aPhase.needsUpdate = true;
    if (far) {
      far.count = fi;
      far.instanceMatrix.needsUpdate = true;
      far.geometry.attributes.aPhase.needsUpdate = true;
    }
  }

  nearestFish(p, maxDist) {
    let best = null, bd = maxDist;
    for (const s of this.schools) {
      if (!s.active || s.center.distanceTo(p) > maxDist + 20) continue;
      for (const f of s.fish) {
        const d = f.p.distanceTo(p);
        if (d < bd) { bd = d; best = { fish: f, school: s }; }
      }
    }
    return best;
  }

  respawnFish(entry) {
    const s = entry.school;
    entry.fish.p.copy(s.center).add(V((Math.random() - 0.5) * 6, (Math.random() - 0.5) * 3, (Math.random() - 0.5) * 6));
  }

  scanTargets(p, out) {
    for (const s of this.schools) {
      if (!s.active || s.center.distanceTo(p) > 40) continue;
      for (const f of s.fish) if (f.p.distanceTo(p) < 30) out.push({ id: 'glimmerfin', pos: f.p, radius: 0.5 });
    }
  }
}

// ---------------------------------------------------------------- DRIFTERS
class Drifters {
  constructor(scene, terrain, classic = false) {
    this.terrain = terrain;
    const rnd = mulberry32(55);
    this.list = [];
    const areas = [[0, 0, 220, 30], [-250, 20, 160, 14], [30, 300, 220, 22], [350, 0, 150, 8]];
    for (const [x, z, r, n] of areas) {
      for (let i = 0; i < n; i++) {
        const a = rnd() * Math.PI * 2, d = 20 + rnd() * r;
        const px = x + Math.cos(a) * d, pz = z + Math.sin(a) * d;
        const gh = terrain.heightAt(px, pz);
        const y = clamp(gh + 6 + rnd() * 18, gh + 4, -4);
        this.list.push({ p: V(px, y, pz), base: y, v: V((rnd() - 0.5) * 0.4, 0, (rnd() - 0.5) * 0.4), s: 0.7 + rnd() * 0.9, ph: rnd() * 6.28, tilt: rnd() });
      }
    }
    const mat = waterMat({ vertexColors: true, transparent: true, opacity: 0.78, roughness: 0.2, side: THREE.DoubleSide, depthWrite: false },
      { swim: { mode: 3, amp: 0.16, speed: 1.6, freq: 1.4, len: 0.75 }, glow: { color: 0xa88cff, intensity: 1.1, pulse: 1.6 } });
    const count = this.list.length;
    const instanced = (geo) => {
      geo.setAttribute('aPhase', new THREE.InstancedBufferAttribute(new Float32Array(count), 1).setUsage(THREE.DynamicDrawUsage));
      const mesh = new THREE.InstancedMesh(geo, mat, count);
      mesh.frustumCulled = false;
      mesh.renderOrder = 2;
      mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
      scene.add(mesh);
      return mesh;
    };
    // detailed bell within NEAR_LOD m, light bell beyond
    this.mesh = instanced(classic ? B.drifterGeometry() : S.drifter());
    this.far = classic ? null : instanced(S.drifter({ lod: 1 }));
  }

  update(dt, ctx, t) {
    let ni = 0, fi = 0;
    this.list.forEach((d) => {
      const pd = d.p.distanceTo(ctx.playerPos);
      if (pd < 5) d.v.addScaledVector(_v.subVectors(d.p, ctx.playerPos).normalize(), dt * 0.6);
      d.v.multiplyScalar(1 - dt * 0.2);
      d.v.x += Math.sin(t * 0.1 + d.ph) * 0.02 * dt;
      d.v.z += Math.cos(t * 0.13 + d.ph) * 0.02 * dt;
      d.p.addScaledVector(d.v, dt);
      const pulse = Math.max(0, Math.sin(t * 1.6 + d.ph));
      d.p.y = d.base + Math.sin(t * 0.3 + d.ph) * 1.5 + pulse * 0.15;
      _q.setFromAxisAngle(_v.set(Math.cos(d.ph), 0, Math.sin(d.ph)), 0.15 * Math.sin(t * 0.4 + d.tilt * 6));
      _m.compose(d.p, _q, _s.set(d.s, d.s, d.s));
      const m = !this.far || pd < 35 ? this.mesh : this.far;
      const k = m === this.mesh ? ni++ : fi++;
      m.setMatrixAt(k, _m);
      m.geometry.attributes.aPhase.array[k] = d.ph;
    });
    for (const [m, c] of [[this.mesh, ni], [this.far, fi]]) {
      if (!m) continue;
      m.count = c;
      m.instanceMatrix.needsUpdate = true;
      m.geometry.attributes.aPhase.needsUpdate = true;
    }
  }

  scanTargets(p, out) {
    for (const d of this.list) if (d.p.distanceTo(p) < 30) out.push({ id: 'lanternDrifter', pos: d.p, radius: 1.2 * d.s, offsetY: 0.3 });
  }
}

// ---------------------------------------------------------------- SHELLBACKS
class Shellbacks {
  constructor(scene, terrain, classic = false) {
    this.terrain = terrain;
    this.classic = classic;
    const homes = [[30, 50], [-60, -40], [80, -90], [-30, 110], [150, 40], [-140, -90],
      [-40, 280], [90, 250], [20, 380], [-150, 360], [170, 330], [330, -20], [450, 30], [260, -60]];
    if (!classic) { this.buildDetailed(scene, terrain, homes); return; }
    const geo = B.shellbackGeometry();
    const mat = waterMat({ vertexColors: true, roughness: 0.7 }, { glow: { color: 0x66ffd0, intensity: 2.2, pulse: 0.8 }, detail: 0.9, surface: surface('coral', { space: 'object', scale: 3, strength: 0.9 }) });
    const headMat = waterMat({ color: 0x6d6250, roughness: 0.6 }, { surface: surface('hide', { scale: 6 }) });
    const legMat = waterMat({ color: 0x4a4036, roughness: 0.7 }, { surface: surface('hide', { scale: 8 }) });
    this.list = homes.map(([x, z], i) => {
      const g = new THREE.Group();
      const body = new THREE.Mesh(geo, mat);
      g.add(body);
      const head = new THREE.Mesh(new THREE.SphereGeometry(0.32, 12, 8).scale(1, 0.8, 1.2), headMat);
      head.position.set(0, 0.12, 1.15);
      g.add(head);
      const legs = [];
      for (let k = 0; k < 6; k++) {
        const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.05, 0.6, 5).translate(0, -0.3, 0), legMat);
        const side = k < 3 ? -1 : 1;
        leg.position.set(side * 0.7, 0.1, -0.6 + (k % 3) * 0.6);
        leg.rotation.z = side * 0.8;
        g.add(leg);
        legs.push(leg);
      }
      const s = 1.2 + (i % 4) * 0.3;
      g.scale.setScalar(s);
      const p = V(x, terrain.heightAt(x, z) + 0.3 * s, z);
      g.position.copy(p);
      scene.add(g);
      return { g, head, legs, home: V(x, 0, z), p, target: p.clone(), yaw: i, s, wait: 0, t: i };
    });
  }

  buildDetailed(scene, terrain, homes) {
    // one mesh per animal (shell + walking legs) plus the retractable head
    const bodyGeo = S.shellbackBody();
    const headGeo = S.shellbackHead();
    const headMat = waterMat({ vertexColors: true, roughness: 0.55 }, { surface: surface('hide', { space: 'object', scale: 6 }), reflect: 1.2 });
    this.list = homes.map(([x, z], i) => {
      const g = new THREE.Group();
      const mat = waterMat({ vertexColors: true, roughness: 0.62 }, {
        swim: { mode: 5, amp: 0.1, speed: 1, freq: 1, len: 1, phase: i },
        glow: { color: 0x66ffd0, intensity: 2.2, pulse: 0.8 }, detail: 0.6,
        surface: surface('coral', { space: 'object', scale: 3, strength: 0.75 }), reflect: 1.1,
      });
      g.add(new THREE.Mesh(bodyGeo, mat));
      const head = new THREE.Mesh(headGeo, headMat);
      head.position.set(0, 0.12, 1.02);
      g.add(head);
      const s = 1.2 + (i % 4) * 0.3;
      g.scale.setScalar(s);
      const p = V(x, terrain.heightAt(x, z) + 0.3 * s, z);
      g.position.copy(p);
      scene.add(g);
      return { g, head, legs: [], mat, home: V(x, 0, z), p, target: p.clone(), yaw: i, s, wait: 0, t: i };
    });
  }

  update(dt, ctx) {
    for (const c of this.list) {
      const pd = c.p.distanceTo(ctx.playerPos);
      c.g.visible = pd < 220;
      if (!c.g.visible) continue;
      const shy = pd < 4.5;
      c.head.scale.setScalar(THREE.MathUtils.lerp(c.head.scale.x, shy ? 0.4 : 1, dt * 4));
      c.head.position.z = (this.classic ? 1.15 : 1.02) * c.head.scale.x;
      if (shy) continue;
      if (c.wait > 0) { c.wait -= dt; continue; }
      const d = Math.hypot(c.target.x - c.p.x, c.target.z - c.p.z);
      if (d < 1) {
        c.wait = 2 + Math.random() * 6;
        const a = Math.random() * Math.PI * 2, r = Math.random() * 35;
        c.target.set(c.home.x + Math.cos(a) * r, 0, c.home.z + Math.sin(a) * r);
        continue;
      }
      const targetYaw = Math.atan2(c.target.x - c.p.x, c.target.z - c.p.z);
      let dy = targetYaw - c.yaw;
      dy = Math.atan2(Math.sin(dy), Math.cos(dy));
      c.yaw += clamp(dy, -0.5 * dt, 0.5 * dt);
      const sp = 0.55 * dt;
      c.p.x += Math.sin(c.yaw) * sp;
      c.p.z += Math.cos(c.yaw) * sp;
      c.p.y = this.terrain.heightAt(c.p.x, c.p.z) + 0.3 * c.s;
      c.t += dt * 3;
      c.legs.forEach((l, k) => { l.rotation.x = Math.sin(c.t + k * 1.7) * 0.4; });
      if (c.mat) c.mat.userData.swimPhase.value += dt * 6; // gait advances only while walking
      const n = this.terrain.normalAt(c.p.x, c.p.z, _v);
      _q.setFromUnitVectors(UP, n);
      c.g.quaternion.copy(_q).multiply(new THREE.Quaternion().setFromAxisAngle(UP, c.yaw));
      c.g.position.copy(c.p);
    }
  }

  scanTargets(p, out) {
    for (const c of this.list) if (c.p.distanceTo(p) < 30) out.push({ id: 'shellback', pos: c.p, radius: 1.3 * c.s, offsetY: 0.4 * c.s });
  }
}

// ---------------------------------------------------------------- RAZORMAW
class Razormaws {
  constructor(scene, terrain, classic = false) {
    this.terrain = terrain;
    const geo = classic ? B.razormawGeometry() : S.razormaw();
    const lo = classic ? null : S.razormaw({ lod: 1 });
    const homes = [[-150, 70], [70, 220], [-70, 400], [300, -40], [480, 30], [-330, -60]];
    this.list = homes.map(([x, z], i) => {
      const mat = waterMat({ vertexColors: true, roughness: 0.42, side: THREE.DoubleSide },
        { swim: { mode: 1, amp: 0.32, speed: 7, freq: 1.5, len: 4, head: 2, phase: i * 1.3 }, glow: { color: 0xffa040, intensity: 2.2, pulse: 3 }, surface: surface('scales', { scale: 2.6, strength: 0.8 }), reflect: 1.3 });
      const mesh = lodMesh(geo, lo, mat, 45);
      scene.add(mesh);
      const gh = terrain.heightAt(x, z);
      const p = V(x, gh + 8, z);
      return { mesh, mat, home: V(x, gh, z), p, v: V(1, 0, 0), state: 'patrol', timer: 0, target: p.clone(), cooldown: 0, prey: null, id: i };
    });
  }

  update(dt, ctx) {
    const { playerPos, inSub, fish } = ctx;
    for (const r of this.list) {
      const pd = r.p.distanceTo(playerPos);
      r.mesh.visible = pd < 260;
      if (pd > 300) continue;
      r.timer -= dt;
      r.cooldown -= dt;
      let desired = _v.set(0, 0, 0);
      let maxSpeed = 4;
      const homeD = Math.hypot(r.p.x - r.home.x, r.p.z - r.home.z);
      if (ctx.sonarScare && r.p.distanceTo(ctx.sonarOrigin) < 45) { r.state = 'retreat'; r.timer = 6; }
      if (r.state === 'patrol' || r.state === 'hunt') {
        // aggression: diver in territory
        if (!inSub && pd < 13 && r.cooldown <= 0 && homeD < 70 && ctx.playerDepth > 3) {
          r.state = 'charge';
          r.timer = 6;
          ctx.events.emit('threat', { kind: 'razormaw', pos: r.p });
        }
      }
      switch (r.state) {
        case 'patrol': {
          if (r.p.distanceTo(r.target) < 5 || r.timer < 0) {
            const a = Math.random() * Math.PI * 2, d = Math.random() * 45;
            const tx = r.home.x + Math.cos(a) * d, tz = r.home.z + Math.sin(a) * d;
            const gh = this.terrain.heightAt(tx, tz);
            r.target.set(tx, Math.min(-6, gh + 3 + Math.random() * 10), tz);
            r.timer = 12;
          }
          desired.subVectors(r.target, r.p).normalize().multiplyScalar(3.5);
          if (r.cooldown <= 0 && Math.random() < dt * 0.3) {
            const prey = fish.nearestFish(r.p, 30);
            if (prey) { r.prey = prey; r.state = 'hunt'; r.timer = 6; }
          }
          break;
        }
        case 'hunt': {
          if (!r.prey || r.timer < 0) { r.state = 'patrol'; break; }
          desired.subVectors(r.prey.fish.p, r.p).normalize().multiplyScalar(9.5);
          maxSpeed = 9.5;
          if (r.p.distanceTo(r.prey.fish.p) < 1.4) {
            fish.respawnFish(r.prey);
            r.prey = null;
            r.state = 'patrol';
            r.cooldown = 10;
            ctx.events.emit('predation', { pos: r.p.clone() });
          }
          break;
        }
        case 'charge': {
          if (inSub || r.timer < 0 || homeD > 90) { r.state = 'retreat'; r.timer = 4; break; }
          desired.subVectors(playerPos, r.p).normalize().multiplyScalar(10.5);
          maxSpeed = 10.5;
          if (pd < 2.2) {
            ctx.events.emit('attack', { kind: 'razormaw', damage: 16, pos: r.p.clone() });
            r.state = 'retreat';
            r.timer = 5;
            r.cooldown = 8;
          }
          break;
        }
        case 'retreat': {
          desired.subVectors(r.p, playerPos).normalize().multiplyScalar(8);
          desired.y += 0.5;
          maxSpeed = 8;
          if (r.timer < 0) r.state = 'patrol';
          break;
        }
        default: break;
      }
      desired.clampLength(0, maxSpeed);
      steerTo(r.v, desired, r.state === 'charge' ? 14 : 6, dt);
      keepInWater(this.terrain, r.p, r.v, 2, dt);
      r.p.addScaledVector(r.v, dt);
      // tail beat follows swimming speed (phase advance, so no jumps)
      r.mat.userData.swimPhase.value += dt * 7 * clamp(r.v.length() / 4 - 1, -0.6, 1.4);
      r.mesh.position.copy(r.p);
      faceAlong(r.mesh, r, r.v, dt, r.state === 'charge' ? 8 : 4, 0.25);
    }
  }

  get predators() { return this.list; }

  scanTargets(p, out) {
    for (const r of this.list) if (r.p.distanceTo(p) < 35) out.push({ id: 'razormaw', pos: r.p, radius: 1.6 });
  }
}

// ---------------------------------------------------------------- CANTORS
class Cantors {
  constructor(scene, terrain, classic = false) {
    this.terrain = terrain;
    const geo = classic ? B.cantorGeometry() : S.cantor();
    this.list = [
      { cx: SITES.abyss.x, cz: SITES.abyss.z, r: 330, y: -175, speed: 7, ang: 0.4, dir: 1 },
      { cx: -60, cz: 420, r: 300, y: -125, speed: 6, ang: 2.6, dir: -1 },
    ].map((c, i) => {
      const mat = waterMat({ vertexColors: true, roughness: 0.5, side: THREE.DoubleSide },
        { swim: { mode: classic ? 1 : 6, amp: classic ? 2.4 : 2.0, speed: 0.9, freq: 0.05, len: 100, head: 50, phase: i * 2 }, glow: { color: 0x8ff4ff, intensity: 3.2, pulse: 0.5 }, fogScale: 0.6, surface: surface('hide', { scale: 0.09, strength: 0.9 }), reflect: 1.2 });
      const mesh = new THREE.Mesh(geo, mat);
      mesh.frustumCulled = false;
      scene.add(mesh);
      return { ...c, mesh, p: V(), callTimer: 10 + i * 17, gather: null };
    });
  }

  update(dt, ctx, t) {
    for (const c of this.list) {
      let tx, ty, tz;
      if (c.gather) {
        // final: circle the Threshold
        c.ang += (c.dir * c.speed * 0.6 * dt) / 120;
        tx = c.gather.x + Math.cos(c.ang) * 120;
        tz = c.gather.z + Math.sin(c.ang) * 120;
        ty = c.gather.y + Math.sin(t * 0.1 + c.r) * 20;
      } else {
        c.ang += (c.dir * c.speed * dt) / c.r;
        tx = c.cx + Math.cos(c.ang) * c.r;
        tz = c.cz + Math.sin(c.ang) * c.r;
        ty = c.y + Math.sin(c.ang * 3) * 25;
        ty = Math.max(ty, this.terrain.heightAt(tx, tz) + 30);
        ty = Math.min(ty, -25);
      }
      const prev = c.p.clone();
      if (c.p.lengthSq() === 0) prev.set(tx - 1, ty, tz);
      c.p.set(tx, c.p.lengthSq() === 0 ? ty : THREE.MathUtils.lerp(c.p.y, ty, dt * 0.3), tz);
      _v.subVectors(c.p, prev);
      if (_v.lengthSq() > 1e-6) {
        c.mesh.position.copy(c.p);
        c.mesh.lookAt(_v.add(c.p));
      }
      c.callTimer -= dt;
      if (c.callTimer < 0) {
        c.callTimer = 25 + Math.random() * 40;
        ctx.events.emit('cantorCall', { pos: c.p.clone(), dist: c.p.distanceTo(ctx.playerPos) });
      }
    }
  }

  gatherAt(p) { for (const c of this.list) c.gather = p.clone(); }

  scanTargets(p, out) {
    for (const c of this.list) {
      // the body is huge — accept scans on any point along it
      for (let k = -2; k <= 2; k++) {
        const q = new THREE.Vector3(0, 0, k * 20).applyQuaternion(c.mesh.quaternion).add(c.p);
        if (q.distanceTo(p) < 140) out.push({ id: 'cantor', pos: q, radius: 9 });
      }
    }
  }
}

// ---------------------------------------------------------------- VEIL RAYS
class VeilRays {
  constructor(scene, terrain, caveCenter, classic = false) {
    this.terrain = terrain;
    const geo = classic ? B.veilRayGeometry() : S.veilRay();
    const make = (center, r, y, nightOnly, i) => {
      const mat = waterMat({ vertexColors: true, transparent: true, opacity: 0.7, side: THREE.DoubleSide, roughness: 0.3, depthWrite: false },
        { swim: { mode: 2, amp: 0.22, speed: 2.4, freq: 0.6, len: 1, phase: i }, glow: { color: 0x9fe8ff, intensity: 2.8, pulse: 1.2 } });
      const mesh = new THREE.Mesh(geo, mat);
      mesh.scale.setScalar(1.3);
      mesh.renderOrder = 2;
      scene.add(mesh);
      return { mesh, center, r, y, nightOnly, ang: i * 2, p: center.clone(), v: V(), flee: 0, visible: true };
    };
    this.list = [
      make(caveCenter.clone(), 5.5, caveCenter.y + 1, false, 0),
      make(V(SITES.kelp.x, 0, SITES.kelp.z), 40, -26, true, 1),
    ];
  }

  update(dt, ctx, t) {
    for (const r of this.list) {
      r.visible = !r.nightOnly || ctx.isNight;
      r.mesh.visible = r.visible && r.p.distanceTo(ctx.playerPos) < 200;
      if (!r.visible) continue;
      const pd = r.p.distanceTo(ctx.playerPos);
      if ((pd < 5 || (ctx.playerFast && pd < 12)) && r.flee <= 0) r.flee = 4;
      const prev = r.p.clone();
      if (r.flee > 0) {
        r.flee -= dt;
        _v.subVectors(r.p, ctx.playerPos).normalize();
        r.p.addScaledVector(_v, dt * 6);
        keepInWater(this.terrain, r.p, new THREE.Vector3(), 1, dt);
      } else {
        r.ang += dt * 0.35;
        const tx = r.center.x + Math.cos(r.ang) * r.r, tz = r.center.z + Math.sin(r.ang) * r.r;
        const ty = r.y + Math.sin(t * 0.5) * 1.2;
        r.p.lerp(_v.set(tx, ty, tz), dt * 0.8);
      }
      r.mesh.position.copy(r.p);
      if (dt > 0) faceAlong(r.mesh, r, _v.subVectors(r.p, prev).divideScalar(dt), dt, 3, 0.35);
    }
  }

  scanTargets(p, out) {
    for (const r of this.list) if (r.visible && r.p.distanceTo(p) < 30) out.push({ id: 'veilRay', pos: r.p, radius: 1.6 });
  }
}

// ---------------------------------------------------------------- HOLLOW STALKERS
class Stalkers {
  constructor(scene, terrain, classic = false) {
    this.terrain = terrain;
    const geo = classic ? B.stalkerGeometry() : S.stalker();
    const lo = classic ? null : S.stalker({ lod: 1 });
    const homes = [
      [-380, 410, -240], [-220, 560, -245], [-60, 660, -250],
      [SITES.abyss.x + 60, SITES.abyss.z - 40, -420], [SITES.abyss.x - 70, SITES.abyss.z + 50, -520], [SITES.abyss.x, SITES.abyss.z, -590],
    ];
    this.list = homes.map(([x, z, y], i) => {
      const mat = waterMat({ vertexColors: true, roughness: 0.35, side: THREE.DoubleSide },
        { swim: { mode: 1, amp: 0.55, speed: 4.5, freq: 0.7, len: 8, head: 4, phase: i }, glow: { color: 0xff6a4a, intensity: 3, pulse: 1.1 }, surface: surface('stone', { space: 'object', scale: 0.9, strength: 0.9 }), reflect: 1.4 });
      const mesh = lodMesh(geo, lo, mat, 55);
      scene.add(mesh);
      return { mesh, mat, home: V(x, y, z), p: V(x + 10, y, z), v: V(1, 0, 0), target: V(x, y, z), state: 'patrol', timer: 0, cooldown: 0 };
    });
  }

  update(dt, ctx) {
    const { playerPos, inSub, lampOn } = ctx;
    for (const s of this.list) {
      const pd = s.p.distanceTo(playerPos);
      s.mesh.visible = pd < 260;
      if (pd > 320) continue;
      s.timer -= dt;
      s.cooldown -= dt;
      if (ctx.sonarScare && s.p.distanceTo(ctx.sonarOrigin) < 70 && s.state !== 'flee') {
        s.state = 'flee';
        s.timer = 9;
        ctx.events.emit('stalkerScared', { pos: s.p.clone() });
      }
      const attracted = inSub || lampOn;
      const detect = attracted ? 38 : 16;
      if (s.state === 'patrol' && pd < detect && s.cooldown <= 0 && playerPos.y < -150) {
        s.state = 'stalk';
        s.timer = 14;
        ctx.events.emit('threat', { kind: 'stalker', pos: s.p });
      }
      const desired = _v.set(0, 0, 0);
      let maxSpeed = 4, accel = 5;
      switch (s.state) {
        case 'patrol':
          if (s.p.distanceTo(s.target) < 6 || s.timer < 0) {
            const a = Math.random() * Math.PI * 2, d = 20 + Math.random() * 60;
            s.target.set(s.home.x + Math.cos(a) * d, s.home.y + (Math.random() - 0.5) * 30, s.home.z + Math.sin(a) * d);
            s.timer = 15;
          }
          desired.subVectors(s.target, s.p).normalize().multiplyScalar(4);
          break;
        case 'stalk':
          desired.subVectors(playerPos, s.p).normalize().multiplyScalar(pd > 14 ? 7 : 12);
          maxSpeed = 12; accel = 9;
          if (pd < (inSub ? 4.5 : 2.6)) {
            ctx.events.emit('attack', { kind: 'stalker', damage: inSub ? 14 : 24, pos: s.p.clone(), sub: inSub });
            s.state = 'flee';
            s.timer = 7;
            s.cooldown = 10;
          }
          if (s.timer < 0) { s.state = 'patrol'; s.cooldown = 5; }
          break;
        case 'flee':
          desired.subVectors(s.p, playerPos).normalize().multiplyScalar(10);
          maxSpeed = 10; accel = 10;
          if (s.timer < 0) s.state = 'patrol';
          break;
        default: break;
      }
      desired.clampLength(0, maxSpeed);
      steerTo(s.v, desired, accel, dt);
      keepInWater(this.terrain, s.p, s.v, 4, dt);
      s.p.addScaledVector(s.v, dt);
      s.mat.userData.swimPhase.value += dt * 4.5 * clamp(s.v.length() / 4 - 1, -0.6, 1.5);
      s.mesh.position.copy(s.p);
      faceAlong(s.mesh, s, s.v, dt, s.state === 'stalk' ? 6 : 3, 0.2);
    }
  }

  scanTargets(p, out) {
    for (const s of this.list) if (s.p.distanceTo(p) < 45) out.push({ id: 'hollowStalker', pos: s.p, radius: 2.2 });
  }
}

// ---------------------------------------------------------------- EMBER SHRIMP (The Forge)
class EmberShrimp {
  constructor(scene, terrain, plumes) {
    this.terrain = terrain;
    this.list = [];
    const rnd = mulberry32(808);
    (plumes || []).forEach((pl, ci) => {
      const base = pl.pos.clone();
      for (let k = 0; k < 26; k++) {
        this.list.push({
          home: base, ci,
          ang: rnd() * Math.PI * 2, rad: 1.2 + rnd() * 3, hgt: -0.5 - rnd() * 7,
          spd: (0.35 + rnd() * 0.5) * (rnd() < 0.5 ? -1 : 1), ph: rnd() * 6.28,
          p: base.clone(), v: V(), s: 0.12 + rnd() * 0.07, flee: 0,
        });
      }
    });
    this.count = this.list.length;
    if (!this.count) return;
    const geo = S.emberShrimp();
    geo.setAttribute('aPhase', new THREE.InstancedBufferAttribute(new Float32Array(this.list.map((s) => s.ph)), 1));
    const mat = waterMat({ vertexColors: true, roughness: 0.35, transparent: true, opacity: 0.88, side: THREE.DoubleSide },
      { swim: { mode: 1, amp: 0.05, speed: 14, freq: 6, len: 1, head: 0.5 }, glow: { color: 0xff7a30, intensity: 2.4, pulse: 3 }, reflect: 1.2 });
    this.mesh = new THREE.InstancedMesh(geo, mat, this.count);
    this.mesh.frustumCulled = false;
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    scene.add(this.mesh);
    this.center = (plumes[0] && plumes[0].pos.clone()) || V();
  }

  update(dt, ctx, t) {
    if (!this.count) return;
    const near = this.center.distanceTo(ctx.playerPos) < 140;
    this.mesh.visible = near;
    if (!near) return;
    this.list.forEach((s, i) => {
      // orbit the chimney in the warm water, darting and bobbing
      s.ang += dt * s.spd * (1 + 0.6 * Math.sin(t * 2.3 + s.ph));
      const target = _v.set(s.home.x + Math.cos(s.ang) * s.rad, s.home.y + s.hgt + Math.sin(t * 0.9 + s.ph) * 0.6, s.home.z + Math.sin(s.ang) * s.rad);
      const pd = s.p.distanceTo(ctx.playerPos);
      if (pd < 2.4 || (ctx.lampOn && pd < 4)) s.flee = 1.2;
      if (s.flee > 0) {
        s.flee -= dt;
        target.copy(s.p).addScaledVector(_w.subVectors(s.p, ctx.playerPos).normalize(), 3);
      }
      const desired = target.sub(s.p).multiplyScalar(2.2).clampLength(0, s.flee > 0 ? 3.5 : 1.4);
      steerTo(s.v, desired, s.flee > 0 ? 18 : 5, dt);
      s.p.addScaledVector(s.v, dt);
      const gh = this.terrain.heightAt(s.p.x, s.p.z);
      if (s.p.y < gh + 0.3) s.p.y = gh + 0.3;
      orientMatrix(_m, s.p, s.v.lengthSq() > 1e-4 ? s.v : _w.set(Math.cos(s.ang), 0, Math.sin(s.ang)), s.s);
      this.mesh.setMatrixAt(i, _m);
    });
    this.mesh.instanceMatrix.needsUpdate = true;
  }

  scanTargets(p, out) {
    if (!this.count || this.center.distanceTo(p) > 60) return;
    for (const s of this.list) if (s.p.distanceTo(p) < 12) out.push({ id: 'emberShrimp', pos: s.p, radius: 0.35 });
  }
}

export class Creatures {
  constructor(scene, terrain, caveCenter, events, assets = null, { classic = false, ventPlumes = [] } = {}) {
    this.events = events;
    this.fish = new FishSchools(scene, terrain, assets, classic);
    this.drifters = new Drifters(scene, terrain, classic);
    this.shellbacks = new Shellbacks(scene, terrain, classic);
    this.razormaws = new Razormaws(scene, terrain, classic);
    this.cantors = new Cantors(scene, terrain, classic);
    this.veilRays = new VeilRays(scene, terrain, caveCenter, classic);
    this.stalkers = new Stalkers(scene, terrain, classic);
    this.shrimp = new EmberShrimp(scene, terrain, ventPlumes);
    this.time = 0;
  }

  update(dt, ctx) {
    this.time += dt;
    const c = { ...ctx, events: this.events, fish: this.fish, predators: this.razormaws.predators };
    this.fish.update(dt, c);
    this.drifters.update(dt, c, this.time);
    this.shellbacks.update(dt, c);
    this.razormaws.update(dt, c);
    this.cantors.update(dt, c, this.time);
    this.veilRays.update(dt, c, this.time);
    this.stalkers.update(dt, c);
    this.shrimp.update(dt, c, this.time);
  }

  scanTargets(p) {
    const out = [];
    this.fish.scanTargets(p, out);
    this.drifters.scanTargets(p, out);
    this.shellbacks.scanTargets(p, out);
    this.razormaws.scanTargets(p, out);
    this.cantors.scanTargets(p, out);
    this.veilRays.scanTargets(p, out);
    this.stalkers.scanTargets(p, out);
    this.shrimp.scanTargets(p, out);
    return out;
  }
}
