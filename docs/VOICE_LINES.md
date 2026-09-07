# Voice Lines — recording script

A script you can hand to each creator. Every line is written for the character as the series shows
them, and each block says what game moment triggers it so the read has a reason behind it.

## How to read the tags

Each line carries one tag:

| Tag | Meaning |
|-----|---------|
| **[C]** | **Canon-grounded.** References an event the research database records as `canon_confirmed`. The reference is real; the wording is ours. |
| **[S]** | **Supported.** References something the community wiki reports but that has not been cross-checked against an episode. Safe, but softer. |
| **[G]** | **Game mechanic.** Invented for this game. Refers to a tower-defence idea (waves, emeralds, upgrades) that does not exist in the series. |

Nothing here is a real quote. If a creator remembers saying something better, **their version wins** —
these are prompts, not scripts, and the file should be updated to match what they actually record.

## Recording notes

- **Format:** WAV, OGG or MP3 all work — send whatever is easiest. Mono, 48 kHz, 16-bit or better if
  you have the choice. Name each file `<character>_<key>`, e.g. `parrotx2_ability_1.mp3`; keys are in
  each table. Naming files after the *line text* is fine too — that is what ParrotX2's set did, and
  matching them back up took a minute — filenames get their `?` and `"` stripped and non-ASCII
  mangled on the way through a zip, so the matcher ignores punctuation entirely.
- **Length:** 1–2 seconds for combat barks, up to 4 for arc lines. Anything longer will be cut off by
  the next game event.
- **Takes:** three per line — one flat, one urgent, one wry. Combat barks repeat a lot, so variety
  matters more than perfection.
- **Room:** dry and close. The game applies its own positioning and mixing.
- **Priority:** if a creator only has ten minutes, record the **bold** lines. Those are the ones a
  player hears in the first two minutes of a run.

---

## ParrotX2 — the First King

Leadership hero: buffs towers, funds the defence, summons the Royal Army. Plays like a commander, so
the read is measured rather than loud. He has lost a kingdom already and is trying not to lose
another.

| Key | Trigger | Line | Tag |
|-----|---------|------|-----|
| `select` | Chosen at hero select | **"Fort Feather holds. That's not a hope, that's an order."** | [C] |
| `placed` | Dropped on the map | "Positions, everyone. We've done this before." | [G] |
| `ability_1` | Royal Decree (tower attack speed) | **"Royal Decree — everyone, faster!"** | [G] |
| `ability_2` | Fort Feather (wall) | "Raise the wall! Hold the road!" | [C] |
| `ability_3` | Royal Army (summons) | **"Royal Army, to me!"** | [C] |
| `ultimate` | I Became King | **"I built this kingdom once. I'll do it again."** | [C] |
| `level_2` | Level up | "The line's tightening. Good." | [G] |
| `level_15` | Late level up | "A hundred days, I said. We're not done yet." | [C] |
| `wave_clear` | Wave survived | "Hold. Next one's coming." | [G] |
| `low_lives` | Under 25 lives | **"They're inside the walls. Everyone, back to the keep!"** | [G] |
| `boss_enter` | Saparata appears | **"Saparata. You took my crown. You don't get the fort."** | [C] |
| `victory` | Campaign won | "Fort Feather stands. Write that down." | [G] |
| `defeat` | Campaign lost | "Blow the tunnel. Everyone out. We rebuild." | [C] |

> `ability_2` and `defeat` both reference Parrot building Fort Feather to train an army and rigging it
> with TNT rather than letting Cindercrest take it.

---

## Wemmbu — the Strongest Player

Aggressive melee hero built around the mace and orbital strikes. Cocky, fast, enjoys the fight — but
he has been betrayed enough times that the confidence has an edge to it.

| Key | Trigger | Line | Tag |
|-----|---------|------|-----|
| `select` | Chosen at hero select | **"You want them gone? Point me at them."** | [G] |
| `placed` | Dropped on the map | "Fine. I'll do it myself." | [G] |
| `ability_1` | Mace slam | **"Gambit!"** | [C] |
| `ability_2` | Stab Shot | "Orbital — locked." | [C] |
| `ability_3` | Nuke Shot | **"Everybody move!"** | [C] |
| `ultimate` | Full orbital barrage | **"You've all seen what this thing does."** | [C] |
| `level_2` | Level up | "Better. Keep them coming." | [G] |
| `level_15` | Late level up | "I've been in the pit. This is nothing." | [S] |
| `wave_clear` | Wave survived | "That's it? Next." | [G] |
| `low_lives` | Under 25 lives | **"Don't you dare clutch this. I've got it."** | [S] |
| `boss_enter` | Saparata appears | "Netherite. Cute. I've killed better." | [S] |
| `victory` | Campaign won | "Told you. Point me at them." | [G] |
| `defeat` | Campaign lost | "...I had it. I had it." | [G] |

> `ability_1` names the mace *Gambit* (Density V, Mending, Unbreaking III, Fire Aspect II, Wind Burst
> II), his signature weapon. `level_15` refers to the pit he was imprisoned in with PrinceZam.

---

## SpokeIsHere — Leader of the NULL

Control hero: traps, conversion, denial. He does not shout. Quiet, deliberate, always a step ahead —
someone who has been on every side of this server and is comfortable there.

| Key | Trigger | Line | Tag |
|-----|---------|------|-----|
| `select` | Chosen at hero select | **"They'll walk right into it. They always do."** | [G] |
| `placed` | Dropped on the map | "Nobody sees me until I want them to." | [C] |
| `ability_1` | Wind Charge Trap | **"Wind charge. Watch your footing."** | [C] |
| `ability_2` | Turncoat (convert an enemy) | **"You work for me now."** | [S] |
| `ability_3` | Nullify | "Null." | [S] |
| `ultimate` | The NULL army | **"The NULL doesn't negotiate."** | [S] |
| `level_2` | Level up | "Good. They're predictable." | [G] |
| `level_15` | Late level up | "I've been inside the Mafia. This is easy." | [C] |
| `wave_clear` | Wave survived | "Next group. Same trap." | [G] |
| `low_lives` | Under 25 lives | **"Fine. No more games."** | [G] |
| `boss_enter` | Saparata appears | "A king who thinks he's the first. Cute." | [S] |
| `victory` | Campaign won | "It was always going to end like this." | [G] |
| `defeat` | Campaign lost | "Hm. I miscalculated." | [G] |

> `placed` refers to Spoke operating as an invisible player; `level_15` to infiltrating the Invisible
> Mafia. **Note for the creator:** `ability_2` is the in-game "Turncoat" ability, which flips an enemy
> to your side — it is a game mechanic named after his infiltration arc, not a claim about a specific
> episode.

---

## FlameFrags — the Duelist

Single-target burst and survivability. Direct, unfussy, no posturing — a man who wins 1v1s and does
not need to explain how. Warmer than the others when Lomedy comes up.

| Key | Trigger | Line | Tag |
|-----|---------|------|-----|
| `select` | Chosen at hero select | **"One at a time. That's how I do this."** | [C] |
| `placed` | Dropped on the map | "Right. Who's first?" | [G] |
| `ability_1` | Duel Challenge | **"You. One-vee-one. Now."** | [C] |
| `ability_2` | Mace Drop | "Lomedy gave me this. Don't waste it." | [C] |
| `ability_3` | TNT minecart | **"Theo taught me this one!"** | [S] |
| `ultimate` | Burst finisher | **"I've beaten a whole civilization on my own. You're nothing."** | [C] |
| `level_2` | Level up | "Getting warmed up." | [G] |
| `level_15` | Late level up | "I took the farm. I'm not losing this one." | [C] |
| `wave_clear` | Wave survived | "Clear. Send more." | [G] |
| `low_lives` | Under 25 lives | **"Get behind me!"** | [G] |
| `boss_enter` | Saparata appears | "Finally. Someone worth it." | [G] |
| `victory` | Campaign won | "Hey Lomedy — we held it." | [C] |
| `defeat` | Campaign lost | "I'm sorry. I couldn't hold them." | [C] |

> The Toxic War arc is the spine of this set: he was hunted by a toxic civilization, forced his way
> into Lomedy's farm, was given Lomedy's old teammate's mace, killed the attackers, beat the leader
> 1v1, and later apologised and returned both maces. `defeat` deliberately echoes that apology.

---

## Saparata — the boss

Cindercrest's king. He should never sound like a raider. He believes he is correcting an injustice:
the veteran players are starving because the server keeps filling with new ones. Calm, certain,
almost reasonable — which is what makes him frightening.

| Key | Trigger | Line | Tag |
|-----|---------|------|-----|
| `phase_1` | Vanguard enters | **"Cindercrest is moving on the fort."** | [C] |
| `phase_2` | Elite strike | "You built an army out of children, Parrot." | [S] |
| `phase_3` | Blimp assault | **"Look up."** | [S] |
| `phase_4` | Saparata enters | **"The old players are starving. Every one of these new spawns is why."** | [C] |
| `phase_5` | Usurper King | **"I am the King of Unstable. You were just first."** | [C] |
| `persuade` | Converts a tower | "You know I'm right. Stand aside." | [C] |
| `taunt_a` | Random, mid-fight | "You lost this the day you let them in." | [S] |
| `taunt_b` | Random, mid-fight | "My friends died for your kingdom." | [C] |
| `low_hp` | Below 25% | "...Then take it from me." | [G] |
| `death` | Defeated | **"Skymore. Say their names. Say them."** | [S] |
| `victory` | Player loses | "Retreat through your tunnel, Parrot. Merchant City is next." | [S] |

> `persuade` is the in-game ability that flips a tower, named after the Royal Army defecting to him.
> `death` refers to Cindercrest destroying Skymore — ShoeBilly killed 999 of 1,000 settlers, and
> ReinaDrop is one of the survivors.

---

## Towers — short barks

Fourteen characters, so keep these to a single word or short phrase. Each tower needs four:
**place**, **upgrade**, **signature** (its tier-4 upgrade) and **sold**. All are [G] — they are about
placing turrets, which is not something the series does — but each is written toward that character's
role in the story.

| Character | place | upgrade | signature | sold |
|-----------|-------|---------|-----------|------|
| Royal Recruit | "Reporting!" | "Better gear!" | "For the King!" | "Aw..." |
| TheobaldTheBird | "I've got carts." | "More TNT." | "Everybody back up!" | "Fine, fine." |
| Eggchan | "Hi!" | "Ooh, upgrade!" | "The Egg provides." | "Bye!" |
| Lomedy | "Off my farm." | "Reinforced." | "The Farm War taught me this." | "Back to the crops." |
| Mapicc | "On it." | "Sharper." | "Nobody's faster." | "Later." |
| Leow0ok | "Target?" | "Cleaner." | "Contract accepted." | "Understood." |
| MinuteTech | "Give me a minute." | "Rewired." | "Trap's live. Don't touch it." | "Packing up." |
| ReinaDrop | "I can help." | "More supplies." | "Nobody else dies today." | "Take care." |
| Spepticle | "I see them." | "Clearer now." | "Nothing hides from me." | "Eyes off." |
| Deputy_Ace | "Deputy Ace, reporting." | "Deputised." | "This is the law." | "Off duty." |
| 4CVIT | "Ready." | "Tighter." | "Nobody moves." | "Falling back." |
| Purpled | "Fine." | "Better." | "You're wasting my time." | "Finally." |
| Fymada | "I'll build it." | "Reinforced!" | "Get them out — all of them!" | "It'll hold." |
| Jaden_MAN | "Which side am I on today?" | "Upgraded." | "This one's for me." | "Nothing personal." |

> ReinaDrop's signature line leans on her being one of two Skymore survivors — she is the medic
> because of it. Jaden_MAN's lines lean on his switching between antagonist and ally.

---

## Where these go

Save recordings to `assets/audio/voice/<character>_<key>.mp3` (`.ogg` and `.wav` also work) and add
each to `data/asset_manifest.json` with the creator's name and the permission they gave.

**Playback is built.** `AudioMgr.play_voice(character, key)` looks the file up by that naming
convention and does nothing if it is absent, so **adding a creator's lines needs no code and no data
entry — just the files.** A `Voice` bus ducks the music by 9 dB while a line plays, and a new line
replaces one already playing rather than talking over it.

Recorded so far:

| Character | Status |
|-----------|--------|
| **ParrotX2** | **All 13 lines recorded and in the game.** |
| **Wemmbu** | **All 13 lines recorded and in the game.** |
| SpokeIsHere | not recorded |
| FlameFrags | not recorded |
| Saparata | not recorded |
| Towers (14) | not recorded |

Two notes for the remaining sets. `level_2` plays on any level-up below 15 and `level_15` from 15
upward, so they want to be readable at either point in a run. `low_lives` fires once, the first time
the base drops under a quarter — it is a "this is going badly" line, not a repeated alarm.

If a creator wants to record something not on this list, take it. A line the person actually wants to
say will always beat a line written for them.
