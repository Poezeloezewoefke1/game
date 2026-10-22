# FunCraft – Minecraft minigame server

A ready-to-run minigame server to play with your friends. It's one Paper plugin with
**8 minigames, a hub lobby, stats and a kit-vote FFA event**. Every map is generated
automatically, so there's nothing to build or set up in-game.

| Game | What it is | Players |
|------|------------|---------|
| **BedWars** | Up to 4 teams with beds, iron/gold generators, diamond and emerald islands, an item shop and team upgrades. Fireballs, TNT and permanent armor are in. | 2–8 |
| **SkyWars** | Each player starts in a cage on their own island. Loot the chests, bridge to the middle (better loot) and be the last one alive. Chests refill at 4:00. Pick a starter kit (Fighter, Archer, Builder, Enderman, Healer, Bomber) in the queue. | 2–8 |
| **Build Battle** | Everyone gets the same theme (40 built in) and 5 minutes in creative mode, then votes on every build from *Super Poop* to *Legendary*. | 2–12 |
| **PvP Arena** | Free-for-all in a gladiator arena with a kit. Last one alive wins. | 2–12 |
| **Duels** | 1v1. Queue up or challenge someone: `/duel <player> [kit]`. | 2 |
| **Spleef** | Two snow floors over the void. Dig out the snow under the others, and use snowballs too. | 2–12 |
| **TNT Run** | The floor vanishes behind you. Three layers and three double jumps. | 2–12 |
| **Sumo** | Knock everyone off the platform with your fists. Everyone has 3 lives. | 2–8 |

Plus:
- **Hub island** with an NPC for every game, a game-selector compass, a live player count and a top-wins leaderboard.
- **FFA event for ops:** `/fc ffa` starts a kit vote for everyone online. When the vote ends, **everyone online is put in one big FFA**. If you die you spectate, and the last one alive wins.
- **16 PvP kits:** Classic, Sword, Axe, Mace, UHC, Netherite OP, Pot, SMP, Crystal, Bed Fight, Bridge, Creeper PvP, Dia SMP, Fireball Fight, Spear Elytra and Spear Mace. They're used by the FFA event, the PvP Arena and duels. Fire charges throw fireballs and TNT lights itself.
- **Stats:** wins, kills, deaths, games and K/D per game (`/stats`), shown in the sidebar.
- **Random map themes:** SkyWars and BedWars islands come in Plains, Desert, Snowy, Nether, The End, Mushroom or Cherry Blossom. Arenas can be a Colosseum, Desert Temple, Nether Fortress, Ocean Monument or Deep Dark. TNT Run and Sumo get random colours.
- **Combat feedback:** your target's health on your action bar when you hit them, a +1 Kill notice, and killstreak announcements (3 / UNSTOPPABLE 5 / GODLIKE 7 / LEGENDARY 10, plus "X ended Y's streak").
- **[PLAY AGAIN]** button when a game ends puts you straight back in the queue; after a duel it's **[REMATCH]** with the same kit.
- Varied death messages ("was knocked into the void by", "was sent to the shadow realm by", ...) and a lightning strike when someone is eliminated.
- **Hub:** double jump (press jump twice), launch pads, and a **parkour course** around the island with checkpoints, a timer and a best-times leaderboard.
- **BedWars team picker:** choose your team while you're in the queue, so you can team up with friends (teams stay balanced).
- **Spectate:** `/spectate <player>` lets you watch a friend's game.
- Sidebar scoreboard, titles, sounds, fireworks for the winner, team-coloured name tags in BedWars.

## Commands

| Command | |
|---------|--|
| `/play [game]` | Join a game queue (no argument opens the menu). Games: `bedwars skywars buildbattle pvp duels spleef tntrun sumo` |
| `/leave` (`/hub`, `/lobby`) | Leave your game or queue |
| `/duel <player> [kit]` | Challenge someone to a 1v1 (they click **[ACCEPT]**) |
| `/vote` | Open the FFA kit vote |
| `/stats [player]` | Show stats |
| `/spectate <player>` | Watch someone's game |

**Op-only (`/fc`):**

| Command | |
|---------|--|
| `/fc ffa` | Start a kit vote, then put **everyone online** into an FFA |
| `/fc ffa <kit>` | Skip the vote and start the FFA with that kit (e.g. `/fc ffa mace`) |
| `/fc ffa cancel` | Cancel the vote |
| `/fc start [id]` | Force-start a queue now. Works with 1 player, so you can look at the maps alone |
| `/fc skip [id]` | Skip the countdown or the current phase (e.g. Build Battle build time) |
| `/fc stop [id]` | End a game |
| `/fc list` | Running games |
| `/fc build` | Toggle building in the hub (needs creative) |
| `/fc rebuildhub` | Regenerate the hub island |
| `/fc reload` | Reload `config.yml` and `kits.yml` |
| `/fc selftest` | Generate every map once to check everything works |

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
