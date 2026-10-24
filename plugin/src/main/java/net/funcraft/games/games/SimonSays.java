package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.Msg;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.player.PlayerMoveEvent;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Simon Says: do what Simon says - but only when Simon says it. "Simon says jump!" means jump;
 * plain "Jump!" means don't. Get it wrong and you're out. The orders come faster every round.
 */
public final class SimonSays extends LastStanding {

    private static final int FLOOR = 64;
    private static final double RADIUS = 12;

    private enum Task {
        JUMP("JUMP!"), SNEAK("CROUCH!"), LOOK_UP("LOOK UP!"), LOOK_DOWN("LOOK DOWN!"), PUNCH("PUNCH SOMEONE!"),
        MIDDLE("GO TO THE MIDDLE!"), EDGE("GO TO THE EDGE!"), COLOUR("STAND ON "), STILL("DON'T MOVE!");

        final String text;

        Task(String text) {
            this.text = text;
        }
    }

    private record Colour(Material block, String name) {
    }

    private static final Colour[] COLOURS = {new Colour(Material.RED_WOOL, "<red>RED"), new Colour(Material.BLUE_WOOL, "<blue>BLUE"),
            new Colour(Material.LIME_WOOL, "<green>GREEN"), new Colour(Material.YELLOW_WOOL, "<yellow>YELLOW"),
            new Colour(Material.PURPLE_WOOL, "<dark_purple>PURPLE"), new Colour(Material.ORANGE_WOOL, "<gold>ORANGE")};

    private Task task;
    private boolean simon;
    private Colour colour;
    private int roundTicks;
    private int roundLength;
    private int breakTicks = 60;
    private int round;
    private final Map<UUID, Location> startPos = new HashMap<>();
    private final Map<UUID, Double> moved = new HashMap<>();
    private final Set<UUID> jumped = new HashSet<>();
    private final Set<UUID> punched = new HashSet<>();

    public SimonSays(FunCraft plugin, int id) {
        super(plugin, id, GameType.SIMON_SAYS);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-16, -16, 16, 16};
    }

    @Override
    protected void buildMap() {
        mapName = "Simon's Stage";
        center = new Location(world, 0.5, FLOOR + 1, 0.5);
        Build.disc(world, 0, FLOOR - 1, 0, RADIUS + 1, Material.STONE);
        Build.disc(world, 0, FLOOR, 0, RADIUS, Material.WHITE_CONCRETE);
        Build.ring(world, 0, FLOOR, 0, RADIUS - 1.5, RADIUS, Material.BLACK_CONCRETE);
        Build.disc(world, 0, FLOOR, 0, 2.2, Material.GOLD_BLOCK);
        for (int i = 0; i < COLOURS.length; i++) {
            double a = Math.toRadians(i * 360.0 / COLOURS.length + 30);
            int x = (int) Math.round(Math.cos(a) * 7);
            int z = (int) Math.round(Math.sin(a) * 7);
            Build.fill(world, x - 1, FLOOR, z - 1, x + 1, FLOOR, z + 1, COLOURS[i].block());
        }
        for (int y = FLOOR + 1; y <= FLOOR + 5; y++) {
            Build.ring(world, 0, y, 0, RADIUS, RADIUS + 1, y <= FLOOR + 1 ? Material.QUARTZ_BLOCK : Material.BARRIER);
        }
        spawnRing(FLOOR + 1, 4.5, Math.max(2, online().isEmpty() ? 8 : online().size()));
    }

    @Override
    protected void equip(Player player) {
        player.getInventory().clear();
    }

    @Override
    protected void onStart(List<Player> list) {
        super.onStart(list);
        Msg.all(list, "<gray>Only do it when <green>Simon says</green> so! Doing it without \"Simon says\" gets you out too.");
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
        if (task == null) {
            if (--breakTicks <= 0) {
                newRound();
            }
            return;
        }
        if (++roundTicks >= roundLength) {
            judge();
        }
    }

    private void newRound() {
        round++;
        Task[] tasks = Task.values();
        task = tasks[random.nextInt(tasks.length)];
        simon = task == Task.STILL || random.nextInt(10) < 7;
        colour = COLOURS[random.nextInt(COLOURS.length)];
        roundTicks = 0;
        roundLength = Math.max(45, 100 - round * 4);
        startPos.clear();
        moved.clear();
        jumped.clear();
        punched.clear();
        for (Player p : alivePlayers()) {
            startPos.put(p.getUniqueId(), p.getLocation());
            moved.put(p.getUniqueId(), 0.0);
        }
        String order = task == Task.COLOUR ? task.text + colour.name() + "!" : task.text;
        String line = (simon ? "<green><bold>Simon says:</bold> <white>" : "<white>") + order;
        for (Player p : online()) {
            Msg.title(p, line, "<gray>Round " + round, 0, roundLength, 5);
        }
        Msg.all(online(), line);
        Msg.sound(online(), "block.note_block.pling", simon ? 1.4f : 0.9f);
    }

    private boolean did(Player p) {
        UUID id = p.getUniqueId();
        Location l = p.getLocation();
        return switch (task) {
            case JUMP -> jumped.contains(id);
            case SNEAK -> p.isSneaking();
            case LOOK_UP -> l.getPitch() < -45;
            case LOOK_DOWN -> l.getPitch() > 45;
            case PUNCH -> punched.contains(id);
            case MIDDLE -> l.distanceSquared(center) < 3.2 * 3.2;
            case EDGE -> Math.hypot(l.getX() - 0.5, l.getZ() - 0.5) > RADIUS - 2.5;
            case COLOUR -> l.clone().subtract(0, 0.2, 0).getBlock().getType() == colour.block();
            case STILL -> moved.getOrDefault(id, 0.0) < 0.4;
        };
    }

    private void judge() {
        List<Player> out = new ArrayList<>();
        for (Player p : alivePlayers()) {
            if (p.getGameMode() == GameMode.SURVIVAL && did(p) != simon) {
                out.add(p);
            }
        }
        List<Player> playing = alivePlayers();
        if (out.size() >= playing.size() && playing.size() > 1) {
            Msg.all(online(), "<yellow>Everyone got that one wrong - nobody is out!");
        } else {
            for (Player p : out) {
                Msg.all(online(), "<red>" + p.getName() + " <gray>" + (simon ? "didn't do it!" : "fell for it - Simon didn't say!"));
                plugin.stats().addDeath(p, type);
                eliminate(p, true);
            }
        }
        if (out.isEmpty()) {
            Msg.all(online(), "<green>Everyone got it right!");
        }
        for (Player p : alivePlayers()) {
            p.setSneaking(false);
        }
        task = null;
        breakTicks = Math.max(25, 50 - round);
    }

    @Override
    public void onMove(PlayerMoveEvent event) {
        if (task == null) {
            return;
        }
        UUID id = event.getPlayer().getUniqueId();
        Location start = startPos.get(id);
        Location to = event.getTo();
        if (start != null && to.getY() > start.getY() + 0.6) {
            jumped.add(id);
        }
        double dx = to.getX() - event.getFrom().getX();
        double dz = to.getZ() - event.getFrom().getZ();
        moved.merge(id, Math.sqrt(dx * dx + dz * dz), Double::sum);
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (attacker != null && task != null) {
            punched.add(attacker.getUniqueId());
        }
        if (event.getCause() != EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(true);
        }
    }

    @Override
    public void botTick(Player bot, net.funcraft.games.bots.BotBrain brain) {
        if (task == null) {
            brain.memo = null;
            brain.wander(center, 5, false);
            return;
        }
        if (brain.memo == null) {
            // decide whether to do it (bots are good, not perfect) and how fast to react
            boolean obey = simon ? brain.random().nextInt(100) < 88 : brain.random().nextInt(100) < 18;
            brain.memo = obey;
            brain.timer = 6 + brain.random().nextInt(18);
        }
        if (!(Boolean) brain.memo) {
            if (task == Task.STILL) {
                brain.wander(center, 6, true); // fell for it
            } else {
                brain.stop();
            }
            return;
        }
        if (brain.timer > 0) {
            brain.stop();
            return;
        }
        switch (task) {
            case JUMP -> brain.jump();
            case SNEAK -> bot.setSneaking(true);
            case LOOK_UP -> brain.setPitch(-80);
            case LOOK_DOWN -> brain.setPitch(80);
            case PUNCH -> {
                Player near = brain.nearestEnemy(this, 30);
                if (near != null) {
                    brain.fight(near);
                }
            }
            case MIDDLE -> brain.moveTo(center, true);
            case EDGE -> {
                Location l = bot.getLocation();
                double a = Math.atan2(l.getZ() - 0.5, l.getX() - 0.5);
                brain.moveTo(center.clone().add(Math.cos(a) * (RADIUS - 1.2), 0, Math.sin(a) * (RADIUS - 1.2)), true);
            }
            case COLOUR -> {
                for (int i = 0; i < COLOURS.length; i++) {
                    if (COLOURS[i] == colour) {
                        double a = Math.toRadians(i * 360.0 / COLOURS.length + 30);
                        brain.moveTo(new Location(world, Math.round(Math.cos(a) * 7) + 0.5, FLOOR + 1, Math.round(Math.sin(a) * 7) + 0.5), true);
                    }
                }
            }
            case STILL -> brain.stop();
        }
    }

    @Override
    protected int timeLimit() {
        return 300;
    }

    @Override
    protected String objective() {
        return "Only do it when Simon says!";
    }

    @Override
    protected double voidLevel() {
        return FLOOR - 8;
    }

    @Override
    protected List<String> extraSidebar(Player player) {
        return List.of("<white>Round: <yellow>" + round);
    }

    @Override
    protected void cleanup() {
        super.cleanup();
        task = null;
        startPos.clear();
        moved.clear();
        jumped.clear();
        punched.clear();
    }
}
