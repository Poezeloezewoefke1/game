package net.funcraft.games;

import net.funcraft.games.game.Game;
import net.funcraft.games.util.Sidebar;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Owns one {@link Sidebar} per online player and refreshes it every second. */
public final class Sidebars {

    private final FunCraft plugin;
    private final Map<UUID, Sidebar> sidebars = new HashMap<>();

    public Sidebars(FunCraft plugin) {
        this.plugin = plugin;
    }

    public Sidebar of(Player player) {
        return sidebars.computeIfAbsent(player.getUniqueId(), id -> new Sidebar(player));
    }

    /** Fresh scoreboard (drops team colours from the previous match). */
    public void reset(Player player) {
        sidebars.put(player.getUniqueId(), new Sidebar(player));
        update(player);
    }

    public void remove(Player player) {
        sidebars.remove(player.getUniqueId());
    }

    public void updateAll() {
        for (Player p : Bukkit.getOnlinePlayers()) {
            update(p);
        }
    }

    public void update(Player player) {
        Sidebar sidebar = of(player);
        player.sendPlayerListHeaderAndFooter(
                net.funcraft.games.util.Msg.mm("\n<gradient:#ffb300:#ff5e00><bold>" + plugin.serverName() + "</bold></gradient>\n<gray>"
                        + Bukkit.getOnlinePlayers().size() + " online\n"),
                net.funcraft.games.util.Msg.mm("\n<gray>/play <dark_gray>|</dark_gray> /duel <dark_gray>|</dark_gray> /spectate <dark_gray>|</dark_gray> /stats\n"));
        Game game = plugin.games().gameOf(player);
        if (game != null) {
            sidebar.update(game.sidebarTitle(), game.sidebarFor(player));
            return;
        }
        Stats s = plugin.stats();
        UUID id = player.getUniqueId();
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>Hub");
        lines.add(" ");
        lines.add("<white>Player: <yellow>" + player.getName());
        lines.add("<white>Online: <green>" + Bukkit.getOnlinePlayers().size());
        lines.add("  ");
        lines.add("<white>Wins: <green>" + s.get(id, "total", "wins"));
        lines.add("<white>Kills: <red>" + s.get(id, "total", "kills"));
        lines.add("<white>Games: <aqua>" + s.get(id, "total", "games"));
        lines.add("   ");
        lines.add("<gray>Use the <gold>compass</gold> or");
        lines.add("<gray>click an <gold>NPC</gold> to play!");
        lines.add("    ");
        lines.add(plugin.footer());
        sidebar.update("<gradient:#ffb300:#ff5e00><bold>" + plugin.serverName() + "</bold></gradient>", lines);
    }
}
