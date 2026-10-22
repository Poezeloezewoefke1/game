package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.enchantments.Enchantment;
import org.bukkit.entity.Player;
import org.bukkit.entity.Snowball;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.entity.ProjectileHitEvent;
import org.bukkit.inventory.ItemStack;

/** Two snow floors over the void. Dig the snow out from under the others. */
public final class Spleef extends LastStanding {

    private static final int TOP_Y = 70;
    private static final int LOWER_Y = 58;
    private static final int RADIUS = 16;

    public Spleef(FunCraft plugin, int id) {
        super(plugin, id, GameType.SPLEEF);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-24, -24, 24, 24};
    }

    @Override
    protected void buildMap() {
        center = new Location(world, 0.5, TOP_Y + 1, 0.5);
        Build.disc(world, 0, TOP_Y, 0, RADIUS, Material.SNOW_BLOCK);
        Build.disc(world, 0, LOWER_Y, 0, RADIUS - 2, Material.SNOW_BLOCK);
        Build.ring(world, 0, TOP_Y, 0, RADIUS, RADIUS + 1, Material.BLUE_ICE);
        Build.ring(world, 0, LOWER_Y, 0, RADIUS - 2, RADIUS - 1, Material.BLUE_ICE);
        for (int i = 0; i < 8; i++) {
            double a = Math.toRadians(i * 45);
            int x = (int) Math.round(Math.cos(a) * (RADIUS + 3));
            int z = (int) Math.round(Math.sin(a) * (RADIUS + 3));
            Build.fill(world, x, LOWER_Y - 4, z, x, TOP_Y + 4, z, Material.PACKED_ICE);
            Build.set(world, x, TOP_Y + 5, z, Material.SEA_LANTERN);
        }
        spawnRing(TOP_Y + 1, RADIUS - 4, Math.max(2, online().isEmpty() ? 8 : online().size()));
    }

    @Override
    protected void equip(Player player) {
        player.getInventory().setItem(0, ItemBuilder.of(Material.DIAMOND_SHOVEL).name("<aqua>Spleef Shovel")
                .enchant(Enchantment.EFFICIENCY, 5).unbreakable().build());
    }

    @Override
    public void onBlockBreak(BlockBreakEvent event) {
        if (event.getBlock().getType() != Material.SNOW_BLOCK || elapsed < 3) {
            event.setCancelled(true);
            return;
        }
        event.setDropItems(false);
        Player p = event.getPlayer();
        if (!p.getInventory().containsAtLeast(new ItemStack(Material.SNOWBALL), 16)) {
            p.getInventory().addItem(new ItemStack(Material.SNOWBALL));
        }
    }

    @Override
    public void onProjectileHit(ProjectileHitEvent event) {
        if (event.getEntity() instanceof Snowball) {
            Block hit = event.getHitBlock();
            if (hit != null && hit.getType() == Material.SNOW_BLOCK) {
                hit.setType(Material.AIR);
            }
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (event.getCause() == EntityDamageEvent.DamageCause.PROJECTILE) {
            event.setDamage(0);
        } else if (event.getCause() != EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(true);
        }
    }

    @Override
    protected int timeLimit() {
        return 300;
    }

    @Override
    protected String objective() {
        return "Break the snow under the others!";
    }

    @Override
    protected double voidLevel() {
        return LOWER_Y - 8;
    }
}
