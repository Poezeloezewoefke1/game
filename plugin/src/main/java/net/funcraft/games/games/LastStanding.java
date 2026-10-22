package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.Msg;
import org.bukkit.Location;
import org.bukkit.entity.Player;

import java.util.ArrayList;
import java.util.List;

/** Base for solo games on a single arena where the last player alive wins. */
public abstract class LastStanding extends Game {

    protected final List<Location> spawns = new ArrayList<>();
    protected Location center;

    protected LastStanding(FunCraft plugin, int id, GameType type) {
        super(plugin, id, type);
    }

    /** Give the player their kit; called after teleporting. */
    protected abstract void equip(Player player);

    /** Seconds until the match ends in a draw; 0 for no limit. */
    protected int timeLimit() {
        return 600;
    }

    protected String objective() {
        return "Be the last one standing!";
    }

    /** Evenly spaced spawn points on a circle, all looking at the centre. */
    protected void spawnRing(double y, double radius, int count) {
        spawns.clear();
        for (int i = 0; i < count; i++) {
            double a = Math.toRadians(i * 360.0 / count);
            Location l = new Location(world, center.getX() + Math.cos(a) * radius, y, center.getZ() + Math.sin(a) * radius);
            spawns.add(Build.lookAt(l, new Location(world, center.getX(), y, center.getZ())));
        }
    }

    @Override
    protected void onStart(List<Player> list) {
        for (int i = 0; i < list.size(); i++) {
            Player p = list.get(i);
            p.teleport(spawns.get(i % spawns.size()));
            equip(p);
            Msg.title(p, "<bold>" + type.colored(), "<gray>" + objective(), 5, 50, 10);
        }
    }

    @Override
    protected void onSecond() {
        if (timeLimit() <= 0) {
            return;
        }
        int left = timeLimit() - elapsed;
        bossBar("<yellow>Time left: <white>" + Msg.time(left) + " <dark_gray>| <green>" + alive.size() + " alive",
                (float) left / timeLimit(), net.kyori.adventure.bossbar.BossBar.Color.YELLOW);
        if (left == 60 || left == 30 || left == 10) {
            Msg.all(online(), "<yellow>" + left + " seconds left!");
        }
        if (left <= 0) {
            Msg.all(online(), "<red>Time is up!");
            end(null, List.of());
        }
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        deathMessage(victim, killer, null);
        eliminate(victim, true);
        if (alive.size() > 1) {
            Msg.all(online(), "<gray>" + alive.size() + " players remaining.");
        }
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        lines.add("<white>Alive: <green>" + alive.size() + "/" + startingPlayers);
        if (timeLimit() > 0) {
            lines.add("<white>Time left: <yellow>" + Msg.time(timeLimit() - elapsed));
        }
        lines.add("  ");
        lines.add("<white>Your kills: <red>" + kills.getOrDefault(player.getUniqueId(), 0));
        lines.addAll(extraSidebar(player));
        return lines;
    }

    protected List<String> extraSidebar(Player player) {
        return List.of();
    }

    @Override
    protected Location spectatorSpawn() {
        return center.clone().add(0, 12, 0);
    }
}
