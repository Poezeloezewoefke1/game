package net.funcraft.games.command;

import net.funcraft.games.FunCraft;
import net.funcraft.games.Kits;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.games.PvpArena;
import net.funcraft.games.util.Msg;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/** /duel invitations between two players. */
public final class Duels {

    private static final long EXPIRE_MS = 60_000;

    private final FunCraft plugin;
    /** target -> (challenger -> time) */
    private final Map<UUID, Map<UUID, Long>> invites = new HashMap<>();
    /** challenger -> kit they picked */
    private final Map<UUID, String> chosenKit = new HashMap<>();

    public Duels(FunCraft plugin) {
        this.plugin = plugin;
    }

    public void challenge(Player from, Player to, String kit) {
        if (from.equals(to)) {
            Msg.send(from, "<red>You can't duel yourself.");
            return;
        }
        if (busy(from) || busy(to)) {
            Msg.send(from, "<red>One of you is already in a game.");
            return;
        }
        Map<UUID, Long> mine = invites.get(from.getUniqueId());
        if (mine != null && mine.containsKey(to.getUniqueId())) {
            accept(from, to);
            return;
        }
        invites.computeIfAbsent(to.getUniqueId(), k -> new HashMap<>()).put(from.getUniqueId(), System.currentTimeMillis());
        Kits.Kit chosen = plugin.kits().getOrDefault(kit);
        chosenKit.put(from.getUniqueId(), chosen.id());
        Msg.send(from, "<green>Duel request sent to <yellow>" + to.getName() + "<green> (kit: " + chosen.name() + "<green>).");
        Msg.send(to, "<yellow>" + from.getName() + " <gold>challenged you to a duel with the " + chosen.name() + " <gold>kit! "
                + "<click:run_command:'/duel accept " + from.getName() + "'><green><bold>[ACCEPT]</bold></green></click> "
                + "<click:run_command:'/duel deny " + from.getName() + "'><red><bold>[DENY]</bold></red></click>");
        Msg.sound(to, "entity.player.levelup", 1.5f);
    }

    public void accept(Player target, Player challenger) {
        Map<UUID, Long> mine = invites.get(target.getUniqueId());
        Long time = mine == null ? null : mine.remove(challenger.getUniqueId());
        if (time == null || System.currentTimeMillis() - time > EXPIRE_MS) {
            Msg.send(target, "<red>You have no (recent) duel request from " + challenger.getName() + ".");
            return;
        }
        if (busy(target) || busy(challenger)) {
            Msg.send(target, "<red>One of you is already in a game.");
            return;
        }
        leaveQueue(target);
        leaveQueue(challenger);
        Game game = plugin.games().create(GameType.DUELS);
        game.setPrivate(true);
        if (game instanceof PvpArena arena) {
            arena.setKit(plugin.kits().getOrDefault(chosenKit.remove(challenger.getUniqueId())));
        }
        game.addPlayer(challenger);
        game.addPlayer(target);
        game.forceStart();
    }

    public void deny(Player target, Player challenger) {
        Map<UUID, Long> mine = invites.get(target.getUniqueId());
        if (mine != null && mine.remove(challenger.getUniqueId()) != null) {
            Msg.send(target, "<gray>Duel request denied.");
            Msg.send(challenger, "<red>" + target.getName() + " denied your duel request.");
        } else {
            Msg.send(target, "<red>No duel request from " + challenger.getName() + ".");
        }
    }

    private boolean busy(Player player) {
        Game game = plugin.games().gameOf(player);
        return game != null && game.state() != Game.State.WAITING && game.state() != Game.State.STARTING;
    }

    private void leaveQueue(Player player) {
        Game game = plugin.games().gameOf(player);
        if (game != null) {
            game.removePlayer(player);
        }
    }

    public void clear(Player player) {
        invites.remove(player.getUniqueId());
        chosenKit.remove(player.getUniqueId());
        for (Map<UUID, Long> map : invites.values()) {
            map.remove(player.getUniqueId());
        }
    }

    public Player resolve(String name) {
        return Bukkit.getPlayerExact(name);
    }
}
