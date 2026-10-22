package net.funcraft.games.util;

import org.bukkit.Bukkit;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.entity.Fireball;
import org.bukkit.entity.Player;
import org.bukkit.entity.TNTPrimed;
import org.bukkit.event.block.Action;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.plugin.Plugin;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/** Throwable fireballs (right-click a fire charge) and TNT that lights itself when placed. */
public final class Explosives {

    private static final long FIREBALL_COOLDOWN_MS = 500;

    private final Map<UUID, Long> lastFireball = new HashMap<>();

    /** Launches a fireball if the player right-clicked with a fire charge. Returns true if handled. */
    public boolean handleFireball(PlayerInteractEvent event) {
        ItemStack item = event.getItem();
        if (item == null || item.getType() != Material.FIRE_CHARGE) {
            return false;
        }
        if (event.getAction() != Action.RIGHT_CLICK_AIR && event.getAction() != Action.RIGHT_CLICK_BLOCK) {
            return false;
        }
        event.setCancelled(true);
        Player p = event.getPlayer();
        long now = System.currentTimeMillis();
        if (now - lastFireball.getOrDefault(p.getUniqueId(), 0L) < FIREBALL_COOLDOWN_MS) {
            return true;
        }
        lastFireball.put(p.getUniqueId(), now);
        Fireball ball = p.launchProjectile(Fireball.class);
        ball.setYield(2.5f);
        ball.setIsIncendiary(false);
        ball.setVelocity(p.getLocation().getDirection().multiply(1.4));
        item.setAmount(item.getAmount() - 1);
        return true;
    }

    /**
     * Fireball hits: scale the damage and throw the player away from the blast. Shooting at your own
     * feet launches you ("fireball jump"). Returns true if the damage came from a fireball.
     */
    public static boolean fireballHit(Plugin plugin, org.bukkit.event.entity.EntityDamageEvent event, Player victim,
                                      double damageFactor, double launch) {
        if (!(event instanceof org.bukkit.event.entity.EntityDamageByEntityEvent byEntity)
                || !(byEntity.getDamager() instanceof Fireball ball)) {
            return false;
        }
        event.setDamage(event.getDamage() * damageFactor);
        org.bukkit.util.Vector push = victim.getLocation().add(0, 1, 0).toVector().subtract(ball.getLocation().toVector());
        if (push.lengthSquared() < 0.01) {
            push = new org.bukkit.util.Vector(0, 1, 0);
        }
        org.bukkit.util.Vector v = push.normalize().multiply(launch);
        v.setY(Math.max(v.getY(), 0.35) + 0.35);
        if (plugin instanceof net.funcraft.games.FunCraft fc) {
            fc.antiCheat().exempt(victim, 3500);
        }
        Bukkit.getScheduler().runTask(plugin, () -> {
            victim.setVelocity(v);
            victim.setFallDistance(0);
        });
        return true;
    }

    /** Replaces a freshly placed TNT block with lit TNT on the next tick. */
    public static void primeNextTick(Plugin plugin, Block block, Player placer) {
        Bukkit.getScheduler().runTask(plugin, () -> {
            if (block.getType() == Material.TNT) {
                block.setType(Material.AIR);
                block.getWorld().spawn(block.getLocation().add(0.5, 0, 0.5), TNTPrimed.class, tnt -> {
                    tnt.setFuseTicks(50);
                    tnt.setSource(placer);
                });
            }
        });
    }
}
