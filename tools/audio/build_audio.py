#!/usr/bin/env python3
"""Builds the trailer's finished audio: score, voice, and the mix between them.

The voice is eSpeak NG, deliberately. There is no neural TTS available here and
nothing was downloaded, but a synthetic voice is not a compromise for this film -
the premise is a recovered transmission from a world with nothing alive on it,
so a voice that is almost but not quite human is the right instrument. It is
pitched down, band-limited to something like a radio channel, and given a room
to sit in, which is most of the distance between "text to speech" and "a
recording someone found".

Lines are placed at explicit cue times against the picture, so "the ruins",
"the cave" and "the grove" land on the three crystal shots.

    python3 tools/audio/build_audio.py --out captures/audio/mix.wav
"""

import argparse
import math
import os
import struct
import subprocess
import sys
import tempfile
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import score  # noqa: E402  (same directory, deliberate)

SR = score.SR
VOICE = "en-gb-x-rp+m3"

# Cue seconds and text, timed against the shot list in tools/trailer.gd. The
# cuts there fall at 3.0 / 8.0 / 13.4 / 18.4 / 23.4 / 29.3 / 33.3 / 37.3 / 41.3 /
# 46.7 / 51.2 / 54.7 / 59.1 / 63.1, and the lines are placed to use them: "the
# ruins", "the cave" and "the grove" each land on their own crystal, "opened its
# eye" lands after the guardian is revealed rather than on top of it, and the
# black dip before that reveal is left in silence.
#
# --report prints every line's span and flags overlaps, which is not a nicety:
# the first pass had four lines talking over each other, because a clip is
# longer than its text suggests once the echo tail is on it.
LINES = [
    (0.7,  "We were not the first to hear it."),
    (5.2,  "The signal came from Nerava."),
    (9.0,  "Nothing has lived there for a very long time."),
    (14.4, "We went down anyway."),
    (24.2, "The temple was already open."),
    (29.5, "Three crystals."),
    (31.3, "The ruins."),
    (35.0, "The cave."),
    (39.0, "The grove."),
    (42.0, "The altar wanted all three."),
    (47.0, "And something underneath it opened its eye."),
    (54.9, "Take the map. Run for the pod."),
    (59.3, "Do not look back."),
    (62.0, "You will hear it too."),
    (65.2, "Do not answer."),
]

# Pitched down and slowed by resampling, band-limited like a radio channel, then
# put in a room. The echo taps are deliberately short and quiet: a long tail on
# every word turns speech into mud.
CHAIN = (
    "asetrate=22050*0.86,aresample=48000,"
    "highpass=f=160,lowpass=f=3700,"
    "acompressor=threshold=0.06:ratio=4:attack=8:release=200,"
    "chorus=0.7:0.9:44|58:0.28|0.22:0.35|0.4:1.4|1.9,"
    "aecho=0.9:0.75:55|130:0.24|0.13,"
    "volume=2.0,"
    "aformat=sample_fmts=s16:channel_layouts=stereo"
)


def ffmpeg_bin():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


def render_line(text, work, index, ff):
    """espeak-ng -> ffmpeg chain -> float32 stereo at SR."""
    raw = os.path.join(work, "raw%02d.wav" % index)
    wet = os.path.join(work, "wet%02d.wav" % index)
    subprocess.run(
        ["espeak-ng", "-v", VOICE, "-s", "132", "-p", "22", "-g", "6",
         "-w", raw, text],
        check=True, capture_output=True)
    subprocess.run(
        [ff, "-y", "-loglevel", "error", "-i", raw, "-af", CHAIN, wet],
        check=True, capture_output=True)
    with wave.open(wet, "rb") as w:
        frames = w.readframes(w.getnframes())
        chans = w.getnchannels()
    a = np.frombuffer(frames, dtype="<i2").astype(np.float64) / 32768.0
    return a.reshape(-1, chans) if chans == 2 else np.column_stack([a, a])


def build_voice(total, work, ff):
    buf = np.zeros((int(total * SR), 2))
    spans = []
    for i, (cue, text) in enumerate(LINES):
        clip = render_line(text, work, i, ff)
        start = int(cue * SR)
        end = min(start + len(clip), len(buf))
        if end <= start:
            continue
        buf[start:end] += clip[: end - start]
        spans.append((cue, cue + speech_end(clip), cue + len(clip) / SR, text))
    return buf, spans


def speech_end(clip, floor=0.08):
    """Where the WORDS stop, as opposed to where the buffer stops.

    Every clip carries an echo tail, so comparing buffer lengths reported four
    overlaps that were only tails ringing into the next line - which is what a
    tail is for. Flagging those trains you to ignore the flag. This finds the
    last sample above a fraction of the clip's own peak, so an overlap warning
    means two lines are actually speaking at once."""
    env = np.abs(clip).max(axis=1)
    loud = np.nonzero(env > env.max() * floor)[0]
    return (loud[-1] + 1) / SR if len(loud) else len(clip) / SR


def duck(music, voice, depth=0.42, attack=0.05, release=0.55):
    """Pulls the music down under the voice.

    Without this the drone and the speech fight in the same low-mid band and the
    words stop being words. The control signal is the voice's own envelope,
    smoothed asymmetrically so the music dips fast and comes back slowly."""
    env = np.abs(voice).max(axis=1)
    # Fast peak follower, then a one-pole release.
    a_at = math.exp(-1.0 / (attack * SR))
    a_rl = math.exp(-1.0 / (release * SR))
    out = np.empty_like(env)
    acc = 0.0
    for i in range(env.shape[0]):
        x = env[i]
        acc = (a_at if x < acc else a_rl) * acc + (1.0 - (a_at if x < acc else a_rl)) * x
        out[i] = acc
    out /= out.max() + 1e-9
    gain = 1.0 - depth * np.clip(out * 2.4, 0.0, 1.0)
    return music * gain[:, None]


# Music level across the film, as (seconds, gain) breakpoints. Without this the
# opening measured the same loudness as the guardian, which wastes the three
# seconds of black the film opens on and leaves the hit with nowhere to go. The
# voice is NOT automated - keeping it flat while the bed drops away is what puts
# it alone in the dark at the start.
MUSIC_CURVE = [
    (0.0, 0.30), (3.0, 0.40), (8.0, 0.54), (13.4, 0.62), (23.4, 0.70),
    (29.3, 0.72), (41.3, 0.86), (46.6, 1.00), (51.1, 0.95), (54.6, 0.88),
    (58.6, 1.00), (59.1, 0.70), (63.0, 0.86), (200.0, 0.86),
]


def music_curve(total):
    t = np.arange(int(total * SR)) / SR
    xs = np.array([p[0] for p in MUSIC_CURVE])
    ys = np.array([p[1] for p in MUSIC_CURVE])
    return np.interp(t, xs, ys)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="captures/audio/mix.wav")
    ap.add_argument("--seconds", type=float, default=69.1)
    ap.add_argument("--report", action="store_true",
                    help="print each line's placement, for checking against the cut")
    args = ap.parse_args()

    ff = ffmpeg_bin()
    with tempfile.TemporaryDirectory() as work:
        voice, spans = build_voice(args.seconds, work, ff)

    music = score.build(args.seconds)
    for ch in range(2):
        music[:, ch] = score.reverb(music[:, ch], seconds=3.4, mix=0.34)
    music /= np.abs(music).max() + 1e-9
    voice /= np.abs(voice).max() + 1e-9

    mix = duck(music * music_curve(args.seconds)[:len(music), None], voice) + voice * 0.86
    fade = int(0.5 * SR)
    mix[:fade] *= np.linspace(0, 1, fade)[:, None]
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
    mix = score.saturate(mix / (np.abs(mix).max() + 1e-9) * 0.95, 1.1) * 0.89

    data = (np.clip(mix, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(args.out, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())

    print("MIX %.1fs -> %s" % (args.seconds, args.out))
    if args.report:
        prev_end = 0.0
        clashes = 0
        for start, end, tail, text in spans:
            flag = ""
            if start < prev_end - 0.02:
                flag = "  <-- OVERLAPS PREVIOUS SPEECH"
                clashes += 1
            print("  %6.2f - %6.2f (tail %5.2f)  %-46s%s"
                  % (start, end, tail, text, flag))
            prev_end = max(prev_end, end)
        print("  %d line(s) overlapping" % clashes)


if __name__ == "__main__":
    main()
