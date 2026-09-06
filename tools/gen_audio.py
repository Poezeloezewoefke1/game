#!/usr/bin/env python3
"""Generates ORIGINAL music and sound effects for UNSTABLE: LAST STAND as 16-bit PCM WAV.

Everything here is synthesised from scratch (sine/square/saw/noise oscillators, ADSR envelopes and
simple filters) — no sampled or copyrighted audio is used, and no music associated with any real
creator is referenced. Tracks are written as seamless loops.
"""
import math, os, struct, random, wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
os.makedirs(OUT, exist_ok=True)
SR = 44100

# ---------------------------------------------------------------- oscillators / helpers

def sine(f, t): return math.sin(2 * math.pi * f * t)
def saw(f, t):
    p = (f * t) % 1.0
    return 2.0 * p - 1.0
def square(f, t, duty=0.5):
    return 1.0 if (f * t) % 1.0 < duty else -1.0
def tri(f, t):
    p = (f * t) % 1.0
    return 4.0 * abs(p - 0.5) - 1.0

def adsr(i, n, a=0.01, d=0.1, s=0.7, r=0.2):
    t = i / SR
    total = n / SR
    if t < a:
        return t / max(a, 1e-6)
    if t < a + d:
        return 1.0 - (1.0 - s) * (t - a) / max(d, 1e-6)
    if t < total - r:
        return s
    return s * max(0.0, (total - t) / max(r, 1e-6))

def note_freq(semitones_from_a4):
    return 440.0 * (2.0 ** (semitones_from_a4 / 12.0))

# Note names -> semitone offsets from A4
NOTES = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3,
         "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}

def nf(name, octave=4):
    return note_freq(NOTES[name] + (octave - 4) * 12)

class Buf:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.d = [0.0] * self.n
    def add(self, start, samples, gain=1.0):
        s = int(start * SR)
        for i, v in enumerate(samples):
            j = s + i
            if 0 <= j < self.n:
                self.d[j] += v * gain
            elif j >= self.n:      # wrap for seamless loops
                self.d[j - self.n] += v * gain * 0.9
    def normalize(self, peak=0.85):
        m = max(1e-9, max(abs(v) for v in self.d))
        k = peak / m
        self.d = [v * k for v in self.d]
    def lowpass(self, cutoff=4000.0):
        a = math.exp(-2.0 * math.pi * cutoff / SR)
        prev = 0.0
        for i in range(self.n):
            prev = (1 - a) * self.d[i] + a * prev
            self.d[i] = prev

def tone(freq, dur, wave_fn=sine, a=0.01, d=0.08, s=0.7, r=0.15, detune=0.0, vibrato=0.0):
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        f = freq * (1.0 + vibrato * math.sin(2 * math.pi * 5.0 * t))
        v = wave_fn(f, t)
        if detune:
            v = 0.6 * v + 0.4 * wave_fn(f * (1.0 + detune), t)
        out.append(v * adsr(i, n, a, d, s, r))
    return out

def noise_burst(dur, decay=18.0, lp=0.35, seed=0):
    rnd = random.Random(seed)
    n = int(dur * SR)
    out = []
    prev = 0.0
    for i in range(n):
        w = rnd.uniform(-1, 1)
        prev = prev * (1 - lp) + w * lp
        out.append(prev * math.exp(-decay * i / SR))
    return out

def kick(dur=0.28, f0=140.0, f1=45.0):
    n = int(dur * SR)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = f1 + (f0 - f1) * math.exp(-14.0 * t)
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph) * math.exp(-7.0 * t))
    return out

def snare(dur=0.2, seed=1):
    n = int(dur * SR)
    body = noise_burst(dur, decay=22.0, lp=0.5, seed=seed)
    out = []
    for i in range(n):
        t = i / SR
        out.append(0.75 * body[i] + 0.25 * math.sin(2 * math.pi * 185 * t) * math.exp(-24 * t))
    return out

def hat(dur=0.07, seed=2):
    return [v * 0.5 for v in noise_burst(dur, decay=60.0, lp=0.9, seed=seed)]

def write_wav(name, buf, peak=0.85):
    buf.normalize(peak)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in buf.d)
        w.writeframes(frames)
    # No .import file is written: WAVs go through Godot's normal audio importer so they
    # become AudioStreamWAV resources (unlike skins, which are read as raw PNG bytes).
    return path

# ---------------------------------------------------------------- music
# Original compositions. Each is a seamless loop built from a chord progression plus a lead motif.

def build_track(name, bpm, bars, progression, lead_motif, lead_oct=5, bass_oct=2,
                drums=True, lead_wave=square, pad=True, swing=0.0, seed=7, peak=0.8):
    beat = 60.0 / bpm
    bar = beat * 4
    total = bar * bars
    buf = Buf(total)
    rnd = random.Random(seed)
    for b in range(bars):
        root_name, quality = progression[b % len(progression)]
        t0 = b * bar
        root = nf(root_name, bass_oct)
        # bass: root on 1 and 3, fifth on 4
        buf.add(t0, tone(root, beat * 0.9, saw, 0.005, 0.05, 0.65, 0.1), 0.5)
        buf.add(t0 + beat * 2, tone(root, beat * 0.7, saw, 0.005, 0.05, 0.65, 0.1), 0.45)
        buf.add(t0 + beat * 3, tone(root * 1.5, beat * 0.6, saw, 0.005, 0.05, 0.6, 0.1), 0.35)
        if pad:
            third = 3 if quality == "min" else 4
            for interval in (0, third, 7):
                f = nf(root_name, bass_oct + 2) * (2 ** (interval / 12.0))
                buf.add(t0, tone(f, bar * 0.98, tri, 0.25, 0.2, 0.55, 0.5), 0.16)
        if drums:
            for beat_i in range(4):
                tb = t0 + beat_i * beat
                if beat_i in (0, 2):
                    buf.add(tb, kick(), 0.55)
                if beat_i in (1, 3):
                    buf.add(tb, snare(seed=seed + beat_i), 0.32)
                for half in (0.0, 0.5):
                    buf.add(tb + half * beat + swing * (half > 0) * beat * 0.08, hat(seed=seed + beat_i * 2 + int(half * 2)), 0.2)
        # lead motif
        motif = lead_motif[b % len(lead_motif)]
        pos = 0.0
        for (deg, length) in motif:
            if deg is not None:
                f = nf(root_name, lead_oct) * (2 ** (deg / 12.0))
                buf.add(t0 + pos, tone(f, beat * length * 0.95, lead_wave, 0.01, 0.06, 0.55, 0.12, detune=0.004), 0.3)
            pos += beat * length
    buf.lowpass(7000)
    return write_wav(name, buf, peak)

MIN_PROG = [("A", "min"), ("F", "maj"), ("C", "maj"), ("G", "maj")]
DARK_PROG = [("D", "min"), ("A#", "maj"), ("F", "maj"), ("C", "maj")]
BOSS_PROG = [("D", "min"), ("D", "min"), ("A#", "maj"), ("C", "maj")]

MOTIF_A = [[(0, 1), (3, 0.5), (7, 0.5), (5, 1), (3, 1)],
           [(5, 1), (3, 1), (0, 1), (None, 1)],
           [(7, 0.5), (5, 0.5), (3, 1), (0, 1), (3, 1)],
           [(0, 2), (7, 1), (5, 1)]]
MOTIF_B = [[(0, 0.5), (0, 0.5), (3, 1), (5, 1), (7, 1)],
           [(7, 1), (5, 0.5), (3, 0.5), (0, 2)],
           [(3, 1), (7, 1), (10, 1), (7, 1)],
           [(5, 2), (3, 1), (0, 1)]]
MOTIF_BOSS = [[(0, 0.5), (0, 0.5), (0, 0.5), (3, 0.5), (0, 1), (-2, 1)],
              [(0, 0.5), (0, 0.5), (3, 0.5), (5, 0.5), (7, 2)],
              [(7, 0.5), (6, 0.5), (5, 0.5), (3, 0.5), (0, 2)],
              [(0, 1), (12, 1), (7, 1), (3, 1)]]
MOTIF_CALM = [[(0, 2), (3, 2)], [(5, 2), (3, 2)], [(7, 2), (5, 2)], [(3, 4)]]

def build_music():
    build_track("menu", 92, 8, MIN_PROG, MOTIF_CALM, lead_oct=5, drums=False, lead_wave=tri, seed=11, peak=0.7)
    build_track("map_fort_feather", 108, 8, MIN_PROG, MOTIF_A, lead_oct=5, lead_wave=square, seed=21)
    build_track("map_merchant_city", 116, 8, DARK_PROG, MOTIF_B, lead_oct=5, lead_wave=saw, seed=31)
    build_track("combat_cindercrest", 132, 8, DARK_PROG, MOTIF_B, lead_oct=5, lead_wave=square, seed=41)
    build_track("combat_mafia", 126, 8, DARK_PROG, MOTIF_A, lead_oct=4, lead_wave=tri, seed=51)
    build_track("combat_law", 120, 8, MIN_PROG, MOTIF_B, lead_oct=5, lead_wave=saw, seed=61)
    build_track("combat_caves", 104, 8, DARK_PROG, MOTIF_CALM, lead_oct=4, lead_wave=tri, seed=71)
    build_track("boss_saparata", 146, 8, BOSS_PROG, MOTIF_BOSS, lead_oct=5, lead_wave=saw, seed=81, peak=0.9)
    build_track("boss_generic", 140, 8, BOSS_PROG, MOTIF_BOSS, lead_oct=4, lead_wave=square, seed=91, peak=0.88)
    # short stingers
    v = Buf(3.2)
    for i, (deg, t) in enumerate([(0, 0.0), (4, 0.18), (7, 0.36), (12, 0.54)]):
        v.add(t, tone(nf("C", 5) * (2 ** (deg / 12.0)), 1.6, tri, 0.01, 0.2, 0.6, 1.0), 0.5)
    v.add(0.54, tone(nf("C", 3), 2.4, saw, 0.01, 0.3, 0.5, 1.6), 0.35)
    write_wav("victory", v, 0.8)
    d = Buf(3.2)
    for i, (deg, t) in enumerate([(0, 0.0), (-3, 0.3), (-7, 0.6), (-12, 0.95)]):
        d.add(t, tone(nf("D", 4) * (2 ** (deg / 12.0)), 1.8, tri, 0.02, 0.3, 0.5, 1.2), 0.45)
    d.lowpass(2200)
    write_wav("defeat", d, 0.75)

# ---------------------------------------------------------------- sound effects

def build_sfx():
    def w(name, seconds):
        return name, Buf(seconds)

    # UI
    n, b = w("click", 0.09)
    b.add(0.0, tone(880, 0.05, square, 0.001, 0.02, 0.3, 0.03), 0.5)
    b.add(0.01, tone(1320, 0.04, sine, 0.001, 0.02, 0.3, 0.02), 0.3)
    write_wav(n, b, 0.5)

    n, b = w("denied", 0.22)
    b.add(0.0, tone(220, 0.1, square, 0.002, 0.03, 0.5, 0.05), 0.5)
    b.add(0.1, tone(165, 0.12, square, 0.002, 0.03, 0.5, 0.06), 0.5)
    write_wav(n, b, 0.55)

    n, b = w("place", 0.3)
    b.add(0.0, kick(0.18, 180, 70), 0.7)
    b.add(0.02, noise_burst(0.14, 26, 0.3, 5), 0.35)
    b.add(0.05, tone(523, 0.14, tri, 0.005, 0.04, 0.4, 0.08), 0.3)
    write_wav(n, b, 0.7)

    n, b = w("sell", 0.3)
    for i, f in enumerate([784, 659, 523]):
        b.add(i * 0.06, tone(f, 0.12, tri, 0.004, 0.03, 0.4, 0.07), 0.35)
    write_wav(n, b, 0.6)

    n, b = w("coin", 0.22)
    b.add(0.0, tone(1318, 0.09, sine, 0.002, 0.03, 0.4, 0.05), 0.4)
    b.add(0.05, tone(1976, 0.12, sine, 0.002, 0.03, 0.4, 0.07), 0.32)
    write_wav(n, b, 0.5)

    n, b = w("upgrade", 0.6)
    for i, deg in enumerate([0, 4, 7, 12]):
        b.add(i * 0.07, tone(nf("C", 5) * (2 ** (deg / 12.0)), 0.28, tri, 0.004, 0.05, 0.5, 0.18), 0.34)
    b.add(0.0, noise_burst(0.3, 12, 0.2, 9), 0.15)
    write_wav(n, b, 0.75)

    n, b = w("levelup", 0.9)
    for i, deg in enumerate([0, 5, 9, 12, 16]):
        b.add(i * 0.08, tone(nf("C", 5) * (2 ** (deg / 12.0)), 0.45, tri, 0.005, 0.06, 0.55, 0.3), 0.3)
    write_wav(n, b, 0.8)

    n, b = w("relationship", 0.9)
    for i, deg in enumerate([0, 7, 12]):
        b.add(i * 0.1, tone(nf("G", 4) * (2 ** (deg / 12.0)), 0.6, sine, 0.02, 0.1, 0.6, 0.4), 0.32)
    write_wav(n, b, 0.7)

    # combat
    n, b = w("swing", 0.16)
    b.add(0.0, noise_burst(0.14, 32, 0.55, 3), 0.55)
    b.add(0.0, tone(320, 0.08, tri, 0.002, 0.02, 0.3, 0.05), 0.2)
    write_wav(n, b, 0.6)

    n, b = w("bow", 0.24)
    b.add(0.0, noise_burst(0.06, 60, 0.8, 4), 0.4)
    n2 = int(0.16 * SR)
    swoosh = []
    for i in range(n2):
        t = i / SR
        swoosh.append(math.sin(2 * math.pi * (1400 - 900 * t / 0.16) * t) * math.exp(-16 * t))
    b.add(0.02, swoosh, 0.3)
    write_wav(n, b, 0.55)

    n, b = w("cannon", 0.55)
    b.add(0.0, kick(0.4, 220, 40), 0.9)
    b.add(0.0, noise_burst(0.45, 9, 0.25, 6), 0.6)
    b.lowpass(2600)
    write_wav(n, b, 0.9)

    n, b = w("explosion", 0.9)
    b.add(0.0, kick(0.6, 260, 32), 0.9)
    b.add(0.0, noise_burst(0.85, 5.5, 0.2, 7), 0.75)
    b.add(0.02, noise_burst(0.5, 11, 0.45, 8), 0.4)
    b.lowpass(2000)
    write_wav(n, b, 0.95)

    n, b = w("magic", 0.35)
    for i in range(4):
        b.add(i * 0.03, tone(660 * (1 + i * 0.28), 0.2, sine, 0.004, 0.05, 0.4, 0.12, vibrato=0.02), 0.25)
    write_wav(n, b, 0.55)

    n, b = w("armor_break", 0.4)
    b.add(0.0, noise_burst(0.3, 16, 0.7, 12), 0.6)
    for i, f in enumerate([1400, 1900, 1150]):
        b.add(0.01 * i, tone(f, 0.09, square, 0.001, 0.02, 0.3, 0.05), 0.22)
    write_wav(n, b, 0.7)

    n, b = w("totem", 0.8)
    for i, deg in enumerate([0, 7, 12, 16]):
        b.add(i * 0.05, tone(nf("A", 4) * (2 ** (deg / 12.0)), 0.6, sine, 0.01, 0.08, 0.6, 0.4), 0.3)
    write_wav(n, b, 0.75)

    n, b = w("leak", 0.6)
    b.add(0.0, tone(196, 0.3, saw, 0.005, 0.08, 0.5, 0.2), 0.5)
    b.add(0.12, tone(147, 0.36, saw, 0.005, 0.08, 0.5, 0.24), 0.5)
    b.lowpass(1800)
    write_wav(n, b, 0.8)

    n, b = w("wave_start", 0.8)
    b.add(0.0, tone(nf("C", 3), 0.7, saw, 0.02, 0.1, 0.6, 0.4), 0.4)
    b.add(0.0, tone(nf("G", 3), 0.7, saw, 0.02, 0.1, 0.6, 0.4), 0.3)
    b.add(0.25, snare(0.3, 21), 0.4)
    write_wav(n, b, 0.8)

    n, b = w("ability", 0.5)
    n2 = int(0.4 * SR)
    rise = []
    for i in range(n2):
        t = i / SR
        rise.append(math.sin(2 * math.pi * (300 + 1400 * (t / 0.4) ** 2) * t) * adsr(i, n2, 0.02, 0.1, 0.6, 0.2))
    b.add(0.0, rise, 0.45)
    b.add(0.28, noise_burst(0.2, 14, 0.4, 15), 0.25)
    write_wav(n, b, 0.75)

    n, b = w("boss_intro", 2.2)
    b.add(0.0, tone(nf("D", 2), 2.0, saw, 0.05, 0.3, 0.7, 1.0), 0.5)
    b.add(0.0, tone(nf("A", 2), 2.0, saw, 0.05, 0.3, 0.7, 1.0), 0.3)
    b.add(0.3, kick(0.5, 200, 35), 0.7)
    b.add(1.0, kick(0.5, 200, 35), 0.7)
    b.add(1.6, noise_burst(0.6, 6, 0.2, 22), 0.35)
    b.lowpass(2400)
    write_wav(n, b, 0.9)

    n, b = w("boss_down", 1.6)
    b.add(0.0, kick(0.7, 300, 30), 0.9)
    b.add(0.0, noise_burst(1.2, 4.0, 0.18, 23), 0.6)
    for i, deg in enumerate([12, 7, 4, 0]):
        b.add(0.3 + i * 0.12, tone(nf("D", 4) * (2 ** (deg / 12.0)), 0.5, tri, 0.01, 0.1, 0.5, 0.3), 0.25)
    b.lowpass(2600)
    write_wav(n, b, 0.92)

    n, b = w("ember", 0.45)
    b.add(0.0, noise_burst(0.35, 12, 0.28, 31), 0.5)
    b.add(0.0, tone(140, 0.25, saw, 0.004, 0.06, 0.5, 0.15), 0.4)
    b.lowpass(2200)
    write_wav(n, b, 0.8)

    n, b = w("blimp", 2.0)
    for i in range(int(1.9 * SR)):
        t = i / SR
        b.d[i] += (0.45 * math.sin(2 * math.pi * 58 * t) + 0.25 * math.sin(2 * math.pi * 87 * t)) \
            * (0.6 + 0.4 * math.sin(2 * math.pi * 3.2 * t)) * min(1.0, t / 0.4) * min(1.0, (1.9 - t) / 0.4)
    b.lowpass(900)
    write_wav(n, b, 0.7)

    n, b = w("drop", 0.5)
    n2 = int(0.4 * SR)
    fall = []
    for i in range(n2):
        t = i / SR
        fall.append(math.sin(2 * math.pi * (900 - 700 * t / 0.4) * t) * adsr(i, n2, 0.01, 0.05, 0.5, 0.2))
    b.add(0.0, fall, 0.4)
    b.add(0.36, noise_burst(0.12, 30, 0.4, 33), 0.3)
    write_wav(n, b, 0.65)

def main():
    build_music()
    build_sfx()
    files = sorted(f for f in os.listdir(OUT) if f.endswith(".wav"))
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in files)
    print("generated %d audio files (%.1f MB)" % (len(files), total / 1048576.0))
    for f in files:
        print("  ", f, "%.0f KB" % (os.path.getsize(os.path.join(OUT, f)) / 1024.0))

if __name__ == "__main__":
    main()
