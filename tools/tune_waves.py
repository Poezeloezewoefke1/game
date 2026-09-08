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
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WAVES = ROOT / "data" / "waves" / "fort_feather_waves.json"
## The hand-authored table this curve is applied to. Never edited by this script, and kept out of
## data/ on purpose: it is an input to the build, not something the game should ship or load.
BASELINE = ROOT / "tools" / "tuning" / "fort_feather_waves.baseline.json"


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
        return 0.9, 1.0, 1.9
    if wave <= 15:
        # Mid game: the board is filling in, so pressure starts climbing while
        # the income bonus tapers off.
        n = wave - 8
        return 0.95 + 0.02 * n, 1.02 + 0.065 * n, 1.5
    # Late game the board is at or near its 18-tower cap with deep upgrades, so
    # the curve climbs faster here than anywhere else.
    #
    # These numbers were refitted after the spatial-grid fix.  Splash and tower
    # targeting used to see only the first unit in each 4x4 cell, so the whole
    # previous curve had been fitted against a board doing a fraction of the
    # damage it was configured for.  With that fixed the benchmark won 5 of 5
    # without losing a life, and the sim said why: mean kill depth 0.42, i.e.
    # enemies were dying less than halfway down the path, with damage spread
    # evenly across six towers rather than one being overtuned.  Roughly
    # doubling survival time is what moves that back toward the far end.
    #
    # Count climbs here too, not just HP.  Bigger crowds are what make splash
    # and crowd control worth buying, and after the grid fix those towers
    # finally work as designed -- a curve made only of fatter individuals would
    # quietly push the roster back towards single-target damage.
    #
    # The constant term has to MEET the mid-game curve where it ends, not start
    # above it.  A first attempt jumped from 1.73 at wave 15 to 2.90 at wave 16
    # and the benchmark simply died there: a 68% step in one wave is a wall, not
    # a difficulty curve.  Mid now ends at 1.48, so late starts at 1.50 and does
    # its climbing through the slope instead.
    #
    # Fitting the slope below took four sweeps and it is a bracket, not a guess:
    #
    #   0.13   5 of 5, never losing a life       no campaign at all
    #   0.20   5 of 5, 71-96 lives                still comfortable
    #   0.22   see TEST_REPORT section 9
    #   0.245  3 of 5, wins on 72-84 lives, both losses at wave 21
    #   0.30   lost at wave 21
    #
    # The aim is a benchmark that wins most runs and loses the occasional one
    # near the end.  One that never loses measures nothing; one that loses at
    # the same mid-late wave every time is measuring a wall rather than a curve.
    #
    # Wave 21 is where it breaks when it breaks, and that is authored content
    # rather than an artifact: wave 20 is a wither plus ten flying elytra
    # gliders, and 21 follows it with ten tier-6 chungies and five shield
    # bearers at 50% armour who also block a third of all projectiles.  Flyers
    # then heavy armour, back to back.  A person answers that by buying into it;
    # the benchmark cannot, because it follows one fixed build order and never
    # adapts, so above 0.24 it simply falls over there.  That is the benchmark's
    # ceiling showing, not the curve's, which is why the slope sits below it.
    n = wave - 15
    return 1.10 + 0.025 * n, 1.50 + 0.22 * n, 1.15


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

    # Always regenerate from the untuned baseline so repeated runs are idempotent
    # instead of compounding multipliers.
    #
    # This used to read HEAD:data/waves/fort_feather_waves.json, which was only
    # idempotent while the tuned output had never been committed.  Once it was,
    # HEAD *became* the tuned file and a second run would have squared the whole
    # curve.  The baseline is now a file of its own, extracted from the commit
    # before the first tuning pass, so it cannot drift into the output.
    baseline = BASELINE.read_text()
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
