// Pre-filtered environment maps for image-based reflections.
//  - water: procedural light field of the shallow ocean (bright Snell's window
//    above, teal haze at the horizon, dark seabed below). The shader patch
//    attenuates it per pixel with depth, so one map serves every depth.
//  - interior: the CC0 "lab" HDRI for Meridian Station's air pocket.

import * as THREE from 'three';

export function buildEnvironmentMaps(renderer, assets) {
  const pmrem = new THREE.PMREMGenerator(renderer);
  const scene = new THREE.Scene();
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide,
    depthWrite: false,
    vertexShader: 'varying vec3 vDir; void main(){ vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
    fragmentShader: /* glsl */`
      varying vec3 vDir;
      void main() {
        vec3 d = normalize(vDir);
        vec3 horizon = vec3(0.06, 0.26, 0.33);
        vec3 seabed = vec3(0.035, 0.05, 0.05);
        vec3 col = mix(horizon, seabed, smoothstep(0.0, -0.6, d.y));
        // brighter water column toward the surface, then Snell's window
        col = mix(col, vec3(0.16, 0.48, 0.56), smoothstep(0.0, 0.7, d.y));
        col += vec3(0.9, 1.0, 1.0) * smoothstep(0.72, 0.8, d.y) * 1.6;
        col += vec3(1.4, 1.3, 1.1) * pow(max(d.y, 0.0), 64.0) * 4.0;
        gl_FragColor = vec4(col, 1.0);
      }`,
  });
  scene.add(new THREE.Mesh(new THREE.SphereGeometry(10, 48, 24), mat));
  const water = pmrem.fromScene(scene, 0.02, 0.1, 50).texture;
  let interior = null;
  const hdr = assets.envTexture('interior');
  if (hdr) {
    hdr.mapping = THREE.EquirectangularReflectionMapping;
    interior = pmrem.fromEquirectangular(hdr).texture;
  }
  mat.dispose();
  pmrem.dispose();
  return { water, interior };
}
