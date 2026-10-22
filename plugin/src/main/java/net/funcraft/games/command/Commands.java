package net.funcraft.games.command;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Msg;
import org.bukkit.Bukkit;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.command.PluginCommand;
import org.bukkit.command.TabExecutor;
import org.bukkit.entity.Player;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.logging.Level;

/** All plugin commands: /play, /leave, /games, /duel, /stats and the admin command /fc. */
public final class Commands implements TabExecutor {

    private final FunCraft plugin;

    public Commands(FunCraft plugin) {
        this.plugin = plugin;
    }

    public void register() {
        for (String name : List.of("play", "leave", "games", "duel", "stats", "vote", "spectate", "party", "fc")) {
            PluginCommand command = plugin.getCommand(name);
            if (command != null) {
                command.setExecutor(this);
                command.setTabCompleter(this);
            }
        }
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        String name = command.getName().toLowerCase(Locale.ROOT);
        if (name.equals("fc")) {
            admin(sender, args);
            return true;
        }
        if (name.equals("stats")) {
            stats(sender, args);
            return true;
        }
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Only players can use this command.");
            return true;
        }
        switch (name) {
            case "play" -> {
                if (args.length == 0) {
                    plugin.hub().openSelector(player);
                    return true;
                }
                GameType type = GameType.parse(String.join("", args));
                if (type == null) {
                    Msg.send(player, "<red>Unknown game. Try: <yellow>" + gameList());
                } else {
                    plugin.games().join(player, type);
                }
            }
            case "leave" -> plugin.games().leave(player);
            case "games" -> plugin.hub().openSelector(player);
            case "duel" -> duel(player, args);
            case "vote" -> plugin.ffa().openVote(player);
            case "party" -> party(player, args);
            case "spectate" -> {
                Player target = args.length > 0 ? Bukkit.getPlayerExact(args[0]) : null;
                Game game = target == null ? null : plugin.games().activeGameOf(target);
                if (target == null || game == null || game.state() != Game.State.RUNNING) {
                    Msg.send(player, "<red>That player isn't in a running game.");
                } else if (plugin.games().gameOf(player) != null) {
                    Msg.send(player, "<red>Leave your game or queue first (<yellow>/leave</yellow>).");
                } else if (game.addSpectator(player)) {
                    player.teleport(target.getLocation());
                }
            }
            default -> {
                return false;
            }
        }
        return true;
    }

    private void duel(Player player, String[] args) {
        if (args.length == 0) {
            Msg.send(player, "<gray>Usage: <yellow>/duel <player></yellow>, <yellow>/duel accept <player></yellow>, <yellow>/duel deny <player>");
            return;
        }
        String sub = args[0].toLowerCase(Locale.ROOT);
        if ((sub.equals("accept") || sub.equals("deny")) && args.length >= 2) {
            Player other = Bukkit.getPlayerExact(args[1]);
            if (other == null) {
                Msg.send(player, "<red>That player is not online.");
                return;
            }
            if (sub.equals("accept")) {
                plugin.duels().accept(player, other);
            } else {
                plugin.duels().deny(player, other);
            }
            return;
        }
        Player target = Bukkit.getPlayerExact(args[0]);
        if (target == null) {
            Msg.send(player, "<red>That player is not online.");
            return;
        }
        String kit = args.length > 1 ? args[1] : null;
        if (kit != null && plugin.kits().get(kit) == null) {
            Msg.send(player, "<red>Unknown kit. Kits: <yellow>" + plugin.ffa().kitNames());
            return;
        }
        plugin.duels().challenge(player, target, kit);
    }

    private void party(Player player, String[] args) {
        String sub = args.length == 0 ? "list" : args[0].toLowerCase(Locale.ROOT);
        Player other = args.length > 1 ? Bukkit.getPlayerExact(args[1]) : null;
        switch (sub) {
            case "invite", "inv", "add" -> {
                if (other == null) {
                    Msg.send(player, "<red>Usage: /party invite <online player>");
                } else {
                    plugin.parties().invite(player, other);
                }
            }
            case "accept", "join" -> {
                if (other == null) {
                    Msg.send(player, "<red>Usage: /party accept <leader>");
                } else {
                    plugin.parties().accept(player, other);
                }
            }
            case "leave", "quit" -> plugin.parties().leave(player, true);
            case "kick", "remove" -> {
                if (other == null) {
                    Msg.send(player, "<red>Usage: /party kick <player>");
                } else {
                    plugin.parties().kick(player, other);
                }
            }
            case "chat", "c" -> plugin.parties().chat(player, String.join(" ", java.util.Arrays.copyOfRange(args, 1, args.length)));
            case "list", "info" -> plugin.parties().list(player);
            default -> {
                // "/party <name>" is a shortcut for invite
                Player target = Bukkit.getPlayerExact(args[0]);
                if (target != null) {
                    plugin.parties().invite(player, target);
                } else {
                    Msg.raw(player, "<aqua><bold>Party</bold> <gray>- play together, the leader's /play brings everyone");
                    Msg.raw(player, "<yellow>/party invite <player> <gray>| <yellow>/party accept <leader> <gray>| <yellow>/party leave");
                    Msg.raw(player, "<yellow>/party kick <player> <gray>| <yellow>/party list <gray>| <yellow>/party chat <message>");
                }
            }
        }
    }

    private void stats(CommandSender sender, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Only players can use this command.");
            return;
        }
        UUID target = player.getUniqueId();
        if (args.length > 0) {
            Player online = Bukkit.getPlayerExact(args[0]);
            target = online != null ? online.getUniqueId() : plugin.stats().find(args[0]);
            if (target == null) {
                Msg.send(player, "<red>No stats found for " + Msg.escape(args[0]) + ".");
                return;
            }
        }
        plugin.hub().openStats(player, target);
    }

    private void admin(CommandSender sender, String[] args) {
        if (!sender.hasPermission("funcraft.admin")) {
            Msg.send(sender, "<red>You don't have permission.");
            return;
        }
        String sub = args.length == 0 ? "help" : args[0].toLowerCase(Locale.ROOT);
        switch (sub) {
            case "list" -> {
                if (plugin.games().games().isEmpty()) {
                    Msg.send(sender, "<gray>No games right now.");
                }
                for (Game game : plugin.games().games()) {
                    List<String> names = new ArrayList<>();
                    game.online().forEach(p -> names.add(p.getName()));
                    Msg.send(sender, "<yellow>#" + game.id() + " <white>" + game.type().displayName() + " <gray>"
                            + game.state() + " <dark_gray>- <white>" + String.join(", ", names));
                }
            }
            case "start", "forcestart" -> {
                Game game = null;
                if (args.length > 1) {
                    game = byId(args[1]);
                } else if (sender instanceof Player p) {
                    game = plugin.games().gameOf(p);
                }
                if (game == null) {
                    Msg.send(sender, "<red>Join a queue first (or give a game id from /fc list).");
                    return;
                }
                game.forceStart();
                Msg.send(sender, "<green>Starting " + game.name() + ".");
            }
            case "ac", "anticheat" -> {
                if (args.length > 1 && args[1].equalsIgnoreCase("alerts") && sender instanceof Player p) {
                    boolean on = plugin.antiCheat().toggleAlerts(p);
                    Msg.send(p, on ? "<green>Anti-cheat alerts on." : "<gray>Anti-cheat alerts off.");
                } else if (args.length > 1 && Bukkit.getPlayerExact(args[1]) != null) {
                    Player target = Bukkit.getPlayerExact(args[1]);
                    Msg.send(sender, "<white>" + target.getName() + ": " + plugin.antiCheat().summary(target));
                } else {
                    var totals = plugin.antiCheat().totals();
                    if (totals.isEmpty()) {
                        Msg.send(sender, "<green>Nobody has anti-cheat violations right now.");
                    }
                    totals.forEach((id, vl) -> {
                        Player p = Bukkit.getPlayer(id);
                        if (p != null) {
                            Msg.send(sender, "<yellow>" + p.getName() + " <gray>- " + plugin.antiCheat().summary(p));
                        }
                    });
                    Msg.send(sender, "<gray>/fc ac <player> for details, /fc ac alerts to toggle alerts.");
                }
            }
            case "skip" -> {
                Game game = args.length > 1 ? byId(args[1]) : sender instanceof Player p ? plugin.games().gameOf(p) : null;
                if (game == null) {
                    Msg.send(sender, "<red>Unknown game.");
                } else if (game.skip()) {
                    Msg.send(sender, "<green>Skipped ahead in " + game.name() + ".");
                } else {
                    Msg.send(sender, "<gray>Nothing to skip in " + game.name() + ".");
                }
            }
            case "stop" -> {
                Game game = args.length > 1 ? byId(args[1]) : sender instanceof Player p ? plugin.games().gameOf(p) : null;
                if (game == null) {
                    Msg.send(sender, "<red>Unknown game.");
                    return;
                }
                if (game.state() == Game.State.RUNNING) {
                    game.end(null, List.of());
                } else {
                    game.finish();
                }
                Msg.send(sender, "<green>Stopped " + game.name() + ".");
            }
            case "build" -> {
                if (sender instanceof Player p) {
                    boolean on = plugin.hubListener().toggleBuild(p);
                    Msg.send(p, on ? "<green>Hub build mode enabled (needs creative mode)." : "<gray>Hub build mode disabled.");
                }
            }
            case "rebuildhub" -> {
                plugin.hub().build();
                Msg.send(sender, "<green>Hub rebuilt.");
            }
            case "reload" -> {
                plugin.reloadConfig();
                plugin.kits().load();
                Msg.send(sender, "<green>Config reloaded.");
            }
            case "selftest" -> selftest(sender);
            case "ffa" -> {
                if (!(sender instanceof Player p)) {
                    Msg.send(sender, "<red>Run this in-game.");
                    return;
                }
                if (args.length > 1 && args[1].equalsIgnoreCase("cancel")) {
                    plugin.ffa().cancel(p);
                } else {
                    plugin.ffa().start(p, args.length > 1 ? args[1] : null);
                }
            }
            default -> {
                Msg.raw(sender, "<gold><bold>FunCraft admin</bold>");
                Msg.raw(sender, "<yellow>/fc ffa <gray>- start a kit vote, then put everyone online into an FFA");
                Msg.raw(sender, "<yellow>/fc ffa <kit> <gray>- start the FFA right away with that kit");
                Msg.raw(sender, "<yellow>/fc ffa cancel <gray>- cancel the running kit vote");
                Msg.raw(sender, "<yellow>/fc ac [player|alerts] <gray>- anti-cheat violations / toggle alerts");
                Msg.raw(sender, "<yellow>/fc list <gray>- show running games");
                Msg.raw(sender, "<yellow>/fc start [id] <gray>- force start a queue (works solo too)");
                Msg.raw(sender, "<yellow>/fc skip [id] <gray>- skip the countdown or the current phase (e.g. Build Battle build time)");
                Msg.raw(sender, "<yellow>/fc stop [id] <gray>- end a game");
                Msg.raw(sender, "<yellow>/fc build <gray>- toggle building in the hub");
                Msg.raw(sender, "<yellow>/fc rebuildhub <gray>- regenerate the hub island");
                Msg.raw(sender, "<yellow>/fc reload <gray>- reload config.yml");
                Msg.raw(sender, "<yellow>/fc selftest <gray>- generate every map once to check it works");
            }
        }
    }

    /** Generates every map one after another (chunks load asynchronously, so the server keeps running). */
    private void selftest(CommandSender sender) {
        selftest(sender, 0, 0);
    }

    private void selftest(CommandSender sender, int index, int ok) {
        GameType[] types = GameType.values();
        if (index >= types.length) {
            Msg.send(sender, "<white>Selftest finished: " + ok + "/" + types.length + " passed");
            plugin.getLogger().info("SELFTEST RESULT " + ok + "/" + types.length);
            return;
        }
        GameType type = types[index];
        long start = System.currentTimeMillis();
        CompletableFuture<Void> test;
        try {
            test = type.create(plugin, 9000 + index).selfTest();
        } catch (Exception e) {
            test = CompletableFuture.failedFuture(e);
        }
        test.whenComplete((ignored, error) -> Bukkit.getScheduler().runTask(plugin, () -> {
            if (error == null) {
                Msg.send(sender, "<green>OK</green> <white>" + type.displayName() + " <gray>(" + (System.currentTimeMillis() - start) + " ms)");
            } else {
                plugin.getLogger().log(Level.SEVERE, "Selftest failed for " + type, error);
                Msg.send(sender, "<red>FAIL</red> <white>" + type.displayName() + " <gray>" + error);
            }
            selftest(sender, index + 1, error == null ? ok + 1 : ok);
        }));
    }

    private Game byId(String raw) {
        try {
            int id = Integer.parseInt(raw.replace("#", ""));
            for (Game game : plugin.games().games()) {
                if (game.id() == id) {
                    return game;
                }
            }
        } catch (NumberFormatException ignored) {
        }
        return null;
    }

    private static String gameList() {
        List<String> keys = new ArrayList<>();
        for (GameType type : GameType.values()) {
            keys.add(type.key());
        }
        return String.join(", ", keys);
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        String name = command.getName().toLowerCase(Locale.ROOT);
        List<String> options = new ArrayList<>();
        if (args.length == 1) {
            switch (name) {
                case "play" -> {
                    for (GameType type : GameType.values()) {
                        options.add(type.key());
                    }
                }
                case "duel" -> {
                    options.add("accept");
                    options.add("deny");
                    Bukkit.getOnlinePlayers().forEach(p -> options.add(p.getName()));
                }
                case "stats", "spectate" -> Bukkit.getOnlinePlayers().forEach(p -> options.add(p.getName()));
                case "party" -> {
                    options.addAll(List.of("invite", "accept", "leave", "kick", "list", "chat"));
                    Bukkit.getOnlinePlayers().forEach(p -> options.add(p.getName()));
                }
                case "fc" -> options.addAll(List.of("ffa", "ac", "list", "start", "skip", "stop", "build", "rebuildhub", "reload", "selftest"));
                default -> {
                }
            }
        } else if (args.length == 2 && name.equals("party")) {
            Bukkit.getOnlinePlayers().forEach(p -> options.add(p.getName()));
        } else if (args.length == 2 && name.equals("duel")) {
            if (args[0].equalsIgnoreCase("accept") || args[0].equalsIgnoreCase("deny")) {
                Bukkit.getOnlinePlayers().forEach(p -> options.add(p.getName()));
            } else {
                plugin.kits().all().forEach(k -> options.add(k.id()));
            }
        } else if (args.length == 2 && name.equals("fc") && args[0].equalsIgnoreCase("ffa")) {
            options.add("cancel");
            plugin.kits().all().forEach(k -> options.add(k.id()));
        }
        String last = args.length == 0 ? "" : args[args.length - 1].toLowerCase(Locale.ROOT);
        options.removeIf(o -> !o.toLowerCase(Locale.ROOT).startsWith(last));
        return options;
    }
}
