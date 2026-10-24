package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import org.bukkit.Bukkit;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.Particle;
import org.bukkit.block.Block;
import org.bukkit.enchantments.Enchantment;
import org.bukkit.entity.AbstractArrow;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.entity.ProjectileHitEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;

import java.util.List;

/**
 * Bow Spleef: two layers of TNT floor over the void and an Infinity bow. Every arrow blows a hole
 * where it lands; arrows that hit players only knock them back. Last one standing wins.
 */
public final class BowSpleef extends LastStanding {

    private static final int TOP = 64;
    private static final int LOWER = 54;
    private static final double RADIUS = 15;

    public BowSpleef(FunCraft plugin, int id) {
        super(plugin, id, GameType.BOW_SPLEEF);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-20, -20, 20, 20};
    }

    @Override
    protected void buildMap() {
        mapName = "TNT Field";
        center = new Location(world, 0.5, TOP + 1, 0.5);
        Build.disc(world, 0, TOP, 0, RADIUS, Material.TNT);
        Build.disc(world, 0, LOWER, 0, RADIUS - 2, Material.TNT);
        Build.ring(world, 0, TOP, 0, RADIUS - 0.8, RADIUS, Material.RED_CONCRETE);
        spawnRing(TOP + 1, RADIUS - 4, Math.max(2, online().isEmpty() ? 8 : online().size()));
    }

    @Override
    protected void equip(Player player) {
        player.getInventory().setItem(0, ItemBuilder.of(Material.BOW).name("<red>Spleef Bow")
                .enchant(Enchantment.INFINITY, 1).enchant(Enchantment.PUNCH, 1).unbreakable().build());
        player.getInventory().setItem(9, new ItemStack(Material.ARROW));
        player.addPotionEffect(new PotionEffect(PotionEffectType.RESISTANCE, 20 * 3, 4, false, false));
        player.addPotionEffect(new PotionEffect(PotionEffectType.SPEED, PotionEffect.INFINITE_DURATION, 0, false, false));
    }

    @Override
    public void onProjectileHit(ProjectileHitEvent event) {
        if (!(event.getEntity() instanceof AbstractArrow arrow)) {
            return;
        }
        Block hit = event.getHitBlock();
        if (hit != null && (hit.getType() == Material.TNT || hit.getType() == Material.RED_CONCRETE)) {
            Location at = hit.getLocation().add(0.5, 0.5, 0.5);
            world.spawnParticle(Particle.EXPLOSION, at, 1);
            world.playSound(at, "entity.generic.explode", 0.6f, 1.4f);
            for (int dx = -1; dx <= 1; dx++) {
                for (int dz = -1; dz <= 1; dz++) {
                    if (Math.abs(dx) + Math.abs(dz) <= 1 || random.nextInt(3) == 0) {
                        Block b = hit.getRelative(dx, 0, dz);
                        if (b.getType() == Material.TNT || b.getType() == Material.RED_CONCRETE) {
                            b.setType(Material.AIR, false);
                        }
                    }
                }
            }
        }
        Bukkit.getScheduler().runTask(plugin, arrow::remove);
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (event.getCause() == EntityDamageEvent.DamageCause.PROJECTILE && attacker != null && !attacker.equals(victim)) {
            event.setDamage(0.01); // knockback only
            Bukkit.getScheduler().runTask(plugin, () -> {
                if (victim.isOnline() && !victim.isDead()) {
                    victim.setHealth(20);
                }
            });
        } else if (event.getCause() != EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(true);
        }
    }

    @Override
    protected void onStart(List<Player> list) {
        super.onStart(list);
        Msg.all(list, "<gray>Every arrow blows a hole in the floor. Shoot the floor under the others!");
    }

    @Override
    protected int timeLimit() {
        return 300;
    }

    @Override
    protected String objective() {
        return "Shoot the floor out from under everyone!";
    }

    @Override
    protected double voidLevel() {
        return LOWER - 8;
    }
}
