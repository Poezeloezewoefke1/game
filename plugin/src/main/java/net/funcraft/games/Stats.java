package net.funcraft.games;

import net.funcraft.games.game.GameType;
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
        String base = player.getUniqueId().toString();
        data.set(base + ".name", player.getName());
        data.set(base + ".total." + stat, data.getInt(base + ".total." + stat) + 1);
        data.set(base + "." + type.key() + "." + stat, data.getInt(base + "." + type.key() + "." + stat) + 1);
        dirty = true;
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
