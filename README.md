# FunCraft – Minecraft minigame server

A ready-to-run minigame server to play with your friends. It's one Paper plugin with
**30 minigames, lobby bots, a hub lobby, stats and a kit-vote FFA event**. Every map is generated
automatically, so there's nothing to build or set up in-game.

| Game | What it is | Players |
|------|------------|---------|
| **BedWars** | Up to 4 teams with beds, iron/gold generators, diamond and emerald islands, an item shop and team upgrades. Fireballs, TNT, permanent armor and an "It's a Trap!" upgrade are in. Old-school spam-click PvP. | 2–8 |
| **Bed Fight** | Red vs Blue (automatic teams). Bridge to the other island and break their bed; after that they can't respawn. | 2–8 |
| **The Bridge** | Red vs Blue across a narrow bridge. Jump into the enemy's end portal to score; every point resets the round. First to 5 wins. | 2–8 |
| **Fireball Fight** | Red vs Blue on islands far apart. Fireballs only knock back, so fireball-jump across and break their bed. Fireballs and wool regenerate. | 2–8 |
| **SkyWars** | A 40-island archipelago with a huge castle island in the middle. Each player starts in a cage on their own island with a house. Loot the chests, bridge across and be the last one alive. Chests refill at 4:00. Pick a starter kit (Fighter, Archer, Builder, Enderman, Healer, Bomber) in the queue. | 2–8 |
| **Build Battle** | Everyone gets the same theme (40 built in) and 5 minutes in creative mode (with a floor changer), then votes on every build from *Super Poop* to *Legendary*. Plots are walled in while you build, so nobody can peek or copy. | 2–12 |
| **PvP Arena** | Free-for-all in a gladiator arena with a kit. Last one alive wins. | 2–12 |
| **Duels** | 1v1. Queue up or challenge someone: `/duel <player> [kit]`. | 2 |
| **Spleef** | Two snow floors over the void. Dig out the snow under the others; snowballs break snow and knock players back. | 2–12 |
| **TNT Run** | The floor vanishes behind you. Three layers and three double jumps. | 2–12 |
| **Block Party** | A colour is called; stand on it before every other colour vanishes. The floor and timer get faster every round. | 2–16 |
| **One in the Chamber** | A sword, a bow and one arrow. Arrows kill in one hit and every kill gives you another. You respawn; first to 15 kills wins. | 2–12 |
| **Sumo** | Knock everyone off the platform with your fists. Everyone has 3 lives. | 2–8 |
| **Pillars of Fortune** | Everyone starts on a bedrock pillar over the void and gets a random item every 4 seconds: blocks, swords, bows, TNT, fireballs, pearls, wind charges, a knockback stick, even a mace. Build, bridge and knock them off. After 5 minutes items come twice as fast. | 2–12 |
| **TNT Tag** | Hot potato with TNT. Whoever has it glows and is faster; hit someone to pass it on. When the timer runs out, everyone still holding TNT blows up. Rounds get shorter until one survivor is left. | 2–16 |
| **Murder Mystery** | One secret murderer (a knife after 10 s), one detective with a bow, everyone else innocent. Collect gold: 10 gold gets you a bow. Shoot an innocent and you die too; if the detective dies, their bow drops for someone else. Name tags are hidden. | 3–12 |
| **Hide and Seek** | Hide in a big village for 30 seconds while the seekers wait in a box in the sky. Seekers glow; one hit finds a hider, who becomes a seeker too. In the last minute hiders give themselves away every 15 seconds. Survive 4 minutes to win. | 2–16 |
| **Zombie Survival** | Co-op. Hold out against 10 night waves of zombies, skeletons, spiders, husks and creepers, with a Zombie Brute on wave 5 and the Zombie King on wave 10. Fallen players come back next wave; every cleared wave upgrades everyone's gear. | 1–8 |
| **Gun Game** | Every kill swaps your weapon for the next of 12: netherite sword, power bow, diamond axe, trident, mace, crossbow ... down to the Golden Knife. A kill with the knife wins. | 2–12 |
| **Quake** | Railguns that kill in one shot (right click), plus speed and high jumps. Headshots get announced. First to 20 kills. | 2–12 |
| **King of the Hill** | A golden hill in a village. Stand on it alone to score a point a second; if it's contested, nobody scores. First to 100. | 2–12 |
| **Paintball** | Red vs Blue with endless snowballs in a park full of cover. Every hit splats them back to base. First team to 30. | 2–16 |
| **Parkour Race** | Everyone gets their own lane of the same random 44-jump course with emerald checkpoints. Falling puts you back on your checkpoint. First to the gold platform wins. | 2–8 |
| **Red Light, Green Light** | Run to the red line while the giant looks away. Move on a red light and you're out. Everyone who makes it across wins. | 2–16 |
| **Bow Spleef** | An Infinity bow on a two-layer TNT floor over the void. Every arrow blows a hole where it lands. Last one standing. | 2–12 |
| **Anvil Rain** | Anvils fall from the sky, faster and faster, and some aim right at you. One hit and you're out. | 2–12 |
| **UHC Meetup** | A random UHC kit (iron/diamond gear, golden apples, lava and water buckets, blocks) on a hilly island. No natural regeneration, and the world border closes in after a minute. Last one alive wins. | 2–16 |
| **The Floor is Lava** | Lava rises through a hilly map full of towers, one layer every few seconds and faster as time goes on. Climb, build up with your cobblestone and knock others down with the push stick. | 2–16 |
| **Capture the Flag** | Red vs Blue. Grab the enemy banner and bring it to your base while your own flag is home. The carrier glows; kill them and the flag drops. First to 3 captures. | 2–16 |
| **Simon Says** | Jump, crouch, look up, punch someone, stand on red, don't move... but only when Simon says! Rounds get faster. | 2–16 |

Plus:
- **Lobby bots:** fake players (no Minecraft account needed) hang out in the hub and **join any queue where a real player is waiting**, so a game can start even when only you or a couple of friends are online. They really play: they fight, bridge across gaps, break beds, run for the portal in The Bridge, find the Block Party colour, freeze on red lights, jump the parkour, collect gold in Murder Mystery, hide and seek, fight zombies, chase the flag... They accept `/duel` challenges too, say "gg" after a game, show up as `[BOT]` in the tab list and never count for stats or leaderboards. Manage them with `/fc bots` and `bots:` in `config.yml`.
- **Hub island** with an NPC for every game, a game-selector compass, a live player count and a top-wins leaderboard.
- **FFA event for ops:** `/fc ffa` starts a kit vote for everyone online. When the vote ends, **everyone online is put in one big FFA**. If you die you spectate, and the last one alive wins.
- **16 PvP kits:** Classic, Sword, Axe, Mace, UHC, Netherite OP, Pot, SMP, Crystal, Bed Fight, Bridge, Creeper PvP, Dia SMP, Fireball Fight, Spear Elytra and Spear Mace. They're used by the FFA event, the PvP Arena and duels. Fire charges throw fireballs and TNT lights itself.
- **Stats:** wins, kills, deaths, games and K/D per game (`/stats`), shown in the sidebar.
- **Buildings on the maps:** houses, towers, wells, ruins, lamp posts and castles in the map's theme.
- **Crystal and Creeper kits** play on a deep, fully destructible terrain map, so you can blast and dig down. Creepers from spawn eggs are lit instantly and stand still until hit. Fireballs knock back instead of hurting.
- **Random map themes:** SkyWars and BedWars islands come in Plains, Desert, Snowy, Nether, The End, Mushroom or Cherry Blossom. Arenas can be a Colosseum, Desert Temple, Nether Fortress, Ocean Monument or Deep Dark. TNT Run and Sumo get random colours.
- **Combat feedback:** your target's health on your action bar when you hit them, a +1 Kill notice, and killstreak announcements (3 / UNSTOPPABLE 5 / GODLIKE 7 / LEGENDARY 10, plus "X ended Y's streak").
- **[PLAY AGAIN]** button when a game ends puts you straight back in the queue; after a duel it's **[REMATCH]** with the same kit.
- Varied death messages ("was knocked into the void by", "was sent to the shadow realm by", ...) and a lightning strike when someone is eliminated.
- **Quick Play** in the game menu joins the queue with the most players waiting.
- **Hub:** double jump (press jump twice), launch pads, and a **parkour course** around the island with checkpoints, a timer and a best-times leaderboard.
- **BedWars team picker:** choose your team while you're in the queue, so you can team up with friends (teams stay balanced).
- **Spectate:** `/spectate <player>` lets you watch a friend's game.
- **Parties:** `/party invite <friend>`. When the party leader joins a game, the whole party comes along, and in BedWars a party is kept on one team when the teams have room.
- **Levels:** earn XP from games (10), kills (5) and wins (50). Your level `[12✫]` shows in chat, the tab list and the hub sidebar, and level-ups are announced. Your name in chat has your BedWars team colour.
- **Built-in anti-cheat:** catches Fly, Speed, Reach, KillAura, AutoClicker, FastPlace/Scaffold and FastBreak/Nuker. Movement cheats get pulled back, too-long hits are cancelled, ops get `[AC]` alerts and very high violation levels get kicked. Fireballs, launch pads, explosions, wind charges, maces, spears and elytras are exempt, so legit play doesn't flag. Configure it under `anticheat:` in `config.yml`.
- Boss bar timers (next BedWars/SkyWars event, build time, time left), sidebar scoreboard, titles, sounds, fireworks for the winner, team-coloured name tags in BedWars.

## Commands

| Command | |
|---------|--|
| `/play [game]` | Join a game queue (no argument opens the menu). Games: `bedwars skywars buildbattle pvp duels spleef tntrun blockparty oitc sumo bedfight bridge fireball pillars tnttag murder hideandseek zombies gungame quake koth paintball parkour redlight bowspleef anvilrain uhc lava ctf simon` |
| `/leave` (`/hub`, `/lobby`) | Leave your game or queue |
| `/duel <player> [kit]` | Challenge someone to a 1v1 (they click **[ACCEPT]**) |
| `/vote` | Open the FFA kit vote |
| `/stats [player]` | Show stats |
| `/spectate <player>` | Watch someone's game |
| `/party invite <player>` (`/p`) | Party up; also `accept`, `leave`, `kick`, `list`, `chat <msg>` |

**Op-only (`/fc`):**

| Command | |
|---------|--|
| `/fc ffa` | Start a kit vote, then put **everyone online** into an FFA |
| `/fc ffa <kit>` | Skip the vote and start the FFA with that kit (e.g. `/fc ffa mace`) |
| `/fc ffa cancel` | Cancel the vote |
| `/fc start [id]` | Force-start a queue now. Works with 1 player, so you can look at the maps alone |
| `/fc ac [player\|alerts]` | Anti-cheat violations, or turn your alerts on/off |
| `/fc skip [id]` | Skip the countdown or the current phase (e.g. Build Battle build time, a TNT Tag round or the Hide and Seek hiding time) |
| `/fc stop [id]` | End a game |
| `/fc list` | Running games |
| `/fc build` | Toggle building in the hub (needs creative) |
| `/fc rebuildhub` | Regenerate the hub island |
| `/fc reload` | Reload `config.yml` and `kits.yml` |
| `/fc selftest` | Generate every map once to check everything works |
| `/fc bots` | Bot status. `/fc bots add [n]`, `remove [n\|all]`, `clear`, `list`, `fill on\|off` (turns queue filling and the hub bots on/off) |

## Running the server

### 1. Get the plugin

Pick one:
- **Download** `FunCraftGames.jar` from the [Releases page](https://github.com/Poezeloezewoefke1/game/releases) (published automatically for every commit on `main`), or from the *Actions* tab → latest run → *FunCraftGames* artifact.
- **Build it yourself** (Java 21): `cd plugin && ./gradlew build`. The jar is at `plugin/build/libs/FunCraftGames.jar`.

Put the jar in the `plugins/` folder of this repo.

### 2a. Start with Docker (easiest)

1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/).
2. Open `docker-compose.yml` and put your Minecraft name in `OPS: ""` so you can use `/fc`.
3. Run:
   ```
   docker compose up -d
   ```
   The first start downloads Paper and takes a minute. Logs: `docker compose logs -f`. Console: `docker attach funcraft` (detach with Ctrl+P, Ctrl+Q).

`VERSION: "LATEST"` runs the newest Minecraft version. If you and your friends play on an older version, set it to that, e.g. `"1.21.11"`.

### 2b. Start without Docker

1. Install Java 21 (Java 25 for Minecraft 26.x).
2. Download Paper from <https://papermc.io/downloads/paper> and save it as `server/paper.jar`.
3. Run `server/start.bat` (Windows) or `server/start.sh` (Mac/Linux).
4. Type `op YourName` in the server console.

### 3. Let your friends join

- **Same Wi-Fi/house:** they join your computer's local IP (e.g. `192.168.1.20`).
- **Over the internet:** either forward port **25565** (TCP) on your router to your computer and give friends your public IP, or use a free tunnel like [playit.gg](https://playit.gg) and share the address it gives you.

Recommended: at least 4 GB of RAM for the server.

## Configuration

After the first start these files are in `data/plugins/FunCraftGames/` (Docker) or `server/plugins/FunCraftGames/`:

- `config.yml`: enable/disable games, min/max players, countdown, Build Battle time and themes, the kit for the PvP queue and duels, FFA vote length, server name.
- `kits.yml`: all PvP kits. The format is simple, one line per item: `"netherite_sword sharpness:5 unbreaking:3"`, `"golden_apple x64"`, `"splash_potion potion:strong_healing"`, `"leather_chestplate unbreakable color:#FF5555"`, `"crossbow quick_charge:1 charged:strong_harming"`. Add your own and run `/fc reload`.
- `stats.yml`: everybody's stats.

## How it works

- Players wait in the hub while queued. When a game starts, a fresh empty world is created, the map is generated, and the world is deleted again when the game ends. No resetting, no map files.
- Deaths are handled by the plugin (no death screen). In BedWars you respawn while your bed stands; in the other games you become a spectator. Totems of undying still work.

Project layout:

```
plugin/              the Paper plugin (Java 21, Gradle)
  src/main/java/net/funcraft/games/
    game/            game engine: queues, match lifecycle, death handling
    games/           the minigames (bedwars/, SkyWars, BuildBattle, PvpArena, ...)
    Hub.java         hub island, NPCs, menus
    FfaEvent.java    /fc ffa kit vote
    Kits.java        kits.yml loader
  src/main/resources/  plugin.yml, config.yml, kits.yml
docker-compose.yml   one-command server
server/              start scripts without Docker
test/                bot test used by CI (two bots join and play every game)
```

CI (`.github/workflows/build.yml`) builds the plugin and starts a real Paper server for 1.21.11 and the newest version. It generates every map with `/fc selftest` and, on 1.21.11, has two bots join and play: every game, a real PvP fight to the death, BedWars void deaths, respawns, bed breaking and final kills, Build Battle voting, kit duels and the FFA event.

## Credits

The Sword, Axe, Mace, UHC, Netherite OP, Pot, SMP and Crystal kits follow the MCTiers default
kit layouts as collected in [HelixCraft/Minecraft-PVP-Kits](https://github.com/HelixCraft/Minecraft-PVP-Kits).
They were rewritten as `kits.yml` entries for this plugin. The Bed Fight, Bridge, Creeper PvP, Dia SMP, Fireball Fight,
Spear Elytra and Spear Mace kits were converted from PlayerKits `.dat` files.
