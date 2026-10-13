// First-person diver: swimming physics, surfacing, collision and camera.

import * as THREE from 'three';
import { BOUNDARY } from '../world/layout.js';
import { clamp } from '../core/noise.js';

export const PLAYER_RADIUS = 0.45;
const _f = new THREE.Vector3();
const _r = new THREE.Vector3();
const _a = new THREE.Vector3();

export class Player {
  constructor(camera, collision) {
    this.camera = camera;
    this.collision = collision;
    this.pos = new THREE.Vector3(0, -20, 0);
    this.vel = new THREE.Vector3();
    this.yaw = 0;
    this.pitch = 0;
    this.roll = 0;
    this.bob = 0;
    this.speed = 0;
    this.surfaced = false;
    this.inAirPocket = false;
    this.aboveSurface = false;
    this.waterLevel = 0;
    this.boundaryWarning = 0;
    this.sprinting = false;
    this.lastSplash = 0;
  }

  place(p, yaw = this.yaw, pitch = 0) {
    this.pos.copy(p);
    this.vel.set(0, 0, 0);
    this.yaw = yaw;
    this.pitch = pitch;
  }

  look(dx, dy, settings) {
    const s = 0.0022 * settings.sensitivity;
    this.yaw -= dx * s;
    this.pitch -= dy * s * (settings.invertY ? -1 : 1);
    this.pitch = clamp(this.pitch, -1.5, 1.5);
  }

  /** opts: { input, settings, speedMult, frozen } */
  update(dt, input, settings, speedMult = 1, events) {
    const level = this.collision.waterLevelAt(this.pos);
    this.waterLevel = level;
    const nearSurface = this.pos.y > level - 0.6;

    // input direction
    const cp = Math.cos(this.pitch);
    _f.set(-Math.sin(this.yaw) * cp, Math.sin(this.pitch), -Math.cos(this.yaw) * cp);
    _r.set(Math.cos(this.yaw), 0, -Math.sin(this.yaw));
    _a.set(0, 0, 0);
    if (input.held('forward')) _a.add(_f);
    if (input.held('back')) _a.sub(_f);
    if (input.held('right')) _a.add(_r);
    if (input.held('left')) _a.sub(_r);
    if (input.held('up')) _a.y += 1;
    if (input.held('down')) _a.y -= 1;
    // at the surface, forward motion stays level unless diving deliberately
    if (nearSurface && _a.y > 0 && !input.held('down') && this.pitch > -0.45) _a.y = Math.min(_a.y, 0.0);
    if (_a.lengthSq() > 1) _a.normalize();

    this.sprinting = input.held('sprint') && _a.lengthSq() > 0.01;
    const maxSpeed = 5.2 * speedMult * (this.sprinting ? 1.55 : 1);
    const accel = maxSpeed * 3.6;
    this.vel.addScaledVector(_a, accel * dt);
    const drag = accel / maxSpeed;
    this.vel.multiplyScalar(Math.exp(-drag * dt * (_a.lengthSq() > 0.01 ? 1 : 0.8)));

    // gentle negative buoyancy when idle underwater
    if (!nearSurface && _a.lengthSq() < 0.01) this.vel.y -= 0.12 * dt;
    // floating at the surface (spring toward the waterline)
    if (nearSurface && !input.held('down')) {
      const target = level + 0.16 + Math.sin(performance.now() * 0.0016) * 0.06;
      if (this.pos.y > level - 1.4) {
        this.vel.y += (target - this.pos.y) * 7 * dt;
        this.vel.y *= Math.exp(-3 * dt);
      }
    }

    // world boundary: strong currents push back
    const edge = Math.max(Math.abs(this.pos.x), Math.abs(this.pos.z));
    this.boundaryWarning = Math.max(0, (edge - (BOUNDARY - 60)) / 60);
    if (edge > BOUNDARY) {
      const push = (edge - BOUNDARY) * 0.6 + 2;
      _r.set(-this.pos.x, 0, -this.pos.z).normalize();
      this.vel.addScaledVector(_r, push * dt * 4);
    }

    this.pos.addScaledVector(this.vel, dt);
    // never rise above the water line + head height
    if (this.pos.y > level + 0.32) { this.pos.y = level + 0.32; if (this.vel.y > 0) this.vel.y = 0; }
    this.collision.resolve(this.pos, PLAYER_RADIUS, this.vel);

    const wasSurfaced = this.surfaced;
    this.surfaced = this.pos.y > level - 0.05;
    this.inAirPocket = level !== 0 && this.surfaced;
    this.aboveSurface = level === 0 && this.pos.y > 0.02;
    if (this.surfaced !== wasSurfaced && performance.now() - this.lastSplash > 800) {
      this.lastSplash = performance.now();
      events?.emit('splash', { up: this.surfaced });
    }
    this.speed = this.vel.length();

    // camera
    const lateral = this.vel.dot(_r.set(Math.cos(this.yaw), 0, -Math.sin(this.yaw)));
    this.roll = THREE.MathUtils.lerp(this.roll, -lateral * 0.012, 1 - Math.exp(-dt * 5));
    this.bob += dt * (0.8 + this.speed * 0.45);
    const bobAmt = settings.headBob ? Math.min(1, this.speed / 5) * 0.035 : 0;
    this.applyCamera(bobAmt);
  }

  applyCamera(bobAmt = 0) {
    const cam = this.camera;
    cam.position.copy(this.pos);
    cam.position.y += Math.sin(this.bob * 2) * bobAmt;
    cam.rotation.order = 'YXZ';
    cam.rotation.set(this.pitch + Math.sin(this.bob) * bobAmt * 0.3, this.yaw, this.roll + Math.cos(this.bob) * bobAmt * 0.4);
  }

  get depth() { return Math.max(0, -this.pos.y); }
}
