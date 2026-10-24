package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Msg;
import net.kyori.adventure.bossbar.BossBar;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.entity.Player;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Base for free-for-all games where you respawn and race to a score (Gun Game, Quake, King of
 * the Hill): spawns far from other players, respawn timers, a leader boss bar and a top-5 sidebar.
 */
public abstract class RespawnGame extends Game {

    protected static final int Y = 64;

    protected final List<Location> spawns = new ArrayList<>();
    private final Map<UUID, Integer> respawning = new HashMap<>();

    protected RespawnGame(FunCraft plugin, int id, GameType type) {
        super(plugin, id, type);
    }

    /** Items and effects a player gets every time they spawn. */
    protected abstract void loadout(Player player);

    protected abstract int score(UUID player);

    protected abstract int goal();

    /** e.g. "kills" or "points". */
    protected abstract String scoreName();

    protected abstract String objective();

    protected int timeLimit() {
        return 420;
    }

    protected int respawnSeconds() {
        return 3;
    }

    /** Called every second while running, before the leader and timer are updated. */
    protected void tickGame() {
    }

    /** Called when a player kills another player. */
    protected void onKill(Player killer, Player victim) {
    }

    @Override
    protected void onStart(List<Player> list) {
        for (Player p : list) {
            spawn(p);
            Msg.title(p, "<bold>" + type.colored(), "<gray>" + objective(), 5, 60, 10);
        }
    }

    /** Puts the player at the spawn point furthest from everyone else, with a fresh loadout. */
    protected void spawn(Player p) {
        Location far = spawns.get(random.nextInt(spawns.size()));
        double best = -1;
        for (Location s : spawns) {
            double nearest = Double.MAX_VALUE;
            for (Player other : alivePlayers()) {
                if (!other.equals(p) && other.getWorld() == world && other.getGameMode() != GameMode.SPECTATOR) {
                    nearest = Math.min(nearest, other.getLocation().distanceSquared(s));
                }
            }
            if (nearest > best) {
                best = nearest;
                far = s;
            }
        }
        plugin.games().prepare(p, GameMode.SURVIVAL);
        p.teleport(far);
        loadout(p);
        p.addPotionEffect(new PotionEffect(PotionEffectType.RESISTANCE, 40, 4, false, false));
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        deathMessage(victim, killer, null);
        if (killer != null && isAlive(killer)) {
            onKill(killer, victim);
            if (state != State.RUNNING) {
                return;
            }
            checkGoal(killer);
            if (state != State.RUNNING) {
                return;
            }
        }
        victim.getInventory().clear();
        victim.setGameMode(GameMode.SPECTATOR);
        victim.teleport(spectatorSpawn());
        respawning.put(victim.getUniqueId(), respawnSeconds());
        Msg.title(victim, "<red><bold>YOU DIED", "<gray>Respawning in " + respawnSeconds() + "...", 0, 30, 5);
    }

    /** Ends the game if the player reached the goal. */
    protected void checkGoal(Player p) {
        int s = score(p.getUniqueId());
        if (s >= goal()) {
            end(p.getName(), List.of(p.getUniqueId()));
        } else if (s == goal() - 3 && goal() > 6) {
            Msg.all(online(), "<gold>" + p.getName() + " <yellow>needs just 3 more " + scoreName() + "!");
        }
    }

    @Override
    protected void onSecond() {
        for (Map.Entry<UUID, Integer> e : new ArrayList<>(respawning.entrySet())) {
            Player p = Bukkit.getPlayer(e.getKey());
            if (p == null || !isAlive(p)) {
                respawning.remove(e.getKey());
            } else if (e.getValue() <= 1) {
                respawning.remove(e.getKey());
                spawn(p);
            } else {
                respawning.put(e.getKey(), e.getValue() - 1);
            }
        }
        tickGame();
        if (state != State.RUNNING) {
            return;
        }
        int left = timeLimit() - elapsed;
        UUID leader = leader();
        Player lp = leader == null ? null : Bukkit.getPlayer(leader);
        bossBar(bossText(lp == null ? "-" : lp.getName() + " (" + score(leader) + ")") + " <dark_gray>| <yellow>" + Msg.time(left),
                (float) left / timeLimit(), BossBar.Color.RED);
        if (left <= 0) {
            if (lp == null) {
                end(null, List.of());
            } else {
                end(lp.getName(), List.of(leader));
            }
        }
    }

    protected String bossText(String leader) {
        return "<white>Leader: <gold>" + leader;
    }

    protected boolean isRespawning(Player p) {
        return respawning.containsKey(p.getUniqueId());
    }

    protected UUID leader() {
        UUID best = null;
        int most = 0;
        for (UUID id : alive) {
            int s = score(id);
            if (s > most) {
                most = s;
                best = id;
            }
        }
        return best;
    }

    @Override
    protected void checkWin() {
        if (state == State.RUNNING && alive.size() == 1 && startingPlayers > 1) {
            UUID last = alive.iterator().next();
            Player p = Bukkit.getPlayer(last);
            end(p == null ? "?" : p.getName(), List.of(last));
        }
    }

    @Override
    protected double voidLevel() {
        return Y - 25;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 0.5, Y + 24, 0.5, 0, 70);
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        lines.add("<white>First to <gold>" + goal() + "</gold> " + scoreName());
        lines.add("  ");
        List<UUID> top = new ArrayList<>(alive);
        top.sort((a, b) -> score(b) - score(a));
        for (int i = 0; i < Math.min(5, top.size()); i++) {
            Player p = Bukkit.getPlayer(top.get(i));
            lines.add("<yellow>" + (i + 1) + ". <white>" + (p == null ? "?" : p.getName()) + " <gray>" + score(top.get(i)));
        }
        lines.add("   ");
        lines.addAll(extraSidebar(player));
        lines.add("<white>Time: <yellow>" + Msg.time(timeLimit() - elapsed));
        return lines;
    }

    protected List<String> extraSidebar(Player player) {
        return List.of("<white>You: <green>" + score(player.getUniqueId()) + " " + scoreName());
    }

    @Override
    protected void cleanup() {
        respawning.clear();
    }
}
