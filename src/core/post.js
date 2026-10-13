// Post-processing: world pass, first-person equipment pass, bloom for
// bioluminescence, and a final underwater lens (distortion, vignette, grain).

import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

const LensShader = {
  uniforms: {
    tDiffuse: { value: null },
    uTime: { value: 0 },
    uUnderwater: { value: 1 },
    uHurt: { value: 0 },
    uLowO2: { value: 0 },
    uFade: { value: 0 },
    uWhite: { value: 0 },
    uAspect: { value: 1 },
  },
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
  fragmentShader: /* glsl */`
    uniform sampler2D tDiffuse; uniform float uTime; uniform float uUnderwater; uniform float uHurt; uniform float uLowO2; uniform float uFade; uniform float uWhite; uniform float uAspect;
    varying vec2 vUv;
    float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
    void main() {
      vec2 uv = vUv;
      vec2 c = uv - 0.5;
      float r2 = dot(c * vec2(uAspect, 1.0), c * vec2(uAspect, 1.0));
      // gentle refraction wobble underwater
      uv += uUnderwater * vec2(sin(uv.y * 18.0 + uTime * 1.3), cos(uv.x * 16.0 + uTime * 1.1)) * 0.0011;
      // chromatic aberration grows toward the visor edge
      float ca = (0.0012 + r2 * 0.006) * (1.0 + uHurt * 3.0);
      vec3 col;
      col.r = texture2D(tDiffuse, uv + c * ca).r;
      col.g = texture2D(tDiffuse, uv).g;
      col.b = texture2D(tDiffuse, uv - c * ca).b;
      // low oxygen: desaturate + tunnel vision
      float l = dot(col, vec3(0.299, 0.587, 0.114));
      col = mix(col, vec3(l), uLowO2 * 0.7);
      col *= 1.0 - smoothstep(0.08, 0.5, r2) * uLowO2 * 0.9;
      // hurt tint
      col = mix(col, col * vec3(1.4, 0.55, 0.5), uHurt * 0.6);
      // vignette
      col *= 1.0 - smoothstep(0.25, 0.9, r2) * 0.45;
      // grain
      col += (hash(uv * 1000.0 + uTime) - 0.5) * 0.018;
      col = mix(col, vec3(0.0), uFade);
      col = mix(col, vec3(1.0), uWhite);
      gl_FragColor = vec4(col, 1.0);
    }`,
};

export class Post {
  constructor(renderer, scene, viewScene, camera) {
    this.renderer = renderer;
    this.composer = new EffectComposer(renderer);
    this.worldPass = new RenderPass(scene, camera);
    this.composer.addPass(this.worldPass);
    this.vmPass = new RenderPass(viewScene, camera);
    this.vmPass.clear = false;
    this.vmPass.clearDepth = true;
    this.composer.addPass(this.vmPass);
    this.bloom = new UnrealBloomPass(new THREE.Vector2(512, 512), 0.6, 0.5, 0.82);
    this.composer.addPass(this.bloom);
    this.lens = new ShaderPass(LensShader);
    this.composer.addPass(this.lens);
    this.composer.addPass(new OutputPass());
  }

  setSize(w, h, pr) {
    this.composer.setPixelRatio(pr);
    this.composer.setSize(w, h);
    this.bloom.resolution.set(w * pr * 0.5, h * pr * 0.5);
    this.lens.uniforms.uAspect.value = w / h;
  }

  setQuality(q) { this.bloom.enabled = q !== 'low'; }

  render(dt) {
    this.lens.uniforms.uTime.value += dt;
    this.composer.render(dt);
  }
}
