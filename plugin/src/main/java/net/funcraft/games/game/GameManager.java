package net.funcraft.games.game;

import net.funcraft.games.FunCraft;
import net.funcraft.games.util.Msg;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.World;
import org.bukkit.entity.Player;
import org.bukkit.potion.PotionEffect;
import org.bukkit.util.Vector;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Keeps track of every match and which player is in which match. */
public final class GameManager {

    private final FunCraft plugin;
    private final List<Game> games = new ArrayList<>();
    private final Map<UUID, Game> byPlayer = new HashMap<>();
    private int nextId = 1;

    public GameManager(FunCraft plugin) {
        this.plugin = plugin;
    }

    /** Puts a player in the queue of the given game type. */
    public void join(Player player, GameType type) {
        if (!type.enabled(plugin)) {
            Msg.send(player, "<red>" + type.displayName() + " is disabled on this server.");
            return;
        }
        Game current = byPlayer.get(player.getUniqueId());
        if (current != null && current.state() == Game.State.ENDING) {
            // "Play again" while the previous match is still showing its results
            current.removePlayer(player);
            plugin.hub().send(player);
            current = null;
        }
        if (current != null) {
            if (current.type() == type && current.state() != Game.State.RUNNING) {
                Msg.send(player, "<gray>You are already in the " + type.displayName() + " queue.");
                return;
            }
            if (current.state() == Game.State.RUNNING) {
                Msg.send(player, "<red>You are in a game. Type <yellow>/leave</yellow> first.");
                return;
            }
            current.removePlayer(player);
        }
        Game target = null;
        for (Game game : games) {
            if (game.type() == type && !game.isPrivate() && !game.isLoading()
                    && (game.state() == Game.State.WAITING || game.state() == Game.State.STARTING)
                    && game.players().size() < type.maxPlayers(plugin)) {
                target = game;
                break;
            }
        }
        if (target == null) {
            target = create(type);
        }
        target.addPlayer(player);
    }

    public Game create(GameType type) {
        Game game = type.create(plugin, nextId++);
        games.add(game);
        return game;
    }

    /** Removes a player from whatever they are in and sends them to the hub. */
    public void leave(Player player) {
        Game game = byPlayer.get(player.getUniqueId());
        if (game == null) {
            Msg.send(player, "<gray>You are not in a game.");
            plugin.hub().send(player);
            return;
        }
        boolean wasRunning = game.state() != Game.State.WAITING && game.state() != Game.State.STARTING;
        game.removePlayer(player);
        if (wasRunning) {
            plugin.hub().send(player);
        } else {
            plugin.hub().giveHubItems(player);
        }
        Msg.send(player, "<gray>You left " + game.type().displayName() + ".");
    }

    /** Called when a player disconnects. */
    public void quit(Player player) {
        Game game = byPlayer.get(player.getUniqueId());
        if (game != null) {
            game.removePlayer(player);
        }
        byPlayer.remove(player.getUniqueId());
    }

    void track(Player player, Game game) {
        byPlayer.put(player.getUniqueId(), game);
    }

    void untrack(Player player) {
        byPlayer.remove(player.getUniqueId());
    }

    void remove(Game game) {
        games.remove(game);
        byPlayer.values().removeIf(g -> g == game);
    }

    public Game gameOf(Player player) {
        return byPlayer.get(player.getUniqueId());
    }

    /** The running match a player is actually playing in (not just queued for). */
    public Game activeGameOf(Player player) {
        Game game = byPlayer.get(player.getUniqueId());
        if (game == null || game.world() == null || player.getWorld() != game.world()) {
            return null;
        }
        return game;
    }

    public Game gameOf(World world) {
        for (Game game : games) {
            if (game.world() != null && game.world().equals(world)) {
                return game;
            }
        }
        return null;
    }

    public List<Game> games() {
        return games;
    }

    public int playing(GameType type) {
        int count = 0;
        for (Game game : games) {
            if (game.type() == type) {
                count += game.players().size();
            }
        }
        return count;
    }

    public int queued(GameType type) {
        int count = 0;
        for (Game game : games) {
            if (game.type() == type && !game.isPrivate()
                    && (game.state() == Game.State.WAITING || game.state() == Game.State.STARTING)) {
                count += game.players().size();
            }
        }
        return count;
    }

    public void tick() {
        for (Game game : new ArrayList<>(games)) {
            game.second();
        }
    }

    public void shutdown() {
        for (Game game : new ArrayList<>(games)) {
            if (game.world() != null) {
                game.finish();
            } else {
                for (Player p : game.online()) {
                    untrack(p);
                }
            }
        }
        games.clear();
        byPlayer.clear();
    }

    /** Resets a player to a clean state for a match. */
    public void prepare(Player player, GameMode mode) {
        player.closeInventory();
        player.getInventory().clear();
        player.getInventory().setArmorContents(null);
        player.setItemOnCursor(null);
        for (PotionEffect effect : player.getActivePotionEffects()) {
            player.removePotionEffect(effect.getType());
        }
        player.setGameMode(mode);
        player.setHealth(20);
        player.setFoodLevel(20);
        player.setSaturation(5);
        player.setExhaustion(0);
        player.setExp(0);
        player.setLevel(0);
        player.setFireTicks(0);
        player.setFallDistance(0);
        player.setAllowFlight(false);
        player.setFlying(false);
        player.setWalkSpeed(0.2f);
        player.setFlySpeed(0.1f);
        player.setVelocity(new Vector());
        player.setGlowing(false);
        player.setInvulnerable(false);
        Bukkit.getScheduler().runTask(plugin, () -> player.setFireTicks(0));
    }
}
