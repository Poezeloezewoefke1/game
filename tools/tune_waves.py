#!/usr/bin/env python3
"""Regenerate Fort Feather's wave table from a tuning curve.

The hand-authored baseline (see git history) escalated only by swapping in
higher-tier enemies: counts stayed flat around 15-24 and every group ran at
hp_mult 1.0 for all 24 waves.  Player power does not stay flat -- a run goes
from 2-3 towers to 18 fully-upgraded ones -- so the back half of the campaign
collapsed into a formality.  This script applies an explicit difficulty curve
on top of the baseline so enemy pressure tracks board growth.

The data files are hand-formatted for reading (several keys per line, compact
inline groups), so this edits values in the baseline *text* rather than
reserialising the JSON.  Reserialising expands every inline array and turns a
handful of number changes into a two-thousand-line diff.

Usage:  tools/tune_waves.py [--dry-run]

The curve constants below are the tuning knobs.  Re-run the balance simulation
afterwards -- `tools/balance_sweep.sh` across several seeds, never a single run
-- and aim for a win that stays close rather than a flawless one.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WAVES = ROOT / "data" / "waves" / "fort_feather_waves.json"


def curve(wave: int) -> tuple[float, float, float]:
    """Return (count_mult, hp_mult, reward_mult) for a 1-indexed wave."""
    if wave <= 3:
        # Tutorial waves. The player has one or two towers; leave the enemies
        # alone, but pay better so the board can actually get started.
        return 1.0, 1.0, 2.2
    if wave <= 8:
        # The early spike, and the hardest stretch of the run: a three-tower
        # board met the TNT runners on wave 8 and lost 17 lives in one wave.
        # Thin it out and keep income up so the player is not priced out of
        # answering it.
        return 0.8, 1.0, 2.0
    if wave <= 15:
        # Mid game: the board is filling in, so pressure starts climbing while
        # the income bonus tapers off.
        n = wave - 8
        return 0.9 + 0.02 * n, 1.0 + 0.03 * n, 1.8
    # Late game the board is at or near its 18-tower cap with deep upgrades, so
    # the curve climbs faster here than anywhere else.  It climbs mostly in HP
    # rather than in count, because kill rewards scale with count: a bigger wave
    # largely pays for the towers that answer it, which makes quantity a weak
    # difficulty lever and a strong economy one.
    n = wave - 15
    return 1.0 + 0.02 * n, 1.20 + 0.07 * n, 1.6


WAVE_START = re.compile(r'\{"name": "(?P<name>[^"]*)", "reward": (?P<reward>\d+)')
GROUP = re.compile(r'\{"enemy": "(?P<enemy>[^"]+)",\s*"count": (?P<count>\d+)')


def tune_text(text: str) -> str:
    """Apply the curve to the wave table's values, leaving its layout alone."""
    out: list[str] = []
    wave_no = 0
    for line in text.splitlines(keepends=True):
        m = WAVE_START.search(line)
        if m:
            wave_no += 1
            _, _, rm = curve(wave_no)
            reward = max(1, round(int(m.group("reward")) * rm))
            line = line[: m.start("reward")] + str(reward) + line[m.end("reward") :]

        g = GROUP.search(line)
        if g and wave_no > 0:
            cm, hm, _ = curve(wave_no)
            count = max(1, round(int(g.group("count")) * cm))
            line = line[: g.start("count")] + str(count) + line[g.end("count") :]
            line = _set_hp_mult(line, hm)
        out.append(line)
    return "".join(out)


def _set_hp_mult(line: str, hm: float) -> str:
    """Set (or clear) a group's hp_mult without disturbing the rest of the line."""
    existing = re.search(r',\s*"hp_mult": [0-9.]+', line)
    if existing:
        line = line[: existing.start()] + line[existing.end() :]
    if abs(hm - 1.0) < 1e-9:
        return line
    # Insert just before the group object's closing brace.
    close = line.rfind("}")
    if close < 0:
        return line
    return f'{line[:close]}, "hp_mult": {round(hm, 2)}{line[close:]}'


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    # Always regenerate from the committed baseline so repeated runs are
    # idempotent instead of compounding multipliers.
    baseline = subprocess.run(
        ["git", "show", "HEAD:data/waves/fort_feather_waves.json"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout
    tuned = tune_text(baseline)

    data = json.loads(tuned)          # also validates that the edit kept it parseable
    for i, wave in enumerate(data["waves"], start=1):
        total = sum(g["count"] for g in wave.get("groups", []))
        hp = max([g.get("hp_mult", 1.0) for g in wave.get("groups", [])], default=1.0)
        print(f"{i:2d} {wave['name'][:26]:28s} n={total:3d} hp={hp:.2f} rew={wave['reward']:4d}")

    if not args.dry_run:
        WAVES.write_text(tuned)
        print(f"\nwrote {WAVES.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
