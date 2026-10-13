// Fully synthesized soundscape (Web Audio API) — no audio files required.
// Ambient beds, depth drone, the Low Song, creature calls, equipment sounds,
// submarine hum and generative music, all muffled while underwater.

export class AudioEngine {
  constructor() {
    this.ctx = null;
    this.ready = false;
    this.volumes = { master: 0.8, music: 0.5, sfx: 0.8, ambience: 0.8 };
    this.musicTimer = 8;
    this.state = { depth: 0, underwater: true };
  }

  init() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    const ctx = new AC();
    this.ctx = ctx;
    this.master = ctx.createGain();
    this.comp = ctx.createDynamicsCompressor();
    this.comp.threshold.value = -16;
    this.comp.ratio.value = 3;
    this.muffle = ctx.createBiquadFilter();
    this.muffle.type = 'lowpass';
    this.muffle.frequency.value = 2400;
    this.muffle.Q.value = 0.5;
    this.muffle.connect(this.master);
    this.master.connect(this.comp);
    this.comp.connect(ctx.destination);

    this.reverb = ctx.createConvolver();
    this.reverb.buffer = this.impulse(4.2, 2.6);
    this.reverbGain = ctx.createGain();
    this.reverbGain.gain.value = 0.55;
    this.reverb.connect(this.reverbGain);
    this.reverbGain.connect(this.muffle);

    this.bus = {};
    for (const name of ['sfx', 'ambience', 'music', 'ui']) {
      const g = ctx.createGain();
      g.connect(name === 'ui' ? this.master : this.muffle);
      this.bus[name] = g;
    }
    this.noiseBuf = this.makeNoise(4, 'white');
    this.brownBuf = this.makeNoise(6, 'brown');
    this.buildAmbience();
    this.applyVolumes();
    this.ready = true;
  }

  impulse(seconds, decay) {
    const ctx = this.ctx;
    const len = Math.floor(ctx.sampleRate * seconds);
    const buf = ctx.createBuffer(2, len, ctx.sampleRate);
    for (let c = 0; c < 2; c++) {
      const d = buf.getChannelData(c);
      for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay);
    }
    return buf;
  }

  makeNoise(seconds, kind) {
    const ctx = this.ctx;
    const len = Math.floor(ctx.sampleRate * seconds);
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = buf.getChannelData(0);
    let last = 0;
    for (let i = 0; i < len; i++) {
      const w = Math.random() * 2 - 1;
      if (kind === 'brown') { last = (last + 0.02 * w) / 1.02; d[i] = last * 3.5; } else d[i] = w;
    }
    return buf;
  }

  noiseSource(buf = this.noiseBuf) {
    const s = this.ctx.createBufferSource();
    s.buffer = buf;
    s.loop = true;
    return s;
  }

  buildAmbience() {
    const ctx = this.ctx;
    const amb = this.bus.ambience;
    // 1. water bed
    const bed = this.noiseSource(this.brownBuf);
    const bedF = ctx.createBiquadFilter();
    bedF.type = 'lowpass'; bedF.frequency.value = 420;
    this.bedGain = ctx.createGain(); this.bedGain.gain.value = 0.5;
    bed.connect(bedF); bedF.connect(this.bedGain); this.bedGain.connect(amb);
    bed.start();
    const lfo = ctx.createOscillator(); lfo.frequency.value = 0.07;
    const lfoG = ctx.createGain(); lfoG.gain.value = 160;
    lfo.connect(lfoG); lfoG.connect(bedF.frequency); lfo.start();
    // 2. depth drone
    this.droneGain = ctx.createGain(); this.droneGain.gain.value = 0;
    const droneF = ctx.createBiquadFilter(); droneF.type = 'lowpass'; droneF.frequency.value = 160;
    this.droneOsc = [];
    for (const f of [41.2, 61.7, 82.6]) {
      const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = f;
      const g = ctx.createGain(); g.gain.value = 0.18;
      o.connect(g); g.connect(droneF); o.start();
      this.droneOsc.push(o);
    }
    droneF.connect(this.droneGain); this.droneGain.connect(amb);
    this.droneGain.connect(this.reverb);
    // 3. surface (air) waves & wind — bypasses the muffle
    const surf = this.noiseSource();
    const surfF = ctx.createBiquadFilter(); surfF.type = 'bandpass'; surfF.frequency.value = 900; surfF.Q.value = 0.4;
    this.surfGain = ctx.createGain(); this.surfGain.gain.value = 0;
    surf.connect(surfF); surfF.connect(this.surfGain); this.surfGain.connect(this.master);
    surf.start();
    const surfLfo = ctx.createOscillator(); surfLfo.frequency.value = 0.12;
    const surfLfoG = ctx.createGain(); surfLfoG.gain.value = 0.05;
    surfLfo.connect(surfLfoG); surfLfoG.connect(this.surfGain.gain); surfLfo.start();
    // 4. the Low Song (audible sub-harmonic shadow of the 7 Hz signal)
    this.songGain = ctx.createGain(); this.songGain.gain.value = 0;
    const songF = ctx.createBiquadFilter(); songF.type = 'lowpass'; songF.frequency.value = 240;
    this.songOsc = ctx.createOscillator(); this.songOsc.type = 'triangle'; this.songOsc.frequency.value = 55;
    this.songOsc2 = ctx.createOscillator(); this.songOsc2.type = 'sine'; this.songOsc2.frequency.value = 82.5;
    const trem = ctx.createOscillator(); trem.frequency.value = 7;
    const tremG = ctx.createGain(); tremG.gain.value = 0.35;
    const songAmp = ctx.createGain(); songAmp.gain.value = 0.6;
    trem.connect(tremG); tremG.connect(songAmp.gain);
    this.songOsc.connect(songAmp); this.songOsc2.connect(songAmp);
    songAmp.connect(songF); songF.connect(this.songGain);
    this.songGain.connect(amb); this.songGain.connect(this.reverb);
    this.songOsc.start(); this.songOsc2.start(); trem.start();
    this.songPhrase = 0;
    // 5. submarine hum + thrusters
    this.subGain = ctx.createGain(); this.subGain.gain.value = 0;
    const hum = ctx.createOscillator(); hum.type = 'sawtooth'; hum.frequency.value = 48;
    const humF = ctx.createBiquadFilter(); humF.type = 'lowpass'; humF.frequency.value = 200;
    hum.connect(humF); humF.connect(this.subGain); hum.start();
    this.humOsc = hum;
    const thr = this.noiseSource();
    this.thrF = ctx.createBiquadFilter(); this.thrF.type = 'bandpass'; this.thrF.frequency.value = 300; this.thrF.Q.value = 0.8;
    this.thrGain = ctx.createGain(); this.thrGain.gain.value = 0;
    thr.connect(this.thrF); this.thrF.connect(this.thrGain); this.thrGain.connect(this.bus.sfx); thr.start();
    this.subGain.connect(this.bus.sfx);
    // 6. swim wash (movement through water)
    const wash = this.noiseSource();
    this.washF = ctx.createBiquadFilter(); this.washF.type = 'bandpass'; this.washF.frequency.value = 500; this.washF.Q.value = 0.6;
    this.washGain = ctx.createGain(); this.washGain.gain.value = 0;
    wash.connect(this.washF); this.washF.connect(this.washGain); this.washGain.connect(this.bus.sfx); wash.start();
    // 7. scanner loop
    this.scanOsc = ctx.createOscillator(); this.scanOsc.type = 'sine'; this.scanOsc.frequency.value = 600;
    this.scanGain = ctx.createGain(); this.scanGain.gain.value = 0;
    const scanLfo = ctx.createOscillator(); scanLfo.frequency.value = 12;
    const scanLfoG = ctx.createGain(); scanLfoG.gain.value = 40;
    scanLfo.connect(scanLfoG); scanLfoG.connect(this.scanOsc.frequency);
    this.scanOsc.connect(this.scanGain); this.scanGain.connect(this.bus.sfx);
    this.scanOsc.start(); scanLfo.start();
  }

  setVolumes(v) { Object.assign(this.volumes, v); this.applyVolumes(); }

  applyVolumes() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.master.gain.setTargetAtTime(this.volumes.master, t, 0.05);
    this.bus.music.gain.setTargetAtTime(this.volumes.music * 0.5, t, 0.05);
    this.bus.sfx.gain.setTargetAtTime(this.volumes.sfx, t, 0.05);
    this.bus.ui.gain.setTargetAtTime(this.volumes.sfx * 0.6, t, 0.05);
    this.bus.ambience.gain.setTargetAtTime(this.volumes.ambience, t, 0.05);
  }

  suspend(paused) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.muffle.frequency.setTargetAtTime(paused ? 500 : this.muffleTarget || 2400, t, 0.15);
  }

  /** Called every frame with the current world/player state. */
  update(dt, s) {
    if (!this.ready) return;
    const ctx = this.ctx;
    const t = ctx.currentTime;
    this.state = s;
    const underwater = s.underwater && !s.inAir;
    this.muffleTarget = underwater ? (s.inSub ? 1500 : 2200) - Math.min(s.depth, 600) * 0.9 : 16000;
    if (!s.paused) this.muffle.frequency.setTargetAtTime(this.muffleTarget, t, 0.2);
    const depthF = Math.min(1, s.depth / 300);
    this.bedGain.gain.setTargetAtTime(underwater ? 0.45 + depthF * 0.15 : 0.05, t, 0.3);
    this.droneGain.gain.setTargetAtTime(underwater ? 0.02 + depthF * 0.16 : 0, t, 1.0);
    this.droneOsc.forEach((o, i) => o.frequency.setTargetAtTime([41.2, 61.7, 82.6][i] * (1 - depthF * 0.12), t, 2));
    this.surfGain.gain.setTargetAtTime(s.aboveSurface ? 0.14 : 0, t, 0.2);
    this.songGain.gain.setTargetAtTime(underwater ? s.song * 0.32 : 0, t, 1.5);
    this.subGain.gain.setTargetAtTime(s.inSub ? 0.12 : 0, t, 0.3);
    this.thrGain.gain.setTargetAtTime(s.inSub ? s.subThrust * 0.22 : 0, t, 0.1);
    this.thrF.frequency.setTargetAtTime(220 + s.subThrust * 500, t, 0.1);
    this.humOsc.frequency.setTargetAtTime(46 + s.subThrust * 10, t, 0.2);
    this.washGain.gain.setTargetAtTime(underwater && !s.inSub ? Math.min(0.2, s.speed * 0.03) : 0, t, 0.1);
    this.washF.frequency.setTargetAtTime(300 + s.speed * 90, t, 0.1);
    this.scanGain.gain.setTargetAtTime(s.scanning ? 0.05 : 0, t, 0.03);
    if (s.scanning) this.scanOsc.frequency.setTargetAtTime(500 + s.scanProgress * 700, t, 0.05);

    // Low Song phrasing: prime-ratio intervals that drift slowly
    this.songPhrase -= dt;
    if (this.songPhrase < 0) {
      this.songPhrase = 3 + Math.random() * 5;
      const ratios = [1, 7 / 5, 3 / 2, 11 / 7, 13 / 11, 5 / 3];
      const r = ratios[Math.floor(Math.random() * ratios.length)];
      this.songOsc.frequency.setTargetAtTime(55 * r, t, 1.2);
      this.songOsc2.frequency.setTargetAtTime(55 * r * 1.5, t, 1.6);
    }
    // generative music
    if (!s.paused) {
      this.musicTimer -= dt;
      if (this.musicTimer < 0) {
        this.musicTimer = 22 + Math.random() * 26;
        this.playChord(s.depth);
      }
    }
  }

  env(g, t, a, peak, d, sustain = 0) {
    g.gain.cancelScheduledValues(t);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(peak, t + a);
    g.gain.exponentialRampToValueAtTime(Math.max(0.0001, sustain), t + a + d);
  }

  tone({ freq = 440, type = 'sine', dur = 0.3, gain = 0.2, attack = 0.005, bus = 'sfx', glide = 0, reverb = 0.3, pan = 0, filter = 0, delay = 0 }) {
    if (!this.ready) return;
    const ctx = this.ctx;
    const t = ctx.currentTime + delay;
    const o = ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (glide) o.frequency.exponentialRampToValueAtTime(Math.max(20, freq * glide), t + dur);
    const g = ctx.createGain();
    this.env(g, t, attack, gain, dur);
    let node = o;
    if (filter) {
      const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = filter;
      o.connect(f); node = f;
    }
    node.connect(g);
    let out = g;
    if (pan && ctx.createStereoPanner) {
      const p = ctx.createStereoPanner(); p.pan.value = Math.max(-1, Math.min(1, pan));
      g.connect(p); out = p;
    }
    out.connect(this.bus[bus]);
    if (reverb > 0) {
      const rg = ctx.createGain(); rg.gain.value = reverb;
      out.connect(rg); rg.connect(this.reverb);
    }
    o.start(t);
    o.stop(t + attack + dur + 0.1);
  }

  noiseBurst({ dur = 0.3, gain = 0.2, freq = 1000, q = 1, type = 'bandpass', bus = 'sfx', reverb = 0.2, attack = 0.005, sweep = 0 }) {
    if (!this.ready) return;
    const ctx = this.ctx;
    const t = ctx.currentTime;
    const s = ctx.createBufferSource();
    s.buffer = this.noiseBuf;
    const f = ctx.createBiquadFilter(); f.type = type; f.frequency.setValueAtTime(freq, t); f.Q.value = q;
    if (sweep) f.frequency.exponentialRampToValueAtTime(freq * sweep, t + dur);
    const g = ctx.createGain();
    this.env(g, t, attack, gain, dur);
    s.connect(f); f.connect(g); g.connect(this.bus[bus]);
    if (reverb) { const rg = ctx.createGain(); rg.gain.value = reverb; g.connect(rg); rg.connect(this.reverb); }
    s.start(t, Math.random() * 2);
    s.stop(t + attack + dur + 0.1);
  }

  // ---- named effects
  ui() { this.tone({ freq: 880, type: 'sine', dur: 0.06, gain: 0.08, bus: 'ui', reverb: 0 }); }
  uiOpen() { this.tone({ freq: 520, dur: 0.12, gain: 0.08, bus: 'ui', glide: 1.6, reverb: 0 }); }
  uiClose() { this.tone({ freq: 760, dur: 0.12, gain: 0.07, bus: 'ui', glide: 0.6, reverb: 0 }); }
  ping() {
    this.tone({ freq: 1320, dur: 1.6, gain: 0.22, reverb: 0.9 });
    this.tone({ freq: 1320, dur: 1.2, gain: 0.08, reverb: 0.9, delay: 0.45 });
    this.tone({ freq: 1320, dur: 1.0, gain: 0.04, reverb: 0.9, delay: 0.9 });
  }
  echo(distance) { this.tone({ freq: 990, dur: 0.9, gain: 0.08, reverb: 1, delay: Math.min(2.5, distance / 120) }); }
  scanComplete() {
    this.tone({ freq: 660, dur: 0.2, gain: 0.12, reverb: 0.4 });
    this.tone({ freq: 990, dur: 0.35, gain: 0.12, reverb: 0.5, delay: 0.1 });
  }
  pickup() {
    this.noiseBurst({ dur: 0.18, gain: 0.12, freq: 1600, q: 2, sweep: 0.5 });
    this.tone({ freq: 740, dur: 0.15, gain: 0.08, glide: 1.4 });
  }
  craft() {
    for (let i = 0; i < 4; i++) this.tone({ freq: 300 + i * 120, dur: 0.12, gain: 0.08, delay: i * 0.08, type: 'triangle' });
    this.noiseBurst({ dur: 0.8, gain: 0.08, freq: 3000, q: 0.5, sweep: 0.3 });
  }
  denied() { this.tone({ freq: 180, type: 'square', dur: 0.15, gain: 0.06, filter: 900, reverb: 0 }); }
  damage() {
    this.tone({ freq: 90, type: 'sine', dur: 0.4, gain: 0.5, glide: 0.5, reverb: 0.3 });
    this.noiseBurst({ dur: 0.25, gain: 0.25, freq: 400, q: 0.7, type: 'lowpass' });
  }
  warn() { this.tone({ freq: 1040, type: 'square', dur: 0.08, gain: 0.05, filter: 2000, reverb: 0 }); this.tone({ freq: 1040, type: 'square', dur: 0.08, gain: 0.05, filter: 2000, reverb: 0, delay: 0.16 }); }
  creak() {
    this.tone({ freq: 70 + Math.random() * 40, type: 'sawtooth', dur: 1.2, gain: 0.08, glide: 0.7, filter: 400, reverb: 0.6, attack: 0.3 });
  }
  breathe(lowO2) {
    // exhale + bubbles
    this.noiseBurst({ dur: 0.9, gain: lowO2 ? 0.07 : 0.035, freq: 700, q: 0.8, attack: 0.25, reverb: 0 });
    for (let i = 0; i < 6; i++) this.tone({ freq: 300 + Math.random() * 500, dur: 0.06, gain: 0.03, glide: 1.8, delay: 0.5 + i * 0.07, reverb: 0.1 });
  }
  splash() { this.noiseBurst({ dur: 0.6, gain: 0.2, freq: 1200, q: 0.4, sweep: 0.3, bus: 'ui' }); }
  heartbeat() {
    this.tone({ freq: 55, dur: 0.15, gain: 0.25, reverb: 0 });
    this.tone({ freq: 50, dur: 0.15, gain: 0.18, reverb: 0, delay: 0.22 });
  }
  cantorCall(dist, pan = 0) {
    const vol = Math.max(0.03, 0.42 * Math.exp(-dist / 450));
    const base = 70 + Math.random() * 40;
    this.tone({ freq: base, type: 'sawtooth', dur: 4.5, gain: vol * 0.5, attack: 1.2, glide: 1.5, filter: 380, reverb: 1.4, pan });
    this.tone({ freq: base * 1.5, type: 'sine', dur: 4.0, gain: vol * 0.4, attack: 1.5, glide: 1.3, reverb: 1.4, pan, delay: 0.6 });
    this.tone({ freq: base * 2.01, type: 'triangle', dur: 3, gain: vol * 0.25, attack: 1.0, glide: 0.8, filter: 600, reverb: 1.4, pan, delay: 2.2 });
  }
  creatureClick(dist) {
    const vol = Math.max(0, 0.15 * (1 - dist / 60));
    for (let i = 0; i < 5; i++) this.noiseBurst({ dur: 0.03, gain: vol, freq: 2500 + Math.random() * 2000, q: 6, reverb: 0.4 });
  }
  stalkerScreech(dist) {
    const vol = Math.max(0.05, 0.4 * (1 - dist / 120));
    this.tone({ freq: 340, type: 'sawtooth', dur: 1.6, gain: vol * 0.4, glide: 0.4, filter: 1400, reverb: 1.2, attack: 0.1 });
    this.tone({ freq: 351, type: 'square', dur: 1.4, gain: vol * 0.2, glide: 0.45, filter: 900, reverb: 1.2, attack: 0.15 });
  }
  discovery() {
    const notes = [392, 523.25, 659.25, 783.99];
    notes.forEach((f, i) => this.tone({ freq: f, type: 'sine', dur: 3.5, gain: 0.07, attack: 0.4, delay: i * 0.18, bus: 'music', reverb: 1.2 }));
  }
  powerOn() {
    this.tone({ freq: 60, type: 'sawtooth', dur: 2.5, gain: 0.25, glide: 4, filter: 900, attack: 0.5, reverb: 0.8 });
    for (let i = 0; i < 3; i++) this.tone({ freq: 440 * (1 + i * 0.5), dur: 1.4, gain: 0.08, delay: 1.6 + i * 0.2, reverb: 1 });
  }
  voiceLog(on) {
    if (!this.ready) return;
    if (on && !this.voiceNode) {
      const ctx = this.ctx;
      const src = this.noiseSource();
      const f = ctx.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = 1800; f.Q.value = 1.5;
      const g = ctx.createGain(); g.gain.value = 0.015;
      src.connect(f); f.connect(g); g.connect(this.bus.ui); src.start();
      this.voiceNode = { src, g };
    } else if (!on && this.voiceNode) {
      this.voiceNode.src.stop();
      this.voiceNode = null;
    }
  }
  playChord(depth) {
    const shallow = [[261.63, 329.63, 392, 493.88], [293.66, 369.99, 440, 554.37], [220, 277.18, 329.63, 415.3]];
    const deep = [[110, 130.81, 164.81, 196], [98, 116.54, 146.83, 174.61], [103.83, 123.47, 155.56, 185]];
    const set = depth > 140 ? deep : shallow;
    const chord = set[Math.floor(Math.random() * set.length)];
    chord.forEach((f, i) => {
      this.tone({ freq: f, type: i % 2 ? 'triangle' : 'sine', dur: 9, gain: 0.05, attack: 3.5, bus: 'music', reverb: 1.5, delay: i * 0.6, pan: (i - 1.5) * 0.4 });
    });
  }
  shimmer(dist) {
    const vol = Math.max(0, 0.05 * (1 - dist / 40));
    if (vol <= 0) return;
    for (let i = 0; i < 4; i++) this.tone({ freq: 2400 + Math.random() * 1600, dur: 0.25, gain: vol, delay: i * 0.05 + Math.random() * 0.05, reverb: 0.7 });
  }
  crystalRing() {
    const scale = [523.25, 587.33, 659.25, 783.99, 880, 1046.5];
    const n = 1 + Math.floor(Math.random() * 3);
    for (let i = 0; i < n; i++) {
      const f = scale[Math.floor(Math.random() * scale.length)];
      this.tone({ freq: f, type: 'sine', dur: 3.5, gain: 0.035, attack: 0.02, delay: i * 0.4, reverb: 1.4, pan: (Math.random() - 0.5) * 1.2 });
      this.tone({ freq: f * 2.76, type: 'sine', dur: 1.2, gain: 0.008, attack: 0.01, delay: i * 0.4, reverb: 1.2 });
    }
  }
  deepGroan() {
    this.tone({ freq: 38 + Math.random() * 20, type: 'sawtooth', dur: 5, gain: 0.07, attack: 1.5, glide: 0.6, filter: 220, reverb: 1.6, pan: (Math.random() - 0.5) * 1.6 });
  }
  endingSwell() {
    const notes = [65.41, 98, 130.81, 196, 261.63, 392, 523.25];
    notes.forEach((f, i) => this.tone({ freq: f, type: i < 3 ? 'sawtooth' : 'sine', dur: 14, gain: i < 3 ? 0.06 : 0.05, attack: 5, delay: i * 0.9, bus: 'music', filter: 1800, reverb: 1.8 }));
  }
}
