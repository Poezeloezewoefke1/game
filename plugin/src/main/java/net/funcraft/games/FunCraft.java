package net.funcraft.games;

import net.funcraft.games.command.Commands;
import net.funcraft.games.command.Duels;
import net.funcraft.games.game.GameManager;
import net.funcraft.games.listener.GameListener;
import net.funcraft.games.listener.HubListener;
import net.funcraft.games.util.Worlds;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;
import org.bukkit.plugin.java.JavaPlugin;

public final class FunCraft extends JavaPlugin {

    private GameManager games;
    private Hub hub;
    private Stats stats;
    private Sidebars sidebars;
    private Duels duels;
    private Kits kits;
    private FfaEvent ffa;
    private Parkour parkour;
    private Parties parties;
    private AntiCheat antiCheat;
    private net.funcraft.games.listener.ChatListener chat;
    private HubListener hubListener;
    private int ticks;

    @Override
    public void onEnable() {
        saveDefaultConfig();
        Worlds.cleanLeftovers(this);

        stats = new Stats(this);
        kits = new Kits(this);
        kits.load();
        ffa = new FfaEvent(this);
        parkour = new Parkour(this);
        parties = new Parties();
        games = new GameManager(this);
        sidebars = new Sidebars(this);
        duels = new Duels(this);
        hub = new Hub(this);
        hub.load();

        hubListener = new HubListener(this);
        getServer().getPluginManager().registerEvents(hubListener, this);
        getServer().getPluginManager().registerEvents(new GameListener(this), this);
        getServer().getPluginManager().registerEvents(parkour, this);
        antiCheat = new AntiCheat(this);
        getServer().getPluginManager().registerEvents(antiCheat, this);
        chat = new net.funcraft.games.listener.ChatListener();
        getServer().getPluginManager().registerEvents(chat, this);
        Bukkit.getScheduler().runTaskTimer(this, parkour::tick, 40L, 2L);
        new Commands(this).register();

        Bukkit.getScheduler().runTaskTimer(this, () -> {
            games.tick();
            ffa.tick();
            sidebars.updateAll();
            if (++ticks % 5 == 0) {
                hub.refreshLabels();
            }
            if (ticks % 60 == 0) {
                stats.saveAsync();
            }
        }, 20L, 20L);

        // Players already online after a /reload
        for (Player p : Bukkit.getOnlinePlayers()) {
            hub.send(p);
        }
        getLogger().info("FunCraft Games enabled - " + net.funcraft.games.game.GameType.values().length + " minigames ready.");
    }

    @Override
    public void onDisable() {
        if (games != null) {
            games.shutdown();
        }
        if (stats != null) {
            stats.saveNow();
        }
    }

    public String serverName() {
        return getConfig().getString("server-name", "FunCraft");
    }

    public String footer() {
        return getConfig().getString("sidebar-footer", "<gold>Have fun!");
    }

    public GameManager games() {
        return games;
    }

    public Hub hub() {
        return hub;
    }

    public Stats stats() {
        return stats;
    }

    public Sidebars sidebars() {
        return sidebars;
    }

    public Duels duels() {
        return duels;
    }

    public Kits kits() {
        return kits;
    }

    public net.funcraft.games.listener.ChatListener chat() {
        return chat;
    }

    public AntiCheat antiCheat() {
        return antiCheat;
    }

    public Parties parties() {
        return parties;
    }

    public Parkour parkour() {
        return parkour;
    }

    public FfaEvent ffa() {
        return ffa;
    }

    public HubListener hubListener() {
        return hubListener;
    }
}
