// Simple sphere-vs-world collision. Static colliders live in a spatial hash.
// Collider types:
//   sphere   { c: Vector3, r }
//   box      { c: Vector3, h: Vector3 (half extents), yaw }   (oriented about Y)
//   capsule  { a: Vector3, b: Vector3, r }
//   tube     { c, rIn, rOut, y0, y1 }  vertical hollow cylinder / disc with hole

import * as THREE from 'three';

const CELL = 24;
const _v = new THREE.Vector3();
const _l = new THREE.Vector3();
const _ab = new THREE.Vector3();

export class CollisionWorld {
  constructor(terrain) {
    this.terrain = terrain;
    this.cells = new Map();
    this.all = [];
    this.airPockets = []; // { min: Vector3, max: Vector3, level }
  }

  key(i, j) { return i * 73856093 ^ j * 19349663; }

  add(col) {
    col.bounds = this.boundsOf(col);
    this.all.push(col);
    const b = col.bounds;
    const i0 = Math.floor(b.minX / CELL), i1 = Math.floor(b.maxX / CELL);
    const j0 = Math.floor(b.minZ / CELL), j1 = Math.floor(b.maxZ / CELL);
    for (let i = i0; i <= i1; i++) {
      for (let j = j0; j <= j1; j++) {
        const k = this.key(i, j);
        let arr = this.cells.get(k);
        if (!arr) { arr = []; this.cells.set(k, arr); }
        arr.push(col);
      }
    }
    return col;
  }

  sphere(c, r, tag) { return this.add({ type: 'sphere', c: c.clone(), r, tag }); }
  box(c, h, yaw = 0, tag) { return this.add({ type: 'box', c: c.clone(), h: h.clone(), yaw, cos: Math.cos(yaw), sin: Math.sin(yaw), tag }); }
  capsule(a, b, r, tag) { return this.add({ type: 'capsule', a: a.clone(), b: b.clone(), r, tag }); }
  tube(c, rIn, rOut, y0, y1, tag) { return this.add({ type: 'tube', c: c.clone(), rIn, rOut, y0, y1, tag }); }

  boundsOf(col) {
    switch (col.type) {
      case 'sphere': return { minX: col.c.x - col.r, maxX: col.c.x + col.r, minZ: col.c.z - col.r, maxZ: col.c.z + col.r };
      case 'box': {
        const ext = Math.abs(col.h.x * col.cos) + Math.abs(col.h.z * col.sin);
        const ezt = Math.abs(col.h.x * col.sin) + Math.abs(col.h.z * col.cos);
        return { minX: col.c.x - ext, maxX: col.c.x + ext, minZ: col.c.z - ezt, maxZ: col.c.z + ezt };
      }
      case 'capsule': return {
        minX: Math.min(col.a.x, col.b.x) - col.r, maxX: Math.max(col.a.x, col.b.x) + col.r,
        minZ: Math.min(col.a.z, col.b.z) - col.r, maxZ: Math.max(col.a.z, col.b.z) + col.r,
      };
      case 'tube': return { minX: col.c.x - col.rOut, maxX: col.c.x + col.rOut, minZ: col.c.z - col.rOut, maxZ: col.c.z + col.rOut };
      default: return { minX: 0, maxX: 0, minZ: 0, maxZ: 0 };
    }
  }

  query(x, z, r, out) {
    out.length = 0;
    const i0 = Math.floor((x - r) / CELL), i1 = Math.floor((x + r) / CELL);
    const j0 = Math.floor((z - r) / CELL), j1 = Math.floor((z + r) / CELL);
    for (let i = i0; i <= i1; i++) {
      for (let j = j0; j <= j1; j++) {
        const arr = this.cells.get(this.key(i, j));
        if (!arr) continue;
        for (const c of arr) if (!out.includes(c)) out.push(c);
      }
    }
    return out;
  }

  /**
   * Push a sphere (center p, radius r) out of all geometry. Modifies p in place.
   * If vel is given, removes the velocity component into surfaces. Returns true on contact.
   */
  resolve(p, r, vel, skipTerrain = false) {
    let hit = false;
    const list = this.query(p.x, p.z, r + 1, this._tmp || (this._tmp = []));
    for (let iter = 0; iter < 3; iter++) {
      let any = false;
      for (const c of list) {
        if (this.pushOut(c, p, r, _v)) {
          any = true;
          hit = true;
          if (vel) {
            const n = _v.normalize();
            const vn = vel.dot(n);
            if (vn < 0) vel.addScaledVector(n, -vn);
          }
        }
      }
      if (!any) break;
    }
    if (!skipTerrain && this.terrain) {
      // push out along the surface normal so steep walls act as walls
      // (a purely vertical push would lift you up cliff faces)
      for (let k = 0; k < 4; k++) {
        const gh = this.terrain.heightAt(p.x, p.z);
        const pen = gh + r - p.y;
        if (pen <= 0) break;
        const n = this.terrain.normalAt(p.x, p.z);
        p.addScaledVector(n, pen * Math.max(n.y, 0.25));
        if (vel) {
          const vn = vel.dot(n);
          if (vn < 0) vel.addScaledVector(n, -vn);
        }
        hit = true;
      }
      const gh = this.terrain.heightAt(p.x, p.z);
      if (p.y < gh + r * 0.5) p.y = gh + r * 0.5; // never end up inside the seabed
    }
    return hit;
  }

  // Returns true and writes push vector into out if penetrating.
  pushOut(c, p, r, out) {
    switch (c.type) {
      case 'sphere': {
        out.subVectors(p, c.c);
        const d = out.length();
        const min = c.r + r;
        if (d >= min) return false;
        if (d < 1e-5) out.set(0, 1, 0); else out.divideScalar(d);
        out.multiplyScalar(min - d);
        p.add(out);
        return true;
      }
      case 'capsule': {
        _ab.subVectors(c.b, c.a);
        const t = Math.max(0, Math.min(1, _l.subVectors(p, c.a).dot(_ab) / _ab.lengthSq()));
        _l.copy(c.a).addScaledVector(_ab, t);
        out.subVectors(p, _l);
        const d = out.length();
        const min = c.r + r;
        if (d >= min) return false;
        if (d < 1e-5) out.set(0, 1, 0); else out.divideScalar(d);
        out.multiplyScalar(min - d);
        p.add(out);
        return true;
      }
      case 'box': {
        // to local
        const dx = p.x - c.c.x, dy = p.y - c.c.y, dz = p.z - c.c.z;
        const lx = dx * c.cos - dz * c.sin;
        const lz = dx * c.sin + dz * c.cos;
        const ly = dy;
        const qx = Math.max(-c.h.x, Math.min(c.h.x, lx));
        const qy = Math.max(-c.h.y, Math.min(c.h.y, ly));
        const qz = Math.max(-c.h.z, Math.min(c.h.z, lz));
        let ox = lx - qx, oy = ly - qy, oz = lz - qz;
        let d = Math.hypot(ox, oy, oz);
        let push;
        if (d > 1e-6) {
          if (d >= r) return false;
          push = (r - d) / d;
          ox *= push; oy *= push; oz *= push;
        } else {
          // center inside box: push out along the axis of least penetration
          const px = c.h.x - Math.abs(lx), py = c.h.y - Math.abs(ly), pz = c.h.z - Math.abs(lz);
          ox = oy = oz = 0;
          if (px <= py && px <= pz) ox = Math.sign(lx || 1) * (px + r);
          else if (py <= pz) oy = Math.sign(ly || 1) * (py + r);
          else oz = Math.sign(lz || 1) * (pz + r);
        }
        // back to world (inverse rotation)
        const wx = ox * c.cos + oz * c.sin;
        const wz = -ox * c.sin + oz * c.cos;
        out.set(wx, oy, wz);
        p.add(out);
        return true;
      }
      case 'tube': {
        const dx = p.x - c.c.x, dz = p.z - c.c.z;
        const rr = Math.hypot(dx, dz);
        const y0 = c.y0 - r, y1 = c.y1 + r;
        if (p.y < y0 || p.y > y1) return false;
        const rOut = c.rOut + r;
        const rIn = c.rIn > 0 ? c.rIn - r : -1;
        if (rr > rOut || rr < rIn) return false;
        const pushOutR = rOut - rr;
        const pushInR = rIn >= 0 ? rr - rIn : Infinity;
        const pushDown = p.y - y0;
        const pushUp = y1 - p.y;
        const m = Math.min(pushOutR, pushInR, pushDown, pushUp);
        const nx = rr > 1e-5 ? dx / rr : 1, nz = rr > 1e-5 ? dz / rr : 0;
        if (m === pushOutR) out.set(nx * m, 0, nz * m);
        else if (m === pushInR) out.set(-nx * m, 0, -nz * m);
        else if (m === pushDown) out.set(0, -m, 0);
        else out.set(0, m, 0);
        p.add(out);
        return true;
      }
      default: return false;
    }
  }

  addAirPocket(min, max, level) {
    this.airPockets.push({ min: min.clone(), max: max.clone(), level });
  }

  /** Water ceiling at a point: 0 for the open sea, or the level of an air pocket. */
  waterLevelAt(p) {
    for (const a of this.airPockets) {
      if (p.x > a.min.x && p.x < a.max.x && p.z > a.min.z && p.z < a.max.z && p.y > a.min.y && p.y < a.max.y) {
        return a.level;
      }
    }
    return 0;
  }

  /** Ray vs colliders (approximate, via marching spheres). Returns distance or -1. */
  raycastColliders(origin, dir, maxDist) {
    const p = new THREE.Vector3();
    const tmp = new THREE.Vector3();
    const list = [];
    for (let t = 0; t < maxDist; t += 0.5) {
      p.copy(origin).addScaledVector(dir, t);
      this.query(p.x, p.z, 1, list);
      for (const c of list) {
        tmp.copy(p);
        if (this.pushOut(c, tmp, 0.05, _v)) return t;
      }
    }
    return -1;
  }
}
