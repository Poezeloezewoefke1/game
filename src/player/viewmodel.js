// First-person equipment: gloved hand holding the scanner, the wrist PDA,
// and the scan beam. Rendered in a separate scene over the world.

import * as THREE from 'three';

export class ViewModel {
  constructor() {
    this.scene = new THREE.Scene();
    this.root = new THREE.Group();
    this.scene.add(this.root);
    this.hemi = new THREE.HemisphereLight(0x9fd8e8, 0x0a1a24, 1.2);
    this.scene.add(this.hemi);
    this.lamp = new THREE.PointLight(0xe8f6ff, 1.5, 3, 1.5);
    this.lamp.position.set(0.1, 0.25, 0.1);
    this.root.add(this.lamp);
    this.sway = new THREE.Vector2();
    this.reach = 0;
    this.pdaRaise = 0;
    this.scanPulse = 0;
    this.build();
  }

  build() {
    const suit = new THREE.MeshStandardMaterial({ color: 0xd9d6cc, roughness: 0.75 });
    const glove = new THREE.MeshStandardMaterial({ color: 0x3a3f45, roughness: 0.8 });
    const orange = new THREE.MeshStandardMaterial({ color: 0xd8692a, roughness: 0.6 });
    const dev = new THREE.MeshStandardMaterial({ color: 0x23292f, roughness: 0.45, metalness: 0.5 });
    this.emitMat = new THREE.MeshStandardMaterial({ color: 0x062028, emissive: 0x5fe8ff, emissiveIntensity: 1.5 });

    // ---- right hand + scanner
    const hand = new THREE.Group();
    hand.position.set(0.24, -0.23, -0.44);
    hand.rotation.set(0.05, -0.18, 0.04);
    this.hand = hand;
    this.handBase = hand.position.clone();
    this.root.add(hand);
    const limb = (a, b, r0, r1, mat) => {
      const A = new THREE.Vector3(...a), B = new THREE.Vector3(...b);
      const m = new THREE.Mesh(new THREE.CylinderGeometry(r1, r0, A.distanceTo(B), 14), mat);
      m.position.copy(A).add(B).multiplyScalar(0.5);
      m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), B.clone().sub(A).normalize());
      hand.add(m);
      return m;
    };
    // forearm runs down and back out of frame
    limb([0.06, -0.33, 0.42], [0.02, -0.06, 0.06], 0.075, 0.05, suit);
    limb([0.03, -0.09, 0.1], [0.018, -0.055, 0.055], 0.058, 0.056, orange);
    // glove wrapped around the grip
    const palm = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.075, 0.075), glove);
    palm.position.set(0.012, -0.035, 0.0);
    palm.rotation.x = 0.2;
    hand.add(palm);
    for (let i = 0; i < 4; i++) {
      const f = new THREE.Mesh(new THREE.CapsuleGeometry(0.011, 0.045, 4, 6), glove);
      f.rotation.z = Math.PI / 2;
      f.position.set(-0.018, -0.012 - i * 0.018, -0.03);
      hand.add(f);
    }
    const thumb = new THREE.Mesh(new THREE.CapsuleGeometry(0.012, 0.045, 4, 6), glove);
    thumb.rotation.set(1.1, 0, 0.5);
    thumb.position.set(-0.022, 0.012, -0.012);
    hand.add(thumb);
    // scanner: compact body on top of a grip
    const grip = new THREE.Mesh(new THREE.BoxGeometry(0.032, 0.08, 0.04), dev);
    grip.position.set(-0.004, -0.03, -0.03);
    grip.rotation.x = 0.25;
    hand.add(grip);
    const body = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.05, 0.15), dev);
    body.position.set(-0.004, 0.026, -0.07);
    hand.add(body);
    const cap = new THREE.Mesh(new THREE.BoxGeometry(0.066, 0.012, 0.09), orange);
    cap.position.set(-0.004, 0.052, -0.035);
    hand.add(cap);
    const nose = new THREE.Mesh(new THREE.CylinderGeometry(0.026, 0.032, 0.04, 18), dev);
    nose.rotation.x = Math.PI / 2;
    nose.position.set(-0.004, 0.026, -0.163);
    hand.add(nose);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.023, 0.004, 8, 24), this.emitMat);
    ring.position.set(-0.004, 0.026, -0.184);
    hand.add(ring);
    const lens = new THREE.Mesh(new THREE.CircleGeometry(0.018, 16), this.emitMat);
    lens.position.set(-0.004, 0.026, -0.1835);
    lens.rotation.y = Math.PI;
    hand.add(lens);
    const strip = new THREE.Mesh(new THREE.BoxGeometry(0.003, 0.008, 0.1), this.emitMat);
    strip.position.set(0.027, 0.03, -0.075);
    hand.add(strip);
    // screen on top of scanner
    this.screenCanvas = document.createElement('canvas');
    this.screenCanvas.width = 128; this.screenCanvas.height = 64;
    this.screenTex = new THREE.CanvasTexture(this.screenCanvas);
    this.screenTex.colorSpace = THREE.SRGBColorSpace;
    const scr = new THREE.Mesh(new THREE.PlaneGeometry(0.046, 0.023), new THREE.MeshBasicMaterial({ map: this.screenTex, toneMapped: false }));
    scr.rotation.x = -Math.PI / 2 + 0.2;
    scr.position.set(-0.004, 0.0515, -0.105);
    hand.add(scr);
    this.emitter = new THREE.Object3D();
    this.emitter.position.set(-0.004, 0.026, -0.19);
    hand.add(this.emitter);

    // ---- scan beam (world-space-ish cone attached to the emitter)
    const beamGeo = new THREE.CylinderGeometry(0.004, 0.25, 1, 20, 1, true);
    beamGeo.translate(0, -0.5, 0);
    beamGeo.rotateX(Math.PI / 2); // extends along -z
    this.beamMat = new THREE.ShaderMaterial({
      uniforms: { uTime: { value: 0 }, uStrength: { value: 0 } },
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
      fragmentShader: `uniform float uTime; uniform float uStrength; varying vec2 vUv;
        void main(){
          float lines = smoothstep(0.6, 1.0, sin(vUv.y * 60.0 - uTime * 18.0) * 0.5 + 0.5);
          float edge = pow(abs(sin(vUv.x * 3.14159)), 0.5);
          float a = (0.12 + lines * 0.5) * edge * uStrength * (1.0 - vUv.y * 0.2);
          gl_FragColor = vec4(vec3(0.35, 0.9, 1.0) * a, 1.0);
        }`,
    });
    this.beam = new THREE.Mesh(beamGeo, this.beamMat);
    this.beam.visible = false;
    this.emitter.add(this.beam);

    // ---- left wrist PDA
    const left = new THREE.Group();
    left.position.set(-0.32, -0.75, -0.5);
    this.left = left;
    this.root.add(left);
    const larm = new THREE.Mesh(new THREE.CylinderGeometry(0.055, 0.07, 0.5, 14), suit);
    larm.rotation.x = Math.PI / 2 - 0.6;
    larm.position.set(0, -0.08, 0.2);
    left.add(larm);
    const wrist = new THREE.Mesh(new THREE.BoxGeometry(0.11, 0.035, 0.12), dev);
    wrist.position.set(0, 0.03, -0.02);
    wrist.rotation.x = 0.6;
    left.add(wrist);
    const pdaScreen = new THREE.Mesh(new THREE.PlaneGeometry(0.09, 0.09), this.emitMat);
    pdaScreen.rotation.x = -Math.PI / 2 + 0.6;
    pdaScreen.position.set(0, 0.049, -0.02);
    left.add(pdaScreen);
    const lglove = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.05, 0.1), glove);
    lglove.position.set(0, -0.01, -0.11);
    lglove.rotation.x = 0.6;
    left.add(lglove);
  }

  drawScreen(text, progress, color = '#5fe8ff') {
    const c = this.screenCanvas.getContext('2d');
    c.fillStyle = '#031016';
    c.fillRect(0, 0, 128, 64);
    c.fillStyle = color;
    c.font = '600 13px "IBM Plex Mono", monospace';
    c.fillText(text.slice(0, 14), 6, 22);
    c.fillStyle = 'rgba(95,232,255,0.25)';
    c.fillRect(6, 38, 116, 10);
    c.fillStyle = color;
    c.fillRect(6, 38, 116 * Math.max(0, Math.min(1, progress)), 10);
    this.screenTex.needsUpdate = true;
  }

  pickup() { this.reach = 1; }

  attachCockpit(group) {
    this.cockpit = group;
    this.root.add(group);
  }

  update(dt, camera, opts) {
    const { mouse, speed, bob, scanning, scanTarget, visible, pdaOpen, lampOn, ambient, time, cockpit } = opts;
    this.root.visible = visible || !!cockpit;
    this.hand.visible = visible;
    if (this.cockpit) this.cockpit.visible = !!cockpit;
    this.root.position.copy(camera.position);
    this.root.quaternion.copy(camera.quaternion);
    this.root.updateMatrixWorld(true);
    // sway lags behind look motion
    this.sway.x = THREE.MathUtils.lerp(this.sway.x, -mouse[0] * 0.0006, 1 - Math.exp(-dt * 8));
    this.sway.y = THREE.MathUtils.lerp(this.sway.y, mouse[1] * 0.0006, 1 - Math.exp(-dt * 8));
    this.reach = Math.max(0, this.reach - dt * 3);
    const r = Math.sin(this.reach * Math.PI);
    this.scanPulse = THREE.MathUtils.lerp(this.scanPulse, scanning ? 1 : 0, 1 - Math.exp(-dt * 10));
    const bobA = Math.min(1, speed / 6);
    this.hand.position.set(
      this.handBase.x + this.sway.x + Math.cos(bob) * 0.008 * bobA - r * 0.06,
      this.handBase.y + this.sway.y + Math.sin(bob * 2) * 0.01 * bobA + this.scanPulse * 0.03 + Math.sin(time * 1.3) * 0.004,
      this.handBase.z - r * 0.15 - this.scanPulse * 0.06,
    );
    this.hand.rotation.y = -0.12 - this.scanPulse * 0.1 + this.sway.x;
    this.pdaRaise = THREE.MathUtils.lerp(this.pdaRaise, pdaOpen ? 1 : 0, 1 - Math.exp(-dt * 9));
    this.left.position.set(-0.32 + this.pdaRaise * 0.18, -0.75 + this.pdaRaise * 0.42, -0.5);
    this.left.visible = visible && this.pdaRaise > 0.02;
    this.emitMat.emissiveIntensity = 1.2 + this.scanPulse * 2 + Math.sin(time * 4) * 0.2;
    this.hemi.intensity = ambient;
    this.lamp.intensity = lampOn ? 1.6 : 0.05;
    // beam
    if (scanning && scanTarget) {
      this.beam.visible = true;
      const wp = new THREE.Vector3();
      this.emitter.getWorldPosition(wp);
      const dist = wp.distanceTo(scanTarget);
      this.emitter.lookAt(scanTarget);
      this.emitter.rotateY(Math.PI); // cone extends along -z
      this.beam.scale.set(1 + dist * 0.15, 1 + dist * 0.15, dist);
      this.beamMat.uniforms.uStrength.value = this.scanPulse;
    } else {
      this.beam.visible = false;
      this.emitter.rotation.set(0, 0, 0);
    }
    this.beamMat.uniforms.uTime.value = time;
  }
}
