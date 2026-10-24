package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Structures;
import net.funcraft.games.util.Theme;
import net.kyori.adventure.bossbar.BossBar;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.entity.Player;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.player.PlayerItemConsumeEvent;
import org.bukkit.event.player.PlayerMoveEvent;
import org.bukkit.inventory.ItemStack;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * The Bridge: two islands joined by a narrow bridge. Fight your way across and jump into the
 * enemy's end portal to score. Every point resets everyone to their cages; first to 5 wins.
 * You respawn instantly, your arrow comes back every few seconds and golden apples heal fully.
 */
public final class Bridge extends TeamGame {

    private static final int Y = 64;
    private static final int ISLAND_X = 32;
    private static final int GOALS_TO_WIN = 5;
    private static final int TIME_LIMIT = 900;
    private static final int CAGE_SECONDS = 5;
    private static final int ARROW_SECONDS = 4;

    private final Map<UUID, Integer> arrowTimer = new HashMap<>();
    private int freeze;

    public Bridge(FunCraft plugin, int id) {
        super(plugin, id, GameType.BRIDGE);
    }

    @Override
    protected String kitId() {
        return "bridge";
    }

    @Override
    protected String objective() {
        return "Jump into the enemy portal - first to " + GOALS_TO_WIN;
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-ISLAND_X - 14, -20, ISLAND_X + 14, 20};
    }

    private int goalX(Side side) {
        return (side == red ? -1 : 1) * (ISLAND_X + 5);
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + " Bridge";
        for (Side side : sides) {
            int dir = side == red ? -1 : 1;
            int cx = dir * ISLAND_X;
            theme.island(world, cx, Y, 0, 9.5, random);
            // goal: a 3x3 end portal pit framed by end portal frames
            int gx = goalX(side);
            Build.fill(world, gx - 2, Y - 3, -2, gx + 2, Y - 3, 2, theme.trim);
            Build.fill(world, gx - 2, Y - 2, -2, gx + 2, Y, 2, Material.END_STONE_BRICKS);
            Build.fill(world, gx - 2, Y, -2, gx + 2, Y, 2, Material.END_PORTAL_FRAME);
            Build.fill(world, gx - 1, Y - 2, -1, gx + 1, Y, 1, Material.END_PORTAL);
            // towers and lamps either side
            Structures.tower(world, cx, Y + 1, 7, 5, theme);
            Structures.tower(world, cx, Y + 1, -7, 5, theme);
            Structures.lamp(world, cx - dir * 6, Y + 1, 3, theme);
            Structures.lamp(world, cx - dir * 6, Y + 1, -3, theme);
            int sx = cx - dir * 4;
            side.spawn = Build.lookAt(new Location(world, sx + 0.5, Y + 4, 0.5), new Location(world, 0.5, Y + 4, 0.5));
        }
        // the bridge: one block wide, team coloured halves, with a platform in the middle
        for (int x = -ISLAND_X + 9; x <= ISLAND_X - 9; x++) {
            Material m = x < -2 ? Material.RED_TERRACOTTA : x > 2 ? Material.BLUE_TERRACOTTA : Material.WHITE_TERRACOTTA;
            Build.set(world, x, Y, 0, m);
        }
        Build.fill(world, -2, Y, -2, 2, Y, 2, Material.WHITE_TERRACOTTA);
        Structures.lamp(world, -2, Y + 1, 2, theme);
        Structures.lamp(world, 2, Y + 1, -2, theme);
    }

    @Override
    protected void onStart(List<Player> list) {
        super.onStart(list);
        Msg.all(list, "<gray>Knock them off the bridge and jump into the <dark_purple>end portal</dark_purple> on their island!");
        startRound();
    }

    /** Cages everyone at their spawn for a few seconds. */
    private void startRound() {
        for (Side side : sides) {
            Location s = side.spawn;
            Build.cage(world, s.getBlockX(), s.getBlockY(), s.getBlockZ(), side == red ? Material.RED_STAINED_GLASS : Material.BLUE_STAINED_GLASS);
        }
        for (Player p : online()) {
            if (isAlive(p)) {
                respawning.remove(p.getUniqueId());
                respawn(p);
            }
        }
        freeze = CAGE_SECONDS;
    }

    private void openCages() {
        for (Side side : sides) {
            Location s = side.spawn;
            Build.removeCage(world, s.getBlockX(), s.getBlockY(), s.getBlockZ());
        }
        for (Player p : alivePlayers()) {
            Msg.title(p, "<green><bold>FIGHT!", "", 0, 20, 5);
        }
        Msg.sound(alivePlayers(), "entity.player.levelup", 1.2f);
    }

    private boolean inGoal(Location l, Side side) {
        int gx = goalX(side);
        return Math.abs(l.getBlockX() - gx) <= 1 && Math.abs(l.getBlockZ()) <= 1 && l.getY() < Y + 1.2 && l.getY() > Y - 3;
    }

    @Override
    public void onMove(PlayerMoveEvent event) {
        Player p = event.getPlayer();
        Side mine = side(p);
        if (mine == null || p.getGameMode() != GameMode.SURVIVAL || state != State.RUNNING) {
            return;
        }
        if (inGoal(event.getTo(), mine)) {
            event.setTo(mine.spawn);
            Msg.actionBar(p, "<red>That's your own portal - score in theirs!");
            return;
        }
        Side enemy = enemy(mine);
        if (freeze <= 0 && inGoal(event.getTo(), enemy)) {
            score(p, mine);
        }
    }

    private void score(Player scorer, Side side) {
        side.score++;
        plugin.stats().addKill(scorer, type); // goals count towards your stats like kills
        Msg.all(online(), side.mm + "<bold>" + scorer.getName() + " scored!</bold> " + red.colored() + " " + red.score
                + " <gray>- " + blue.colored() + " " + blue.score);
        Msg.title(online(), side.mm + "<bold>" + scorer.getName() + " SCORED!", red.mm + red.score + " <gray>- " + blue.mm + blue.score);
        Msg.sound(online(), "entity.firework_rocket.twinkle", 1f);
        if (side.score >= GOALS_TO_WIN) {
            end("Team " + side.colored(), new ArrayList<>(side.members));
        } else {
            startRound();
        }
    }

    @Override
    public void onBlockPlace(BlockPlaceEvent event) {
        Block b = event.getBlock();
        if (Math.abs(b.getZ()) > 15 || b.getY() > Y + 10 || b.getY() < Y - 8 || Math.abs(b.getX()) > ISLAND_X + 10) {
            event.setCancelled(true);
            Msg.actionBar(event.getPlayer(), "<red>You can't build here!");
            return;
        }
        for (Side side : sides) {
            int gx = goalX(side);
            boolean nearGoal = Math.abs(b.getX() - gx) <= 3 && Math.abs(b.getZ()) <= 3;
            boolean nearCage = side.spawn.distanceSquared(b.getLocation().add(0.5, 0, 0.5)) < 9;
            if (nearGoal || nearCage) {
                event.setCancelled(true);
                Msg.actionBar(event.getPlayer(), "<red>You can't build here!");
                return;
            }
        }
        super.onBlockPlace(event);
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        super.onDamage(event, victim, attacker);
        if (freeze > 0 || event.getCause() == EntityDamageEvent.DamageCause.FALL) {
            event.setCancelled(true);
        }
    }

    @Override
    public void onConsume(PlayerItemConsumeEvent event) {
        if (event.getItem().getType() == Material.GOLDEN_APPLE) {
            org.bukkit.Bukkit.getScheduler().runTask(plugin, () -> event.getPlayer().setHealth(20));
        }
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        deathMessage(victim, killer, null);
        respawn(victim); // instant respawn in The Bridge
    }

    @Override
    protected void onSecond() {
        super.onSecond();
        if (freeze > 0) {
            for (Player p : alivePlayers()) {
                Msg.title(p, "<yellow>" + freeze, "<gray>Cages open soon...", 0, 25, 0);
            }
            Msg.sound(alivePlayers(), "block.note_block.hat", 1.5f);
            if (--freeze == 0) {
                openCages();
            }
        }
        // the bow's single arrow comes back every few seconds
        for (Player p : alivePlayers()) {
            if (p.getGameMode() != GameMode.SURVIVAL || p.getInventory().contains(Material.ARROW)) {
                arrowTimer.remove(p.getUniqueId());
                continue;
            }
            int t = arrowTimer.merge(p.getUniqueId(), 1, Integer::sum);
            if (t >= ARROW_SECONDS) {
                arrowTimer.remove(p.getUniqueId());
                p.getInventory().setItem(8, new ItemStack(Material.ARROW));
            }
        }
        int left = TIME_LIMIT - elapsed;
        bossBar(red.colored() + " " + dots(red) + " <dark_gray>| <white>" + Msg.time(left) + " <dark_gray>| " + dots(blue) + " " + blue.colored(),
                (float) left / TIME_LIMIT, BossBar.Color.PURPLE);
        if (left <= 0) {
            if (red.score == blue.score) {
                end(null, List.of());
            } else {
                Side winner = red.score > blue.score ? red : blue;
                end("Team " + winner.colored(), new ArrayList<>(winner.members));
            }
        }
    }

    private String dots(Side side) {
        StringBuilder sb = new StringBuilder(side.mm);
        for (int i = 0; i < GOALS_TO_WIN; i++) {
            sb.append(i < side.score ? "⬤" : "<dark_gray>⬤" + side.mm);
        }
        return sb.toString();
    }

    @Override
    protected double voidLevel() {
        return Y - 12;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 0.5, Y + 18, 12.5, 180, 45);
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        lines.add(red.mm + "<bold>R</bold> " + dots(red) + (side(player) == red ? " <gray>YOU" : ""));
        lines.add(blue.mm + "<bold>B</bold> " + dots(blue) + (side(player) == blue ? " <gray>YOU" : ""));
        lines.add("  ");
        lines.add("<white>Kills: <green>" + kills.getOrDefault(player.getUniqueId(), 0));
        lines.add("<white>Time: <yellow>" + Msg.time(TIME_LIMIT - elapsed));
        return lines;
    }

    @Override
    protected void cleanup() {
        super.cleanup();
        arrowTimer.clear();
    }

    @Override
    public void botTick(Player bot, net.funcraft.games.bots.BotBrain brain) {
        Side mine = side(bot);
        if (mine == null || freeze > 0) {
            brain.stop();
            return;
        }
        Side enemy = enemy(mine);
        botGoal(bot, brain, new Location(world, goalX(enemy) + 0.5, Y + 1, 0.5), null);
    }
}
