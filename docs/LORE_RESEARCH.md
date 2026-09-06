# Lore Research

How the Unstable Universe research behind this game was gathered, what confidence it carries, and
where the sources disagree.

## Method, and its honest limits

The brief asked for a serious multi-source research pass. Here is exactly what happened.

**Direct page fetching was blocked.** This build environment routes outbound HTTPS through a
policy-enforcing proxy. Both primary destinations were refused:

```
unstable-universe-mc.fandom.com   → EGRESS_BLOCKED
unstablesmp.gg                    → EGRESS_BLOCKED
crafty.gg                         → EGRESS_BLOCKED
```

Research therefore proceeded through **search-engine result summaries** of those same pages: the
community wiki's article extracts, TV Tropes recap pages, and the official site's metadata as
surfaced in search. Roughly 25 targeted searches were run across characters, factions, locations,
arcs, battles, weapons and episodes.

**What that means for the data.** Every claim in `data/lore/*.json` carries the page it came from and
a confidence tier. But those citations record *which page the statement came from*, not that the full
page was read end to end. A statement marked `supported` is one the wiki asserts in a snippet that
was actually seen; it has not been cross-checked against the episode itself. This distinction is
recorded in the schema block of `data/lore/characters.json` and is repeated here so nobody mistakes
the citation list for full-text verification.

**Nothing was invented and labelled canon.** Where the game needed a mechanic the sources do not
provide — which they very often do, because a tower-defense game needs numbers and the story does not
have them — the entry says `GAME MECHANIC` in its own text. The in-game Codex shows the confidence
tier next to every entry, so a player can see the difference too.

## Confidence tiers

| Tier | Meaning | Example |
|---|---|---|
| `canon_confirmed` | Stated by the official site, or by multiple independent sources | The four protagonists are Spoke, Parrot, Wemmbu and FlameFrags |
| `supported` | Asserted by the community wiki in a snippet that was seen | ShoeBilly killed 999 of the 1,000 Skymore settlers |
| `uncertain` | Partial, inferred, or contradicted between sources | The Fake Identity Arc's exact contents |
| `fan_theory` | Community interpretation, not canon | *(no entry currently uses this tier)* |

## The four protagonists

The official UnstableSMP site describes the series as one story told through four perspectives, and
names Spoke, Parrot, Wemmbu and FlameFrags as those perspectives. This is the single most load-bearing
fact in the project and it is the reason the game is built around choosing exactly one hero per run.

FlameFrags is the late addition — he has been uploading his perspective since Season 2, where the
other three date from Season 1.

## Arcs overlap; the timeline is not a line

The brief specifically warned against flattening the arcs into one sequence, and the sources bear that
out. `data/lore/arcs.json` records overlap explicitly in a `concurrent_with` field rather than forcing
a single ordering. The clearest cases:

- **Treasure Arc / Fake Identity Arc / Skill vs Power Arc** run at the same time across Parrot's,
  Wemmbu's and Flame's POVs. Parrot traps Wemmbu and Flame in a cell in his own arc; the same events
  appear from the other side in theirs.
- **Kingdoms Saga / NULL Arc / Purgatory Arc** are concurrent in Season 3. Spoke is taking over the
  NULL while Parrot's kingdom is being dismantled by Cindercrest; the two threads only touch at the
  end, when the NULL captures a Cindercrest stronghold.
- **Zam Empire Arc** runs alongside the **Invisible Mafia Arc** in Season 1.

The game's map select shows each map's arc, and the Codex's Arcs category lists the concurrency.

## Contradictions found, and how they are recorded

Where sources disagree, both readings are stored rather than one being silently chosen.

1. **Seasons vs arcs as the organising unit.** The wiki states that seasons were abolished in favour
   of arcs after Season 1, yet also maintains Season 2 and Season 3 pages with date ranges. Both are
   recorded in `arcs.json` — the seasons block carries the dates, and the note explains the conflict.

2. **Two arcs numbered "the 16th".** The BAT Arc and the Kingdoms Saga are both described as the 16th
   arc. Both `order_hint` values are kept as given; neither was adjusted to remove the clash.

3. **Who led the attack in the Toxic War.** Flame's arc describes an unnamed toxic-civilization leader
   whom he beats 1v1, while a wiki summary of the same arc names SpokeIsHere as leading the attacking
   group. `factions.json` records both and marks the entry `uncertain`.

4. **Capital City vs Capitol City.** The sources use both spellings, and there appear to be distinct
   entities (Reddoons' Capital City 2.0; Fymada's Capitol City 2.0). `locations.json` keeps both names
   and both leaders on one entry rather than merging or splitting them on a guess.

## What was researched

| Category | Entries | File |
|---|---|---|
| Characters | 49 | `data/lore/characters.json` |
| Arcs (+ 3 seasons) | 18 | `data/lore/arcs.json` |
| Factions | 21 | `data/lore/factions.json` |
| Locations | 19 | `data/lore/locations.json` |
| Events / battles | 34 | `data/lore/events.json` |
| Weapons and technology | 20 | `data/lore/weapons.json` |
| Boss tiering | 12 | `data/lore/bosses.json` |

## Key findings that shaped the game

**Cindercrest is the right first antagonist.** Saparata leads a revanchist faction of veteran players
that kills new players or forces them to work, on the argument that the old players are "starving".
That is a tower-defense premise as written: a faction that marches on the places where new players are
protected. Fort Feather is where they first tried it.

**Fort Feather is the right first map.** It is the first battle of the Civil War, it has a documented
two-stage assault (a ground attack the fort repelled, then slow-falling paratroopers from a Redstone
Blimp that took it), and it ends with Parrot detonating TNT in his own fort. That gives the map a
boss encounter with real structure instead of a health bar.

**The Chungie gear ladder is the enemy system.** The sources are dense with Minecraft gear as a status
marker — Cindercrest can field thousands in netherite; maces are rare because the Invisible Mafia
destroyed the ominous spawners; Wemmbu broke ShoeBilly's *helmet* specifically. So enemy tiers are
gear tiers, each layer visibly breaks off, and armor is modelled as separate 3D pieces.

**Relationships are the unique mechanic, and they are all real.** Every one of the 18 relationship
bonds is a documented association: Theo is Parrot's bodyguard, Eggchan is Wemmbu's best friend, Lomedy
armed Flame with the mace, Mapicc is Spoke's deuteragonist. The *bonus* is a game mechanic; the
*relationship* is sourced, and the Codex shows the basis and the sources for each one.

**Wemmbu's orbital strikes are documented in detail.** The Orbital Strike Cannon has a real described
mechanism (TNT duplicated in lazy chunks, coordinates delivered by book to a Nether control room) and
two named shot types — stab shots and nuke shots. Both became abilities with those names.

## Primary sources consulted

Official:
- `unstablesmp.gg` — series description, the four protagonists, creator profiles

Community wiki (`unstable-universe-mc.fandom.com`), pages including:
`Wemmbu`, `Wemmbu/History`, `Wemmbu/Relationships`, `ParrotX2`, `ParrotX2/Relationships`,
`FlameFrags`, `FlameFrags/History`, `SpokeIsHere`, `SpokeIsHere/History`, `Saparata`, `ShoeBilly`,
`Arachn1d`, `Ashswagg`, `ClownPierce`, `LettuceK`, `TheobaldTheBird`, `Eggchan`, `Lomedy`, `Mapicc`,
`Leow0ok`, `ReinaDrop`, `Deputy_Ace`, `Spepticle`, `Purpled`, `Fymada`, `4CVIT`, `Jaden_MAN`,
`PrinceZam`, `Cindercrest`, `Parrot's Kingdom`, `The Invisible Mafia`, `The Law`, `The NULL`,
`Spider Web Faction`, `Arachnid's Kingdom`, `Skymore Civilization`, `Ice Mountain Civilization`,
`Skyblock Civilization`, `Eggchan's Civilization`, `Wemmbu's Civilization`, `Far Lands Civilisation`,
`Bounty Assassin Team`, `NULL Hunters`, `Pirates`, `Fort Feather`, `Spawn`, `Capitol City 2.0`,
`Steampunk City`, `Northern Council`, `Landmarks of Unstable`, `Maces`, `Orbital Strike Cannon`,
`Blimp`, `Important Items in Unstable Universe`, `Battles of Unstable`, `Kingdoms Saga`,
`The Kingdoms Arc`, `Kings Arc`, `The Treasure Arc`, `The Power Arc`, `Toxic War Arc`,
`Skill vs Power Arc`, `Invisible Mafia Arc`, `Zam Empire Arc`, `Pirate Arc`, `BAT Arc`,
`Purgatory Arc`, `End Civilisation Arc`, `Warriors Council`, `Teams`, `All Members`, `Episode Order`,
`Season 1`, `Season 3`, `Unstable SMP: Civil War`, `Blog:Cart PvP/Carting`

Secondary:
- TV Tropes recap pages for the Civil War finale
- `villains.fandom.com` for Ashswagg's antagonist framing

## Reproducing or extending the research

The database is plain JSON and the game reads it live. To correct or extend an entry:

1. Edit the entry in `data/lore/*.json`.
2. Keep `research_sources` (or `sources`) and `confidence` accurate — the test suite fails the build
   if any entry is missing either, and the Codex renders both.
3. Run the suite: `godot --headless --path . -s tests/run_headless.gd -- res://tests/test_suite.gd 4`

The suite enforces that every lore entry has an id, a confidence tier drawn from the four known
values, and at least one source; that the four protagonists are flagged as such; and that at least
three arcs record concurrency.
