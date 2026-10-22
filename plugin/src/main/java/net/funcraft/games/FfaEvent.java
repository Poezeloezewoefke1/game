package net.funcraft.games;

import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.games.PvpArena;
import net.funcraft.games.util.Gui;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import org.bukkit.Bukkit;
import org.bukkit.Material;
import org.bukkit.entity.Player;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

/**
 * Server-wide FFA started by an op: everyone votes on a kit, then every online player who is
 * not already in a match is put into one big PvP arena. Dead players spectate.
 */
public final class FfaEvent {

    private final FunCraft plugin;
    private final Map<UUID, String> votes = new HashMap<>();
    private boolean voting;
    private int timer;

    public FfaEvent(FunCraft plugin) {
        this.plugin = plugin;
    }

    public boolean isVoting() {
        return voting;
    }

    /** Starts a kit vote, or jumps straight to the fight when {@code kitId} is given. */
    public void start(Player starter, String kitId) {
        if (voting) {
            Msg.send(starter, "<red>An FFA vote is already running. Use <yellow>/fc ffa cancel</yellow> to stop it.");
            return;
        }
        if (kitId != null) {
            Kits.Kit kit = plugin.kits().get(kitId);
            if (kit == null) {
                Msg.send(starter, "<red>Unknown kit. Kits: <yellow>" + kitNames());
                return;
            }
            launch(kit);
            return;
        }
        votes.clear();
        voting = true;
        timer = Math.max(10, plugin.getConfig().getInt("ffa.vote-seconds", 30));
        for (Player p : Bukkit.getOnlinePlayers()) {
            Msg.title(p, "<gold><bold>FFA EVENT", "<yellow>Vote for a kit!", 5, 50, 10);
            Msg.sound(p, "event.raid.horn", 1f);
            Msg.raw(p, Msg.PREFIX + "<gold><bold>FFA event!</bold></gold> <gray>" + starter.getName() + " started a kit vote. "
                    + "<click:run_command:'/vote'><green><bold>[CLICK TO VOTE]</bold></green></click> <gray>or type <yellow>/vote");
            if (canJoin(p)) {
                openVote(p);
            }
        }
    }

    public void cancel(Player by) {
        if (!voting) {
            Msg.send(by, "<gray>No FFA vote is running.");
            return;
        }
        voting = false;
        votes.clear();
        Msg.all(new ArrayList<>(Bukkit.getOnlinePlayers()), "<red>The FFA event was cancelled.");
    }

    /** Called once per second. */
    public void tick() {
        if (!voting) {
            return;
        }
        timer--;
        if (timer == 10 || timer == 5) {
            Msg.all(new ArrayList<>(Bukkit.getOnlinePlayers()), "<gold>FFA kit vote ends in <white>" + timer + "</white> seconds! <yellow>/vote");
        }
        for (Player p : Bukkit.getOnlinePlayers()) {
            if (canJoin(p)) {
                Msg.actionBar(p, "<gold>FFA kit vote <dark_gray>| <white>" + timer + "s left <dark_gray>| <yellow>/vote");
            }
        }
        if (timer <= 0) {
            voting = false;
            launch(winner());
        }
    }

    private Kits.Kit winner() {
        Map<String, Integer> counts = new HashMap<>();
        for (String kit : votes.values()) {
            counts.merge(kit, 1, Integer::sum);
        }
        List<String> best = new ArrayList<>();
        int top = 0;
        for (Map.Entry<String, Integer> e : counts.entrySet()) {
            if (e.getValue() > top) {
                best.clear();
                top = e.getValue();
            }
            if (e.getValue() == top) {
                best.add(e.getKey());
            }
        }
        List<Kits.Kit> all = plugin.kits().all();
        Random random = new Random();
        if (best.isEmpty()) {
            return all.get(random.nextInt(all.size()));
        }
        return plugin.kits().getOrDefault(best.get(random.nextInt(best.size())));
    }

    private void launch(Kits.Kit kit) {
        votes.clear();
        List<Player> joining = new ArrayList<>();
        for (Player p : Bukkit.getOnlinePlayers()) {
            if (canJoin(p)) {
                joining.add(p);
            }
        }
        if (joining.isEmpty()) {
            Msg.all(new ArrayList<>(Bukkit.getOnlinePlayers()), "<red>Nobody is free to play the FFA right now.");
            return;
        }
        Msg.all(new ArrayList<>(Bukkit.getOnlinePlayers()), "<gold><bold>FFA:</bold> <white>the " + kit.name()
                + " <white>kit won! <gray>" + joining.size() + " players are being sent to the arena...");
        Game game = plugin.games().create(GameType.PVP);
        game.setPrivate(true);
        game.setMaxPlayers(Math.max(2, joining.size()));
        if (game instanceof PvpArena arena) {
            arena.setKit(kit);
            arena.setEvent(true);
        }
        for (Player p : joining) {
            Game current = plugin.games().gameOf(p);
            if (current != null) {
                current.removePlayer(p);
            }
            game.addPlayer(p);
        }
        game.forceStart();
    }

    /** Players already playing a match are left alone. */
    private boolean canJoin(Player p) {
        Game game = plugin.games().gameOf(p);
        return game == null || game.state() == Game.State.WAITING || game.state() == Game.State.STARTING && !game.isPrivate();
    }

    public void openVote(Player player) {
        if (!voting) {
            Msg.send(player, "<gray>There is no kit vote right now.");
            return;
        }
        List<Kits.Kit> kits = plugin.kits().all();
        int rows = Math.max(1, Math.min(6, (kits.size() + 8) / 9));
        Gui gui = new Gui(rows, "<dark_gray>Vote for the FFA kit");
        String mine = votes.get(player.getUniqueId());
        for (int i = 0; i < kits.size() && i < rows * 9; i++) {
            Kits.Kit kit = kits.get(i);
            long count = votes.values().stream().filter(kit.id()::equals).count();
            ItemBuilder b = ItemBuilder.of(kit.icon()).name("<bold>" + kit.name()).flags();
            if (!kit.description().isEmpty()) {
                b.lore("<gray>" + kit.description());
            }
            b.lore(kitSummary(kit));
            b.lore("", "<white>Votes: <yellow>" + count, kit.id().equals(mine) ? "<green>You voted for this" : "<yellow>Click to vote!");
            if (kit.id().equals(mine)) {
                b.glow();
            }
            gui.set(i, b.build(), (p, click) -> {
                if (!voting) {
                    p.closeInventory();
                    return;
                }
                votes.put(p.getUniqueId(), kit.id());
                Msg.send(p, "<green>You voted for " + kit.name() + "<green>.");
                Msg.sound(p, "block.note_block.pling", 1.5f);
                openVote(p);
            });
        }
        gui.open(player);
    }

    private static List<String> kitSummary(Kits.Kit kit) {
        List<String> lines = new ArrayList<>();
        if (kit.chestplate() != null) {
            lines.add("<dark_gray>• <gray>" + pretty(kit.chestplate().getType()) + " armor");
        }
        int shown = 0;
        for (int slot = 0; slot < 9 && shown < 5; slot++) {
            if (kit.items().containsKey(slot)) {
                lines.add("<dark_gray>• <gray>" + pretty(kit.items().get(slot).getType())
                        + (kit.items().get(slot).getAmount() > 1 ? " x" + kit.items().get(slot).getAmount() : ""));
                shown++;
            }
        }
        return lines;
    }

    private static String pretty(Material m) {
        String s = m.name().toLowerCase().replace("_chestplate", "").replace('_', ' ');
        return Character.toUpperCase(s.charAt(0)) + s.substring(1);
    }

    public String kitNames() {
        List<String> ids = new ArrayList<>();
        plugin.kits().all().forEach(k -> ids.add(k.id()));
        return String.join(", ", ids);
    }
}
