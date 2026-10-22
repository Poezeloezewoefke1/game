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
