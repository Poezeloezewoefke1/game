package net.funcraft.games.util;

import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.NamespacedKey;
import org.bukkit.block.Block;
import org.bukkit.entity.Fireball;
import org.bukkit.entity.Player;
import org.bukkit.entity.TNTPrimed;
import org.bukkit.event.block.Action;
import org.bukkit.event.entity.EntityExplodeEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.persistence.PersistentDataType;
import org.bukkit.plugin.Plugin;
import org.bukkit.util.Vector;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/** Throwable fireballs (right-click a fire charge) and TNT that lights itself when placed. */
public final class Explosives {

    private static final long FIREBALL_COOLDOWN_MS = 500;
    private static final double LAUNCH_RADIUS = 4.5;
    /** How hard a fireball's explosion throws players, stored on every fireball we launch. */
    private static final NamespacedKey LAUNCH = new NamespacedKey("funcraft", "fireball_launch");

    private final Map<UUID, Long> lastFireball = new HashMap<>();
    private final double launch;

    public Explosives() {
        this(1.6);
    }

    /** @param launch speed a fireball's explosion throws nearby players at (about 1.9 = a big jump) */
    public Explosives(double launch) {
        this.launch = launch;
    }

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
        ball.getPersistentDataContainer().set(LAUNCH, PersistentDataType.DOUBLE, launch);
        item.setAmount(item.getAmount() - 1);
        return true;
    }

    /**
     * Fireball hits: scale the damage. Fireballs we launched throw players around in
     * {@link #onExplode}; any other fireball throws the victim here. Returns true if the damage
     * came from a fireball.
     */
    public static boolean fireballHit(Plugin plugin, org.bukkit.event.entity.EntityDamageEvent event, Player victim,
                                      double damageFactor, double launch) {
        if (!(event instanceof org.bukkit.event.entity.EntityDamageByEntityEvent byEntity)
                || !(byEntity.getDamager() instanceof Fireball ball)) {
            return false;
        }
        event.setDamage(event.getDamage() * damageFactor);
        if (!ball.getPersistentDataContainer().has(LAUNCH, PersistentDataType.DOUBLE)) {
            throwAway(plugin, victim, ball.getLocation(), launch);
        }
        return true;
    }

    /**
     * Throws every player near one of our fireballs' explosions away from it - shooting at your
     * own feet launches you ("fireball jump"). This does not rely on the explosion damaging the
     * player, so it works through resistance, blocking and cancelled damage too.
     */
    public static void onExplode(Plugin plugin, EntityExplodeEvent event) {
        if (!(event.getEntity() instanceof Fireball ball)) {
            return;
        }
        Double launch = ball.getPersistentDataContainer().get(LAUNCH, PersistentDataType.DOUBLE);
        if (launch == null) {
            return;
        }
        Location center = event.getLocation();
        for (Player p : center.getNearbyPlayers(LAUNCH_RADIUS)) {
            if (p.getGameMode() == GameMode.SURVIVAL || p.getGameMode() == GameMode.ADVENTURE) {
                double distance = p.getLocation().add(0, 1, 0).distance(center);
                throwAway(plugin, p, center, launch * Math.max(0.55, 1 - distance / (LAUNCH_RADIUS * 2)));
            }
        }
    }

    private static void throwAway(Plugin plugin, Player victim, Location from, double strength) {
        Vector push = victim.getLocation().add(0, 1, 0).toVector().subtract(from.toVector());
        if (push.lengthSquared() < 0.01) {
            push = new Vector(0, 1, 0);
        }
        Vector v = push.normalize().multiply(strength);
        v.setY(Math.max(v.getY(), 0.35) + 0.35);
        if (plugin instanceof net.funcraft.games.FunCraft fc) {
            fc.antiCheat().exempt(victim, 3500);
        }
        Bukkit.getScheduler().runTask(plugin, () -> {
            victim.setVelocity(v);
            victim.setFallDistance(0);
        });
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
