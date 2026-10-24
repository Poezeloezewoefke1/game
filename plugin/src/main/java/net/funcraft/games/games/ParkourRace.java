package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.kyori.adventure.bossbar.BossBar;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.entity.Player;
import org.bukkit.event.block.Action;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.event.player.PlayerMoveEvent;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

/**
 * Parkour Race: everyone gets their own lane of the same randomly generated jump course with
 * checkpoints. Fall and you go back to your last checkpoint. First to the finish wins; the race
 * ends a little after that or when the timer runs out (then furthest along wins).
 */
public final class ParkourRace extends Game {

    private static final int Y = 70;
    private static final int JUMPS = 44;
    private static final int CHECKPOINT_EVERY = 8;
    private static final int LANE_GAP = 9;
    private static final int TIME_LIMIT = 300;
    private static final int AFTER_FIRST = 30;

    /** One block of the course, relative to the lane start. */
    private record Step(int x, int y, int z, boolean checkpoint) {
    }

    private final List<Step> course = new ArrayList<>();
    private final Map<UUID, Integer> lane = new HashMap<>();
    private final Map<UUID, Integer> checkpoint = new HashMap<>();
    private final Map<UUID, Integer> best = new HashMap<>();
    private final List<UUID> finished = new ArrayList<>();
    private int lanes;
    private int endAt = -1;
    private Material[] palette;

    public ParkourRace(FunCraft plugin, int id) {
        super(plugin, id, GameType.PARKOUR);
    }

    private void generate() {
        if (!course.isEmpty()) {
            return;
        }
        Random r = new Random(random.nextLong());
        int x = 0;
        int y = 0;
        int z = 0;
        course.add(new Step(0, 0, 0, true));
        for (int i = 1; i <= JUMPS; i++) {
            int dy = r.nextInt(10) < 3 ? 1 : r.nextInt(10) < 2 ? -1 : 0;
            if (y + dy < -6 || y + dy > 14) {
                dy = 0;
            }
            // horizontal distance between block centres: 2-3 when climbing, 2-4 otherwise
            int maxDist = dy > 0 ? 3 : dy < 0 ? 4 : 3 + (r.nextInt(4) == 0 ? 1 : 0);
            int dist = 2 + r.nextInt(maxDist - 1);
            int dz = r.nextInt(3) - 1;
            if (Math.abs(z + dz) > 2) {
                dz = -dz;
            }
            if (dist == 4) {
                dz = 0; // keep the long jumps straight
            }
            x += dist;
            y += dy;
            z += dz;
            course.add(new Step(x, y, z, i % CHECKPOINT_EVERY == 0 || i == JUMPS));
        }
    }

    private int laneZ(int laneIndex) {
        return laneIndex * LANE_GAP;
    }

    @Override
    protected int[] mapArea() {
        generate();
        int length = course.get(course.size() - 1).x() + 10;
        int maxLanes = Math.max(2, type.maxPlayers(plugin));
        return new int[]{-8, -6, length, (maxLanes - 1) * LANE_GAP + 6};
    }

    @Override
    protected void buildMap() {
        generate();
        Material[][] palettes = {
                {Material.LIME_CONCRETE, Material.LIGHT_BLUE_CONCRETE, Material.YELLOW_CONCRETE},
                {Material.QUARTZ_BLOCK, Material.PURPUR_BLOCK, Material.END_STONE_BRICKS},
                {Material.MOSSY_STONE_BRICKS, Material.MOSS_BLOCK, Material.OAK_LEAVES},
                {Material.PRISMARINE_BRICKS, Material.DARK_PRISMARINE, Material.SEA_LANTERN},
                {Material.NETHER_BRICKS, Material.MAGMA_BLOCK, Material.BLACKSTONE}};
        palette = palettes[random.nextInt(palettes.length)];
        mapName = new String[]{"Sky Hop", "End Leap", "Jungle Run", "Ocean Steps", "Nether Dash"}[java.util.Arrays.asList(palettes).indexOf(palette)];
        lanes = Math.max(2, Math.min(type.maxPlayers(plugin), online().isEmpty() ? 4 : online().size()));
        for (int l = 0; l < lanes; l++) {
            int oz = laneZ(l);
            // start pad
            Build.fill(world, -4, Y - 1, oz - 2, 1, Y - 1, oz + 2, Material.SMOOTH_QUARTZ);
            for (int i = 1; i < course.size(); i++) {
                Step s = course.get(i);
                Material m = i == course.size() - 1 ? Material.GOLD_BLOCK : s.checkpoint() ? Material.EMERALD_BLOCK : palette[i % palette.length];
                Build.set(world, s.x(), Y - 1 + s.y(), oz + s.z(), m);
            }
            Step last = course.get(course.size() - 1);
            Build.fill(world, last.x() + 1, Y - 1 + last.y(), oz - 2, last.x() + 5, Y - 1 + last.y(), oz + 2, Material.GOLD_BLOCK);
            Build.set(world, last.x() + 3, Y + last.y(), oz, Material.BEACON);
        }
    }

    private Location stepLocation(Player p, int index) {
        Step s = course.get(index);
        int oz = laneZ(lane.getOrDefault(p.getUniqueId(), 0));
        double x = index == 0 ? -1.5 : s.x() + 0.5;
        Location l = new Location(world, x, Y + s.y(), oz + s.z() + 0.5, -90, 10);
        return l;
    }

    @Override
    protected void onStart(List<Player> list) {
        for (int i = 0; i < list.size(); i++) {
            Player p = list.get(i);
            lane.put(p.getUniqueId(), i % lanes);
            checkpoint.put(p.getUniqueId(), 0);
            best.put(p.getUniqueId(), 0);
            p.teleport(stepLocation(p, 0));
            p.getInventory().setItem(4, ItemBuilder.of(Material.RED_DYE).name("<red>Back to checkpoint <gray>(right click)").build());
            Msg.title(p, "<green><bold>Parkour Race", "<gray>First to the gold platform wins!", 5, 50, 10);
        }
        Msg.all(list, "<gray>Jump from block to block. <green>Emerald</green> blocks are checkpoints. Falling sends you back to your last one.");
    }

    private int progressAt(Player p, Location at) {
        Block below = at.clone().subtract(0, 0.2, 0).getBlock();
        int oz = laneZ(lane.getOrDefault(p.getUniqueId(), 0));
        for (int i = course.size() - 1; i >= 0; i--) {
            Step s = course.get(i);
            if (below.getX() == s.x() && below.getY() == Y - 1 + s.y() && below.getZ() == oz + s.z()) {
                return i;
            }
        }
        return -1;
    }

    @Override
    public void onMove(PlayerMoveEvent event) {
        Player p = event.getPlayer();
        if (finished.contains(p.getUniqueId()) || p.getGameMode() != GameMode.SURVIVAL) {
            return;
        }
        Location to = event.getTo();
        Step last = course.get(course.size() - 1);
        // fell well below the next few jumps: back to the checkpoint
        // (the range starts at the checkpoint, so being put back there never counts as a fall)
        int from = checkpoint.getOrDefault(p.getUniqueId(), 0);
        int ahead = best.getOrDefault(p.getUniqueId(), 0) + 3;
        int lowest = Integer.MAX_VALUE;
        for (int i = from; i <= Math.min(course.size() - 1, ahead); i++) {
            lowest = Math.min(lowest, course.get(i).y());
        }
        if (to.getY() < Y + lowest - 4) {
            back(p);
            return;
        }
        int at = progressAt(p, to);
        if (at < 0) {
            // on the finish platform?
            Block below = to.clone().subtract(0, 0.2, 0).getBlock();
            if (below.getType() == Material.GOLD_BLOCK && to.getX() > last.x() - 0.5) {
                finish(p);
            }
            return;
        }
        best.merge(p.getUniqueId(), at, Math::max);
        if (at == course.size() - 1) {
            finish(p);
        } else if (course.get(at).checkpoint() && at > checkpoint.getOrDefault(p.getUniqueId(), 0)) {
            checkpoint.put(p.getUniqueId(), at);
            Msg.actionBar(p, "<green><bold>Checkpoint!</bold> <gray>(" + (at / CHECKPOINT_EVERY) + "/" + (JUMPS / CHECKPOINT_EVERY) + ")");
            Msg.sound(p, "entity.experience_orb.pickup", 1.2f);
        }
    }

    private void back(Player p) {
        p.setFallDistance(0);
        p.setVelocity(new org.bukkit.util.Vector());
        p.teleport(stepLocation(p, checkpoint.getOrDefault(p.getUniqueId(), 0)));
    }

    @Override
    public void onInteract(PlayerInteractEvent event) {
        if (event.getItem() != null && event.getItem().getType() == Material.RED_DYE
                && (event.getAction() == Action.RIGHT_CLICK_AIR || event.getAction() == Action.RIGHT_CLICK_BLOCK)) {
            event.setCancelled(true);
            back(event.getPlayer());
        }
    }

    private void finish(Player p) {
        if (finished.contains(p.getUniqueId())) {
            return;
        }
        finished.add(p.getUniqueId());
        best.put(p.getUniqueId(), course.size());
        int place = finished.size();
        String suffix = place == 1 ? "st" : place == 2 ? "nd" : place == 3 ? "rd" : "th";
        Msg.all(online(), "<green>" + p.getName() + " <gray>finished <gold>" + place + suffix + "</gold>! <dark_gray>(" + Msg.time(elapsed) + ")");
        Msg.title(p, "<gold><bold>FINISHED!", "<gray>" + place + suffix + " place in " + Msg.time(elapsed), 0, 50, 10);
        firework(p.getLocation());
        if (place == 1) {
            endAt = elapsed + AFTER_FIRST;
            if (alivePlayers().size() > 1) {
                Msg.all(online(), "<yellow>The race ends in " + AFTER_FIRST + " seconds!");
            }
        }
        if (finished.size() >= alivePlayers().size()) {
            endRace();
        }
    }

    private void endRace() {
        if (state != State.RUNNING) {
            return;
        }
        UUID winner = null;
        if (!finished.isEmpty()) {
            winner = finished.get(0);
        } else {
            int most = -1;
            for (UUID id : alive) {
                if (best.getOrDefault(id, 0) > most) {
                    most = best.get(id);
                    winner = id;
                }
            }
        }
        Player w = winner == null ? null : Bukkit.getPlayer(winner);
        if (w == null) {
            end(null, List.of());
        } else {
            end(w.getName(), List.of(winner));
        }
    }

    @Override
    protected void checkWin() {
        if (state == State.RUNNING && (alive.isEmpty() || (alive.size() == 1 && startingPlayers > 1 && finished.isEmpty()))) {
            endRace();
        }
    }

    @Override
    protected void onSecond() {
        int left = endAt >= 0 ? endAt - elapsed : TIME_LIMIT - elapsed;
        bossBar("<green>Parkour Race <dark_gray>| <white>" + Msg.time(Math.max(0, left)) + (endAt >= 0 ? " <yellow>(hurry!)" : ""),
                Math.max(0, Math.min(1, left / (float) (endAt >= 0 ? AFTER_FIRST : TIME_LIMIT))), BossBar.Color.GREEN);
        if (left <= 0) {
            endRace();
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        event.setCancelled(true);
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        back(victim);
    }

    @Override
    public void handleVoid(Player player) {
        if (isAlive(player) && player.getGameMode() == GameMode.SURVIVAL) {
            back(player);
        } else if (world != null) {
            player.teleport(spectatorSpawn());
        }
    }

    @Override
    protected double voidLevel() {
        return Y - 12;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 10, Y + 12, -10, -45, 30);
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        int mine = best.getOrDefault(player.getUniqueId(), 0);
        lines.add("<white>Progress: <green>" + Math.min(100, mine * 100 / JUMPS) + "%");
        lines.add("<white>Checkpoint: <green>" + (checkpoint.getOrDefault(player.getUniqueId(), 0) / CHECKPOINT_EVERY) + "/" + (JUMPS / CHECKPOINT_EVERY));
        lines.add("  ");
        List<UUID> order = new ArrayList<>(alive);
        order.sort((a, b) -> best.getOrDefault(b, 0) - best.getOrDefault(a, 0));
        for (int i = 0; i < Math.min(5, order.size()); i++) {
            Player p = Bukkit.getPlayer(order.get(i));
            lines.add("<yellow>" + (i + 1) + ". <white>" + (p == null ? "?" : p.getName()) + " <gray>"
                    + Math.min(100, best.getOrDefault(order.get(i), 0) * 100 / JUMPS) + "%");
        }
        lines.add("   ");
        lines.add("<white>Time: <yellow>" + Msg.time(elapsed));
        return lines;
    }

    @Override
    protected void cleanup() {
        lane.clear();
        checkpoint.clear();
        best.clear();
        finished.clear();
        endAt = -1;
    }
}
