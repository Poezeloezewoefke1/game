// External asset layer. Loads optional glTF models (and the reflection HDRI)
// listed in MODEL_MANIFEST. Every consumer must keep its procedural version as
// a fallback: if a file is missing, fails to load or the player starts with
// `?classic`, get() returns null and the original geometry is used.
//
// To replace an asset with your own model, drop a .glb into public/models/
// and point the matching manifest entry at it. Models are normalised to the
// size, pivot and facing the game expects (see `fit`).

import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { EXRLoader } from 'three/addons/loaders/EXRLoader.js';

/**
 * id -> { url, license, forward ('+z' | '-z'), notes }
 * `forward` is the axis the model's front faces in its own mesh data.
 */
export const MODEL_MANIFEST = {
  glimmerfin: { url: 'models/glimmerfin.glb', license: 'CC0 1.0 (Khronos BarramundiFish)', forward: '+z' }, // node rotation already turns the head to +z
  crewHelmet: { url: 'models/helmet_crew.glb', license: 'CC0 1.0 (Khronos SciFiHelmet)', forward: '+z' },
  abalone: { url: 'models/abalone.glb', license: 'CC BY 4.0 (Khronos IridescenceAbalone)', forward: '+z' },
  bottle: { url: 'models/bottle.glb', license: 'CC0 1.0 (Khronos WaterBottle)', forward: '+z' },
  radio: { url: 'models/radio.glb', license: 'CC0 1.0 (Khronos BoomBox)', forward: '+z' },
};

export const ENV_MAPS = {
  interior: { url: 'textures/env/lab.exr', license: 'CC0 1.0 (@pmndrs/assets)' },
};

const TIMEOUT_MS = 20000;

function withTimeout(promise, ms) {
  return Promise.race([promise, new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), ms))]);
}

/** Run every material in a loaded model through a material adapter (e.g. the underwater patch). */
export function adaptMaterials(object, adapt) {
  const seen = new Map();
  object.traverse((o) => {
    if (!o.isMesh) return;
    const conv = (m) => { if (!seen.has(m)) seen.set(m, adapt(m.clone())); return seen.get(m); };
    o.material = Array.isArray(o.material) ? o.material.map(conv) : conv(o.material);
  });
  return object;
}

export class AssetLibrary {
  constructor({ enabled = true } = {}) {
    this.enabled = enabled;
    this.models = new Map();
    this.env = new Map();
    this.failures = [];
    this.disabled = new Set(); // ids skipped for performance (e.g. Low quality)
  }

  disable(id) { this.disabled.add(id); }

  async preload(onProgress) {
    if (!this.enabled) return;
    const gltf = new GLTFLoader();
    const exr = new EXRLoader();
    const jobs = [
      ...Object.entries(MODEL_MANIFEST).map(([id, m]) => ['model', id, m.url, () => gltf.loadAsync(m.url)]),
      ...Object.entries(ENV_MAPS).map(([id, m]) => ['env', id, m.url, () => exr.loadAsync(m.url)]),
    ];
    let done = 0;
    await Promise.all(jobs.map(async ([kind, id, url, load]) => {
      try {
        const res = await withTimeout(load(), TIMEOUT_MS);
        (kind === 'model' ? this.models : this.env).set(id, res);
      } catch (err) {
        this.failures.push({ id, url, error: String(err?.message || err) });
        console.warn(`[assets] ${url} unavailable, using procedural fallback (${err?.message || err})`);
      } finally {
        onProgress?.(++done / jobs.length);
      }
    }));
  }

  has(id) { return this.models.has(id) && !this.disabled.has(id); }

  /** A fresh copy of the model's scene graph, or null. */
  instance(id) {
    const g = this.has(id) ? this.models.get(id) : null;
    return g ? g.scene.clone(true) : null;
  }

  /**
   * First mesh of a model as { geometry, material } with the node transform
   * baked in (for InstancedMesh use), or null.
   */
  meshData(id) {
    const g = this.has(id) ? this.models.get(id) : null;
    if (!g) return null;
    let found = null;
    g.scene.updateMatrixWorld(true);
    g.scene.traverse((o) => { if (!found && o.isMesh) found = o; });
    if (!found) return null;
    const geometry = found.geometry.clone();
    geometry.applyMatrix4(found.matrixWorld);
    return { geometry, material: found.material };
  }

  envTexture(id) { return this.env.get(id) || null; }
}

/**
 * Normalise a model so it faces +z, is centred on its pivot and spans `length`
 * metres along its longest horizontal axis. Works on Object3D or geometry.
 * pivot: 'center' | 'base' (bottom of the bounding box at y = 0)
 */
export function fit(target, { forward = '+z', length = 1, height = 0, pivot = 'center' } = {}) {
  const isGeo = target.isBufferGeometry;
  if (forward === '-z') {
    if (isGeo) target.rotateY(Math.PI); else target.rotateY(Math.PI);
  }
  const box = new THREE.Box3();
  if (isGeo) { target.computeBoundingBox(); box.copy(target.boundingBox); } else { target.updateMatrixWorld(true); box.setFromObject(target); }
  const size = box.getSize(new THREE.Vector3());
  const s = height ? height / Math.max(size.y, 1e-6) : length / Math.max(size.x, size.z, 1e-6);
  const c = box.getCenter(new THREE.Vector3());
  const offset = new THREE.Vector3(-c.x, pivot === 'base' ? -box.min.y : -c.y, -c.z);
  if (isGeo) {
    target.translate(offset.x, offset.y, offset.z);
    target.scale(s, s, s);
    target.computeBoundingBox();
    target.computeBoundingSphere();
    return target;
  }
  const wrap = new THREE.Group();
  target.position.add(offset);
  wrap.add(target);
  wrap.scale.setScalar(s);
  return wrap;
}
