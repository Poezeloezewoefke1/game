// The Forge: a hydrothermal vent field on the floor of the Hadal Rift.
// Black-smoker chimneys with animated plumes, sulfide rubble, bacterial
// mats, tube worm thickets and the wreck of a survey drone.

import * as THREE from 'three';
import { U } from './shading.js';
import { trunk, finish, smooth, mix } from '../creatures/anatomy.js';
import { fbm3, boulderGeometry } from './rocks.js';
import { mulberry32 } from '../core/noise.js';
import * as G from './geom.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);

const SOOT = new THREE.Color(0.1, 0.095, 0.09), OXIDE = new THREE.Color(0.5, 0.25, 0.08), SULFUR = new THREE.Color(0.72, 0.62, 0.2), MAT = new THREE.Color(0.85, 0.84, 0.78);

/** Knobbly sulfide chimney, height h, base radius r0, orifice radius r1; base at y=0. */
export function chimneyGeometry(h, r0, r1, seed = 1) {
  const rnd = mulberry32(seed * 41 + 9);
  const ledges = [];
  for (let k = 0; k < 4; k++) ledges.push({ y: 0.2 + rnd() * 0.7, w: 0.04 + rnd() * 0.05, s: 0.25 + rnd() * 0.35 });
  const R = (t, a) => {
    let r = mix(r0, r1, Math.pow(t, 0.7));
    for (const l of ledges) r *= 1 + l.s * Math.exp(-(((t - l.y) / l.w) ** 2)) * (0.6 + 0.4 * Math.sin(a * 2 + l.y * 9));
    r *= 1 + 0.2 * fbm3(Math.cos(a) * 1.5 + seed, t * h * 0.6, Math.sin(a) * 1.5, 3);
    if (t > 0.97) r *= 1.12; // crater lip
    return r;
  };
  const g = trunk({ z0: 0, z1: h, segs: Math.round(h * 5), radial: 20, section: (t, a) => {
    const r = R(t, a);
    const lean = 0.25 * Math.sin(t * 2 + seed) * t;
    return [Math.cos(a) * r + lean, Math.sin(a) * r];
  } });
  g.rotateX(-Math.PI / 2); // trunk z (height) -> y
  return finish(g, {
    color: (x, y, z, c) => {
      const t = y / h;
      const n = fbm3(x * 1.3 + seed, y * 0.8, z * 1.3, 3);
      c.copy(SOOT).lerp(OXIDE, smooth(0.0, 0.4, n) * 0.8);
      c.lerp(SULFUR, smooth(0.75, 1, t) * smooth(-0.2, 0.3, fbm3(x * 3, y * 3, z * 3, 2)) * 0.8);
      if (t > 0.985 && Math.hypot(x, z) < r1 * 0.6) c.setRGB(0.02, 0.02, 0.02); // crater throat
      if (t < 0.25) c.lerp(MAT, smooth(0.1, 0.5, fbm3(x * 2 + 4, y * 2, z * 2, 2)) * 0.7 * (1 - t / 0.25));
    },
    // hot rim and throat; the crater centre stays dark
    glow: (x, y, z) => {
      if (y < h * 0.95) return 0;
      const rr = Math.hypot(x, z) / Math.max(r1, 0.05);
      return rr > 0.75 ? 0.7 : rr > 0.35 ? 0.25 : 0;
    },
  });
}

/** Smoke plume: open cone, base at 0, animated by uTime. */
export function plumeMaterial() {
  return new THREE.ShaderMaterial({
    uniforms: { uTime: U.uTime },
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
    vertexShader: /* glsl */`
      uniform float uTime; varying vec2 vUv; varying float vH;
      void main() {
        vUv = uv; vH = uv.y;
        vec3 p = position;
        p.x += sin(uTime * 0.7 + uv.y * 4.0) * 0.6 * uv.y * uv.y;
        p.z += cos(uTime * 0.5 + uv.y * 3.0) * 0.5 * uv.y * uv.y;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
      }`,
    fragmentShader: /* glsl */`
      uniform float uTime; varying vec2 vUv; varying float vH;
      float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
      float n(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
        return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
      void main() {
        vec2 q = vec2(vUv.x * 10.0, vUv.y * 5.0 - uTime * 0.9);
        float d = n(q) * 0.55 + n(q * 2.1 + 3.7) * 0.3 + n(q * 4.3 - 1.3) * 0.15;
        float fade = (1.0 - smoothstep(0.55, 1.0, vH)) * smoothstep(0.0, 0.04, vH);
        float a = smoothstep(0.35, 0.8, d) * fade * 0.75;
        float heat = exp(-vH * 28.0);
        vec3 col = mix(vec3(0.075, 0.075, 0.085), vec3(1.0, 0.45, 0.12) * 1.3, heat);
        gl_FragColor = vec4(col, a * (0.7 + heat * 0.6));
      }`,
  });
}

/** Irregular bacterial mat conforming to the terrain (world coordinates). */
export function bacterialMat(cx, cz, radius, terrain, seed = 1) {
  const nu = 24, nv = 6;
  const pos = [], col = [], glow = [], idx = [];
  const c = new THREE.Color();
  for (let j = 0; j <= nv; j++) {
    for (let i = 0; i <= nu; i++) {
      const a = (i / nu) * Math.PI * 2, v = j / nv;
      const edge = radius * (0.7 + 0.45 * fbm3(Math.cos(a) * 1.4 + seed, Math.sin(a) * 1.4, seed, 3));
      const x = cx + Math.cos(a) * edge * v, z = cz + Math.sin(a) * edge * v;
      pos.push(x, terrain.heightAt(x, z) + 0.06, z);
      c.copy(MAT).lerp(OXIDE, smooth(0.5, 1, v) * 0.7).lerp(SULFUR, smooth(0.1, 0.5, fbm3(x * 0.6, z * 0.6, seed, 2)) * 0.5);
      col.push(c.r, c.g, c.b);
      glow.push(v < 0.6 ? 0.12 : 0);
    }
  }
  const cols = nu + 1;
  for (let j = 0; j < nv; j++) for (let i = 0; i < nu; i++) { const a = j * cols + i, b = a + 1, cc = a + cols, d = cc + 1; idx.push(a, cc, d, a, d, b); }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.setAttribute('aGlow', new THREE.Float32BufferAttribute(glow, 1));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

/** Wrecked survey drone (1.9 m torpedo) lying on its side; local, nose +z. */
export function droneGeometry() {
  const parts = [];
  const body = trunk({ z0: -0.95, z1: 0.95, segs: 20, radial: 16, section: (t, a) => {
    const r = 0.2 * Math.pow(Math.sin(Math.PI * Math.min(1, 0.15 + t * 0.95)), 0.35);
    return [Math.cos(a) * r, Math.sin(a) * r];
  } });
  parts.push(finish(body, { color: (x, y, z, c) => { if (z > 0.55) c.setRGB(0.85, 0.42, 0.12); else if (Math.abs(z + 0.1) < 0.05) c.setRGB(0.1, 0.1, 0.1); else c.setRGB(0.8, 0.8, 0.76); c.multiplyScalar(0.75 + 0.3 * fbm3(x * 5, y * 5, z * 5, 2)); } }));
  for (let k = 0; k < 4; k++) {
    const a = (k / 4) * Math.PI * 2 + Math.PI / 4;
    const fin = new THREE.BoxGeometry(0.02, 0.22, 0.2).translate(0, 0.2, -0.75).rotateZ(a);
    if (k === 2) fin.scale(1, 0.5, 1); // snapped fin
    parts.push(finish(fin, { color: 0x2a2a2a }));
  }
  parts.push(finish(new THREE.TorusGeometry(0.17, 0.025, 6, 16).translate(0, 0, -0.98), { color: 0x2a2a2a }));
  parts.push(finish(new THREE.SphereGeometry(0.11, 10, 6, 0, Math.PI * 2, 0, Math.PI / 2).rotateX(Math.PI / 2).translate(0, 0, 0.93), { color: 0x0a1418, glow: 0.2 }));
  return G.merge(parts);
}

export function sulfideRubble(seed) {
  return boulderGeometry(seed + 900, { detail: 3, cuts: 8, tone: [0.13, 0.12, 0.11], moss: 0 });
}
