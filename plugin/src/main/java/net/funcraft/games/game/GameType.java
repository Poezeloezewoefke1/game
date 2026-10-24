package net.funcraft.games.game;

import net.funcraft.games.FunCraft;
import net.funcraft.games.games.bedwars.BedWars;
import net.funcraft.games.games.BedDuel;
import net.funcraft.games.games.BlockParty;
import net.funcraft.games.games.Bridge;
import net.funcraft.games.games.BuildBattle;
import net.funcraft.games.games.OneInTheChamber;
import net.funcraft.games.games.Pillars;
import net.funcraft.games.games.PvpArena;
import net.funcraft.games.games.SkyWars;
import net.funcraft.games.games.Spleef;
import net.funcraft.games.games.Sumo;
import net.funcraft.games.games.TntRun;
import net.funcraft.games.games.TntTag;
import net.funcraft.games.games.AnvilRain;
import net.funcraft.games.games.BowSpleef;
import net.funcraft.games.games.GunGame;
import net.funcraft.games.games.HideAndSeek;
import net.funcraft.games.games.KingOfTheHill;
import net.funcraft.games.games.MurderMystery;
import net.funcraft.games.games.Paintball;
import net.funcraft.games.games.ParkourRace;
import net.funcraft.games.games.Quake;
import net.funcraft.games.games.RedLightGreenLight;
import net.funcraft.games.games.ZombieSurvival;
import org.bukkit.Material;

import java.util.List;
import java.util.Locale;
import java.util.function.BiFunction;

public enum GameType {

    BEDWARS("BedWars", "<red>", Material.RED_BED, 2, 8, BedWars::new,
            "Protect your bed, collect resources at",
            "your generator and buy gear from the shop.",
            "Destroy enemy beds to stop them respawning!"),
    BED_FIGHT("Bed Fight", "<red>", Material.WHITE_BED, 2, 8, BedDuel::bedFight,
            "Red vs Blue. Bridge over to the other",
            "island and break their bed - after that",
            "they can't respawn. Teams are automatic."),
    BRIDGE("The Bridge", "<blue>", Material.END_PORTAL_FRAME, 2, 8, Bridge::new,
            "Fight across a narrow bridge and jump",
            "into the enemy's end portal to score.",
            "First team to 5 points wins!"),
    FIREBALL_FIGHT("Fireball Fight", "<gold>", Material.FIRE_CHARGE, 2, 8, BedDuel::fireballFight,
            "Fireballs only knock back - fireball-jump",
            "across the gap, build, and break the",
            "enemy bed. Teams are automatic."),
    SKYWARS("SkyWars", "<aqua>", Material.ENDER_EYE, 2, 8, SkyWars::new,
            "Start on your own sky island, loot the",
            "chests, bridge to the middle and be the",
            "last player standing."),
    BUILD_BATTLE("Build Battle", "<light_purple>", Material.BRICKS, 2, 12, BuildBattle::new,
            "Everyone gets the same theme and a few",
            "minutes to build it. Then everybody votes",
            "on each build. Highest score wins!"),
    PVP("PvP Arena", "<gold>", Material.DIAMOND_SWORD, 2, 12, PvpArena::pvp,
            "Free-for-all fight in a gladiator arena",
            "with a full kit. Last one alive wins."),
    DUELS("Duels", "<yellow>", Material.IRON_SWORD, 2, 2, PvpArena::duels,
            "1v1 fight. Queue up or challenge a",
            "friend with <white>/duel <player></white>."),
    SPLEEF("Spleef", "<white>", Material.DIAMOND_SHOVEL, 2, 12, Spleef::new,
            "Dig the snow out from under the other",
            "players. Snowballs break blocks too.",
            "Don't fall - last one on the floor wins!"),
    TNT_RUN("TNT Run", "<dark_red>", Material.TNT, 2, 12, TntRun::new,
            "The floor disappears behind you. Keep",
            "running and use your double jumps wisely!"),
    BLOCK_PARTY("Block Party", "<light_purple>", Material.JUKEBOX, 2, 16, BlockParty::new,
            "A colour gets called - stand on it before",
            "every other colour disappears! Each round",
            "is faster. Last dancer standing wins."),
    OITC("One in the Chamber", "<gold>", Material.BOW, 2, 12, OneInTheChamber::new,
            "Arrows kill in one hit and you only get",
            "one. Every kill gives you another arrow.",
            "First to 15 kills wins - don't miss!"),
    SUMO("Sumo", "<green>", Material.SLIME_BALL, 2, 8, Sumo::new,
            "Knock everyone off the platform with",
            "your fists. Last one standing wins."),
    PILLARS("Pillars of Fortune", "<dark_aqua>", Material.BEDROCK, 2, 12, Pillars::new,
            "Everyone stands on a pillar over the void",
            "and gets a random item every few seconds.",
            "Build, bridge and knock them all off!"),
    TNT_TAG("TNT Tag", "<red>", Material.TNT_MINECART, 2, 16, TntTag::new,
            "Got the TNT? Hit someone to pass it on",
            "before the timer runs out - or blow up!",
            "Last survivor wins."),
    MURDER_MYSTERY("Murder Mystery", "<dark_red>", Material.SKELETON_SKULL, 3, 12, MurderMystery::new,
            "One secret murderer, one detective with",
            "a bow. Collect gold, stay alive and",
            "work out who did it!"),
    HIDE_AND_SEEK("Hide and Seek", "<green>", Material.SPYGLASS, 2, 16, HideAndSeek::new,
            "Hide somewhere in the village before the",
            "seekers come out. Found hiders join the",
            "seekers. Survive the timer to win!"),
    ZOMBIES("Zombie Survival", "<dark_green>", Material.ZOMBIE_HEAD, 1, 8, ZombieSurvival::new,
            "Team up against 10 waves of monsters",
            "at night. Better gear after every wave",
            "and bosses on waves 5 and 10."),
    GUN_GAME("Gun Game", "<gold>", Material.CROSSBOW, 2, 12, GunGame::new,
            "Every kill swaps your weapon for the",
            "next one. Get a kill with all 12 weapons",
            "- ending with the Golden Knife - to win!"),
    QUAKE("Quake", "<aqua>", Material.IRON_HOE, 2, 12, Quake::new,
            "Railguns that kill in one shot, speed",
            "and high jumps. First to 20 kills wins."),
    KING_OF_THE_HILL("King of the Hill", "<yellow>", Material.GOLDEN_HELMET, 2, 12, KingOfTheHill::new,
            "Stand on the hill alone to score points.",
            "Knock everyone else off - first to 100!"),
    PAINTBALL("Paintball", "<light_purple>", Material.SNOWBALL, 2, 16, Paintball::new,
            "Red vs Blue with endless snowballs. Every",
            "hit splats them back to base. First team",
            "to 30 points wins!"),
    PARKOUR("Parkour Race", "<green>", Material.FEATHER, 2, 8, ParkourRace::new,
            "Race your friends on a random jump",
            "course with checkpoints. First to the",
            "gold platform wins!"),
    RED_LIGHT("Red Light, Green Light", "<light_purple>", Material.REDSTONE_LAMP, 2, 16, RedLightGreenLight::new,
            "Run to the finish while the giant looks",
            "away. Move on a red light and you're out!"),
    BOW_SPLEEF("Bow Spleef", "<red>", Material.SPECTRAL_ARROW, 2, 12, BowSpleef::new,
            "Every arrow blows a hole in the TNT floor.",
            "Shoot the ground out from under them!"),
    ANVIL_RAIN("Anvil Rain", "<gray>", Material.ANVIL, 2, 12, AnvilRain::new,
            "Anvils fall from the sky - faster and",
            "faster. One hit and you're out!");

    private final String displayName;
    private final String color;
    private final Material icon;
    private final int defaultMin;
    private final int defaultMax;
    private final BiFunction<FunCraft, Integer, Game> factory;
    private final List<String> description;

    GameType(String displayName, String color, Material icon, int min, int max,
             BiFunction<FunCraft, Integer, Game> factory, String... description) {
        this.displayName = displayName;
        this.color = color;
        this.icon = icon;
        this.defaultMin = min;
        this.defaultMax = max;
        this.factory = factory;
        this.description = List.of(description);
    }

    public String displayName() {
        return displayName;
    }

    /** Display name wrapped in the game's MiniMessage colour. */
    public String colored() {
        return color + displayName;
    }

    public String color() {
        return color;
    }

    public Material icon() {
        return icon;
    }

    public List<String> description() {
        return description;
    }

    public String key() {
        return name().toLowerCase(Locale.ROOT).replace("_", "");
    }

    public int minPlayers(FunCraft plugin) {
        return Math.max(1, plugin.getConfig().getInt("games." + key() + ".min-players", defaultMin));
    }

    public int maxPlayers(FunCraft plugin) {
        if (this == DUELS) {
            return 2;
        }
        return Math.max(minPlayers(plugin), plugin.getConfig().getInt("games." + key() + ".max-players", defaultMax));
    }

    public boolean enabled(FunCraft plugin) {
        return plugin.getConfig().getBoolean("games." + key() + ".enabled", true);
    }

    public Game create(FunCraft plugin, int id) {
        return factory.apply(plugin, id);
    }

    public static GameType parse(String input) {
        String in = input.toLowerCase(Locale.ROOT).replace("_", "").replace("-", "").replace(" ", "");
        for (GameType type : values()) {
            if (type.key().equals(in) || type.displayName.toLowerCase(Locale.ROOT).replace(" ", "").equals(in)) {
                return type;
            }
        }
        return switch (in) {
            case "bw", "bed" -> BEDWARS;
            case "sw", "sky" -> SKYWARS;
            case "bb", "build" -> BUILD_BATTLE;
            case "arena", "ffa" -> PVP;
            case "duel", "1v1" -> DUELS;
            case "tnt", "tntrun" -> TNT_RUN;
            case "party", "bp", "blockparty", "disco" -> BLOCK_PARTY;
            case "oneinthechamber", "chamber", "1itc" -> OITC;
            case "bedfight", "bf" -> BED_FIGHT;
            case "thebridge", "bridges" -> BRIDGE;
            case "fireball", "fireballs", "ff", "fbf" -> FIREBALL_FIGHT;
            case "pillar", "pof", "pillarsoffortune", "fortune" -> PILLARS;
            case "tag", "tnttag", "hotpotato", "tntt" -> TNT_TAG;
            case "murder", "mm", "murdermystery" -> MURDER_MYSTERY;
            case "hide", "hns", "hideseek", "hideandseek" -> HIDE_AND_SEEK;
            case "zombie", "zombiesurvival", "waves", "survival" -> ZOMBIES;
            case "gun", "gg", "gungame" -> GUN_GAME;
            case "rail", "railgun", "quakecraft" -> QUAKE;
            case "koth", "hill", "king" -> KING_OF_THE_HILL;
            case "paint", "pb", "snowballfight" -> PAINTBALL;
            case "parkourrace", "race", "jump" -> PARKOUR;
            case "rlgl", "greenlight", "squidgame", "redlightgreenlight" -> RED_LIGHT;
            case "bowspleef", "bs" -> BOW_SPLEEF;
            case "anvil", "anvils" -> ANVIL_RAIN;
            default -> null;
        };
    }
}
