package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.Msg;
import net.kyori.adventure.bossbar.BossBar;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.entity.Giant;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.player.PlayerMoveEvent;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Red Light, Green Light: run to the finish line while the giant has its back turned. When it
 * turns round (red light), anyone who moves is out. Everyone who makes it across wins.
 */
public final class RedLightGreenLight extends Game {

    private static final int Y = 64;
    private static final int LENGTH = 72;
    private static final int HALF_Z = 12;
    private static final int FINISH_X = LENGTH - 5;
    private static final int TIME_LIMIT = 100;
    private static final int GRACE_TICKS = 9;

    private enum Light { WAITING, GREEN, RED }

    private Light light = Light.WAITING;
    private int phaseTicks;
    private int redTicks;
    private final Map<UUID, Location> frozenAt = new HashMap<>();
    private final List<UUID> finished = new ArrayList<>();
    private Giant doll;

    public RedLightGreenLight(FunCraft plugin, int id) {
        super(plugin, id, GameType.RED_LIGHT);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-6, -HALF_Z - 4, LENGTH + 12, HALF_Z + 4};
    }

    @Override
    protected void buildMap() {
        mapName = "The Playground";
        Build.fill(world, -4, Y - 2, -HALF_Z - 1, LENGTH + 10, Y - 1, HALF_Z + 1, Material.SANDSTONE);
        Build.fill(world, -4, Y, -HALF_Z, LENGTH + 10, Y, HALF_Z, Material.SAND);
        Build.fill(world, 3, Y, -HALF_Z, 3, Y, HALF_Z, Material.WHITE_CONCRETE);
        Build.fill(world, FINISH_X, Y, -HALF_Z, FINISH_X + 1, Y, HALF_Z, Material.RED_CONCRETE);
        Build.fill(world, FINISH_X + 2, Y, -HALF_Z, LENGTH + 10, Y, HALF_Z, Material.SMOOTH_SANDSTONE);
        // the pink walls
        Build.fill(world, -4, Y + 1, -HALF_Z - 1, LENGTH + 10, Y + 7, -HALF_Z - 1, Material.PINK_CONCRETE);
        Build.fill(world, -4, Y + 1, HALF_Z + 1, LENGTH + 10, Y + 7, HALF_Z + 1, Material.PINK_CONCRETE);
        Build.fill(world, -5, Y + 1, -HALF_Z - 1, -5, Y + 7, HALF_Z + 1, Material.PINK_CONCRETE);
        Build.fill(world, LENGTH + 11, Y + 1, -HALF_Z - 1, LENGTH + 11, Y + 7, HALF_Z + 1, Material.PINK_CONCRETE);
        Build.walls(world, -5, Y + 8, -HALF_Z - 1, LENGTH + 11, Y + 14, HALF_Z + 1, Material.BARRIER);
        // a tree behind the giant, like the real thing
        for (int y = Y + 1; y <= Y + 6; y++) {
            Build.set(world, LENGTH + 8, y, 0, Material.DARK_OAK_LOG);
        }
        Build.disc(world, LENGTH + 8, Y + 7, 0, 3, Material.DARK_OAK_LEAVES);
        Build.disc(world, LENGTH + 8, Y + 8, 0, 2, Material.DARK_OAK_LEAVES);
    }

    @Override
    protected void onStart(List<Player> list) {
        for (int i = 0; i < list.size(); i++) {
            Player p = list.get(i);
            double z = list.size() == 1 ? 0.5 : -HALF_Z + 2 + (HALF_Z * 2 - 4) * (i / (double) Math.max(1, list.size() - 1));
            Location start = new Location(world, 1.5, Y + 1, z, -90, 0);
            p.teleport(start);
            Msg.title(p, "<light_purple><bold>Red Light, Green Light", "<gray>Only move on <green>green<gray>!", 5, 50, 10);
        }
        doll = world.spawn(new Location(world, LENGTH + 5.5, Y + 1, 0.5, -90, 0), Giant.class, g -> {
            g.setAI(false);
            g.setInvulnerable(true);
            g.setSilent(true);
            g.setPersistent(true);
            g.setRemoveWhenFarAway(false);
        });
        Msg.all(list, "<gray>Run to the <red>red line</red> while the giant looks away. If you move when it's watching, you're out!");
        light = Light.WAITING;
        phaseTicks = 60;
    }

    @Override
    protected boolean wantsTicks() {
        return true;
    }

    @Override
    protected void onTick() {
        if (state != State.RUNNING) {
            return;
        }
        if (light == Light.RED) {
            redTicks++;
            if (redTicks == GRACE_TICKS) {
                frozenAt.clear();
                for (Player p : runners()) {
                    frozenAt.put(p.getUniqueId(), p.getLocation());
                }
            }
        }
        if (--phaseTicks > 0) {
            return;
        }
        if (light == Light.GREEN) {
            light = Light.RED;
            redTicks = 0;
            phaseTicks = 40 + random.nextInt(40);
            turnDoll(true);
            for (Player p : online()) {
                Msg.title(p, "<red><bold>RED LIGHT!", "<gray>Freeze!", 0, phaseTicks, 3);
            }
            Msg.sound(online(), "entity.elder_guardian.curse", 1.6f);
        } else {
            light = Light.GREEN;
            frozenAt.clear();
            // green lights get shorter as the game goes on
            int min = Math.max(20, 50 - elapsed / 2);
            phaseTicks = min + random.nextInt(60);
            turnDoll(false);
            for (Player p : online()) {
                Msg.title(p, "<green><bold>GREEN LIGHT!", "<gray>Go go go!", 0, 20, 5);
            }
            Msg.sound(online(), "block.note_block.bell", 1.2f);
        }
    }

    private void turnDoll(boolean watching) {
        if (doll != null && doll.isValid()) {
            doll.setRotation(watching ? 90 : -90, 0);
        }
    }

    private List<Player> runners() {
        List<Player> list = new ArrayList<>();
        for (Player p : alivePlayers()) {
            if (!finished.contains(p.getUniqueId()) && p.getGameMode() == GameMode.SURVIVAL) {
                list.add(p);
            }
        }
        return list;
    }

    @Override
    public void onMove(PlayerMoveEvent event) {
        Player p = event.getPlayer();
        if (finished.contains(p.getUniqueId()) || p.getGameMode() != GameMode.SURVIVAL) {
            return;
        }
        Location to = event.getTo();
        if (light == Light.WAITING && to.getX() > 3) {
            event.setTo(event.getFrom().clone().add(-0.3, 0, 0));
            Msg.actionBar(p, "<yellow>Wait for the green light!");
            return;
        }
        if (to.getX() >= FINISH_X) {
            finish(p);
            return;
        }
        Location frozen = frozenAt.get(p.getUniqueId());
        if (light == Light.RED && frozen != null) {
            double dx = to.getX() - frozen.getX();
            double dz = to.getZ() - frozen.getZ();
            if (dx * dx + dz * dz > 0.04 || to.getY() - frozen.getY() > 0.5) {
                frozenAt.remove(p.getUniqueId());
                world.playSound(p.getLocation(), "entity.firework_rocket.blast", 1.5f, 0.6f);
                Msg.all(online(), "<red>" + p.getName() + " <gray>moved on a red light!");
                plugin.stats().addDeath(p, type);
                eliminate(p, true);
            }
        }
    }

    private void finish(Player p) {
        finished.add(p.getUniqueId());
        int place = finished.size();
        String suffix = place == 1 ? "st" : place == 2 ? "nd" : place == 3 ? "rd" : "th";
        Msg.all(online(), "<green>" + p.getName() + " <gray>made it across in <gold>" + place + suffix + "</gold> place! <dark_gray>("
                + Msg.time(elapsed) + ")");
        Msg.title(p, "<green><bold>SAFE!", "<gray>" + place + suffix + " place", 0, 40, 10);
        Msg.sound(p, "entity.player.levelup", 1.2f);
        firework(p.getLocation());
        checkWin();
    }

    @Override
    protected void checkWin() {
        if (state != State.RUNNING) {
            return;
        }
        if (runners().isEmpty()) {
            endRace();
        }
    }

    private void endRace() {
        List<UUID> winners = new ArrayList<>();
        for (UUID id : finished) {
            if (players.contains(id)) {
                winners.add(id);
            }
        }
        if (winners.isEmpty()) {
            end(null, List.of());
            return;
        }
        Player first = Bukkit.getPlayer(winners.get(0));
        String name = (first == null ? "?" : first.getName()) + (winners.size() > 1 ? " and " + (winners.size() - 1) + " more" : "");
        end(name, winners);
    }

    @Override
    protected void onSecond() {
        int left = TIME_LIMIT - elapsed;
        BossBar.Color color = light == Light.RED ? BossBar.Color.RED : light == Light.GREEN ? BossBar.Color.GREEN : BossBar.Color.YELLOW;
        String status = light == Light.RED ? "<red><bold>RED LIGHT" : light == Light.GREEN ? "<green><bold>GREEN LIGHT" : "<yellow>Get ready...";
        bossBar(status + " <dark_gray>| <white>" + Msg.time(left) + " <dark_gray>| <green>" + finished.size() + " safe",
                Math.max(0, (float) left / TIME_LIMIT), color);
        if (left == 30 || left == 10) {
            Msg.all(online(), "<yellow>" + left + " seconds left!");
        }
        if (left <= 0) {
            for (Player p : runners()) {
                Msg.all(online(), "<red>" + p.getName() + " <gray>ran out of time!");
                alive.remove(p.getUniqueId());
                makeSpectator(p);
            }
            endRace();
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (event.getCause() != EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(true);
        }
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        eliminate(victim, true);
    }

    @Override
    protected double voidLevel() {
        return Y - 10;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, LENGTH / 2.0, Y + 12, HALF_Z - 2, 0, 50);
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        lines.add(light == Light.RED ? "<red><bold>RED LIGHT" : light == Light.GREEN ? "<green><bold>GREEN LIGHT" : "<yellow>Get ready...");
        lines.add("  ");
        lines.add("<white>Running: <yellow>" + runners().size());
        lines.add("<white>Safe: <green>" + finished.size());
        lines.add("<white>Time: <yellow>" + Msg.time(TIME_LIMIT - elapsed));
        if (isAlive(player) && !finished.contains(player.getUniqueId())) {
            lines.add("   ");
            lines.add("<white>To go: <gold>" + Math.max(0, (int) (FINISH_X - player.getLocation().getX())) + " blocks");
        }
        return lines;
    }

    @Override
    protected void cleanup() {
        frozenAt.clear();
        finished.clear();
        if (doll != null) {
            doll.remove();
        }
    }

    @Override
    public void botTick(Player bot, net.funcraft.games.bots.BotBrain brain) {
        if (finished.contains(bot.getUniqueId())) {
            return;
        }
        if (brain.memo != light) {
            brain.memo = light;
            // reaction time; now and then a bot is too slow and gets caught
            brain.timer = light == Light.RED ? (brain.random().nextInt(25) == 0 ? 14 : brain.random().nextInt(5)) : 2 + brain.random().nextInt(6);
        }
        boolean go = light == Light.GREEN ? brain.timer <= 0 : light == Light.RED && brain.timer > 0;
        if (go) {
            Location l = bot.getLocation();
            brain.moveTo(new Location(world, LENGTH + 2, l.getY(), l.getZ()), brain.random().nextInt(3) > 0);
        }
    }
}
