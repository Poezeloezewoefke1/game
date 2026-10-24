package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Arenas;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Structures;
import net.funcraft.games.util.Theme;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.Particle;
import org.bukkit.block.Block;
import org.bukkit.entity.Player;
import org.bukkit.event.block.BlockFromToEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.inventory.ItemStack;

import java.util.ArrayList;
import java.util.List;

/**
 * The Floor is Lava: lava rises up through a hilly map full of towers, one layer every few
 * seconds and faster as time goes on. Climb, build up and push others down. Last one above the
 * lava wins.
 */
public final class FloorIsLava extends LastStanding {

    private static final int BASE = 50;
    private static final int RADIUS = 28;
    private static final int START_DELAY = 10;

    private int[][] heights;
    private int lavaY = BASE - 6;
    private int riseTimer;
    private final List<Location> peaks = new ArrayList<>();

    public FloorIsLava(FunCraft plugin, int id) {
        super(plugin, id, GameType.FLOOR_IS_LAVA);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-RADIUS - 4, -RADIUS - 4, RADIUS + 4, RADIUS + 4};
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + " Volcano";
        heights = Arenas.hills(world, theme, random, BASE, RADIUS, 9, 8);
        // towers and ruins to climb
        for (int i = 0; i < 9; i++) {
            double a = random.nextDouble() * Math.PI * 2;
            double d = 5 + random.nextDouble() * (RADIUS - 10);
            int x = (int) Math.round(Math.cos(a) * d);
            int z = (int) Math.round(Math.sin(a) * d);
            int h = Arenas.height(heights, RADIUS, x, z);
            if (h < 0) {
                continue;
            }
            if (i % 3 == 0) {
                Structures.tower(world, x, h + 1, z, 8 + random.nextInt(8), theme);
            } else if (i % 3 == 1) {
                Structures.ruins(world, x, h + 1, z, theme, random);
            } else {
                theme.tree(world, x, h + 1, z, random);
            }
        }
        // a tall pillar in the middle with a ladder - the last safe spot
        int mid = Math.max(BASE, Arenas.height(heights, RADIUS, 0, 0));
        Structures.tower(world, 0, mid + 1, 0, 22, theme);
        theme.plants(world, 0, BASE, 0, RADIUS, 80, random);
        // remember the highest ground for the bots
        for (int x = -RADIUS; x <= RADIUS; x += 3) {
            for (int z = -RADIUS; z <= RADIUS; z += 3) {
                int h = Arenas.height(heights, RADIUS, x, z);
                if (h > 0) {
                    peaks.add(new Location(world, x + 0.5, h + 1, z + 0.5));
                }
            }
        }
        peaks.sort((a, b) -> Double.compare(b.getY(), a.getY()));
        while (peaks.size() > 12) {
            peaks.remove(peaks.size() - 1);
        }
        center = new Location(world, 0.5, BASE + 1, 0.5);
        int count = Math.max(2, online().isEmpty() ? 8 : online().size());
        spawns.clear();
        for (int i = 0; i < count; i++) {
            double a = Math.toRadians(i * 360.0 / count);
            int x = (int) Math.round(Math.cos(a) * (RADIUS - 8));
            int z = (int) Math.round(Math.sin(a) * (RADIUS - 8));
            int h = Math.max(BASE, Arenas.height(heights, RADIUS, x, z));
            Build.fill(world, x, h + 1, z, x, h + 3, z, Material.AIR);
            spawns.add(Build.lookAt(new Location(world, x + 0.5, h + 1, z + 0.5), center));
        }
    }

    @Override
    protected void equip(Player p) {
        p.getInventory().clear();
        p.getInventory().setItem(0, ItemBuilder.of(Material.STICK).name("<gold>Push Stick")
                .enchant(org.bukkit.enchantments.Enchantment.KNOCKBACK, 1).build());
        p.getInventory().setItem(1, new ItemStack(Material.COBBLESTONE, 32));
        p.getInventory().setItem(2, new ItemStack(Material.ENDER_PEARL));
        p.getInventory().setItem(3, new ItemStack(Material.LADDER, 8));
    }

    @Override
    protected void onStart(List<Player> list) {
        super.onStart(list);
        Msg.all(list, "<red>The floor is lava!</red> <gray>It starts rising in " + START_DELAY + " seconds. Get high and stay high!");
        riseTimer = START_DELAY;
    }

    @Override
    protected void onSecond() {
        super.onSecond();
        if (state != State.RUNNING) {
            return;
        }
        if (--riseTimer > 0) {
            if (elapsed < START_DELAY) {
                return;
            }
        } else {
            rise();
            riseTimer = elapsed < 60 ? 4 : elapsed < 120 ? 3 : 2;
        }
        for (Player p : alivePlayers()) {
            int above = (int) Math.floor(p.getLocation().getY()) - lavaY;
            Msg.actionBar(p, (above <= 3 ? "<red><bold>" : "<yellow>") + "Lava: " + above + " blocks below you");
        }
    }

    private void rise() {
        lavaY++;
        for (int x = -RADIUS - 2; x <= RADIUS + 2; x++) {
            for (int z = -RADIUS - 2; z <= RADIUS + 2; z++) {
                if (x * x + z * z > (RADIUS + 2) * (RADIUS + 2)) {
                    continue;
                }
                Block b = world.getBlockAt(x, lavaY, z);
                if (b.isPassable() || b.getType() == Material.LADDER) {
                    b.setType(Material.LAVA, false);
                }
            }
        }
        if (lavaY % 5 == 0) {
            Msg.all(online(), "<red>The lava is rising! <gray>(height " + (lavaY - BASE) + ")");
        }
        world.spawnParticle(Particle.LAVA, center.clone().add(0, lavaY - BASE, 0), 30, RADIUS / 2.0, 0.5, RADIUS / 2.0);
    }

    @Override
    public void onFlow(BlockFromToEvent event) {
        if (event.getBlock().getType() == Material.LAVA) {
            event.setCancelled(true); // we fill the layers ourselves
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        EntityDamageEvent.DamageCause c = event.getCause();
        if (c == EntityDamageEvent.DamageCause.LAVA) {
            event.setDamage(1000);
        } else if (c == EntityDamageEvent.DamageCause.FIRE || c == EntityDamageEvent.DamageCause.FIRE_TICK) {
            event.setCancelled(true);
            victim.setFireTicks(0);
        } else if (attacker != null && c == EntityDamageEvent.DamageCause.ENTITY_ATTACK) {
            event.setDamage(0.01); // pushes only
            org.bukkit.Bukkit.getScheduler().runTask(plugin, () -> {
                if (victim.isOnline() && !victim.isDead()) {
                    victim.setHealth(20);
                }
            });
        } else if (c == EntityDamageEvent.DamageCause.FALL) {
            event.setDamage(event.getDamage() / 2);
        }
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        if (killer != null) {
            deathMessage(victim, killer, null);
        } else {
            Msg.all(online(), "<red>" + victim.getName() + " <gray>touched the lava!");
        }
        eliminate(victim, true);
    }

    @Override
    public void onBlockPlace(BlockPlaceEvent event) {
        if (Math.abs(event.getBlock().getX()) > RADIUS + 2 || Math.abs(event.getBlock().getZ()) > RADIUS + 2) {
            event.setCancelled(true);
        }
    }

    @Override
    public void onBlockBreak(org.bukkit.event.block.BlockBreakEvent event) {
        event.setDropItems(false);
    }

    @Override
    public boolean botsBuild() {
        return true;
    }

    @Override
    public void botTick(Player bot, net.funcraft.games.bots.BotBrain brain) {
        Player enemy = brain.nearestEnemy(this, 4);
        if (enemy != null) {
            brain.fight(enemy);
            return;
        }
        if (!(brain.memo instanceof Location) || brain.timer <= 0) {
            brain.memo = peaks.isEmpty() ? center : peaks.get(brain.random().nextInt(Math.min(4, peaks.size())));
            brain.timer = 200;
        }
        Location peak = (Location) brain.memo;
        if (brain.flatDistance(peak) > 1.5) {
            brain.moveTo(peak, true);
        } else if (bot.getLocation().getY() < lavaY + 4) {
            // pillar up out of reach
            brain.jump();
            if (!bot.isOnGround() && bot.getVelocity().getY() < 0.1) {
                Block under = bot.getLocation().subtract(0, 1, 0).getBlock();
                ItemStack blocks = bot.getInventory().getItem(1);
                if (under.isPassable() && blocks != null && blocks.getType() == Material.COBBLESTONE) {
                    brain.place(under, under.getRelative(org.bukkit.block.BlockFace.DOWN), blocks);
                }
            }
        }
    }

    @Override
    protected int timeLimit() {
        return 360;
    }

    @Override
    protected String objective() {
        return "Climb! The lava is rising!";
    }

    @Override
    protected double voidLevel() {
        return BASE - 20;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 0.5, BASE + 40, 0.5, 0, 70);
    }

    @Override
    protected List<String> extraSidebar(Player player) {
        return List.of("<white>Lava height: <red>" + Math.max(0, lavaY - BASE));
    }

    @Override
    protected void cleanup() {
        super.cleanup();
        lavaY = BASE - 6;
        peaks.clear();
    }
}
