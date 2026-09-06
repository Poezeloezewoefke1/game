# Game Design

## What this game is

A tower defense built on a specific premise from the source material: **Cindercrest kills new players,
and the four protagonists are the only reason anyone survives.** Every system is an attempt to make
that premise playable rather than a generic TD reskinned with names.

It takes its structural cues from the genre — a path, build zones, waves, three upgrade paths, a hero
who levels during the run — while the content, the mechanics that matter, and the presentation are its
own. It is not a Bloons TD 6 clone: enemies are not colour-coded balloons but geared players whose
armour visibly breaks off in tiers; the hero system is one-protagonist-per-run rather than a roster; and
the relationship bonds have no genre equivalent.

## The core loop

1. Choose one of the four protagonists. This is the run's biggest decision — the heroes are not
   interchangeable damage sources but four different answers to the same map.
2. Choose a map and difficulty.
3. Place towers on build zones. Some zones are elevated: melee towers there gain a mace-style height
   bonus, which is a real trade-off against the better firing angles of ground zones.
4. Start a wave, or let the auto-timer start it. Enemies walk the path; towers acquire and fire.
5. Kills pay emeralds. Emeralds buy towers and upgrades.
6. Enemy gear escalates tier by tier. What killed wave 8 will not kill wave 18.
7. Scripted events fire mid-wave: dialogue, announcements, the Redstone Blimp.
8. The boss arrives with five scripted phases.
9. Win or lose; earn hero XP and XP Bottles toward permanent progression.

## Economy

The currency is **emeralds** (⬧) — the natural trade currency of the setting, and the one the sources
actually associate with commerce. The meta-currency is **XP Bottles**, taken from the Egg
Civilization, whose documented currency was bottles of enchanting.

Income comes from three places, and a run is largely a question of how you balance them:

- **Kills.** Every gear layer broken pays out, so a Netherite Chungie pays five times on the way down.
- **Economy towers.** Eggchan, Lomedy's farm, Fymada's treasury and Spepticle's informants pay on a
  timer. They generate nothing defensively, so early investment is a real risk.
- **Wave clear bonuses**, scaled by difficulty.

Difficulty multiplies starting emeralds, lives, enemy health and income together, so "hard" is not
merely more enemy HP — it is a tighter economy at the same time.

## The Gear Rule

Each tower has three upgrade paths of four tiers. **One path may reach tier 4; a second may reach
tier 2; the third stays at 0.**

This is the game's central build constraint. It means a tower is a set of committed choices rather
than an accumulation, that the tier-4 Signature upgrades stay special, and that the same character
plays differently across two placements. The rule is enforced in `Tower.can_upgrade()` and covered by
the test suite, including the specific case of starting a second path while the first is already above
tier 2.

## Enemies: gear is the health bar

The Chungie ladder is the design's spine. Rather than an abstract layered enemy, each tier is a gear
set. When a layer's health is gone the armour breaks off — visibly, in 3D — and the unit keeps running
in whatever is underneath, carrying overflow damage down with it.

| Tier | Enemy | The read |
|---|---|---|
| 1 | Chungie | A fresh player with a wooden sword |
| 2 | Iron Chungie | Full iron; cracks into a plain Chungie |
| 3 | Diamond Chungie | Rewards armour-piercing |
| 4 | Enchanted Chungie | Mending: repairs itself, so chip damage fails |
| 5 | Netherite Chungie | What "Cindercrest can equip thousands in netherite" looks like |
| 6 | Cindercrest Warrior | An old player with a mace and a grudge |
| 7 | Cindercrest Commander | Buffs the wave around it; kill it first |

Special enemies each answer a specific defensive assumption: elytra gliders punish having no anti-air,
invisible players punish having no detection, assassins punish clustering towers near the path,
shield bearers punish an all-projectile defence, builders drop walls that soak fire, and TNT runners
punish killing things at the gate instead of early.

## Heroes

One hero per run, levelling from kills during the run and carrying a small permanent bonus between
runs. Each has three actives, an ultimate, and three passives that unlock with level.

**ParrotX2 — leadership.** Weak personally; makes everything around him better. Aura, income,
Royal Decree (global attack speed), Fort Feather (a wall), Royal Army (summons), and an ultimate that
buffs every tower and caps leak damage. He is the "your towers are the answer" hero.

**Wemmbu — aggression.** The highest single-target damage, a mace that hits harder from elevation,
Stab Shot for a focused orbital strike, and a Nuke Shot ultimate that clears a section of path. He is
the "I am the answer" hero.

**FlameFrags — duelling.** The fastest attacks, damage that ramps the longer he focuses one target, a
duel that locks down an elite, and an ultimate that triples his attack speed. Excellent against single
big threats, poor against crowds.

**SpokeIsHere — control.** The lowest damage and the best crowd control. Turncoat converts an elite
into a temporary ally, Into the Void knocks a group back down the path, Purgatory stuns and makes
everything take more damage, and his ultimate brings the NULL. The hardest of the four to play.

Abilities that come from a documented event say so; the ones invented for the format are labelled
`GAME MECHANIC` in their own description text, visible in the hero select screen and the Codex.

## Relationships

The feature with no genre equivalent. Place two characters who are associated in the story and both
get a permanent bonus for the run, announced on screen and listed in the HUD.

All 18 bonds are researched, not invented. Theo is Parrot's bodyguard; Eggchan is Wemmbu's best
friend; Lomedy armed Flame with the mace; Mapicc is Spoke's deuteragonist; Deputy_Ace died freeing
Parrot. The *bonus* is game design, but the *relationship* is sourced, and the Codex shows the basis
and the citations for every one.

Mechanically this pushes against pure optimisation: the best pair of towers by raw DPS is often not
the best pair once a bond is counted, which makes the roster feel like a cast rather than a stat list.

## Bosses

A boss is not a large enemy with a big health bar. Saparata's encounter has five phases, each built on
something that actually happened at Fort Feather and in the Civil War:

1. **Cindercrest Vanguard** — the ground assault the fort repelled.
2. **Elite Strike** — ShoeBilly, whose helmet breaks at half health, as Wemmbu's stab shots broke it.
3. **The Redstone Blimp** — a destructible airship dropping slow-falling paratroopers behind the
   walls. Shooting it down stops the drops; that is the player's counter-play.
4. **Saparata Enters** — Ember Strike stuns your nearest tower; Revanchist Call heals him while his
   soldiers are near, so killing his escort is how you kill him.
5. **The Usurper King** — Persuasion turns one of your towers against you for five seconds, Royal
   Defectors join the waves, and below 25% he enrages.

## Progression

Within a run: emeralds, tower upgrades, hero levels.

Between runs: hero meta-levels (a small permanent damage bonus), XP Bottles, map completion records,
and Codex unlocks. Winning Fort Feather unlocks Merchant City. Codex entries unlock by encountering
their subject, so the research database is revealed by playing.

## Presentation

Blocky, readable, and deliberately not photoreal. Characters are built from the standard humanoid box
layout so that community skin files map correctly. Armour is separate 3D geometry, shaped as shells so
the character's face stays visible and identifiable under a full helmet. Enchanted gear gets an
animated glint. The camera frames the whole battlefield by default and zooms to inspect.

Everything the player needs to read at a glance is a silhouette or a colour: gear tier by armour
material, faction by tint, threat by size, and boss phase by the banner across the top.

## Balance approach

Numbers are set for readability rather than tuned by playtest — that is stated plainly in
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md). The intended shape is:

- Wave strength (total HP × count) roughly doubles between the first and last third of a map; the test
  suite asserts this ramp exists.
- Tower cost-per-DPS is roughly flat at tier 0, so early choices are about role, not power.
- Signature (tier 4) upgrades are deliberately over-costed relative to their DPS, because they also
  bring a qualitative change.
- The boss can be beaten by a full board of maxed towers, which the boss test verifies.
