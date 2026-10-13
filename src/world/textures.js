// Canvas-generated textures (no external image assets).

import * as THREE from 'three';
import { mulberry32 } from '../core/noise.js';

function canvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return [c, c.getContext('2d')];
}

function toTex(c, repeat = 1, srgb = true) {
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeat, repeat);
  t.anisotropy = 4;
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

/** Hull panels with seams, rivets and grime. */
export function panelTexture(base = '#d8dbd5', seed = 1, grime = 0.35) {
  const [c, g] = canvas(512, 512);
  const rnd = mulberry32(seed);
  g.fillStyle = base;
  g.fillRect(0, 0, 512, 512);
  // subtle tonal variation per panel
  const rows = 4, cols = 4;
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      const v = (rnd() - 0.5) * 18;
      g.fillStyle = `rgba(${v > 0 ? 255 : 0},${v > 0 ? 255 : 0},${v > 0 ? 255 : 0},${Math.abs(v) / 255})`;
      g.fillRect(x * 128, y * 128, 128, 128);
    }
  }
  g.strokeStyle = 'rgba(30,35,40,0.55)';
  g.lineWidth = 2;
  for (let i = 0; i <= 4; i++) {
    g.beginPath(); g.moveTo(i * 128, 0); g.lineTo(i * 128, 512); g.stroke();
    g.beginPath(); g.moveTo(0, i * 128); g.lineTo(512, i * 128); g.stroke();
  }
  // rivets
  g.fillStyle = 'rgba(40,45,50,0.5)';
  for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) {
    for (let k = 0; k < 6; k++) {
      g.beginPath(); g.arc(x * 128 + 8 + k * 22, y * 128 + 8, 1.6, 0, 7); g.fill();
      g.beginPath(); g.arc(x * 128 + 8, y * 128 + 8 + k * 22, 1.6, 0, 7); g.fill();
    }
  }
  // hatch/vent details
  for (let i = 0; i < 5; i++) {
    const x = Math.floor(rnd() * 4) * 128 + 30, y = Math.floor(rnd() * 4) * 128 + 40;
    g.strokeStyle = 'rgba(30,35,40,0.45)';
    g.strokeRect(x, y, 60, 40);
    for (let k = 0; k < 5; k++) { g.beginPath(); g.moveTo(x + 6, y + 6 + k * 7); g.lineTo(x + 54, y + 6 + k * 7); g.stroke(); }
  }
  // grime streaks
  for (let i = 0; i < 160 * grime; i++) {
    const x = rnd() * 512, y = rnd() * 512, l = 20 + rnd() * 120;
    const grad = g.createLinearGradient(x, y, x, y + l);
    grad.addColorStop(0, `rgba(40,60,50,${0.25 * grime})`);
    grad.addColorStop(1, 'rgba(40,60,50,0)');
    g.fillStyle = grad;
    g.fillRect(x, y, 2 + rnd() * 6, l);
  }
  return toTex(c);
}

/** Dark Veyru stone with carved glyph grooves; returns { map, emissive }. */
export function glyphTextures(seed = 3) {
  const rnd = mulberry32(seed);
  const [c, g] = canvas(512, 512);
  const [e, ge] = canvas(512, 512);
  g.fillStyle = '#2a3040';
  g.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 2500; i++) {
    g.fillStyle = `rgba(${rnd() < 0.5 ? '255,255,255' : '0,0,0'},${rnd() * 0.05})`;
    g.fillRect(rnd() * 512, rnd() * 512, 2 + rnd() * 12, 2 + rnd() * 12);
  }
  ge.fillStyle = '#000';
  ge.fillRect(0, 0, 512, 512);
  const cell = 64;
  for (let y = 0; y < 512; y += cell) {
    for (let x = 0; x < 512; x += cell) {
      if (rnd() < 0.18) continue;
      const cx = x + cell / 2, cy = y + cell / 2;
      const strokes = 2 + Math.floor(rnd() * 3);
      for (const ctx of [g, ge]) {
        ctx.save();
        ctx.lineCap = 'round';
        ctx.lineWidth = ctx === g ? 5 : 2.5;
        ctx.strokeStyle = ctx === g ? 'rgba(10,12,20,0.9)' : 'rgba(255,255,255,0.95)';
        const r2 = mulberry32(Math.floor(x * 7 + y * 13 + seed));
        // circle/arc motif
        ctx.beginPath();
        const a0 = r2() * Math.PI * 2;
        ctx.arc(cx, cy, 10 + r2() * 14, a0, a0 + Math.PI * (0.8 + r2()));
        ctx.stroke();
        for (let s = 0; s < strokes; s++) {
          ctx.beginPath();
          const a = r2() * Math.PI * 2;
          const r = 6 + r2() * 20;
          ctx.moveTo(cx + Math.cos(a) * 4, cy + Math.sin(a) * 4);
          ctx.lineTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r);
          ctx.stroke();
          if (r2() < 0.6) {
            ctx.beginPath();
            ctx.arc(cx + Math.cos(a) * r, cy + Math.sin(a) * r, 2.5, 0, 7);
            ctx.stroke();
          }
        }
        ctx.restore();
      }
    }
  }
  // flowing channel lines
  for (let k = 0; k < 4; k++) {
    const y0 = rnd() * 512;
    for (const ctx of [g, ge]) {
      ctx.beginPath();
      ctx.lineWidth = ctx === g ? 6 : 3;
      ctx.strokeStyle = ctx === g ? 'rgba(8,10,16,0.9)' : 'rgba(255,255,255,0.8)';
      ctx.moveTo(0, y0);
      for (let x = 0; x <= 512; x += 16) ctx.lineTo(x, y0 + Math.sin(x * 0.02 + k) * 18);
      ctx.stroke();
    }
  }
  return { map: toTex(c), emissive: toTex(e, 1, true) };
}

/** Stencilled label on transparent background. */
export function labelTexture(text, color = '#e8742c', w = 1024, h = 192, font = 'bold 120px "Space Grotesk", sans-serif') {
  const [c, g] = canvas(w, h);
  g.clearRect(0, 0, w, h);
  g.font = font;
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillStyle = color;
  g.fillText(text, w / 2, h / 2 + 6);
  // weathering
  const rnd = mulberry32(text.length * 31);
  g.globalCompositeOperation = 'destination-out';
  for (let i = 0; i < 260; i++) {
    g.fillStyle = `rgba(0,0,0,${rnd() * 0.6})`;
    g.fillRect(rnd() * w, rnd() * h, 2 + rnd() * 8, 2 + rnd() * 5);
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

/** Glowing console screen with fake UI lines. */
export function screenTexture(seed = 1, hue = '#5fe3ff') {
  const [c, g] = canvas(256, 160);
  const rnd = mulberry32(seed);
  g.fillStyle = '#04121a';
  g.fillRect(0, 0, 256, 160);
  g.strokeStyle = hue;
  g.fillStyle = hue;
  g.globalAlpha = 0.85;
  g.lineWidth = 1.5;
  g.strokeRect(6, 6, 244, 148);
  for (let i = 0; i < 9; i++) {
    g.globalAlpha = 0.35 + rnd() * 0.5;
    g.fillRect(14, 16 + i * 14, 30 + rnd() * 120, 5);
  }
  g.globalAlpha = 0.9;
  g.beginPath();
  for (let x = 0; x < 90; x++) g.lineTo(150 + x, 110 + Math.sin(x * 0.25 + seed) * 18 * Math.sin(x * 0.05));
  g.stroke();
  g.beginPath();
  g.arc(196, 50, 26, 0, 7);
  g.stroke();
  g.beginPath();
  g.arc(196, 50, 26, -1.2, 1.5);
  g.lineWidth = 5;
  g.stroke();
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
