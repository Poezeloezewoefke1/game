// Shared underwater shading. Every lit material in the world is patched so that:
//  - sunlight/ambient is computed here (absorbed with depth, with caustics)
//  - fog colour depends on depth (teal shallows -> black abyss)
//  - the sonar pulse paints an expanding ring across all geometry
//  - creatures/plants can animate in the vertex shader (swim/flap/pulse/sway)
// Three.js still handles spot/point lights (headlamp, sub lights) normally.

import * as THREE from 'three';
import { ShaderChunk } from 'three';

export const U = {
  uTime: { value: 0 },
  uCamPos: { value: new THREE.Vector3() },
  uSunDir: { value: new THREE.Vector3(0.3, 1, 0.2).normalize() },
  uSunColor: { value: new THREE.Color(0.75, 0.92, 1.0) },
  uDaylight: { value: 1 },
  uAmbTop: { value: new THREE.Color(0.2, 0.44, 0.52) },
  uAmbBottom: { value: new THREE.Color(0.025, 0.07, 0.1) },
  uAbsorb: { value: new THREE.Vector3(0.045, 0.017, 0.0105) },
  uDeepAmbient: { value: new THREE.Color(0.006, 0.008, 0.016) },
  uFogColor: { value: new THREE.Color(0.045, 0.25, 0.34) },
  uFogAbsorb: { value: new THREE.Vector3(0.022, 0.0125, 0.0092) },
  uFogDensity: { value: 0.016 },
  uInAir: { value: 0 },
  uSonarOrigin: { value: new THREE.Vector3() },
  uSonarRadius: { value: 0 },
  uSonarStrength: { value: 0 },
  uCaustics: { value: 1 },
  uNoiseTex: { value: null },
  uSurfQuality: { value: 1 }, // 0 disables triplanar surface detail (Low quality / classic)
  uEnvBoost: { value: 1 }, // global scale for image-based reflections
};

export const GLSL_COMMON = /* glsl */`
uniform float uTime;
uniform vec3 uCamPos;
uniform vec3 uSunDir;
uniform vec3 uSunColor;
uniform float uDaylight;
uniform vec3 uAmbTop;
uniform vec3 uAmbBottom;
uniform vec3 uAbsorb;
uniform vec3 uDeepAmbient;
uniform vec3 uFogColor;
uniform vec3 uFogAbsorb;
uniform float uFogDensity;
uniform float uInAir;
uniform vec3 uSonarOrigin;
uniform float uSonarRadius;
uniform float uSonarStrength;
uniform float uCaustics;
uniform float uSurfQuality;
uniform float uEnvBoost;

float abyssCaustic(vec2 uv, float t) {
  vec2 p = mod(uv * 6.28318, 6.28318) - 250.0;
  vec2 i = p;
  float c = 1.0;
  float inten = 0.005;
  for (int n = 0; n < 3; n++) {
    float tt = t * (1.0 - (3.5 / float(n + 1)));
    i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
    c += 1.0 / length(vec2(p.x / (sin(i.x + tt) / inten), p.y / (cos(i.y + tt) / inten)));
  }
  c /= 3.0;
  c = 1.17 - pow(c, 1.4);
  return pow(abs(c), 7.0);
}

vec3 abyssWaterColor(float depth) {
  return uFogColor * exp(-uFogAbsorb * depth) * mix(0.18, 1.0, uDaylight) + vec3(0.001, 0.0015, 0.004);
}

vec3 abyssAmbient(vec3 albedo, vec3 wN, vec3 wp) {
  float depth = max(0.0, -wp.y);
  vec3 absorb = exp(-uAbsorb * depth);
  float up = wN.y * 0.5 + 0.5;
  vec3 hemi = mix(uAmbBottom, uAmbTop, up);
  float sunN = max(dot(wN, uSunDir), 0.0);
  vec3 light = hemi + uSunColor * sunN * 0.55;
  float caust = abyssCaustic(wp.xz / 13.0, uTime * 0.45) * smoothstep(-0.1, 0.9, wN.y) * uCaustics * exp(-depth * 0.03);
  light += uSunColor * caust * 1.6 * uDaylight;
  light *= mix(0.12, 1.0, uDaylight);
  return albedo * (light * absorb + uDeepAmbient);
}

// image-based reflections fade with depth like sunlight does (stronger in air pockets)
vec3 abyssEnvAtten(vec3 wp) {
  float depth = max(0.0, -wp.y);
  vec3 a = exp(-uAbsorb * depth) * mix(0.15, 1.0, uDaylight);
  return mix(a, vec3(1.0), uInAir) + uDeepAmbient * 2.0;
}

vec3 abyssFog(vec3 col, vec3 wp) {
  float dist = length(wp - uCamPos);
  float camD = max(0.0, -uCamPos.y);
  float fragD = max(0.0, -wp.y);
  vec3 fogCol = abyssWaterColor(mix(camD, fragD, 0.35));
  float dens = mix(uFogDensity, 0.002, uInAir);
  float f = 1.0 - exp(-dens * dens * dist * dist);
  return mix(col, fogCol, f);
}

vec3 abyssSonar(vec3 col, vec3 wp) {
  if (uSonarStrength <= 0.001) return col;
  float sd = distance(wp, uSonarOrigin);
  float w = 1.5 + uSonarRadius * 0.015;
  float ring = 1.0 - smoothstep(0.0, w, abs(sd - uSonarRadius));
  float trail = step(sd, uSonarRadius) * smoothstep(uSonarRadius - 60.0, uSonarRadius, sd) * 0.12;
  float grid = 0.0;
  vec2 g = abs(fract(wp.xz / 8.0) - 0.5);
  grid = (1.0 - smoothstep(0.0, 0.04, min(g.x, g.y))) * trail * 2.0;
  return col + vec3(0.25, 0.85, 1.0) * (ring * 0.9 + trail + grid) * uSonarStrength;
}
`;

const SWIM_VERTEX = /* glsl */`
#ifdef SWIM_MODE
  #ifdef USE_INSTANCING
    float swimPhase = aPhase;
  #else
    float swimPhase = uSwimPhase;
  #endif
  #if SWIM_MODE == 1
    // lateral body wave; head at +z, tail at -z
    float sT = clamp((uSwimHead - transformed.z) / uSwimLen, 0.0, 1.0);
    transformed.x += sin(uTime * uSwimSpeed + swimPhase - transformed.z * uSwimFreq) * uSwimAmp * (0.15 + sT * sT);
  #elif SWIM_MODE == 2
    // wing flap; wings span along x
    float wx = abs(transformed.x);
    transformed.y += sin(uTime * uSwimSpeed + swimPhase - wx * uSwimFreq) * uSwimAmp * wx * wx;
  #elif SWIM_MODE == 3
    // bell pulse (jellyfish); bell above y=0, tendrils below
    float pulse = sin(uTime * uSwimSpeed + swimPhase);
    if (transformed.y > 0.0) {
      transformed.xz *= 1.0 + pulse * uSwimAmp * (1.0 - transformed.y / uSwimLen);
    } else {
      float d = -transformed.y;
      transformed.x += sin(uTime * 1.3 + swimPhase + d * uSwimFreq) * d * 0.08;
      transformed.z += cos(uTime * 1.1 + swimPhase + d * uSwimFreq) * d * 0.08;
    }
  #elif SWIM_MODE == 4
    // plant sway grows with height
    float hT = clamp(transformed.y / uSwimLen, 0.0, 1.0);
    float sw = pow(hT, 1.5) * uSwimAmp;
    transformed.x += sin(uTime * uSwimSpeed + swimPhase + transformed.y * uSwimFreq) * sw;
    transformed.z += cos(uTime * uSwimSpeed * 0.8 + swimPhase * 1.7 + transformed.y * uSwimFreq) * sw * 0.7;
  #endif
#endif
`;

/**
 * Patch a built-in lit material (Standard/Lambert/Phong) for the underwater look.
 * opts: { swim: {mode, amp, speed, freq, len, head, phase}, detail: number (terrain noise),
 *         caustics: bool(default true), fog: bool(default true), ambient: number scale }
 */
export function patchMaterial(mat, opts = {}) {
  mat.fog = false;
  const swim = opts.swim;
  const detail = opts.detail || 0;
  const ambientScale = opts.ambient ?? 1;
  const fogScale = opts.fogScale ?? 1;
  mat.userData.swimPhase = { value: swim?.phase ?? 0 };
  const glow = opts.glow;
  if (glow) mat.userData.glowColor = { value: new THREE.Color(glow.color ?? 0x66eeff) };
  const surf = opts.surface;
  const reflect = opts.reflect ?? 1;
  const key = [
    'abyss', swim ? swim.mode : 0, detail ? 1 : 0, ambientScale, fogScale, opts.noFog ? 1 : 0, glow ? 1 : 0,
    surf ? surf.space : 0,
  ].join('_');
  mat.userData.abyssSurface = surf || null;

  mat.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, U);
    shader.uniforms.uAmbScale = { value: ambientScale };
    shader.uniforms.uFogScale = { value: fogScale };
    if (swim) {
      shader.uniforms.uSwimAmp = { value: swim.amp ?? 0.2 };
      shader.uniforms.uSwimSpeed = { value: swim.speed ?? 6 };
      shader.uniforms.uSwimFreq = { value: swim.freq ?? 2 };
      shader.uniforms.uSwimLen = { value: swim.len ?? 1 };
      shader.uniforms.uSwimHead = { value: swim.head ?? 0.5 };
      shader.uniforms.uSwimPhase = mat.userData.swimPhase;
      shader.defines = shader.defines || {};
      shader.defines.SWIM_MODE = swim.mode;
    }
    shader.defines = shader.defines || {};
    if (swim || glow) shader.defines.NEEDS_PHASE = 1;
    shader.uniforms.uEnvScale = { value: reflect };
    if (surf) {
      shader.defines.USE_SURFACE = 1;
      if (surf.space === 'object') shader.defines.SURF_OBJECT = 1;
      shader.uniforms.uSurfMap = { value: surf.map };
      shader.uniforms.uSurfSide = { value: surf.side };
      shader.uniforms.uSurfScale = { value: new THREE.Vector2(surf.scale, surf.sideScale) };
      shader.uniforms.uSurfStrength = { value: surf.strength };
      shader.uniforms.uSurfCavity = { value: surf.cavity };
      shader.uniforms.uSurfRough = { value: surf.rough };
    }
    if (glow) {
      shader.defines.USE_GLOW = 1;
      shader.uniforms.uGlowColor = mat.userData.glowColor;
      shader.uniforms.uGlowPulse = { value: glow.pulse ?? 1.5 };
      shader.uniforms.uGlowIntensity = { value: glow.intensity ?? 2.0 };
      if (!swim) shader.uniforms.uSwimPhase = mat.userData.swimPhase;
    }
    // ---- vertex
    let vs = shader.vertexShader;
    vs = vs.replace('#include <common>', `#include <common>
uniform float uTime;
varying vec3 vAbyssWP;
#ifdef SWIM_MODE
uniform float uSwimAmp; uniform float uSwimSpeed; uniform float uSwimFreq; uniform float uSwimLen; uniform float uSwimHead;
#endif
#ifdef NEEDS_PHASE
uniform float uSwimPhase;
#ifdef USE_INSTANCING
attribute float aPhase;
#endif
#endif
#ifdef USE_GLOW
attribute float aGlow;
varying float vGlow;
varying float vGlowPhase;
#endif
#ifdef USE_SURFACE
varying vec3 vSurfP; varying vec3 vSurfN; varying vec3 vSurfBX; varying vec3 vSurfBY; varying vec3 vSurfBZ;
#endif`);
    vs = vs.replace('#include <begin_vertex>', `#include <begin_vertex>
${SWIM_VERTEX}
#ifdef USE_GLOW
  vGlow = aGlow;
  #ifdef USE_INSTANCING
    vGlowPhase = aPhase;
  #else
    vGlowPhase = uSwimPhase;
  #endif
#endif`);
    vs = vs.replace('#include <project_vertex>', `#include <project_vertex>
  vec4 abyssWP = vec4(transformed, 1.0);
  #ifdef USE_BATCHING
    abyssWP = batchingMatrix * abyssWP;
  #endif
  #ifdef USE_INSTANCING
    abyssWP = instanceMatrix * abyssWP;
  #endif
  vAbyssWP = (modelMatrix * abyssWP).xyz;
  #ifdef USE_SURFACE
    mat4 surfM = modelMatrix;
    #ifdef USE_INSTANCING
      surfM = modelMatrix * instanceMatrix;
    #endif
    #ifdef SURF_OBJECT
      vSurfP = transformed;
      vSurfN = objectNormal;
      mat3 surfV = mat3(viewMatrix * surfM);
    #else
      vSurfP = vAbyssWP;
      vSurfN = mat3(surfM) * objectNormal;
      mat3 surfV = mat3(viewMatrix);
    #endif
    vSurfBX = surfV[0]; vSurfBY = surfV[1]; vSurfBZ = surfV[2];
  #endif`);
    shader.vertexShader = vs;

    // ---- fragment
    let fs = shader.fragmentShader;
    fs = fs.replace('#include <common>', `#include <common>
${GLSL_COMMON}
uniform float uAmbScale;
uniform float uFogScale;
varying vec3 vAbyssWP;
#ifdef USE_GLOW
uniform vec3 uGlowColor; uniform float uGlowPulse; uniform float uGlowIntensity;
varying float vGlow; varying float vGlowPhase;
#endif
uniform float uEnvScale;
#ifdef USE_SURFACE
uniform sampler2D uSurfMap; uniform sampler2D uSurfSide; uniform vec2 uSurfScale;
uniform float uSurfStrength; uniform float uSurfCavity; uniform float uSurfRough;
varying vec3 vSurfP; varying vec3 vSurfN; varying vec3 vSurfBX; varying vec3 vSurfBY; varying vec3 vSurfBZ;
#endif
${detail ? 'uniform sampler2D uNoiseTex;' : ''}`);
    // reflections: keep image-based specular, drop image-based diffuse (the
    // underwater ambient above already provides it), and absorb with depth
    fs = fs.replace('#include <lights_fragment_maps>', ShaderChunk.lights_fragment_maps
      .replace('iblIrradiance += getIBLIrradiance( geometryNormal );', '')
      .replace('radiance += iblRadiance;', 'radiance += iblRadiance * uEnvScale * uEnvBoost * abyssEnvAtten(vAbyssWP);'));
    fs = fs.replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
#ifdef USE_SURFACE
  if (uSurfQuality > 0.0) {
    // triplanar normal mapping (whiteout blend) in world or object space
    vec3 sn = normalize(vSurfN);
    vec3 bw = pow(abs(sn), vec3(4.0));
    bw /= (bw.x + bw.y + bw.z);
    vec3 sp = vSurfP;
    vec3 tx = texture2D(uSurfSide, sp.zy * uSurfScale.y).xyz * 2.0 - 1.0;
    vec3 ty = texture2D(uSurfMap, sp.xz * uSurfScale.x).xyz * 2.0 - 1.0;
    vec3 tz = texture2D(uSurfSide, sp.xy * uSurfScale.y).xyz * 2.0 - 1.0;
    float k = uSurfStrength * uSurfQuality;
    tx.xy *= k; ty.xy *= k; tz.xy *= k;
    vec3 nx = vec3(tx.xy + sn.zy, abs(tx.z) * sn.x);
    vec3 ny = vec3(ty.xy + sn.xz, abs(ty.z) * sn.y);
    vec3 nz = vec3(tz.xy + sn.xy, abs(tz.z) * sn.z);
    vec3 nb = normalize(nx.zyx * bw.x + ny.xzy * bw.y + nz.xyz * bw.z);
    vec3 bx = normalize(vSurfBX), by = normalize(vSurfBY), bz = normalize(vSurfBZ);
    float fd = gl_FrontFacing ? 1.0 : -1.0;
    vec3 nView = normalize(bx * nb.x + by * nb.y + bz * nb.z) * fd;
    vec3 baseView = normalize(bx * sn.x + by * sn.y + bz * sn.z) * fd;
    normal = normalize(normal + (nView - baseView));
    float cav = clamp((1.0 - dot(nb, sn)) * 3.0, 0.0, 1.0);
    diffuseColor.rgb *= 1.0 - cav * uSurfCavity * uSurfQuality;
    roughnessFactor = clamp(roughnessFactor + cav * uSurfRough, 0.04, 1.0);
  }
#endif`);
    fs = fs.replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
#ifdef USE_GLOW
  totalEmissiveRadiance += uGlowColor * vGlow * uGlowIntensity * (0.72 + 0.28 * sin(uTime * uGlowPulse + vGlowPhase * 6.2831));
#endif`);
    if (detail) {
      fs = fs.replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
  {
    vec3 wNd = normalize((vec4(normal, 0.0) * viewMatrix).xyz);
    vec3 bw = pow(abs(wNd), vec3(4.0));
    bw /= (bw.x + bw.y + bw.z);
    float s = ${detail.toFixed(3)};
    float nA = texture2D(uNoiseTex, vAbyssWP.zy * s).r * bw.x + texture2D(uNoiseTex, vAbyssWP.xz * s).r * bw.y + texture2D(uNoiseTex, vAbyssWP.xy * s).r * bw.z;
    float nB = texture2D(uNoiseTex, vAbyssWP.xz * s * 0.13 + 0.37).g;
    float strata = sin(vAbyssWP.y * 1.7 + nB * 6.0) * 0.5 + 0.5;
    diffuseColor.rgb *= 0.62 + nA * 0.62;
    diffuseColor.rgb *= mix(1.0, 0.82 + strata * 0.28, bw.x + bw.z);
    diffuseColor.rgb *= 0.85 + nB * 0.3;
  }`);
    }
    fs = fs.replace('#include <opaque_fragment>', `
  {
    vec3 wN = normalize((vec4(normal, 0.0) * viewMatrix).xyz);
    outgoingLight += abyssAmbient(diffuseColor.rgb, wN, vAbyssWP) * uAmbScale;
  }
  #include <opaque_fragment>`);
    fs = fs.replace('#include <fog_fragment>', opts.noFog ? '' : `
  {
    vec3 fogged = abyssFog(gl_FragColor.rgb, vAbyssWP);
    gl_FragColor.rgb = mix(gl_FragColor.rgb, fogged, uFogScale);
    gl_FragColor.rgb = abyssSonar(gl_FragColor.rgb, vAbyssWP);
  }`);
    shader.fragmentShader = fs;
  };
  mat.customProgramCacheKey = () => key;
  mat.needsUpdate = true;
  return mat;
}

/** Shorthand: create a patched MeshStandardMaterial. */
export function waterMat(params = {}, opts = {}) {
  const m = new THREE.MeshStandardMaterial({ roughness: 0.85, metalness: 0.0, ...params });
  return patchMaterial(m, opts);
}

/** Tiling value-noise texture used for terrain/rock detail (R: fine, G: broad). */
export function makeNoiseTexture(size = 256) {
  const data = new Uint8Array(size * size * 4);
  const rnd = (x, y, s) => {
    const n = Math.sin(x * 127.1 + y * 311.7 + s * 74.7) * 43758.5453;
    return n - Math.floor(n);
  };
  const valueNoise = (x, y, period, s) => {
    const xi = Math.floor(x), yi = Math.floor(y);
    const xf = x - xi, yf = y - yi;
    const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
    const w = (a) => ((a % period) + period) % period;
    const a = rnd(w(xi), w(yi), s), b = rnd(w(xi + 1), w(yi), s);
    const c = rnd(w(xi), w(yi + 1), s), d = rnd(w(xi + 1), w(yi + 1), s);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  };
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let r = 0, g = 0, amp = 0.5, norm = 0;
      for (let o = 0; o < 5; o++) {
        const p = 8 << o;
        r += valueNoise((x / size) * p, (y / size) * p, p, o) * amp;
        norm += amp;
        amp *= 0.55;
      }
      r /= norm;
      amp = 0.5; norm = 0;
      for (let o = 0; o < 3; o++) {
        const p = 4 << o;
        g += valueNoise((x / size) * p, (y / size) * p, p, o + 10) * amp;
        norm += amp; amp *= 0.5;
      }
      g /= norm;
      const i = (y * size + x) * 4;
      data[i] = r * 255; data[i + 1] = g * 255; data[i + 2] = rnd(x, y, 3) * 255; data[i + 3] = 255;
    }
  }
  const tex = new THREE.DataTexture(data, size, size, THREE.RGBAFormat);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.magFilter = THREE.LinearFilter;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.generateMipmaps = true;
  tex.needsUpdate = true;
  return tex;
}
