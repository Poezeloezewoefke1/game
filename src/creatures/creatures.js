// The ecosystem: schooling glimmerfin, drifting lanterns, grazing shellbacks,
// hunting razormaws, distant cantor leviathans, rare veil rays and the
// hollow stalkers of the deep. Each species exposes scan targets.

import * as THREE from 'three';
import { waterMat } from '../world/shading.js';
import { SITES } from '../world/layout.js';
import { mulberry32, clamp } from '../core/noise.js';
import * as B from './bodies.js';

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

function steerTo(v, desired, maxAccel, dt) {
  _w.subVectors(desired, v);
  const l = _w.length();
  const max = maxAccel * dt;
  if (l > max) _w.multiplyScalar(max / l);
  v.add(_w);
}

// ---------------------------------------------------------------- GLIMMERFIN
class FishSchools {
  constructor(scene, terrain) {
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
        fish.push({ p: center.clone().add(V((rnd() - 0.5) * 8, (rnd() - 0.5) * 4, (rnd() - 0.5) * 8)), v: V(rnd() - 0.5, 0, rnd() - 0.5).multiplyScalar(2), s: 0.38 + rnd() * 0.18 });
      }
      return { home: V(x, 0, z), radius: r, center, target: center.clone(), fish, rnd, active: true };
    });
    const total = this.schools.length * this.perSchool;
    const mat = waterMat({ vertexColors: true, roughness: 0.35, metalness: 0.5, side: THREE.DoubleSide },
      { swim: { mode: 1, amp: 0.05, speed: 16, freq: 7, len: 1, head: 0.5 }, glow: { color: 0x7ff6ff, intensity: 2.4, pulse: 5 } });
    const geo = B.glimmerfinGeometry();
    const phases = new Float32Array(total);
    for (let i = 0; i < total; i++) phases[i] = Math.random() * 6.28;
    geo.setAttribute('aPhase', new THREE.InstancedBufferAttribute(phases, 1));
    this.mesh = new THREE.InstancedMesh(geo, mat, total);
    this.mesh.frustumCulled = false;
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    scene.add(this.mesh);
  }

  update(dt, ctx) {
    const { playerPos, predators, isNight } = ctx;
    let idx = 0;
    for (const s of this.schools) {
      const dist = s.center.distanceTo(playerPos);
      s.active = dist < 230;
      if (!s.active) {
        for (let k = 0; k < s.fish.length; k++) { _m.makeScale(0, 0, 0); this.mesh.setMatrixAt(idx++, _m); }
        continue;
      }
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
        this.mesh.setMatrixAt(idx++, _m);
      }
    }
    this.mesh.instanceMatrix.needsUpdate = true;
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
  constructor(scene, terrain) {
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
    const geo = B.drifterGeometry();
    const phases = new Float32Array(this.list.length);
    this.list.forEach((d, i) => { phases[i] = d.ph; });
    geo.setAttribute('aPhase', new THREE.InstancedBufferAttribute(phases, 1));
    const mat = waterMat({ vertexColors: true, transparent: true, opacity: 0.78, roughness: 0.2, side: THREE.DoubleSide, depthWrite: false },
      { swim: { mode: 3, amp: 0.16, speed: 1.6, freq: 1.4, len: 0.75 }, glow: { color: 0xa88cff, intensity: 1.1, pulse: 1.6 } });
    this.mesh = new THREE.InstancedMesh(geo, mat, this.list.length);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 2;
    scene.add(this.mesh);
  }

  update(dt, ctx, t) {
    this.list.forEach((d, i) => {
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
      this.mesh.setMatrixAt(i, _m);
    });
    this.mesh.instanceMatrix.needsUpdate = true;
  }

  scanTargets(p, out) {
    for (const d of this.list) if (d.p.distanceTo(p) < 30) out.push({ id: 'lanternDrifter', pos: d.p, radius: 1.2 * d.s, offsetY: 0.3 });
  }
}

// ---------------------------------------------------------------- SHELLBACKS
class Shellbacks {
  constructor(scene, terrain) {
    this.terrain = terrain;
    const homes = [[30, 50], [-60, -40], [80, -90], [-30, 110], [150, 40], [-140, -90],
      [-40, 280], [90, 250], [20, 380], [-150, 360], [170, 330], [330, -20], [450, 30], [260, -60]];
    const geo = B.shellbackGeometry();
    const mat = waterMat({ vertexColors: true, roughness: 0.8 }, { glow: { color: 0x66ffd0, intensity: 2.2, pulse: 0.8 }, detail: 0.9 });
    const headMat = waterMat({ color: 0x6d6250, roughness: 0.8 });
    const legMat = waterMat({ color: 0x4a4036, roughness: 0.9 });
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

  update(dt, ctx) {
    for (const c of this.list) {
      const pd = c.p.distanceTo(ctx.playerPos);
      c.g.visible = pd < 220;
      if (!c.g.visible) continue;
      const shy = pd < 4.5;
      c.head.scale.setScalar(THREE.MathUtils.lerp(c.head.scale.x, shy ? 0.4 : 1, dt * 4));
      c.head.position.z = 1.15 * c.head.scale.x;
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
  constructor(scene, terrain) {
    this.terrain = terrain;
    const geo = B.razormawGeometry();
    const homes = [[-150, 70], [70, 220], [-70, 400], [300, -40], [480, 30], [-330, -60]];
    this.list = homes.map(([x, z], i) => {
      const mat = waterMat({ vertexColors: true, roughness: 0.5, side: THREE.DoubleSide },
        { swim: { mode: 1, amp: 0.32, speed: 7, freq: 1.5, len: 4, head: 2, phase: i * 1.3 }, glow: { color: 0xffa040, intensity: 2.2, pulse: 3 } });
      const mesh = new THREE.Mesh(geo, mat);
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
      if (r.v.lengthSq() > 0.01) {
        _v.copy(r.p).add(r.v);
        r.mesh.position.copy(r.p);
        r.mesh.lookAt(_v);
      }
    }
  }

  get predators() { return this.list; }

  scanTargets(p, out) {
    for (const r of this.list) if (r.p.distanceTo(p) < 35) out.push({ id: 'razormaw', pos: r.p, radius: 1.6 });
  }
}

// ---------------------------------------------------------------- CANTORS
class Cantors {
  constructor(scene, terrain) {
    this.terrain = terrain;
    const geo = B.cantorGeometry();
    this.list = [
      { cx: SITES.abyss.x, cz: SITES.abyss.z, r: 330, y: -175, speed: 7, ang: 0.4, dir: 1 },
      { cx: -60, cz: 420, r: 300, y: -125, speed: 6, ang: 2.6, dir: -1 },
    ].map((c, i) => {
      const mat = waterMat({ vertexColors: true, roughness: 0.6, side: THREE.DoubleSide },
        { swim: { mode: 1, amp: 2.4, speed: 0.9, freq: 0.05, len: 100, head: 50, phase: i * 2 }, glow: { color: 0x8ff4ff, intensity: 3.2, pulse: 0.5 }, fogScale: 0.6 });
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
  constructor(scene, terrain, caveCenter) {
    this.terrain = terrain;
    const geo = B.veilRayGeometry();
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
      _v.subVectors(r.p, prev);
      if (_v.lengthSq() > 1e-6) {
        r.mesh.position.copy(r.p);
        r.mesh.lookAt(_v.add(r.p));
      }
    }
  }

  scanTargets(p, out) {
    for (const r of this.list) if (r.visible && r.p.distanceTo(p) < 30) out.push({ id: 'veilRay', pos: r.p, radius: 1.6 });
  }
}

// ---------------------------------------------------------------- HOLLOW STALKERS
class Stalkers {
  constructor(scene, terrain) {
    this.terrain = terrain;
    const geo = B.stalkerGeometry();
    const homes = [
      [-380, 410, -240], [-220, 560, -245], [-60, 660, -250],
      [SITES.abyss.x + 60, SITES.abyss.z - 40, -420], [SITES.abyss.x - 70, SITES.abyss.z + 50, -520], [SITES.abyss.x, SITES.abyss.z, -590],
    ];
    this.list = homes.map(([x, z, y], i) => {
      const mat = waterMat({ vertexColors: true, roughness: 0.4, side: THREE.DoubleSide },
        { swim: { mode: 1, amp: 0.55, speed: 4.5, freq: 0.7, len: 8, head: 4, phase: i }, glow: { color: 0xff6a4a, intensity: 3, pulse: 1.1 } });
      const mesh = new THREE.Mesh(geo, mat);
      scene.add(mesh);
      return { mesh, home: V(x, y, z), p: V(x + 10, y, z), v: V(1, 0, 0), target: V(x, y, z), state: 'patrol', timer: 0, cooldown: 0 };
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
      if (s.v.lengthSq() > 0.01) {
        s.mesh.position.copy(s.p);
        s.mesh.lookAt(_w.copy(s.p).add(s.v));
      }
    }
  }

  scanTargets(p, out) {
    for (const s of this.list) if (s.p.distanceTo(p) < 45) out.push({ id: 'hollowStalker', pos: s.p, radius: 2.2 });
  }
}

export class Creatures {
  constructor(scene, terrain, caveCenter, events) {
    this.events = events;
    this.fish = new FishSchools(scene, terrain);
    this.drifters = new Drifters(scene, terrain);
    this.shellbacks = new Shellbacks(scene, terrain);
    this.razormaws = new Razormaws(scene, terrain);
    this.cantors = new Cantors(scene, terrain);
    this.veilRays = new VeilRays(scene, terrain, caveCenter);
    this.stalkers = new Stalkers(scene, terrain);
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
    return out;
  }
}
