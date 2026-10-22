package net.funcraft.games.game;

import net.funcraft.games.FunCraft;
import net.funcraft.games.games.bedwars.BedWars;
import net.funcraft.games.games.BlockParty;
import net.funcraft.games.games.BuildBattle;
import net.funcraft.games.games.PvpArena;
import net.funcraft.games.games.SkyWars;
import net.funcraft.games.games.Spleef;
import net.funcraft.games.games.Sumo;
import net.funcraft.games.games.TntRun;
import org.bukkit.Material;

import java.util.List;
import java.util.Locale;
import java.util.function.BiFunction;

public enum GameType {

    BEDWARS("BedWars", "<red>", Material.RED_BED, 2, 8, BedWars::new,
            "Protect your bed, collect resources at",
            "your generator and buy gear from the shop.",
            "Destroy enemy beds to stop them respawning!"),
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
    SUMO("Sumo", "<green>", Material.SLIME_BALL, 2, 8, Sumo::new,
            "Knock everyone off the platform with",
            "your fists. Last one standing wins.");

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
            default -> null;
        };
    }
}
