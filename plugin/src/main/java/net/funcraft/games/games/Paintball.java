package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Theme;
import net.kyori.adventure.bossbar.BossBar;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.Particle;
import org.bukkit.entity.Player;
import org.bukkit.entity.Snowball;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.entity.ProjectileHitEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Paintball: Red vs Blue with endless snowballs. Every hit splats the other player back to their
 * base and scores a point for your team. First team to 30 points wins.
 */
public final class Paintball extends TeamGame {

    private static final int Y = 64;
    private static final int HALF_X = 32;
    private static final int HALF_Z = 18;
    private static final int GOAL = 30;
    private static final int TIME_LIMIT = 480;
    private static final int MAX_BALLS = 16;
    private static final long SPAWN_PROTECTION_MS = 2000;

    private final Map<UUID, Long> spawnedAt = new HashMap<>();

    public Paintball(FunCraft plugin, int id) {
        super(plugin, id, GameType.PAINTBALL);
    }

    @Override
    protected String kitId() {
        return "paintball";
    }

    @Override
    protected String objective() {
        return "Splat the other team - first to " + GOAL + " points!";
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-HALF_X - 4, -HALF_Z - 4, HALF_X + 4, HALF_Z + 4};
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + " Paintball Park";
        Build.fill(world, -HALF_X - 2, Y - 3, -HALF_Z - 2, HALF_X + 2, Y - 1, HALF_Z + 2, theme.stone);
        Build.fill(world, -HALF_X - 2, Y, -HALF_Z - 2, HALF_X + 2, Y, HALF_Z + 2, theme.top);
        // team bases
        Build.fill(world, -HALF_X, Y, -5, -HALF_X + 5, Y, 5, Material.RED_CONCRETE);
        Build.fill(world, HALF_X - 5, Y, -5, HALF_X, Y, 5, Material.BLUE_CONCRETE);
        Build.fill(world, -1, Y, -HALF_Z, 0, Y, HALF_Z, Material.WHITE_CONCRETE);
        // mirrored cover: walls, crates and pillars
        Material[] cover = {theme.trim, theme.accent, Material.OAK_PLANKS, Material.HAY_BLOCK, Material.SPRUCE_LOG};
        for (int i = 0; i < 22; i++) {
            int x = 4 + random.nextInt(HALF_X - 10);
            int z = -HALF_Z + 2 + random.nextInt(HALF_Z * 2 - 3);
            int len = 1 + random.nextInt(4);
            int h = 1 + random.nextInt(3);
            boolean alongZ = random.nextBoolean();
            Material m = cover[random.nextInt(cover.length)];
            for (int j = 0; j < len; j++) {
                int bx = alongZ ? x : x + j;
                int bz = alongZ ? z + j : z;
                if (Math.abs(bz) <= HALF_Z - 1 && bx < HALF_X - 6) {
                    Build.fill(world, bx, Y + 1, bz, bx, Y + h, bz, m);
                    Build.fill(world, -bx - 1, Y + 1, bz, -bx - 1, Y + h, bz, m);
                }
            }
        }
        // a fort in the middle
        Build.walls(world, -3, Y + 1, -3, 2, Y + 2, 2, theme.trim);
        Build.fill(world, -3, Y + 1, -1, -3, Y + 2, 0, Material.AIR);
        Build.fill(world, 2, Y + 1, -1, 2, Y + 2, 0, Material.AIR);
        // invisible walls
        Build.walls(world, -HALF_X - 1, Y + 1, -HALF_Z - 1, HALF_X + 1, Y + 12, HALF_Z + 1, Material.BARRIER);
        red.spawn = Build.lookAt(new Location(world, -HALF_X + 2.5, Y + 1, 0.5), new Location(world, 0.5, Y + 1, 0.5));
        blue.spawn = Build.lookAt(new Location(world, HALF_X - 2.5, Y + 1, 0.5), new Location(world, 0.5, Y + 1, 0.5));
    }

    @Override
    protected void giveKit(Player p) {
        Side side = side(p);
        p.getInventory().clear();
        p.getInventory().setItem(0, new ItemStack(Material.SNOWBALL, MAX_BALLS));
        p.getInventory().setHelmet(ItemBuilder.of(Material.LEATHER_HELMET).color(side.leather).unbreakable().build());
        p.getInventory().setChestplate(ItemBuilder.of(Material.LEATHER_CHESTPLATE).color(side.leather).unbreakable().build());
        p.getInventory().setLeggings(ItemBuilder.of(Material.LEATHER_LEGGINGS).color(side.leather).unbreakable().build());
        p.getInventory().setBoots(ItemBuilder.of(Material.LEATHER_BOOTS).color(side.leather).unbreakable().build());
        p.addPotionEffect(new PotionEffect(PotionEffectType.SPEED, PotionEffect.INFINITE_DURATION, 0, false, false));
        spawnedAt.put(p.getUniqueId(), System.currentTimeMillis());
    }

    @Override
    public void onProjectileHit(ProjectileHitEvent event) {
        if (!(event.getEntity() instanceof Snowball ball) || !(ball.getShooter() instanceof Player shooter)
                || !(event.getHitEntity() instanceof Player victim)) {
            return;
        }
        Side mine = side(shooter);
        Side theirs = side(victim);
        if (mine == null || theirs == null || mine == theirs || !isAlive(victim) || victim.getGameMode() != GameMode.SURVIVAL) {
            return;
        }
        if (System.currentTimeMillis() - spawnedAt.getOrDefault(victim.getUniqueId(), 0L) < SPAWN_PROTECTION_MS) {
            return;
        }
        Particle.DustOptions paint = new Particle.DustOptions(mine.leather, 2f);
        world.spawnParticle(Particle.DUST, victim.getLocation().add(0, 1, 0), 40, 0.4, 0.6, 0.4, 0, paint);
        world.playSound(victim.getLocation(), "entity.slime.squish", 1f, 1.3f);
        mine.score++;
        kills.merge(shooter.getUniqueId(), 1, Integer::sum);
        plugin.stats().addKill(shooter, type);
        plugin.stats().addDeath(victim, type);
        Msg.all(online(), mine.mm + shooter.getName() + " <gray>splatted " + theirs.mm + victim.getName()
                + " <dark_gray>(" + red.mm + red.score + " <dark_gray>- " + blue.mm + blue.score + "<dark_gray>)");
        Msg.sound(shooter, "entity.experience_orb.pickup", 1.4f);
        Msg.title(victim, "<red><bold>SPLAT!", "<gray>by " + shooter.getName(), 0, 25, 5);
        respawn(victim);
        if (mine.score >= GOAL) {
            end("Team " + mine.colored(), new ArrayList<>(mine.members));
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
        respawn(victim);
    }

    @Override
    public void onBlockPlace(BlockPlaceEvent event) {
        event.setCancelled(true);
    }

    @Override
    public void onBlockBreak(BlockBreakEvent event) {
        event.setCancelled(true);
    }

    @Override
    protected void onSecond() {
        super.onSecond();
        for (Player p : alivePlayers()) {
            if (p.getGameMode() != GameMode.SURVIVAL) {
                continue;
            }
            int have = 0;
            for (ItemStack item : p.getInventory().getContents()) {
                if (item != null && item.getType() == Material.SNOWBALL) {
                    have += item.getAmount();
                }
            }
            if (have < MAX_BALLS) {
                p.getInventory().addItem(new ItemStack(Material.SNOWBALL, Math.min(3, MAX_BALLS - have)));
            }
        }
        int left = TIME_LIMIT - elapsed;
        bossBar(red.colored() + " " + red.score + " <dark_gray>| <white>" + Msg.time(left) + " <dark_gray>| " + blue.mm + blue.score + " " + blue.colored(),
                (float) left / TIME_LIMIT, BossBar.Color.PINK);
        if (left <= 0) {
            if (red.score == blue.score) {
                end(null, List.of());
            } else {
                Side winner = red.score > blue.score ? red : blue;
                end("Team " + winner.colored(), new ArrayList<>(winner.members));
            }
        }
    }

    @Override
    protected double voidLevel() {
        return Y - 10;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 0.5, Y + 18, HALF_Z + 6.5, 180, 40);
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        lines.add(red.mm + "<bold>R</bold> <white>Red: " + red.mm + red.score + "/" + GOAL + (side(player) == red ? " <gray>YOU" : ""));
        lines.add(blue.mm + "<bold>B</bold> <white>Blue: " + blue.mm + blue.score + "/" + GOAL + (side(player) == blue ? " <gray>YOU" : ""));
        lines.add("  ");
        lines.add("<white>Your splats: <green>" + kills.getOrDefault(player.getUniqueId(), 0));
        lines.add("<white>Time: <yellow>" + Msg.time(TIME_LIMIT - elapsed));
        return lines;
    }

    @Override
    protected void cleanup() {
        super.cleanup();
        spawnedAt.clear();
    }
}
