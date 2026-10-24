package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.kyori.adventure.bossbar.BossBar;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.inventory.ItemStack;

import java.util.List;

/**
 * Dance floor of coloured tiles. A colour is called, a few seconds later every other colour
 * disappears; whoever isn't standing on the right colour falls. Each round is a bit faster.
 */
public final class BlockParty extends LastStanding {

    private static final int FLOOR_Y = 64;
    private static final int HALF = 16;

    private enum Phase { DANCE, CALL, DROP }

    private record Colour(Material block, String name, String mm) {
    }

    private static final Colour[] COLOURS = {
            new Colour(Material.RED_CONCRETE, "RED", "<red>"),
            new Colour(Material.ORANGE_CONCRETE, "ORANGE", "<gold>"),
            new Colour(Material.YELLOW_CONCRETE, "YELLOW", "<yellow>"),
            new Colour(Material.LIME_CONCRETE, "LIME", "<green>"),
            new Colour(Material.GREEN_CONCRETE, "GREEN", "<dark_green>"),
            new Colour(Material.LIGHT_BLUE_CONCRETE, "LIGHT BLUE", "<aqua>"),
            new Colour(Material.BLUE_CONCRETE, "BLUE", "<blue>"),
            new Colour(Material.PURPLE_CONCRETE, "PURPLE", "<dark_purple>"),
            new Colour(Material.MAGENTA_CONCRETE, "MAGENTA", "<light_purple>"),
            new Colour(Material.PINK_CONCRETE, "PINK", "<#ff9ecb>"),
            new Colour(Material.WHITE_CONCRETE, "WHITE", "<white>"),
            new Colour(Material.BLACK_CONCRETE, "BLACK", "<dark_gray>")};
    private static final float[] MELODY = {0.6f, 0.8f, 0.9f, 1.2f, 0.9f, 0.8f, 1.0f, 1.35f, 1.2f, 0.9f, 0.7f, 1.0f};

    private Phase phase = Phase.DANCE;
    private int phaseTicks;
    private int phaseLength;
    private int round;
    private Colour called;

    public BlockParty(FunCraft plugin, int id) {
        super(plugin, id, GameType.BLOCK_PARTY);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-HALF - 8, -HALF - 8, HALF + 8, HALF + 8};
    }

    @Override
    protected void buildMap() {
        center = new Location(world, 0.5, FLOOR_Y + 1, 0.5);
        mapName = "Disco";
        paintFloor();
        // speaker towers in the corners
        for (int[] c : new int[][]{{-HALF - 3, -HALF - 3}, {HALF + 2, -HALF - 3}, {-HALF - 3, HALF + 2}, {HALF + 2, HALF + 2}}) {
            Build.fill(world, c[0], FLOOR_Y - 6, c[1], c[0] + 1, FLOOR_Y + 6, c[1] + 1, Material.BLACK_CONCRETE);
            Build.fill(world, c[0], FLOOR_Y + 2, c[1], c[0] + 1, FLOOR_Y + 3, c[1] + 1, Material.NOTE_BLOCK);
            Build.fill(world, c[0], FLOOR_Y + 7, c[1], c[0] + 1, FLOOR_Y + 7, c[1] + 1, Material.SEA_LANTERN);
        }
        spawnRing(FLOOR_Y + 1, HALF - 4, Math.max(2, online().isEmpty() ? 8 : online().size()));
    }

    /** A fresh random pattern; tiles get smaller as the rounds go on. */
    private void paintFloor() {
        int colours = Math.min(COLOURS.length, 6 + round / 2);
        int tile = round < 3 ? 4 : round < 7 ? 3 : 2;
        for (int x = -HALF; x < HALF; x += tile) {
            for (int z = -HALF; z < HALF; z += tile) {
                Material m = COLOURS[random.nextInt(colours)].block();
                // clip tiles at the floor edge: 32 isn't a multiple of 3, and anything painted
                // outside -HALF..HALF-1 would never be removed by drop()
                Build.fill(world, x, FLOOR_Y, z, Math.min(x + tile - 1, HALF - 1), FLOOR_Y, Math.min(z + tile - 1, HALF - 1), m);
            }
        }
        // clear any stray blocks just outside the floor
        for (int i = -HALF - 1; i <= HALF; i++) {
            Build.set(world, HALF, FLOOR_Y, i, Material.AIR);
            Build.set(world, i, FLOOR_Y, HALF, Material.AIR);
            Build.set(world, -HALF - 1, FLOOR_Y, i, Material.AIR);
            Build.set(world, i, FLOOR_Y, -HALF - 1, Material.AIR);
        }
    }

    @Override
    protected void equip(Player player) {
        player.setGameMode(GameMode.ADVENTURE);
    }

    @Override
    protected boolean wantsTicks() {
        return true;
    }

    @Override
    protected void onTick() {
        phaseTicks++;
        switch (phase) {
            case DANCE -> {
                if (phaseTicks % 4 == 0) {
                    Msg.sound(online(), "block.note_block.harp", MELODY[(phaseTicks / 4) % MELODY.length]);
                }
                if (phaseTicks >= 60) {
                    callColour();
                }
            }
            case CALL -> {
                float left = 1f - (float) phaseTicks / phaseLength;
                for (Player p : online()) {
                    p.setExp(Math.max(0, Math.min(0.999f, left)));
                    p.setLevel((int) Math.ceil((phaseLength - phaseTicks) / 20.0));
                }
                bossBar(called.mm() + "<bold>" + called.name() + "</bold>", left, BossBar.Color.PINK);
                if (phaseTicks % 5 == 0) {
                    Msg.sound(online(), "block.note_block.bit", 0.8f + (float) phaseTicks / phaseLength);
                }
                if (phaseTicks >= phaseLength) {
                    drop();
                }
            }
            case DROP -> {
                if (phaseTicks >= 50) {
                    round++;
                    paintFloor();
                    for (Player p : alivePlayers()) {
                        p.getInventory().clear();
                    }
                    if (alive.size() > 1 || startingPlayers <= 1) {
                        Msg.all(online(), "<light_purple>Round " + (round + 1) + "! <gray>" + alive.size() + " dancers left.");
                    }
                    setPhase(Phase.DANCE, 0);
                }
            }
        }
    }

    private void setPhase(Phase next, int length) {
        phase = next;
        phaseTicks = 0;
        phaseLength = length;
    }

    private void callColour() {
        // only call colours that are actually on the floor
        List<Material> present = new java.util.ArrayList<>();
        for (int x = -HALF; x < HALF; x += 2) {
            for (int z = -HALF; z < HALF; z += 2) {
                Material m = world.getBlockAt(x, FLOOR_Y, z).getType();
                if (!present.contains(m)) {
                    present.add(m);
                }
            }
        }
        Material pick = present.get(random.nextInt(present.size()));
        for (Colour c : COLOURS) {
            if (c.block() == pick) {
                called = c;
            }
        }
        int ticks = Math.max(22, 90 - round * 7);
        setPhase(Phase.CALL, ticks);
        ItemStack item = ItemBuilder.of(called.block()).name(called.mm() + "<bold>" + called.name()).build();
        for (Player p : alivePlayers()) {
            for (int i = 0; i < 9; i++) {
                p.getInventory().setItem(i, item.clone());
            }
            Msg.title(p, called.mm() + "<bold>" + called.name(), "<gray>Stand on it!", 0, ticks, 5);
        }
    }

    private void drop() {
        for (int x = -HALF; x < HALF; x++) {
            for (int z = -HALF; z < HALF; z++) {
                if (world.getBlockAt(x, FLOOR_Y, z).getType() != called.block()) {
                    world.getBlockAt(x, FLOOR_Y, z).setType(Material.AIR, false);
                }
            }
        }
        Msg.sound(online(), "entity.generic.explode", 1.4f);
        for (Player p : online()) {
            p.setExp(0);
            p.setLevel(0);
        }
        bossBar("<gray>Round " + (round + 1) + " - hold on!", 0, BossBar.Color.PINK);
        setPhase(Phase.DROP, 0);
    }

    @Override
    protected void onSecond() {
        // no time limit - the rounds get faster until someone is left
        if (phase == Phase.DANCE) {
            bossBar("<light_purple><bold>Block Party</bold> <gray>- round " + (round + 1) + " - get ready...", 1, BossBar.Color.PINK);
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (event.getCause() == EntityDamageEvent.DamageCause.ENTITY_ATTACK && attacker != null) {
            // punch people off their colour: knockback, no damage
            // a 0-damage hit can skip knockback, so deal a hair of damage and heal it right back
            event.setDamage(0.01);
            org.bukkit.Bukkit.getScheduler().runTask(plugin, () -> {
                if (victim.isOnline() && !victim.isDead()) {
                    victim.setHealth(20);
                }
            });
        } else if (event.getCause() != EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(true);
        }
    }

    @Override
    protected List<String> extraSidebar(Player player) {
        return List.of("<white>Round: <light_purple>" + (round + 1));
    }

    @Override
    protected String objective() {
        return "Stand on the called colour - punch others off theirs!";
    }

    @Override
    protected int timeLimit() {
        return 0;
    }

    @Override
    protected double voidLevel() {
        return FLOOR_Y - 10;
    }

    @Override
    public void botTick(Player bot, net.funcraft.games.bots.BotBrain brain) {
        if (phase == Phase.DANCE || called == null) {
            brain.memo = null;
            brain.wander(new Location(world, 0.5, FLOOR_Y + 1, 0.5), HALF - 3, false);
            return;
        }
        if (!(brain.memo instanceof Location target) || world.getBlockAt(target.getBlockX(), FLOOR_Y, target.getBlockZ()).getType() != called.block()) {
            // find the nearest tile of the called colour (bots are a little slow to react sometimes)
            Location me = bot.getLocation();
            Location best = null;
            double bestD = Double.MAX_VALUE;
            for (int x = -HALF + 1; x < HALF; x++) {
                for (int z = -HALF + 1; z < HALF; z++) {
                    if (world.getBlockAt(x, FLOOR_Y, z).getType() == called.block()) {
                        double d = (x + 0.5 - me.getX()) * (x + 0.5 - me.getX()) + (z + 0.5 - me.getZ()) * (z + 0.5 - me.getZ());
                        if (d < bestD) {
                            bestD = d;
                            best = new Location(world, x + 0.5, FLOOR_Y + 1, z + 0.5);
                        }
                    }
                }
            }
            brain.memo = best;
            if (best == null) {
                return;
            }
        }
        Location target = (Location) brain.memo;
        if (brain.flatDistance(target) > 0.4) {
            brain.moveTo(target, true);
        }
    }
}
