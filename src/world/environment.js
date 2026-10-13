// Ocean atmosphere: surface, alien sky, light shafts, marine snow,
// bioluminescent plankton, bubbles and the day/night cycle.

import * as THREE from 'three';
import { U, GLSL_COMMON } from './shading.js';
import { smoothstep, clamp } from '../core/noise.js';

export const DAY_LENGTH = 24 * 60; // seconds for a full cycle

const WRAP_VERT = /* glsl */`
vec3 wrapAround(vec3 base, vec3 cam, vec3 halfSize) {
  return mod(base - cam + halfSize, halfSize * 2.0) - halfSize + cam;
}
`;

export class Environment {
  constructor(scene, quality) {
    this.scene = scene;
    this.quality = quality;
    this.dayTime = 0.32; // 0..1, 0.25 = sunrise-ish peak climbing
    this.group = new THREE.Group();
    scene.add(this.group);
    this.buildSurface();
    this.buildSky();
    this.buildRays();
    this.buildSnow();
    this.buildPlankton();
    this.bubbles = new Bubbles(this.group);
    this.sonar = { active: false, t: 0, range: 160, speed: 120 };
  }

  buildSurface() {
    const geo = new THREE.PlaneGeometry(2400, 2400, 1, 1);
    geo.rotateX(-Math.PI / 2);
    const mat = new THREE.ShaderMaterial({
      uniforms: { ...U, uLevel: { value: 0 } },
      side: THREE.DoubleSide,
      transparent: false,
      vertexShader: /* glsl */`
        varying vec3 vWP;
        uniform float uLevel;
        void main() {
          vec4 wp = modelMatrix * vec4(position, 1.0);
          vWP = wp.xyz;
          gl_Position = projectionMatrix * viewMatrix * wp;
        }`,
      fragmentShader: /* glsl */`
        ${GLSL_COMMON}
        uniform sampler2D uNoiseTex;
        varying vec3 vWP;
        vec3 skyCol(vec3 d) {
          float h = clamp(d.y, 0.0, 1.0);
          vec3 day = mix(vec3(0.4, 0.54, 0.6), vec3(0.1, 0.24, 0.44), pow(h, 0.5));
          vec3 night = mix(vec3(0.05, 0.06, 0.12), vec3(0.01, 0.015, 0.04), h);
          return mix(night, day, uDaylight);
        }
        void main() {
          vec2 uv = vWP.xz * 0.018;
          float t = uTime * 0.02;
          float n1 = texture2D(uNoiseTex, uv + vec2(t, t * 0.6)).r;
          float n2 = texture2D(uNoiseTex, uv * 2.3 - vec2(t * 1.3, -t)).r;
          float n3 = texture2D(uNoiseTex, uv * 0.4 + vec2(-t * 0.5, t * 0.2)).g;
          vec2 slope = vec2(n1 - n2, n2 - n3) * 0.6;
          vec3 V = normalize(vWP - uCamPos);
          vec3 col;
          if (!gl_FrontFacing) {
            // seen from below: Snell's window + total internal reflection
            vec3 N = normalize(vec3(slope.x, -1.0, slope.y));
            float up = V.y + (n1 - 0.5) * 0.08;
            float window = smoothstep(0.62, 0.74, up);
            vec3 tir = abyssWaterColor(6.0) * (0.7 + n2 * 0.5);
            vec3 sky = skyCol(vec3(0.0, 1.0, 0.0)) * 1.25;
            float sun = pow(max(dot(normalize(V + vec3(slope.x, 0.0, slope.y) * 0.6), uSunDir), 0.0), 60.0) * 6.0 * uDaylight;
            float ripple = smoothstep(0.45, 0.8, n1 * n2 * 2.2) * 0.35;
            col = mix(tir, sky + ripple * uDaylight, window) + sun * vec3(1.0, 0.95, 0.85);
            col += abyssCaustic(vWP.xz / 24.0, uTime * 0.3) * 0.25 * uDaylight * (1.0 - window);
            col = abyssFog(col, vWP);
          } else {
            // seen from above: dark water, fresnel sky reflection, sun glint
            vec3 N = normalize(vec3(slope.x * 0.8, 1.0, slope.y * 0.8));
            vec3 R = reflect(V, N);
            float fres = pow(1.0 - max(dot(-V, N), 0.0), 4.0);
            vec3 deep = vec3(0.005, 0.04, 0.065) * mix(0.25, 1.0, uDaylight);
            col = mix(deep, skyCol(R) * 0.8, clamp(fres, 0.0, 1.0));
            col += pow(max(dot(R, uSunDir), 0.0), 220.0) * vec3(1.0, 0.9, 0.75) * 8.0 * uDaylight;
            float dist = length(vWP - uCamPos);
            col = mix(col, skyCol(vec3(0.0, 0.02, 0.0)), smoothstep(150.0, 900.0, dist));
          }
          gl_FragColor = vec4(col, 1.0);
        }`,
    });
    this.surfaceMat = mat;
    this.surface = new THREE.Mesh(geo, mat);
    this.surface.frustumCulled = false;
    this.surface.renderOrder = -1;
    this.group.add(this.surface);
  }

  buildSky() {
    const geo = new THREE.SphereGeometry(1500, 48, 24);
    const mat = new THREE.ShaderMaterial({
      uniforms: U,
      side: THREE.BackSide,
      depthWrite: false,
      vertexShader: /* glsl */`
        varying vec3 vDir;
        void main() {
          vDir = normalize(position);
          vec4 wp = modelMatrix * vec4(position, 1.0);
          gl_Position = projectionMatrix * viewMatrix * wp;
        }`,
      fragmentShader: /* glsl */`
        uniform vec3 uSunDir;
        uniform float uDaylight;
        uniform float uTime;
        varying vec3 vDir;
        float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
        void main() {
          vec3 d = normalize(vDir);
          float h = max(d.y, 0.0);
          vec3 day = mix(vec3(0.42, 0.56, 0.62), vec3(0.08, 0.2, 0.42), pow(h, 0.45));
          vec3 dusk = mix(vec3(0.6, 0.36, 0.34), vec3(0.1, 0.12, 0.28), pow(h, 0.5));
          vec3 night = mix(vec3(0.04, 0.05, 0.1), vec3(0.005, 0.008, 0.025), h);
          float sunH = uSunDir.y;
          vec3 col = mix(night, mix(dusk, day, smoothstep(0.05, 0.4, sunH)), uDaylight);
          // stars
          float s = hash(floor(d * 420.0));
          col += step(0.9975, s) * (1.0 - uDaylight) * vec3(0.8, 0.9, 1.0) * (0.6 + 0.4 * sin(uTime * 2.0 + s * 100.0));
          // sun
          float sd = max(dot(d, uSunDir), 0.0);
          col += pow(sd, 900.0) * vec3(1.6, 1.4, 1.1) * 4.0 + pow(sd, 12.0) * vec3(0.4, 0.3, 0.2) * uDaylight;
          // gas giant on the northern horizon with a ring
          vec3 gp = normalize(vec3(0.15, 0.22, -1.0));
          float gd = acos(clamp(dot(d, gp), -1.0, 1.0));
          float R = 0.22;
          if (gd < R) {
            vec3 up = vec3(0.0, 1.0, 0.0);
            vec3 right = normalize(cross(gp, up));
            vec3 upv = cross(right, gp);
            vec2 q = vec2(dot(d - gp, right), dot(d - gp, upv)) / R;
            float lat = q.y * 0.9 + q.x * 0.25;
            vec3 band = mix(vec3(0.62, 0.55, 0.62), vec3(0.42, 0.5, 0.62), sin(lat * 18.0) * 0.5 + 0.5);
            float limb = sqrt(max(0.0, 1.0 - dot(q, q)));
            float lit = clamp(dot(normalize(vec3(q, limb)), normalize(vec3(-0.6, 0.4, 0.7))), 0.0, 1.0);
            col = mix(col, band * (0.15 + lit * 0.9), smoothstep(R, R * 0.97, gd));
          }
          // ring band (thin ellipse)
          {
            vec3 right = normalize(cross(gp, vec3(0.0, 1.0, 0.0)));
            vec3 upv = cross(right, gp);
            vec2 q = vec2(dot(d - gp, right), dot(d - gp, upv)) / R;
            float rr = length(vec2(q.x, (q.y + q.x * 0.28) * 4.2));
            float ring = smoothstep(1.55, 1.6, rr) * smoothstep(2.25, 2.1, rr) * (0.6 + 0.4 * sin(rr * 40.0));
            float behind = (dot(q, q) < 1.0 && (q.y + q.x * 0.28) > 0.0) ? 0.0 : 1.0;
            col += ring * behind * vec3(0.7, 0.66, 0.6) * mix(0.3, 0.9, uDaylight);
          }
          // small moon
          vec3 mp = normalize(vec3(-0.7, 0.45, 0.3));
          float md = dot(d, mp);
          col = mix(col, vec3(0.75, 0.78, 0.82), smoothstep(0.99955, 0.9997, md));
          gl_FragColor = vec4(col, 1.0);
        }`,
    });
    this.sky = new THREE.Mesh(geo, mat);
    this.sky.frustumCulled = false;
    this.sky.renderOrder = -2;
    this.sky.visible = false;
    this.group.add(this.sky);
  }

  buildRays() {
    const count = 22;
    const pos = [], corner = [], seed = [], side = [];
    const rnd = (i) => { const x = Math.sin(i * 91.7) * 43758.5; return x - Math.floor(x); };
    for (let i = 0; i < count; i++) {
      const bx = (rnd(i) - 0.5) * 140, bz = (rnd(i + 31) - 0.5) * 140;
      const w = 1.5 + rnd(i + 7) * 3.5;
      const s = rnd(i + 13);
      const corners = [[-1, 0], [1, 0], [1, 1], [-1, 0], [1, 1], [-1, 1]];
      for (const [cx, cy] of corners) {
        pos.push(bx, 0, bz);
        corner.push(cx * w, cy);
        seed.push(s);
        side.push(cx);
      }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    geo.setAttribute('aCorner', new THREE.Float32BufferAttribute(corner, 2));
    geo.setAttribute('aSeed', new THREE.Float32BufferAttribute(seed, 1));
    geo.setAttribute('aSide', new THREE.Float32BufferAttribute(side, 1));
    const mat = new THREE.ShaderMaterial({
      uniforms: { ...U, uRayStrength: { value: 1 } },
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      side: THREE.DoubleSide,
      vertexShader: /* glsl */`
        uniform vec3 uCamPos; uniform vec3 uSunDir; uniform float uTime;
        attribute vec2 aCorner; attribute float aSeed; attribute float aSide;
        varying float vV; varying float vFade; varying float vSeed; varying float vSide;
        ${WRAP_VERT}
        void main() {
          vec3 base = wrapAround(position, vec3(uCamPos.x, 0.0, uCamPos.z), vec3(70.0, 1.0, 70.0));
          base.y = 0.0;
          float len = 70.0 + aSeed * 50.0;
          float y = -aCorner.y * len;
          vec3 toCam = uCamPos - base; toCam.y = 0.0;
          vec3 right = normalize(vec3(toCam.z, 0.0, -toCam.x) + 1e-4);
          vec3 slant = vec3(uSunDir.x, 0.0, uSunDir.z) / max(uSunDir.y, 0.3);
          vec3 wp = base + right * aCorner.x * (1.0 + aCorner.y * 0.6) + vec3(0.0, y, 0.0) - slant * y;
          vV = aCorner.y;
          vSeed = aSeed;
          vSide = aSide;
          float d = length(base.xz - uCamPos.xz);
          vFade = smoothstep(70.0, 40.0, d) * smoothstep(10.0, 28.0, d);
          gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.0);
        }`,
      fragmentShader: /* glsl */`
        uniform float uTime; uniform float uDaylight; uniform vec3 uCamPos; uniform float uRayStrength;
        varying float vV; varying float vFade; varying float vSeed; varying float vSide;
        void main() {
          float edge = pow(1.0 - abs(vSide), 1.5);
          float flick = 0.55 + 0.45 * sin(uTime * (0.3 + vSeed * 0.4) + vSeed * 40.0);
          float a = pow(1.0 - vV, 1.6) * vFade * flick * uDaylight * uRayStrength * edge;
          float camDepthFade = smoothstep(160.0, 20.0, -uCamPos.y);
          gl_FragColor = vec4(vec3(0.55, 0.85, 0.95) * a * 0.075 * camDepthFade, 1.0);
        }`,
    });
    this.rays = new THREE.Mesh(geo, mat);
    this.rays.frustumCulled = false;
    this.group.add(this.rays);
  }

  buildSnow() {
    const count = this.quality === 'low' ? 1200 : 3200;
    const pos = new Float32Array(count * 3);
    const rnd = new Float32Array(count);
    for (let i = 0; i < count; i++) {
      pos[i * 3] = (Math.random() - 0.5) * 80;
      pos[i * 3 + 1] = (Math.random() - 0.5) * 80;
      pos[i * 3 + 2] = (Math.random() - 0.5) * 80;
      rnd[i] = Math.random();
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('aRnd', new THREE.BufferAttribute(rnd, 1));
    const mat = new THREE.ShaderMaterial({
      uniforms: { ...U, uCamDir: { value: new THREE.Vector3() }, uLamp: { value: 1 }, uPixel: { value: 1 } },
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      vertexShader: /* glsl */`
        uniform vec3 uCamPos; uniform float uTime; uniform vec3 uCamDir; uniform float uLamp; uniform float uPixel; uniform float uDaylight;
        attribute float aRnd;
        varying float vA;
        ${WRAP_VERT}
        void main() {
          vec3 p = position + vec3(sin(uTime * 0.2 + aRnd * 30.0) * 0.6, -uTime * (0.08 + aRnd * 0.12), cos(uTime * 0.17 + aRnd * 20.0) * 0.6);
          vec3 wp = wrapAround(p, uCamPos, vec3(40.0));
          vec3 rel = wp - uCamPos;
          float d = length(rel);
          float cone = smoothstep(0.82, 0.97, dot(rel / max(d, 0.001), uCamDir)) * uLamp * smoothstep(45.0, 4.0, d);
          float depth = max(0.0, -wp.y);
          float amb = exp(-depth * 0.012) * mix(0.25, 1.0, uDaylight);
          vA = (amb * 0.35 + cone * 1.2) * smoothstep(40.0, 25.0, d) * smoothstep(0.3, 1.5, d) * step(wp.y, -0.5);
          vec4 mv = viewMatrix * vec4(wp, 1.0);
          gl_PointSize = (0.06 + aRnd * 0.08) * uPixel * 600.0 / -mv.z;
          gl_Position = projectionMatrix * mv;
        }`,
      fragmentShader: /* glsl */`
        varying float vA;
        void main() {
          vec2 c = gl_PointCoord - 0.5;
          float a = smoothstep(0.5, 0.1, length(c)) * vA;
          gl_FragColor = vec4(vec3(0.75, 0.88, 0.9) * a, 1.0);
        }`,
    });
    this.snowMat = mat;
    this.snow = new THREE.Points(geo, mat);
    this.snow.frustumCulled = false;
    this.group.add(this.snow);
  }

  buildPlankton() {
    const count = this.quality === 'low' ? 300 : 900;
    const pos = new Float32Array(count * 3);
    const rnd = new Float32Array(count);
    for (let i = 0; i < count; i++) {
      pos[i * 3] = (Math.random() - 0.5) * 100;
      pos[i * 3 + 1] = (Math.random() - 0.5) * 100;
      pos[i * 3 + 2] = (Math.random() - 0.5) * 100;
      rnd[i] = Math.random();
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('aRnd', new THREE.BufferAttribute(rnd, 1));
    const mat = new THREE.ShaderMaterial({
      uniforms: { ...U, uPixel: { value: 1 } },
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      vertexShader: /* glsl */`
        uniform vec3 uCamPos; uniform float uTime; uniform float uPixel; uniform float uDaylight;
        attribute float aRnd;
        varying float vA; varying vec3 vC;
        ${WRAP_VERT}
        void main() {
          vec3 p = position + vec3(sin(uTime * 0.13 + aRnd * 50.0) * 2.0, sin(uTime * 0.1 + aRnd * 10.0) * 1.5, cos(uTime * 0.11 + aRnd * 70.0) * 2.0);
          vec3 wp = wrapAround(p, uCamPos, vec3(50.0));
          float d = length(wp - uCamPos);
          float depth = max(0.0, -wp.y);
          float dark = 1.0 - exp(-depth * 0.02) * mix(0.3, 1.0, uDaylight);
          float tw = pow(0.5 + 0.5 * sin(uTime * (0.8 + aRnd * 2.0) + aRnd * 80.0), 3.0);
          vA = dark * tw * smoothstep(50.0, 20.0, d) * smoothstep(1.0, 3.0, d) * step(wp.y, -1.0);
          vC = mix(vec3(0.2, 0.95, 1.0), vec3(0.6, 0.45, 1.0), step(0.8, aRnd));
          vec4 mv = viewMatrix * vec4(wp, 1.0);
          gl_PointSize = (0.08 + aRnd * 0.06) * uPixel * 600.0 / -mv.z;
          gl_Position = projectionMatrix * mv;
        }`,
      fragmentShader: /* glsl */`
        varying float vA; varying vec3 vC;
        void main() {
          vec2 c = gl_PointCoord - 0.5;
          float a = smoothstep(0.5, 0.0, length(c));
          gl_FragColor = vec4(vC * a * vA * 1.6, 1.0);
        }`,
    });
    this.planktonMat = mat;
    this.plankton = new THREE.Points(geo, mat);
    this.plankton.frustumCulled = false;
    this.group.add(this.plankton);
  }

  setPixelRatio(pr, height) {
    const s = pr * height / 900;
    this.snowMat.uniforms.uPixel.value = s;
    this.planktonMat.uniforms.uPixel.value = s;
    this.bubbles.mat.uniforms.uPixel.value = s;
  }

  ping(origin, range) {
    this.sonar.active = true;
    this.sonar.t = 0;
    this.sonar.range = range;
    U.uSonarOrigin.value.copy(origin);
  }

  get sunElevation() {
    return Math.sin((this.dayTime - 0.0) * Math.PI * 2);
  }

  get isNight() { return U.uDaylight.value < 0.3; }

  update(dt, camera, opts) {
    const { inAirPocket, aboveSurface, lampOn } = opts;
    U.uTime.value += dt;
    this.dayTime = (this.dayTime + dt / DAY_LENGTH) % 1;
    const elev = this.sunElevation;
    const az = this.dayTime * Math.PI * 2;
    U.uSunDir.value.set(Math.cos(az) * 0.6, Math.max(0.25, elev), Math.sin(az) * 0.4 - 0.3).normalize();
    U.uDaylight.value = clamp(smoothstep(-0.25, 0.3, elev), 0.0, 1.0);
    const warm = 1 - smoothstep(0.1, 0.5, elev);
    U.uSunColor.value.setRGB(0.75 + warm * 0.25, 0.9 - warm * 0.15, 1.0 - warm * 0.3);

    U.uCamPos.value.copy(camera.position);
    U.uInAir.value = inAirPocket || aboveSurface ? 1 : 0;
    const depth = Math.max(0, -camera.position.y);
    U.uFogDensity.value = 0.0145 + smoothstep(30, 300, depth) * 0.006;

    // surface follows camera
    this.surface.position.set(Math.round(camera.position.x / 50) * 50, 0, Math.round(camera.position.z / 50) * 50);
    this.surface.visible = depth < 260 || aboveSurface;
    this.sky.visible = aboveSurface;
    this.sky.position.copy(camera.position);
    this.rays.visible = !aboveSurface && !inAirPocket && depth < 170;

    const dir = this.snowMat.uniforms.uCamDir.value;
    camera.getWorldDirection(dir);
    this.snowMat.uniforms.uLamp.value = lampOn ? 1 : 0;
    this.snow.visible = !aboveSurface && !inAirPocket;
    this.plankton.visible = !aboveSurface && !inAirPocket;

    // sonar
    if (this.sonar.active) {
      this.sonar.t += dt;
      const r = this.sonar.t * this.sonar.speed;
      U.uSonarRadius.value = r;
      U.uSonarStrength.value = clamp(1 - r / this.sonar.range, 0, 1) * 0.9;
      if (r > this.sonar.range) { this.sonar.active = false; U.uSonarStrength.value = 0; }
    }
    this.bubbles.update(dt);
  }
}

class Bubbles {
  constructor(parent) {
    this.max = 400;
    this.pos = new Float32Array(this.max * 3);
    this.size = new Float32Array(this.max);
    this.vel = new Float32Array(this.max * 3);
    this.life = new Float32Array(this.max);
    this.count = 0;
    this.next = 0;
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    geo.setAttribute('aSize', new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage));
    this.geo = geo;
    this.mat = new THREE.ShaderMaterial({
      uniforms: { uPixel: { value: 1 } },
      transparent: true,
      depthWrite: false,
      vertexShader: /* glsl */`
        attribute float aSize; uniform float uPixel; varying float vA;
        void main() {
          vec4 mv = modelViewMatrix * vec4(position, 1.0);
          vA = step(0.001, aSize) * smoothstep(0.35, 0.9, -mv.z);
          gl_PointSize = min(aSize * uPixel * 600.0 / -mv.z, 48.0);
          gl_Position = projectionMatrix * mv;
        }`,
      fragmentShader: /* glsl */`
        varying float vA;
        void main() {
          vec2 c = gl_PointCoord - 0.5;
          float d = length(c);
          float ring = smoothstep(0.5, 0.42, d) * (smoothstep(0.25, 0.45, d) + 0.15);
          float hl = smoothstep(0.12, 0.0, length(c - vec2(-0.15, -0.15)));
          gl_FragColor = vec4(vec3(0.75, 0.92, 1.0), (ring * 0.5 + hl * 0.8) * vA);
        }`,
    });
    this.points = new THREE.Points(geo, this.mat);
    this.points.frustumCulled = false;
    parent.add(this.points);
  }

  spawn(p, n = 4, spread = 0.15, size = 0.08) {
    for (let k = 0; k < n; k++) {
      const i = this.next;
      this.next = (this.next + 1) % this.max;
      this.pos[i * 3] = p.x + (Math.random() - 0.5) * spread;
      this.pos[i * 3 + 1] = p.y + (Math.random() - 0.5) * spread;
      this.pos[i * 3 + 2] = p.z + (Math.random() - 0.5) * spread;
      this.vel[i * 3] = (Math.random() - 0.5) * 0.3;
      this.vel[i * 3 + 1] = 0.9 + Math.random() * 0.9;
      this.vel[i * 3 + 2] = (Math.random() - 0.5) * 0.3;
      this.size[i] = size * (0.5 + Math.random());
      this.life[i] = 3 + Math.random() * 3;
    }
  }

  update(dt) {
    const t = performance.now() * 0.001;
    for (let i = 0; i < this.max; i++) {
      if (this.life[i] <= 0) { this.size[i] = 0; continue; }
      this.life[i] -= dt;
      this.pos[i * 3] += (this.vel[i * 3] + Math.sin(t * 6 + i) * 0.15) * dt;
      this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt;
      this.pos[i * 3 + 2] += (this.vel[i * 3 + 2] + Math.cos(t * 5 + i) * 0.15) * dt;
      if (this.pos[i * 3 + 1] > -0.05 || this.life[i] <= 0) { this.life[i] = 0; this.size[i] = 0; }
    }
    this.geo.attributes.position.needsUpdate = true;
    this.geo.attributes.aSize.needsUpdate = true;
  }
}
