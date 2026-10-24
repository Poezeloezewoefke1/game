package net.funcraft.games;

import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Msg;
import org.bukkit.Bukkit;
import org.bukkit.configuration.ConfigurationSection;
import org.bukkit.configuration.file.YamlConfiguration;
import org.bukkit.entity.Player;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.logging.Level;

/** Wins, kills, deaths and games played, per game and in total, stored in stats.yml. */
public final class Stats {

    public record Entry(String name, int value) {
    }

    private final FunCraft plugin;
    private final File file;
    private YamlConfiguration data;
    private boolean dirty;

    public Stats(FunCraft plugin) {
        this.plugin = plugin;
        this.file = new File(plugin.getDataFolder(), "stats.yml");
        this.data = YamlConfiguration.loadConfiguration(file);
    }

    private void add(Player player, GameType type, String stat) {
        if (plugin.bots() != null && plugin.bots().isBot(player)) {
            return; // bots stay off the leaderboards
        }
        int before = level(player.getUniqueId());
        String base = player.getUniqueId().toString();
        data.set(base + ".name", player.getName());
        data.set(base + ".total." + stat, data.getInt(base + ".total." + stat) + 1);
        data.set(base + "." + type.key() + "." + stat, data.getInt(base + "." + type.key() + "." + stat) + 1);
        dirty = true;
        int after = level(player.getUniqueId());
        if (after > before) {
            Msg.all(new ArrayList<>(Bukkit.getOnlinePlayers()), "<gold>" + player.getName() + " <yellow>reached " + levelTag(after) + "<yellow>!");
            Msg.title(player, "<gold><bold>LEVEL UP!", levelTag(after), 5, 50, 10);
            Msg.sound(player, "entity.player.levelup", 1f);
        }
    }

    // ---------------------------------------------------------------- levels

    /** XP from everything you've done: games played, kills and (mostly) wins. */
    public int xp(UUID uuid) {
        return get(uuid, "total", "games") * 10 + get(uuid, "total", "kills") * 5 + get(uuid, "total", "wins") * 50;
    }

    /** Level n needs 50*n*(n-1) xp in total: 0, 100, 300, 600, 1000, ... */
    public static int levelFor(int xp) {
        return (int) Math.floor((1 + Math.sqrt(1 + 8 * xp / 100.0)) / 2);
    }

    public static int xpForLevel(int level) {
        return 50 * level * (level - 1);
    }

    public int level(UUID uuid) {
        return levelFor(xp(uuid));
    }

    public static String levelColor(int level) {
        if (level >= 50) {
            return "<light_purple>";
        } else if (level >= 30) {
            return "<aqua>";
        } else if (level >= 20) {
            return "<gold>";
        } else if (level >= 10) {
            return "<yellow>";
        } else if (level >= 5) {
            return "<white>";
        }
        return "<gray>";
    }

    public static String levelTag(int level) {
        return levelColor(level) + "[" + level + "✫]";
    }

    public void addWin(Player player, GameType type) {
        add(player, type, "wins");
    }

    public void addKill(Player player, GameType type) {
        add(player, type, "kills");
    }

    public void addDeath(Player player, GameType type) {
        add(player, type, "deaths");
    }

    public void addGame(Player player, GameType type) {
        add(player, type, "games");
    }

    /** @param scope "total" or a game key */
    public int get(UUID uuid, String scope, String stat) {
        return data.getInt(uuid + "." + scope + "." + stat);
    }

    public String nameOf(UUID uuid) {
        return data.getString(uuid + ".name", "?");
    }

    public boolean has(UUID uuid) {
        return data.isConfigurationSection(uuid.toString());
    }

    public UUID find(String name) {
        for (String key : data.getKeys(false)) {
            if (name.equalsIgnoreCase(data.getString(key + ".name"))) {
                try {
                    return UUID.fromString(key);
                } catch (IllegalArgumentException ignored) {
                    return null;
                }
            }
        }
        return null;
    }

    public List<Entry> top(String scope, String stat, int limit) {
        List<Entry> list = new ArrayList<>();
        for (Map.Entry<String, Object> e : data.getValues(false).entrySet()) {
            if (e.getValue() instanceof ConfigurationSection section) {
                int value = section.getInt(scope + "." + stat);
                if (value > 0) {
                    list.add(new Entry(section.getString("name", "?"), value));
                }
            }
        }
        list.sort((a, b) -> Integer.compare(b.value(), a.value()));
        return list.subList(0, Math.min(limit, list.size()));
    }

    /** Best (lowest) time in ms for a timed challenge, 0 if none. */
    public long getBest(UUID uuid, String key) {
        return data.getLong(uuid + ".best." + key);
    }

    public void setBest(Player player, String key, long ms) {
        data.set(player.getUniqueId() + ".name", player.getName());
        data.set(player.getUniqueId() + ".best." + key, ms);
        dirty = true;
    }

    /** Lowest times first. */
    public List<Entry> topBest(String key, int limit) {
        List<Entry> list = new ArrayList<>();
        for (Map.Entry<String, Object> e : data.getValues(false).entrySet()) {
            if (e.getValue() instanceof ConfigurationSection section) {
                long value = section.getLong("best." + key);
                if (value > 0) {
                    list.add(new Entry(section.getString("name", "?"), (int) Math.min(Integer.MAX_VALUE, value)));
                }
            }
        }
        list.sort((a, b) -> Integer.compare(a.value(), b.value()));
        return list.subList(0, Math.min(limit, list.size()));
    }

    public void saveAsync() {
        if (!dirty) {
            return;
        }
        dirty = false;
        String yaml = data.saveToString();
        Bukkit.getScheduler().runTaskAsynchronously(plugin, () -> write(yaml));
    }

    public void saveNow() {
        dirty = false;
        write(data.saveToString());
    }

    private synchronized void write(String yaml) {
        try {
            plugin.getDataFolder().mkdirs();
            java.nio.file.Files.writeString(file.toPath(), yaml);
        } catch (IOException e) {
            plugin.getLogger().log(Level.WARNING, "Could not save stats", e);
        }
    }
}
