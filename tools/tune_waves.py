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
    # The slope was then refitted a second time, because the board got stronger
    # again: the hero ability that raises a wall on the path had never actually
    # blocked anything (nothing read `blocks_path` during movement) and Fort
    # Feather's detonation had never gone off.  With both working, ParrotX2
    # holds the lane for up to twelve seconds at a time and then drops a
    # 300-damage blast into whatever piled up behind it.  At the old 0.22 the
    # benchmark went from 79/96/71/77/93 lives to 100/100 on all five seeds --
    # not a close campaign, no campaign.
    #
    # All three fits are kept below.  The earlier ones are not superseded
    # history: each column is the same curve measured against a different set of
    # working game systems, and the gaps between them are what those systems are
    # worth.  Read down a column, not across a row.
    #
    #          walls      walls       + bounded
    #          inert      working     mitigation
    #   0.13   5/5, no life lost
    #   0.20   5/5, 71-96
    #   0.22   4/5, 51-98  5/5, all 100/100
    #   0.245  3/5, 72-84
    #   0.30   lost at 21
    #   0.45                          3/3, 51-68
    #   0.55              3/3, 66-79  5/5, 32-54 (one seed 100)  <- this one
    #   0.60                          2/5, wins on 15-35
    #   0.65              4/5, 37-58  0/5, every seed dead at 20-21
    #   0.75              2/3, 26-35
    #
    # The third column is why the shipped slope came back down.  Leak mitigation
    # WAS the second thing that mattered, though not in the way it first looked.
    # Suspecting it because the roster carries 17 points of `leak_reduction` was
    # wrong -- measuring it (the sim's "life economy" line) showed this build
    # order buys 2 and the one-life floor never binding.  But 2 points turn out
    # to be worth a great deal, because the average leak is worth 3.7 threat: a
    # flat -2 was halving the median leak and absorbing 55% of everything that
    # reached the base.  Bounding mitigation to 60% of a leak (see
    # GameController.LEAK_MITIGATION_MAX) therefore costs about a life per leak,
    # which at ~50 leaks a run is the entire margin -- 0.65 went from 4 of 5 to
    # 0 of 5 on that change alone.
    #
    # The aim is a benchmark that wins most runs and loses the occasional one
    # near the end.  One that never loses measures nothing; one that loses at
    # the same mid-late wave every time is measuring a wall rather than a curve.
    #
    # This fit does not hit that aim exactly, and it is worth being straight
    # about why rather than pretending 0.55 is a bullseye.  There is no slope
    # here that wins four of five: the transition is a cliff, 5 of 5 at 0.55 and
    # 2 of 5 at 0.60, with the losses landing on wave 21 every time.  Wave 21 is
    # authored content rather than an artifact -- wave 20 is a wither plus ten
    # flying elytra gliders, and 21 follows it with ten tier-6 chungies and five
    # shield bearers at 50% armour who also block a third of all projectiles.
    # Flyers then heavy armour, back to back.  A person answers that by buying
    # into it; the benchmark cannot, because it follows one fixed build order and
    # never adapts, so it does not degrade across that wave, it falls off it.
    #
    # So 0.55 is chosen as the last slope on the safe side of that cliff, and the
    # 5 of 5 it produces is not the 5 of 5 that meant "no campaign": those wins
    # ended on 100/100 lives having leaked five times, these end on 32-54 having
    # leaked around fifty.  Lives are a resource again, and 0.60 shows the loss
    # condition is one notch away rather than unreachable.
    n = wave - 15
    return 1.10 + 0.025 * n, 1.50 + 0.55 * n, 1.15


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
