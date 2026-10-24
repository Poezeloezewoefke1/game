package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Arenas;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Theme;
import org.bukkit.Color;
import org.bukkit.FluidCollisionMode;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.Particle;
import org.bukkit.entity.Player;
import org.bukkit.event.block.Action;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;
import org.bukkit.util.RayTraceResult;
import org.bukkit.util.Vector;

import java.util.List;
import java.util.UUID;

/**
 * Quake: everyone has a railgun. Right click fires an instant beam that kills whatever it hits.
 * You're fast and jump high; first to 20 kills wins.
 */
public final class Quake extends RespawnGame {

    private static final int KILLS_TO_WIN = 20;
    private static final double RANGE = 80;
    private static final int COOLDOWN_TICKS = 24;

    public Quake(FunCraft plugin, int id) {
        super(plugin, id, GameType.QUAKE);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-34, -34, 34, 34};
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + " Railyard";
        spawns.addAll(Arenas.village(world, theme, random, Y, 26));
    }

    @Override
    protected void loadout(Player p) {
        p.getInventory().setItem(0, ItemBuilder.of(Material.IRON_HOE).name("<aqua><bold>Railgun</bold> <gray>(right click)").glow().build());
        p.addPotionEffect(new PotionEffect(PotionEffectType.SPEED, PotionEffect.INFINITE_DURATION, 1, false, false));
        p.addPotionEffect(new PotionEffect(PotionEffectType.JUMP_BOOST, PotionEffect.INFINITE_DURATION, 1, false, false));
    }

    @Override
    public void onInteract(PlayerInteractEvent event) {
        Player p = event.getPlayer();
        if (event.getAction() != Action.RIGHT_CLICK_AIR && event.getAction() != Action.RIGHT_CLICK_BLOCK) {
            return;
        }
        if (event.getItem() == null || event.getItem().getType() != Material.IRON_HOE) {
            return;
        }
        event.setCancelled(true); // no tilling
        fire(p, p.getEyeLocation().getDirection());
    }

    @Override
    public void botTick(Player bot, net.funcraft.games.bots.BotBrain brain) {
        Player enemy = brain.nearestEnemy(this, 70);
        if (enemy == null) {
            brain.wander(bot.getLocation(), 8, true);
            return;
        }
        brain.fight(enemy);
        Location aim = enemy.getLocation().add(0, 1.1, 0);
        if (brain.canSee(enemy) && brain.readyToShoot() && brain.random().nextInt(4) == 0) {
            Vector dir = aim.toVector().subtract(bot.getEyeLocation().toVector()).normalize();
            dir.add(new Vector((brain.random().nextDouble() - 0.5) * 0.08, (brain.random().nextDouble() - 0.5) * 0.06,
                    (brain.random().nextDouble() - 0.5) * 0.08));
            fire(bot, dir.normalize());
            brain.shotFired(COOLDOWN_TICKS + 4);
        }
    }

    private void fire(Player p, Vector direction) {
        if (p.getGameMode() != GameMode.SURVIVAL || p.hasCooldown(Material.IRON_HOE)) {
            return;
        }
        p.setCooldown(Material.IRON_HOE, COOLDOWN_TICKS);
        Location eye = p.getEyeLocation();
        Vector dir = direction;
        RayTraceResult hit = world.rayTrace(eye, dir, RANGE, FluidCollisionMode.NEVER, true, 0.25,
                e -> e instanceof Player t && !t.equals(p) && isAlive(t) && t.getGameMode() == GameMode.SURVIVAL);
        double length = hit == null ? RANGE : hit.getHitPosition().distance(eye.toVector());
        // the beam
        Particle.DustOptions dust = new Particle.DustOptions(Color.fromRGB(80, 220, 255), 1.0f);
        for (double d = 1; d < length; d += 0.5) {
            world.spawnParticle(Particle.DUST, eye.clone().add(dir.clone().multiply(d)), 1, 0, 0, 0, 0, dust);
        }
        world.playSound(eye, "entity.firework_rocket.blast", 1f, 1.8f);
        if (hit != null && hit.getHitEntity() instanceof Player victim) {
            world.spawnParticle(Particle.FIREWORK, victim.getLocation().add(0, 1, 0), 30, 0.3, 0.5, 0.3, 0.1);
            boolean headshot = hit.getHitPosition().getY() > victim.getLocation().getY() + 1.45;
            if (headshot) {
                Msg.all(online(), "<gold><bold>HEADSHOT!</bold> <white>" + p.getName() + " <gray>-> <white>" + victim.getName());
            }
            kill(victim, p);
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (event.getCause() != EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(true); // only the railgun kills
        }
    }

    @Override
    protected int score(UUID player) {
        return kills.getOrDefault(player, 0);
    }

    @Override
    protected int goal() {
        return KILLS_TO_WIN;
    }

    @Override
    protected String scoreName() {
        return "kills";
    }

    @Override
    protected String objective() {
        return "Railguns kill in one shot - first to " + KILLS_TO_WIN + "!";
    }

    @Override
    protected int respawnSeconds() {
        return 2;
    }

    @Override
    protected List<String> extraSidebar(Player player) {
        return List.of("<white>Your kills: <green>" + score(player.getUniqueId()));
    }
}
