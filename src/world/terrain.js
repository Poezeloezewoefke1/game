// Heightfield terrain: sampled once into a grid, then built as culled chunks.
// heightAt()/normalAt() are fast bilinear lookups used by physics and AI.

import * as THREE from 'three';
import { rawHeight, biomeWeights, WORLD_HALF } from './layout.js';
import { waterMat } from './shading.js';
import { surface } from './surfaces.js';
import { clamp, lerp, smoothstep } from '../core/noise.js';

const SPACING = 3;
const CELLS = Math.round((WORLD_HALF * 2) / SPACING); // 600
const N = CELLS + 1;
const CHUNK = 50; // cells per chunk side

const tmpN = new THREE.Vector3();

export class Terrain {
  constructor() {
    this.heights = new Float32Array(N * N);
    this.group = new THREE.Group();
    this.group.name = 'terrain';
    this.ready = false;
  }

  async generate(onProgress) {
    const H = this.heights;
    for (let j = 0; j < N; j++) {
      const z = -WORLD_HALF + j * SPACING;
      for (let i = 0; i < N; i++) {
        H[j * N + i] = rawHeight(-WORLD_HALF + i * SPACING, z);
      }
      if (j % 24 === 0) {
        onProgress?.(j / N);
        await new Promise((r) => setTimeout(r, 0));
      }
    }
    onProgress?.(1);
  }

  h(i, j) {
    i = i < 0 ? 0 : i >= N ? N - 1 : i;
    j = j < 0 ? 0 : j >= N ? N - 1 : j;
    return this.heights[j * N + i];
  }

  heightAt(x, z) {
    const fx = (x + WORLD_HALF) / SPACING;
    const fz = (z + WORLD_HALF) / SPACING;
    const i = Math.floor(fx), j = Math.floor(fz);
    const tx = fx - i, tz = fz - j;
    // match the triangle split used by the mesh (diagonal from (i,j) to (i+1,j+1))
    const h00 = this.h(i, j), h10 = this.h(i + 1, j), h01 = this.h(i, j + 1), h11 = this.h(i + 1, j + 1);
    if (tx > tz) return h00 + (h10 - h00) * tx + (h11 - h10) * tz;
    return h00 + (h11 - h01) * tx + (h01 - h00) * tz;
  }

  normalAt(x, z, out = tmpN) {
    const e = SPACING;
    const hl = this.heightAt(x - e, z), hr = this.heightAt(x + e, z);
    const hd = this.heightAt(x, z - e), hu = this.heightAt(x, z + e);
    return out.set(hl - hr, 2 * e, hd - hu).normalize();
  }

  colorFor(x, z, h, ny, out) {
    const b = biomeWeights(x, z);
    const rockiness = smoothstep(0.86, 0.62, ny);
    const n = Math.sin(x * 0.07 + Math.cos(z * 0.05) * 2) * 0.5 + 0.5;
    // base sand
    let r = 0.6, g = 0.56, bl = 0.46;
    // kelp silt
    r = lerp(r, 0.36, b.kelp * 0.8); g = lerp(g, 0.42, b.kelp * 0.8); bl = lerp(bl, 0.30, b.kelp * 0.8);
    // coral pink sand
    r = lerp(r, 0.78, b.coral * 0.7); g = lerp(g, 0.56, b.coral * 0.7); bl = lerp(bl, 0.52, b.coral * 0.7);
    // depth darkening for plains
    const deep = smoothstep(-60, -140, h);
    r = lerp(r, 0.42, deep * 0.6); g = lerp(g, 0.44, deep * 0.6); bl = lerp(bl, 0.46, deep * 0.6);
    // rock
    let rr = 0.34 + n * 0.08, rg = 0.34 + n * 0.06, rb = 0.36;
    rr = lerp(rr, 0.52, b.canyon); rg = lerp(rg, 0.34, b.canyon); rb = lerp(rb, 0.26, b.canyon);
    rr = lerp(rr, 0.55, b.coral * 0.5); rg = lerp(rg, 0.36, b.coral * 0.5); rb = lerp(rb, 0.40, b.coral * 0.5);
    r = lerp(r, rr, rockiness); g = lerp(g, rg, rockiness); bl = lerp(bl, rb, rockiness);
    // rift basalt
    const rift = b.rift * smoothstep(-150, -240, h);
    r = lerp(r, 0.20, rift); g = lerp(g, 0.19, rift); bl = lerp(bl, 0.26, rift);
    // abyss obsidian with faint violet
    const ab = b.abyss * smoothstep(-200, -400, h);
    r = lerp(r, 0.13, ab); g = lerp(g, 0.11, ab); bl = lerp(bl, 0.19, ab);
    out[0] = clamp(r, 0, 1); out[1] = clamp(g, 0, 1); out[2] = clamp(bl, 0, 1);
  }

  build(noiseTex) {
    this.material = waterMat({ vertexColors: true, roughness: 0.92 }, { detail: 0.11, surface: surface('seabed'), reflect: 0.6 });
    // the detail sampler is shared through U.uNoiseTex; terrain needs it bound
    this.material.userData.noise = noiseTex;
    const chunksPerSide = CELLS / CHUNK;
    const col = [0, 0, 0];
    for (let cj = 0; cj < chunksPerSide; cj++) {
      for (let ci = 0; ci < chunksPerSide; ci++) {
        const vs = CHUNK + 1;
        const pos = new Float32Array(vs * vs * 3);
        const nor = new Float32Array(vs * vs * 3);
        const colr = new Float32Array(vs * vs * 3);
        let p = 0;
        for (let j = 0; j < vs; j++) {
          for (let i = 0; i < vs; i++) {
            const gi = ci * CHUNK + i, gj = cj * CHUNK + j;
            const x = -WORLD_HALF + gi * SPACING, z = -WORLD_HALF + gj * SPACING;
            const y = this.h(gi, gj);
            pos[p] = x; pos[p + 1] = y; pos[p + 2] = z;
            const nx = this.h(gi - 1, gj) - this.h(gi + 1, gj);
            const nz = this.h(gi, gj - 1) - this.h(gi, gj + 1);
            const ny = 2 * SPACING;
            const l = Math.hypot(nx, ny, nz);
            nor[p] = nx / l; nor[p + 1] = ny / l; nor[p + 2] = nz / l;
            this.colorFor(x, z, y, ny / l, col);
            colr[p] = col[0]; colr[p + 1] = col[1]; colr[p + 2] = col[2];
            p += 3;
          }
        }
        const idx = new Uint32Array(CHUNK * CHUNK * 6);
        let k = 0;
        for (let j = 0; j < CHUNK; j++) {
          for (let i = 0; i < CHUNK; i++) {
            const a = j * vs + i, b = a + 1, c = a + vs, d = c + 1;
            // diagonal a-d to match heightAt()
            idx[k++] = a; idx[k++] = c; idx[k++] = d;
            idx[k++] = a; idx[k++] = d; idx[k++] = b;
          }
        }
        const geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
        geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
        geo.setAttribute('color', new THREE.BufferAttribute(colr, 3));
        geo.setIndex(new THREE.BufferAttribute(idx, 1));
        geo.computeBoundingSphere();
        geo.computeBoundingBox();
        const mesh = new THREE.Mesh(geo, this.material);
        mesh.name = `terrain_${ci}_${cj}`;
        mesh.matrixAutoUpdate = false;
        this.group.add(mesh);
      }
    }
    this.ready = true;
  }

  /** Hide chunks that are entirely beyond the fog. */
  cull(cam, maxDist = 340) {
    for (const m of this.group.children) {
      const bs = m.geometry.boundingSphere;
      m.visible = bs.center.distanceTo(cam) - bs.radius < maxDist;
    }
  }

  /** Raycast against the heightfield by marching. Returns distance or -1. */
  raycast(origin, dir, maxDist = 200, step = 1.0) {
    let prevAbove = origin.y - this.heightAt(origin.x, origin.z);
    if (prevAbove < 0) return 0;
    for (let t = step; t <= maxDist; t += step) {
      const x = origin.x + dir.x * t, y = origin.y + dir.y * t, z = origin.z + dir.z * t;
      const above = y - this.heightAt(x, z);
      if (above < 0) {
        // refine
        const f = prevAbove / (prevAbove - above);
        return t - step + step * f;
      }
      prevAbove = above;
      if (t > 40) step = 2;
    }
    return -1;
  }
}
