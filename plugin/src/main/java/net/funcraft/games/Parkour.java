package net.funcraft.games;

import net.funcraft.games.util.Build;
import net.funcraft.games.util.Msg;
import org.bukkit.Bukkit;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.World;
import org.bukkit.block.Block;
import org.bukkit.entity.Display;
import org.bukkit.entity.Player;
import org.bukkit.entity.TextDisplay;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.block.Action;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.event.player.PlayerMoveEvent;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * A timed jump course spiralling around the hub island: start plate, checkpoints, finish.
 * Best times are kept in stats.yml and shown on a leaderboard at the start.
 */
public final class Parkour implements Listener {

    private static final int JUMPS = 36;
    private static final int CHECKPOINT_EVERY = 12;
    private static final Material[] COLORS = {Material.LIME_CONCRETE, Material.LIGHT_BLUE_CONCRETE, Material.YELLOW_CONCRETE,
            Material.MAGENTA_CONCRETE, Material.ORANGE_CONCRETE, Material.CYAN_CONCRETE};

    private record Run(long start, int checkpoint) {
    }

    private final FunCraft plugin;
    private final Map<UUID, Run> runs = new HashMap<>();
    private final List<Location> path = new ArrayList<>();
    private TextDisplay board;

    public Parkour(FunCraft plugin) {
        this.plugin = plugin;
    }

    /** Deterministic course: points on a rising spiral just outside the island. */
    private void computePath(World world) {
        path.clear();
        double angle = -90;
        for (int i = 0; i <= JUMPS; i++) {
            double radius = 30 + Math.min(i, 4) * 1.5;
            double a = Math.toRadians(angle);
            int x = (int) Math.round(Math.cos(a) * radius);
            int z = (int) Math.round(Math.sin(a) * radius);
            int y = 65 + i / 2;
            path.add(new Location(world, x, y, z));
            // y goes up on every other jump; the occasional long jump is always a flat one
            angle += i % 10 == 4 ? 6.0 : 4.5;
        }
    }

    public void load(World world) {
        computePath(world);
        Location start = path.get(0);
        if (world.getBlockAt(start.getBlockX(), start.getBlockY(), start.getBlockZ()).getType() != Material.LIGHT_WEIGHTED_PRESSURE_PLATE) {
            build(world);
        }
        board = world.spawn(start.clone().add(0.5, 3.2, 0.5), TextDisplay.class, t -> {
            t.setBillboard(Display.Billboard.CENTER);
            t.setPersistent(false);
            t.addScoreboardTag(Hub.NPC_TAG);
            t.setShadowed(true);
        });
        refresh();
    }

    public void build(World world) {
        if (path.isEmpty()) {
            computePath(world);
        }
        for (int i = 0; i < path.size(); i++) {
            Location l = path.get(i);
            int x = l.getBlockX();
            int y = l.getBlockY() - 1;
            int z = l.getBlockZ();
            boolean special = i == 0 || i == path.size() - 1 || i % CHECKPOINT_EVERY == 0;
            if (special) {
                Material base = i == 0 ? Material.QUARTZ_BLOCK : i == path.size() - 1 ? Material.GOLD_BLOCK : Material.EMERALD_BLOCK;
                Build.fill(world, x - 1, y, z - 1, x + 1, y, z + 1, base);
                Build.fill(world, x - 1, y + 1, z - 1, x + 1, y + 3, z + 1, Material.AIR);
                Build.set(world, x, y + 1, z, i == 0 || i == path.size() - 1
                        ? Material.LIGHT_WEIGHTED_PRESSURE_PLATE : Material.STONE_PRESSURE_PLATE);
            } else {
                Build.set(world, x, y, z, COLORS[i % COLORS.length]);
                Build.fill(world, x, y + 1, z, x, y + 3, z, Material.AIR);
            }
        }
    }

    /** Index in the path whose plate is at this block, or -1. */
    private int indexAt(Block plate) {
        for (int i = 0; i < path.size(); i++) {
            Location l = path.get(i);
            if (l.getBlockX() == plate.getX() && l.getBlockY() == plate.getY() && l.getBlockZ() == plate.getZ()) {
                return i;
            }
        }
        return -1;
    }

    public boolean isRunning(Player player) {
        return runs.containsKey(player.getUniqueId());
    }

    public void stop(Player player) {
        runs.remove(player.getUniqueId());
    }

    @EventHandler
    public void onPlate(PlayerInteractEvent event) {
        Block block = event.getClickedBlock();
        if (event.getAction() != Action.PHYSICAL || block == null || !block.getWorld().equals(plugin.hub().world())) {
            return;
        }
        Material type = block.getType();
        if (type != Material.LIGHT_WEIGHTED_PRESSURE_PLATE && type != Material.STONE_PRESSURE_PLATE) {
            return;
        }
        int index = indexAt(block);
        if (index < 0) {
            return;
        }
        Player p = event.getPlayer();
        Run run = runs.get(p.getUniqueId());
        if (index == 0) {
            if (run == null || System.currentTimeMillis() - run.start() > 1500) {
                runs.put(p.getUniqueId(), new Run(System.currentTimeMillis(), 0));
                p.setAllowFlight(false);
                Msg.actionBar(p, "<green>Parkour started! <gray>Fall and you go back to your last checkpoint.");
                Msg.sound(p, "block.note_block.pling", 1.2f);
            }
        } else if (run != null && index == path.size() - 1) {
            finish(p, run);
        } else if (run != null && index > run.checkpoint()) {
            runs.put(p.getUniqueId(), new Run(run.start(), index));
            Msg.send(p, "<green>Checkpoint " + (index / CHECKPOINT_EVERY) + "/" + ((path.size() - 1) / CHECKPOINT_EVERY)
                    + " <gray>(" + seconds(System.currentTimeMillis() - run.start()) + ")");
            Msg.sound(p, "entity.experience_orb.pickup", 1.5f);
        }
    }

    private void finish(Player p, Run run) {
        runs.remove(p.getUniqueId());
        long time = System.currentTimeMillis() - run.start();
        long best = plugin.stats().getBest(p.getUniqueId(), "parkour");
        p.setAllowFlight(true);
        if (best <= 0 || time < best) {
            plugin.stats().setBest(p, "parkour", time);
            Msg.all(new ArrayList<>(Bukkit.getOnlinePlayers()), "<gold>" + p.getName() + " <yellow>finished the parkour in <white>"
                    + seconds(time) + "<yellow>" + (best > 0 ? " - a new personal best!" : "!"));
            refresh();
        } else {
            Msg.send(p, "<yellow>Finished in <white>" + seconds(time) + " <gray>(best: " + seconds(best) + ")");
        }
        Msg.title(p, "<gold><bold>FINISHED!", "<white>" + seconds(time), 5, 40, 10);
        Msg.sound(p, "ui.toast.challenge_complete", 1f);
    }

    @EventHandler(ignoreCancelled = true)
    public void onMove(PlayerMoveEvent event) {
        Player p = event.getPlayer();
        Run run = runs.get(p.getUniqueId());
        if (run == null) {
            return;
        }
        if (!p.getWorld().equals(plugin.hub().world())) {
            runs.remove(p.getUniqueId());
            return;
        }
        Location checkpoint = path.get(run.checkpoint());
        if (event.getTo().getY() < checkpoint.getY() - 6) {
            Location back = checkpoint.clone().add(0.5, 0.1, 0.5);
            back.setDirection(path.get(Math.min(run.checkpoint() + 1, path.size() - 1)).toVector().subtract(checkpoint.toVector()));
            event.setTo(back);
            p.setFallDistance(0);
            Msg.sound(p, "entity.enderman.teleport", 1.4f);
        }
    }

    /** Called every few ticks: running timers on the action bar. */
    public void tick() {
        for (Map.Entry<UUID, Run> e : new ArrayList<>(runs.entrySet())) {
            Player p = Bukkit.getPlayer(e.getKey());
            if (p == null || !p.getWorld().equals(plugin.hub().world())) {
                runs.remove(e.getKey());
                continue;
            }
            Msg.actionBar(p, "<yellow>Parkour <white>" + seconds(System.currentTimeMillis() - e.getValue().start())
                    + " <dark_gray>| <gray>checkpoint " + (e.getValue().checkpoint() / CHECKPOINT_EVERY));
        }
    }

    public void refresh() {
        if (board == null || !board.isValid()) {
            return;
        }
        StringBuilder sb = new StringBuilder("<aqua><bold>PARKOUR</bold></aqua>\n<gray>Step on the plate to start");
        List<Stats.Entry> top = plugin.stats().topBest("parkour", 5);
        for (int i = 0; i < top.size(); i++) {
            sb.append("\n<yellow>").append(i + 1).append(". <white>").append(Msg.escape(top.get(i).name()))
                    .append(" <gray>- <green>").append(seconds(top.get(i).value()));
        }
        board.text(Msg.mm(sb.toString()));
    }

    private static String seconds(long ms) {
        return String.format("%.2fs", ms / 1000.0);
    }
}
