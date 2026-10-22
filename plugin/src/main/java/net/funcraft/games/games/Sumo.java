package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.Msg;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;

import java.util.List;

/** Knock everyone off a small platform with your fists. Hits do knockback but no damage. */
public final class Sumo extends LastStanding {

    private static final int FLOOR_Y = 64;
    private double radius;

    public Sumo(FunCraft plugin, int id) {
        super(plugin, id, GameType.SUMO);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-16, -16, 16, 16};
    }

    @Override
    protected void buildMap() {
        int players = Math.max(2, online().size());
        radius = Math.min(11, 5 + players);
        center = new Location(world, 0.5, FLOOR_Y + 1, 0.5);
        Build.disc(world, 0, FLOOR_Y - 1, 0, radius, Material.STRIPPED_OAK_WOOD);
        Material[][] styles = {{Material.WHITE_CONCRETE, Material.RED_CONCRETE}, {Material.SAND, Material.SMOOTH_SANDSTONE},
                {Material.LIGHT_BLUE_CONCRETE, Material.BLUE_ICE}, {Material.MOSS_BLOCK, Material.OAK_PLANKS},
                {Material.QUARTZ_BLOCK, Material.GOLD_BLOCK}};
        Material[] style = styles[random.nextInt(styles.length)];
        Build.disc(world, 0, FLOOR_Y, 0, radius, style[0]);
        Build.ring(world, 0, FLOOR_Y, 0, radius - 1, radius, style[1]);
        Build.ring(world, 0, FLOOR_Y, 0, 1, 2, Material.BLACK_CONCRETE);
        Build.island(world, 0, FLOOR_Y - 2, 0, radius - 1, Material.STONE, random);
        spawnRing(FLOOR_Y + 1, radius - 2.5, Math.max(2, online().isEmpty() ? 8 : online().size()));
    }

    @Override
    protected void equip(Player player) {
        player.addPotionEffect(new PotionEffect(PotionEffectType.RESISTANCE, 20 * 3, 4, false, false));
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (event.getCause() == EntityDamageEvent.DamageCause.ENTITY_ATTACK && attacker != null) {
            event.setDamage(0);
            victim.setHealth(20);
        } else if (event.getCause() != EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(true);
        }
    }

    @Override
    protected void onStart(List<Player> list) {
        super.onStart(list);
        Msg.all(list, "<gray>No weapons, no damage - just push them off!");
    }

    @Override
    protected int timeLimit() {
        return 240;
    }

    @Override
    protected String objective() {
        return "Push everyone off the platform!";
    }

    @Override
    protected double voidLevel() {
        return FLOOR_Y - 6;
    }
}
