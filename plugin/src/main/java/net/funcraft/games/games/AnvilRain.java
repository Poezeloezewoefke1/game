package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.Msg;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.entity.FallingBlock;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDamageEvent;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Anvil Rain: anvils fall from the sky, faster and faster, and some aim straight at you. One hit
 * and you're out; landed anvils vanish after a few seconds. Last one standing wins.
 */
public final class AnvilRain extends LastStanding {

    private static final int FLOOR = 64;
    private static final int DROP_HEIGHT = 26;
    private static final double RADIUS = 11;
    private static final int LANDED_SECONDS = 3;

    private final Map<Block, Integer> landed = new HashMap<>();

    public AnvilRain(FunCraft plugin, int id) {
        super(plugin, id, GameType.ANVIL_RAIN);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-16, -16, 16, 16};
    }

    @Override
    protected void buildMap() {
        mapName = "The Forge";
        center = new Location(world, 0.5, FLOOR + 1, 0.5);
        Build.disc(world, 0, FLOOR - 1, 0, RADIUS + 1, Material.STONE);
        Build.disc(world, 0, FLOOR, 0, RADIUS, Material.POLISHED_ANDESITE);
        Build.ring(world, 0, FLOOR, 0, RADIUS - 1, RADIUS, Material.POLISHED_BLACKSTONE_BRICKS);
        Build.ring(world, 0, FLOOR, 0, 3, 4, Material.SMOOTH_STONE);
        for (int y = FLOOR + 1; y <= FLOOR + 3; y++) {
            Build.ring(world, 0, y, 0, RADIUS, RADIUS + 1, Material.IRON_BARS);
        }
        Build.ring(world, 0, FLOOR + 4, 0, RADIUS, RADIUS + 1.2, Material.POLISHED_BLACKSTONE_BRICK_WALL);
        spawnRing(FLOOR + 1, RADIUS - 3, Math.max(2, online().isEmpty() ? 8 : online().size()));
    }

    @Override
    protected void equip(Player player) {
        player.getInventory().clear();
    }

    @Override
    protected void onStart(List<Player> list) {
        super.onStart(list);
        Msg.all(list, "<gray>Watch the shadows - anvils are falling! <red>One hit and you're out.");
    }

    @Override
    protected boolean wantsTicks() {
        return true;
    }

    @Override
    protected void onTick() {
        if (state != State.RUNNING || elapsed < 3) {
            return;
        }
        // a few per second at first, a storm after a minute
        double perSecond = 1.5 + elapsed / 6.0;
        double chance = perSecond / 20.0;
        while (chance > 0) {
            if (random.nextDouble() < Math.min(1, chance)) {
                double a = random.nextDouble() * Math.PI * 2;
                double d = Math.sqrt(random.nextDouble()) * (RADIUS - 1.2);
                drop(Math.cos(a) * d, Math.sin(a) * d);
            }
            chance -= 1;
        }
    }

    private void drop(double x, double z) {
        Location at = new Location(world, Math.floor(x) + 0.5, FLOOR + DROP_HEIGHT, Math.floor(z) + 0.5);
        world.spawn(at, FallingBlock.class, fb -> {
            fb.setBlockData(Material.ANVIL.createBlockData());
            fb.setDropItem(false);
            fb.setHurtEntities(true);
            fb.setDamagePerBlock(2f);
            fb.setMaxDamage(40);
        });
    }

    @Override
    protected void onSecond() {
        super.onSecond();
        if (state != State.RUNNING) {
            return;
        }
        // every few seconds an anvil aims right at each player, so standing still doesn't work
        if (elapsed >= 5 && elapsed % 4 == 0) {
            for (Player p : alivePlayers()) {
                if (p.getGameMode() == GameMode.SURVIVAL) {
                    drop(p.getLocation().getX(), p.getLocation().getZ());
                }
            }
        }
        // clear anvils that landed a while ago
        for (int x = (int) -RADIUS; x <= RADIUS; x++) {
            for (int z = (int) -RADIUS; z <= RADIUS; z++) {
                for (int y = FLOOR + 1; y <= FLOOR + 3; y++) {
                    Block b = world.getBlockAt(x, y, z);
                    if (b.getType().name().endsWith("ANVIL")) {
                        landed.putIfAbsent(b, elapsed);
                    }
                }
            }
        }
        for (Map.Entry<Block, Integer> e : new ArrayList<>(landed.entrySet())) {
            if (elapsed - e.getValue() >= LANDED_SECONDS) {
                e.getKey().setType(Material.AIR, false);
                landed.remove(e.getKey());
            }
        }
        if (elapsed == 30 || elapsed == 60 || elapsed == 90) {
            Msg.all(online(), "<red>The anvils are coming down harder!");
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (event.getCause() == EntityDamageEvent.DamageCause.FALLING_BLOCK) {
            event.setDamage(1000);
        } else if (event.getCause() != EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(true);
        }
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        Msg.all(online(), "<red>" + victim.getName() + " <gray>got flattened by an anvil!");
        eliminate(victim, true);
        if (alive.size() > 1) {
            Msg.all(online(), "<gray>" + alive.size() + " players remaining.");
        }
    }

    @Override
    protected int timeLimit() {
        return 240;
    }

    @Override
    protected String objective() {
        return "Dodge the falling anvils!";
    }

    @Override
    protected double voidLevel() {
        return FLOOR - 10;
    }

    @Override
    protected Location spectatorSpawn() {
        return center.clone().add(0, 8, -RADIUS - 6);
    }

    @Override
    protected void cleanup() {
        super.cleanup();
        landed.clear();
    }
}
