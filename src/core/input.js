// Keyboard + mouse input with pointer lock. Actions are queried by name so
// controls can be documented in one place.

export const BINDINGS = {
  forward: ['KeyW', 'ArrowUp'],
  back: ['KeyS', 'ArrowDown'],
  left: ['KeyA', 'ArrowLeft'],
  right: ['KeyD', 'ArrowRight'],
  up: ['Space'],
  down: ['KeyC', 'ControlLeft'],
  sprint: ['ShiftLeft', 'ShiftRight'],
  interact: ['KeyE'],
  scan: ['KeyF'],
  sonar: ['KeyQ'],
  lamp: ['KeyL'],
  pda: ['Tab'],
  map: ['KeyM'],
  medkit: ['KeyH'],
  pause: ['Escape', 'KeyP'],
};

export class Input {
  constructor(canvas) {
    this.canvas = canvas;
    this.down = new Set();
    this.pressed = new Set();
    this.mouseDX = 0;
    this.mouseDY = 0;
    this.mouseButtons = new Set();
    this.mousePressed = new Set();
    this.locked = false;
    this.enabled = true;
    this.onLockChange = null;
    this.lockRequestedAt = 0;

    window.addEventListener('keydown', (e) => {
      if (e.code === 'Tab' || e.code === 'Space' || e.code.startsWith('Arrow')) e.preventDefault();
      if (!this.down.has(e.code)) this.pressed.add(e.code);
      this.down.add(e.code);
    });
    window.addEventListener('keyup', (e) => { this.down.delete(e.code); });
    window.addEventListener('blur', () => { this.down.clear(); this.mouseButtons.clear(); });
    window.addEventListener('mousemove', (e) => {
      if (!this.locked) return;
      this.mouseDX += e.movementX || 0;
      this.mouseDY += e.movementY || 0;
    });
    window.addEventListener('mousedown', (e) => {
      if (!this.locked) return;
      this.mouseButtons.add(e.button);
      this.mousePressed.add(e.button);
    });
    window.addEventListener('mouseup', (e) => { this.mouseButtons.delete(e.button); });
    window.addEventListener('contextmenu', (e) => { if (this.locked) e.preventDefault(); });
    document.addEventListener('pointerlockchange', () => {
      this.locked = document.pointerLockElement === this.canvas;
      if (!this.locked) this.mouseButtons.clear();
      this.onLockChange?.(this.locked);
    });
  }

  lock() {
    this.lockRequestedAt = performance.now();
    if (this.locked) return;
    try {
      const p = this.canvas.requestPointerLock?.();
      if (p && p.catch) p.catch(() => {});
    } catch (e) { /* not available (e.g. headless) */ }
  }

  unlock() {
    if (document.pointerLockElement) document.exitPointerLock();
  }

  held(action) {
    if (!this.enabled) return false;
    if (action === 'scan' && this.mouseButtons.has(2)) return true;
    return BINDINGS[action].some((k) => this.down.has(k));
  }

  hit(action) {
    if (!this.enabled) return false;
    if (action === 'interact' && this.mousePressed.has(0)) return true;
    return BINDINGS[action].some((k) => this.pressed.has(k));
  }

  /** Simulated input for automated tests. */
  simulate(code, isDown) {
    if (isDown) { if (!this.down.has(code)) this.pressed.add(code); this.down.add(code); } else this.down.delete(code);
  }

  consumeMouse() {
    const d = [this.mouseDX, this.mouseDY];
    this.mouseDX = 0; this.mouseDY = 0;
    return d;
  }

  endFrame() {
    this.pressed.clear();
    this.mousePressed.clear();
  }
}
