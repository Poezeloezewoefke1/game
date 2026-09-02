#!/usr/bin/env python3
"""Generates the trailer's score as a stereo WAV.

There is no music library, no sample pack and no downloaded audio in this
repository, so the score is synthesised from scratch with numpy - the same
position everything else here is in, and for the same reason.

The piece is built from a small number of ideas rather than a big arrangement,
because a trailer bed has to sit underneath a voice without competing with it:

  * a SIGNAL motif - three pitched pings on a fixed interval, the thing the
    crew is chasing. It opens the film alone and returns at the end.
  * a DRONE of two stacks a semitone apart. The beating between them is the
    unease; a clean interval would sound calm.
  * a PULSE, one low thud, whose spacing tightens across the film.
  * BELLS with inharmonic partials for the temple, struck sparsely.
  * a RISER and a HIT on the guardian.

Everything is mixed at 48 kHz and written as 24-bit PCM.
"""

import argparse
import math
import struct
import wave

import numpy as np

SR = 48000


def t_of(n):
    return np.arange(n, dtype=np.float64) / SR


def env_ad(n, attack, decay, floor=0.0):
    """Attack-decay envelope. Decay is exponential, which is what a struck or
    plucked thing actually does; a linear fade reads as a fade, not a decay."""
    e = np.zeros(n)
    a = max(int(attack * SR), 1)
    a = min(a, n)
    e[:a] = np.linspace(0.0, 1.0, a)
    rest = n - a
    if rest > 0:
        tau = max(decay, 1e-4)
        e[a:] = np.exp(-t_of(rest) / tau)
    return e * (1.0 - floor) + floor


def onepole_lp(x, cutoff):
    """A one-pole lowpass. Crude, but the point here is to take the edge off
    synthetic harmonics, not to be a filter design exercise."""
    a = math.exp(-2.0 * math.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(x.shape[0]):
        acc = a * acc + (1.0 - a) * x[i]
        y[i] = acc
    return y


def onepole_hp(x, cutoff):
    return x - onepole_lp(x, cutoff)


def saturate(x, drive=1.6):
    return np.tanh(x * drive) / math.tanh(drive)


def reverb(x, seconds=3.2, mix=0.38, predelay=0.03):
    """Convolution reverb against a synthesised impulse: exponentially decaying
    noise, lowpassed so the tail darkens as it dies the way a real room does.
    Done with FFT because a 3-second impulse is 150k taps."""
    n = int(seconds * SR)
    rng = np.random.default_rng(7)
    ir = rng.standard_normal(n) * np.exp(-t_of(n) * (4.5 / seconds))
    ir = onepole_lp(ir, 2600.0)
    ir[: int(predelay * SR)] = 0.0
    ir /= np.abs(ir).max() + 1e-9
    size = 1 << (len(x) + n - 1).bit_length()
    wet = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size))[: len(x)]
    wet /= np.abs(wet).max() + 1e-9
    return (1.0 - mix) * x + mix * wet * np.abs(x).max()


def note(freq, dur, kind="sine", detune=0.0, partials=1):
    n = int(dur * SR)
    t = t_of(n)
    out = np.zeros(n)
    if kind == "bell":
        # Inharmonic ratios: this is what stops a stack of sines sounding like
        # an organ and starts it sounding like struck metal.
        for ratio, amp, dec in ((1.0, 1.0, dur * 0.5), (2.76, 0.55, dur * 0.28),
                                (5.40, 0.32, dur * 0.16), (8.93, 0.18, dur * 0.09)):
            out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t / dec)
        return out / 2.0
    for k in range(1, partials + 1):
        amp = 1.0 / (k ** 1.6)
        for d in (-detune, detune):
            out += amp * np.sin(2 * np.pi * freq * k * (1.0 + d) * t)
    return out / (partials * (2 if detune else 1))


def place(buf, sig, at, gain=1.0, pan=0.0):
    """Mixes a mono signal into the stereo buffer at a time in seconds."""
    i = int(at * SR)
    if i >= buf.shape[0]:
        return
    seg = sig[: buf.shape[0] - i]
    left = gain * math.cos((pan + 1.0) * math.pi / 4.0)
    right = gain * math.sin((pan + 1.0) * math.pi / 4.0)
    buf[i:i + len(seg), 0] += seg * left
    buf[i:i + len(seg), 1] += seg * right


# D minor, low. The signal motif is a falling minor third then a tritone -
# the tritone is doing the heavy lifting for "wrong".
D2, F2, A2, Bb2 = 73.42, 87.31, 110.00, 116.54
D3, Eb3, F3, A3 = 146.83, 155.56, 174.61, 220.00
D4, F4, A4, Ab4 = 293.66, 349.23, 440.00, 415.30


def build(total):
    n = int(total * SR)
    buf = np.zeros((n, 2))

    # --- the signal: three pings, always the same, always the same spacing ---
    def signal(at, gain, bright=1.0):
        for k, (f, off) in enumerate(((A4, 0.0), (F4, 0.30), (Ab4, 0.62))):
            ping = note(f * bright, 2.6, kind="bell")
            place(buf, ping, at + off, gain * (0.9 ** k), pan=(-0.3 + 0.3 * k))

    # --- drone: two stacks a semitone apart, beating against each other ------
    def drone(at, dur, gain, root=D2):
        m = int(dur * SR)
        body = (note(root, dur, partials=6, detune=0.004)
                + 0.7 * note(root * 1.0595, dur, partials=5, detune=0.006)
                + 0.5 * note(root * 2.0, dur, partials=4, detune=0.003))
        body = onepole_lp(body, 420.0)
        e = np.minimum(np.linspace(0, 1, m) * 4.0, 1.0)
        e *= np.minimum(np.linspace(1, 0, m) * 6.0, 1.0)
        place(buf, body * e, at, gain, pan=-0.15)
        place(buf, np.roll(body * e, 900), at, gain * 0.9, pan=0.15)

    # --- pulse: one low thud, spacing tightens as the film goes on -----------
    def pulse(at, count, spacing, gain):
        for i in range(count):
            m = int(0.55 * SR)
            tt = t_of(m)
            f = 58.0 * np.exp(-tt * 7.0) + 34.0
            thud = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(m, 0.004, 0.13)
            place(buf, saturate(thud, 2.2), at + i * spacing, gain)

    def riser(at, dur, gain):
        m = int(dur * SR)
        tt = t_of(m)
        sweep = np.sin(2 * np.pi * np.cumsum(90.0 * np.exp(tt / dur * 2.3)) / SR)
        rng = np.random.default_rng(3)
        air = onepole_hp(rng.standard_normal(m), 1800.0) * 0.35
        e = (tt / dur) ** 2.2
        place(buf, (sweep * 0.6 + air) * e, at, gain)

    def impact(at, gain):
        m = int(3.2 * SR)
        tt = t_of(m)
        f = 120.0 * np.exp(-tt * 4.0) + 27.0
        body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 1.1)
        rng = np.random.default_rng(11)
        crack = onepole_lp(rng.standard_normal(m), 900.0) * np.exp(-tt / 0.16)
        place(buf, saturate(body * 1.2 + crack * 0.5, 1.9), at, gain)

    # ---------------- arrangement ----------------
    # I. black + the station. The signal is alone in the dark first.
    signal(0.6, 0.30)
    signal(3.4, 0.22, bright=0.5)
    drone(2.6, 12.0, 0.16)
    pulse(8.0, 3, 2.6, 0.30)

    # II. the descent. Drone drops a fifth; pulse steadies.
    drone(14.4, 15.5, 0.20, root=A2 / 2)
    pulse(15.0, 6, 2.4, 0.34)
    signal(19.0, 0.16, bright=0.5)
    place(buf, note(D3, 6.0, partials=4, detune=0.004) * env_ad(int(6.0 * SR), 2.0, 3.0),
          23.0, 0.10, pan=0.2)

    # III. the crystals. Bells, one per crystal, and the pulse tightens.
    drone(29.3, 17.8, 0.22, root=D2)
    for i, (f, at) in enumerate(((D4, 30.0), (F4, 34.2), (A4, 38.2))):
        place(buf, note(f, 5.0, kind="bell"), at, 0.30, pan=(-0.4 + 0.4 * i))
    pulse(30.5, 9, 1.8, 0.36)
    place(buf, note(Eb3, 5.0, partials=5, detune=0.005) * env_ad(int(5.0 * SR), 1.6, 2.4),
          42.0, 0.12)

    # IV. the guardian. Riser into a hit, then the floor drops out.
    riser(43.2, 3.5, 0.34)
    impact(46.7, 0.72)
    drone(46.7, 11.4, 0.26, root=Bb2 / 2)
    pulse(47.3, 12, 0.95, 0.40)
    signal(52.0, 0.20, bright=1.0)

    # V. the title. Everything stops for a beat, then one long swell.
    impact(58.7, 0.40)
    drone(59.1, 10.0, 0.24, root=D2)
    place(buf, note(D3, 10.0, partials=6, detune=0.004) * env_ad(int(10.0 * SR), 2.6, 6.0),
          59.1, 0.14, pan=-0.1)
    place(buf, note(A3, 10.0, partials=4, detune=0.005) * env_ad(int(10.0 * SR), 3.4, 5.5),
          59.1, 0.08, pan=0.25)
    signal(63.4, 0.26)

    return buf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="captures/audio/score.wav")
    ap.add_argument("--seconds", type=float, default=69.1)
    args = ap.parse_args()

    buf = build(args.seconds)
    for ch in range(2):
        buf[:, ch] = reverb(buf[:, ch], seconds=3.4, mix=0.34)

    # Fade the very ends so the file cannot click, then normalise with headroom
    # to leave room for the voice on top.
    fade = int(0.4 * SR)
    buf[:fade] *= np.linspace(0, 1, fade)[:, None]
    buf[-fade:] *= np.linspace(1, 0, fade)[:, None]
    buf = saturate(buf / (np.abs(buf).max() + 1e-9) * 0.92, 1.15) * 0.80

    data = (np.clip(buf, -1.0, 1.0) * (2 ** 23 - 1)).astype(np.int32)
    raw = b"".join(struct.pack("<i", v)[:3] for v in data.reshape(-1))
    with wave.open(args.out, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(3)
        w.setframerate(SR)
        w.writeframes(raw)
    print("SCORE %.1fs -> %s" % (args.seconds, args.out))


if __name__ == "__main__":
    main()
