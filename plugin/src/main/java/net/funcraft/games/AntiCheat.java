package net.funcraft.games;

import net.funcraft.games.util.Msg;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.entity.LivingEntity;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockExplodeEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityDamageByEntityEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.entity.EntityExplodeEvent;
import org.bukkit.event.entity.ProjectileHitEvent;
import org.bukkit.event.player.PlayerAnimationEvent;
import org.bukkit.event.player.PlayerAnimationType;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.event.player.PlayerMoveEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.event.player.PlayerRespawnEvent;
import org.bukkit.event.player.PlayerTeleportEvent;
import org.bukkit.event.player.PlayerVelocityEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;
import org.bukkit.util.BoundingBox;
import org.bukkit.util.Vector;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Lightweight server-side anti-cheat tuned for these minigames: Fly, Speed, Reach, KillAura
 * (angle), AutoClicker, FastPlace/Scaffold and FastBreak/Nuker. Every mechanic in the plugin that
 * throws players around (fireballs, launch pads, double jumps, explosions, wind charges, maces,
 * spears, elytras, knockback) exempts them for a moment, so legit play doesn't flag.
 * Movement cheats get set back; ops get alerts; very high violation levels get kicked.
 */
public final class AntiCheat implements Listener {

    private static final double MAX_REACH = 3.6;
    private static final double HARD_REACH = 5.0;
    private static final int KILLAURA_HITS = 3;
    private static final long KILLAURA_WINDOW_MS = 5000;
    private static final int MAX_CPS = 22;
    private static final int MAX_PLACE_PER_SEC = 14;
    private static final int MAX_BREAK_PER_SEC = 24;

    private static final class Data {
        final Map<String, Double> vl = new HashMap<>();
        long exemptUntil;
        Location lastGood;
        int airMoves;
        double movedThisSecond;
        long secondStart = System.currentTimeMillis();
        int clicks;
        long clickSecond;
        int places;
        long placeSecond;
        int breaks;
        long breakSecond;
        long lastAlert;
        final java.util.ArrayDeque<Long> offTargetHits = new java.util.ArrayDeque<>();
        // Timer
        int moveEvents;
        long moveWindow = System.currentTimeMillis();
        // NoFall / Jesus
        int groundSpoofs;
        int waterWalks;
        // Velocity (anti-knockback)
        int kbFails;
        long lastKbFail;
    }

    private final FunCraft plugin;
    private final Map<UUID, Data> data = new HashMap<>();
    private final Set<UUID> alertsOff = new HashSet<>();

    public AntiCheat(FunCraft plugin) {
        this.plugin = plugin;
        // violation levels slowly cool down
        Bukkit.getScheduler().runTaskTimer(plugin, () -> {
            for (Data d : data.values()) {
                d.vl.replaceAll((k, v) -> Math.max(0, v * 0.85 - 0.5));
            }
        }, 100L, 100L);
    }

    private boolean enabled() {
        return plugin.getConfig().getBoolean("anticheat.enabled", true);
    }

    private Data of(Player p) {
        return data.computeIfAbsent(p.getUniqueId(), k -> new Data());
    }

    /** Called by game code whenever it launches/knocks a player, so the next moves aren't checked. */
    public void exempt(Player p, long millis) {
        Data d = of(p);
        d.exemptUntil = Math.max(d.exemptUntil, System.currentTimeMillis() + millis);
        d.airMoves = 0;
    }

    public boolean toggleAlerts(Player p) {
        if (!alertsOff.remove(p.getUniqueId())) {
            alertsOff.add(p.getUniqueId());
            return false;
        }
        return true;
    }

    public String summary(Player target) {
        Data d = data.get(target.getUniqueId());
        if (d == null || d.vl.isEmpty()) {
            return "<green>no violations";
        }
        StringBuilder sb = new StringBuilder();
        d.vl.forEach((k, v) -> {
            if (v >= 1) {
                sb.append("<yellow>").append(k).append(" <white>").append(String.format("%.0f", v)).append("  ");
            }
        });
        return sb.length() == 0 ? "<green>no violations" : sb.toString();
    }

    // ------------------------------------------------------------- flagging

    private void flag(Player p, String check, double amount, String detail) {
        Data d = of(p);
        double vl = d.vl.merge(check, amount, Double::sum);
        long now = System.currentTimeMillis();
        plugin.getLogger().info("[AC] " + p.getName() + " failed " + check + " (" + detail + ") VL " + String.format("%.1f", vl));
        if (now - d.lastAlert > 1500) {
            d.lastAlert = now;
            String text = "<dark_red>[AC]</dark_red> <yellow>" + p.getName() + " <gray>failed <red>" + check
                    + " <gray>(" + detail + ") <dark_gray>VL " + String.format("%.0f", vl);
            for (Player staff : Bukkit.getOnlinePlayers()) {
                if (staff.hasPermission("funcraft.admin") && !alertsOff.contains(staff.getUniqueId())) {
                    Msg.raw(staff, text);
                }
            }
        }
        int kickAt = plugin.getConfig().getInt("anticheat.kick-vl", 40);
        if (plugin.getConfig().getBoolean("anticheat.kick", true) && vl >= kickAt) {
            d.vl.clear();
            Bukkit.getScheduler().runTask(plugin, () -> {
                if (p.isOnline()) {
                    p.kick(Msg.mm("<red>Kicked by the anti-cheat (" + check + ").\n<gray>If this was a mistake, tell an admin."));
                    Bukkit.getOnlinePlayers().forEach(o -> {
                        if (o.hasPermission("funcraft.admin")) {
                            Msg.raw(o, "<dark_red>[AC]</dark_red> <yellow>" + p.getName() + " <red>was kicked for " + check + ".");
                        }
                    });
                }
            });
        }
    }

    private static boolean ignored(Player p) {
        GameMode gm = p.getGameMode();
        return gm == GameMode.CREATIVE || gm == GameMode.SPECTATOR || p.isFlying() || p.isInsideVehicle()
                || p.isGliding() || p.isRiptiding() || p.isDead();
    }

    // ------------------------------------------------------------- exemptions

    @EventHandler(priority = EventPriority.MONITOR)
    public void onTeleport(PlayerTeleportEvent e) {
        exempt(e.getPlayer(), 1500);
        of(e.getPlayer()).lastGood = e.getTo();
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onRespawn(PlayerRespawnEvent e) {
        exempt(e.getPlayer(), 2000);
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onVelocity(PlayerVelocityEvent e) {
        Player p = e.getPlayer();
        exempt(p, 2500);
        if (!enabled() || plugin.bots().isBot(p) || ignored(p)) {
            return;
        }
        // --- Velocity: a player who doesn't move at all after a real knockback is ignoring it
        Vector v = e.getVelocity();
        double push = Math.hypot(v.getX(), v.getZ());
        if (push < 0.3 || e.isCancelled()) {
            return;
        }
        Location start = p.getLocation();
        Vector dir = new Vector(v.getX(), 0, v.getZ()).normalize();
        Bukkit.getScheduler().runTaskLater(plugin, () -> {
            if (!p.isOnline() || p.getWorld() != start.getWorld() || ignored(p) || special(p, p.getLocation())) {
                return;
            }
            // something solid right behind them stops the knockback legitimately
            Location behind = start.clone().add(dir.clone().multiply(0.8));
            if (!behind.getBlock().isPassable() || !behind.clone().add(0, 1, 0).getBlock().isPassable()) {
                return;
            }
            Location now = p.getLocation();
            double moved = Math.hypot(now.getX() - start.getX(), now.getZ() - start.getZ());
            if (moved < push * 0.5) {
                Data d = of(p);
                long t = System.currentTimeMillis();
                d.kbFails = t - d.lastKbFail < 30_000 ? d.kbFails + 1 : 1;
                d.lastKbFail = t;
                if (d.kbFails >= 3) {
                    flag(p, "Velocity", 2, String.format("took %.2f of %.2f knockback", moved, push * 4));
                    d.kbFails = 0;
                }
            }
        }, 6L);
    }

    private static boolean solidAround(Location l) {
        for (int dx = -1; dx <= 1; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                Block b = l.clone().add(dx * 0.4, -0.1, dz * 0.4).getBlock();
                if (b.getType().isSolid() || b.getType() == Material.LILY_PAD) {
                    return true;
                }
            }
        }
        return false;
    }

    private static boolean frostWalker(Player p) {
        ItemStack boots = p.getInventory().getBoots();
        return boots != null && boots.containsEnchantment(org.bukkit.enchantments.Enchantment.FROST_WALKER);
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onHurt(EntityDamageEvent e) {
        if (e.getEntity() instanceof Player p) {
            boolean blast = e.getCause() == EntityDamageEvent.DamageCause.ENTITY_EXPLOSION
                    || e.getCause() == EntityDamageEvent.DamageCause.BLOCK_EXPLOSION;
            exempt(p, blast ? 3500 : 1200);
        }
    }

    private void exemptNear(Location l, double radius, long ms) {
        for (Player p : l.getWorld().getPlayers()) {
            if (p.getLocation().distanceSquared(l) < radius * radius) {
                exempt(p, ms);
            }
        }
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onExplode(EntityExplodeEvent e) {
        exemptNear(e.getLocation(), 10, 3500);
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onBlockExplode(BlockExplodeEvent e) {
        exemptNear(e.getBlock().getLocation(), 10, 3500);
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onProjectile(ProjectileHitEvent e) {
        String type = e.getEntity().getType().name();
        if (type.contains("WIND_CHARGE")) {
            exemptNear(e.getEntity().getLocation(), 7, 3000); // wind charges launch you client-side
        }
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onUse(PlayerInteractEvent e) {
        ItemStack item = e.getItem();
        if (item != null) {
            String n = item.getType().name();
            if (n.contains("WIND_CHARGE") || n.equals("FIREWORK_ROCKET") || n.equals("TRIDENT") || n.equals("ENDER_PEARL")
                    || n.equals("FIRE_CHARGE") || n.equals("CHORUS_FRUIT")) {
                exempt(e.getPlayer(), 2500);
            }
        }
    }

    // ---------------------------------------------------------------- movement

    @EventHandler(priority = EventPriority.HIGH, ignoreCancelled = true)
    public void onMove(PlayerMoveEvent e) {
        if (!enabled()) {
            return;
        }
        Player p = e.getPlayer();
        if (plugin.bots().isBot(p)) {
            return; // bots move and click server-side
        }
        Location from = e.getFrom();
        Location to = e.getTo();
        Data d = of(p);
        long now = System.currentTimeMillis();
        if (d.lastGood == null || !d.lastGood.getWorld().equals(to.getWorld())) {
            d.lastGood = from;
        }
        boolean grounded = supported(to) || supported(from);
        boolean exempt = ignored(p) || now < d.exemptUntil;
        // --- Timer: more movement updates than a normal client sends (20 a second)
        d.moveEvents++;
        if (now - d.moveWindow >= 2000) {
            if (!exempt && d.moveEvents > 52) {
                flag(p, "Timer", 1 + (d.moveEvents - 52) / 10.0, d.moveEvents / 2 + " moves/s");
                e.setTo(d.lastGood);
            }
            d.moveEvents = 0;
            d.moveWindow = now;
        }
        // --- Jesus: walking on top of water (checked here because water is otherwise exempt)
        Block feetBlock = to.getBlock();
        Block belowBlock = to.clone().subtract(0, 0.1, 0).getBlock();
        if (!exempt && belowBlock.getType() == Material.WATER && !feetBlock.isLiquid() && feetBlock.isPassable()
                && !p.isSwimming() && Math.abs(to.getY() - from.getY()) < 0.05 && !solidAround(to) && !frostWalker(p)) {
            if (++d.waterWalks > 20) {
                flag(p, "Jesus", 1.5, "walking on water");
                e.setTo(d.lastGood);
                d.waterWalks = 0;
                return;
            }
        } else {
            d.waterWalks = 0;
        }
        if (exempt || special(p, to)) {
            d.airMoves = 0;
            if (grounded) {
                d.lastGood = to;
            }
            d.movedThisSecond = 0;
            d.secondStart = now;
            return;
        }
        double dy = to.getY() - from.getY();
        // --- Step: going up a full block or more in one move without jumping
        if (supported(from) && supported(to) && dy >= 1.0 && amplifier(p, PotionEffectType.JUMP_BOOST) == 0) {
            flag(p, "Step", 2, String.format("up %.2f", dy));
            e.setTo(d.lastGood);
            return;
        }
        // --- NoFall: the client says it's on the ground while it's falling through the air
        if (!grounded && dy < -0.08 && p.isOnGround()) {
            if (++d.groundSpoofs > 4) {
                flag(p, "NoFall", 1.5, "fake ground while falling");
                d.groundSpoofs = 0;
            }
        } else if (grounded) {
            d.groundSpoofs = 0;
        }
        // --- Fly: staying up or climbing with nothing underneath
        if (!grounded) {
            d.airMoves++;
            double maxUp = 0.43 + 0.1 * amplifier(p, PotionEffectType.JUMP_BOOST);
            if (dy > maxUp && d.airMoves > 1) {
                flag(p, "Fly", 2, String.format("up %.2f", dy));
                e.setTo(d.lastGood);
                return;
            }
            if (d.airMoves > 14 && dy > -0.04 && !p.hasPotionEffect(PotionEffectType.LEVITATION)
                    && !p.hasPotionEffect(PotionEffectType.SLOW_FALLING)) {
                flag(p, "Fly", 1.5, "hovering " + d.airMoves + " moves");
                e.setTo(d.lastGood);
                d.airMoves = 0;
                return;
            }
        } else {
            d.airMoves = 0;
            d.lastGood = to;
        }
        // --- Speed: horizontal distance per second
        double dx = to.getX() - from.getX();
        double dz = to.getZ() - from.getZ();
        d.movedThisSecond += Math.sqrt(dx * dx + dz * dz);
        if (now - d.secondStart >= 1000) {
            double seconds = (now - d.secondStart) / 1000.0;
            double speed = d.movedThisSecond / seconds;
            double limit = 8.6 * (1 + 0.2 * amplifier(p, PotionEffectType.SPEED)) * (onIce(to) ? 1.8 : 1.0) * 1.2;
            if (seconds < 2 && speed > limit) {
                flag(p, "Speed", Math.min(5, (speed - limit) / 2 + 1), String.format("%.1f b/s > %.1f", speed, limit));
                e.setTo(d.lastGood);
            }
            d.movedThisSecond = 0;
            d.secondStart = now;
        }
    }

    private static int amplifier(Player p, PotionEffectType type) {
        PotionEffect effect = p.getPotionEffect(type);
        return effect == null ? 0 : effect.getAmplifier() + 1;
    }

    /** Standing on (or right above) something solid, climbable, liquid or snow layers. */
    private static boolean supported(Location l) {
        BoundingBox feet = new BoundingBox(l.getX() - 0.35, l.getY() - 0.6, l.getZ() - 0.35, l.getX() + 0.35, l.getY() + 0.1, l.getZ() + 0.35);
        for (int x = (int) Math.floor(feet.getMinX()); x <= (int) Math.floor(feet.getMaxX()); x++) {
            for (int y = (int) Math.floor(feet.getMinY()); y <= (int) Math.floor(feet.getMaxY()); y++) {
                for (int z = (int) Math.floor(feet.getMinZ()); z <= (int) Math.floor(feet.getMaxZ()); z++) {
                    Block b = l.getWorld().getBlockAt(x, y, z);
                    Material m = b.getType();
                    if (!m.isAir() && (m.isSolid() || b.isLiquid() || m.name().contains("LADDER") || m.name().contains("VINE")
                            || m == Material.SCAFFOLDING || m == Material.COBWEB || m == Material.SNOW || m.name().contains("CARPET"))) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /** Places where vanilla movement is weird: liquids, cobwebs, bouncy blocks, climbing. */
    private boolean special(Player p, Location l) {
        Block feet = l.getBlock();
        Block below = l.clone().subtract(0, 1, 0).getBlock();
        Material f = feet.getType();
        Material b = below.getType();
        if (feet.isLiquid() || below.isLiquid() || f == Material.COBWEB || f == Material.BUBBLE_COLUMN || f.name().contains("LADDER")
                || f.name().contains("VINE") || f == Material.SCAFFOLDING || f == Material.POWDER_SNOW) {
            return true;
        }
        if (b == Material.SLIME_BLOCK || b == Material.HONEY_BLOCK || b.name().endsWith("_BED")) {
            exempt(p, 2000); // bounces
            return true;
        }
        return false;
    }

    private static boolean onIce(Location l) {
        String n = l.clone().subtract(0, 0.6, 0).getBlock().getType().name();
        return n.contains("ICE");
    }

    // ------------------------------------------------------------------ combat

    @EventHandler(priority = EventPriority.LOWEST, ignoreCancelled = true)
    public void onAttack(EntityDamageByEntityEvent e) {
        if (!enabled() || !(e.getDamager() instanceof Player p) || plugin.bots().isBot(p) || e.getCause() != EntityDamageEvent.DamageCause.ENTITY_ATTACK
                || p.getGameMode() == GameMode.CREATIVE || !(e.getEntity() instanceof LivingEntity target)) {
            return;
        }
        String held = p.getInventory().getItemInMainHand().getType().name();
        if (held.equals("MACE")) {
            exempt(p, 2500); // wind burst / smash launches
        }
        if (held.contains("SPEAR")) {
            exempt(p, 2000); // lunge
            return; // spears have longer reach
        }
        Vector eye = p.getEyeLocation().toVector();
        BoundingBox box = target.getBoundingBox().expand(0.1);
        double reach = distanceToBox(eye, box);
        double allowed = MAX_REACH + Math.min(1.0, p.getPing() / 250.0);
        if (reach > HARD_REACH) {
            e.setCancelled(true);
            flag(p, "Reach", 3, String.format("%.2f blocks", reach));
            return;
        }
        if (reach > allowed) {
            flag(p, "Reach", 1, String.format("%.2f blocks", reach));
        }
        // aim: hitting something far outside your view
        Vector look = p.getEyeLocation().getDirection();
        Vector toTarget = box.getCenter().subtract(eye);
        if (toTarget.lengthSquared() > 1.5) {
            double angle = Math.toDegrees(look.angle(toTarget));
            // the server only knows last tick's rotation, so one fast flick can look off target:
            // only flag players who keep hitting things well behind them
            if (angle > 100) {
                Data d = of(p);
                long now = System.currentTimeMillis();
                d.offTargetHits.addLast(now);
                while (now - d.offTargetHits.peekFirst() > KILLAURA_WINDOW_MS) {
                    d.offTargetHits.removeFirst();
                }
                if (d.offTargetHits.size() >= KILLAURA_HITS) {
                    flag(p, "KillAura", 2, String.format("%d hits %.0f° off target", d.offTargetHits.size(), angle));
                }
            }
        }
    }

    private static double distanceToBox(Vector point, BoundingBox box) {
        double dx = Math.max(Math.max(box.getMinX() - point.getX(), 0), point.getX() - box.getMaxX());
        double dy = Math.max(Math.max(box.getMinY() - point.getY(), 0), point.getY() - box.getMaxY());
        double dz = Math.max(Math.max(box.getMinZ() - point.getZ(), 0), point.getZ() - box.getMaxZ());
        return Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onSwing(PlayerAnimationEvent e) {
        if (!enabled() || e.getAnimationType() != PlayerAnimationType.ARM_SWING) {
            return;
        }
        Player p = e.getPlayer();
        if (plugin.bots().isBot(p)) {
            return; // bots move and click server-side
        }
        if (p.getInventory().getItemInMainHand().getType().name().contains("SPEAR")) {
            exempt(p, 2000); // a jab lunges you forward even when it misses (lunge swaps)
        }
        if (p.getTargetBlockExact(5) != null) {
            return; // holding left click on a block (mining) swings every tick - not clicking
        }
        Data d = of(p);
        long second = System.currentTimeMillis() / 1000;
        if (second != d.clickSecond) {
            if (d.clicks > MAX_CPS && p.getGameMode() != GameMode.CREATIVE) {
                flag(p, "AutoClicker", 1 + (d.clicks - MAX_CPS) / 4.0, d.clicks + " CPS");
            }
            d.clickSecond = second;
            d.clicks = 0;
        }
        d.clicks++;
    }

    // ------------------------------------------------------------------ blocks

    @EventHandler(priority = EventPriority.LOWEST, ignoreCancelled = true)
    public void onPlace(BlockPlaceEvent e) {
        Player p = e.getPlayer();
        if (plugin.bots().isBot(p)) {
            return; // bots move and click server-side
        }
        if (!enabled() || p.getGameMode() == GameMode.CREATIVE) {
            return;
        }
        Data d = of(p);
        long second = System.currentTimeMillis() / 1000;
        if (second != d.placeSecond) {
            d.placeSecond = second;
            d.places = 0;
        }
        if (++d.places > MAX_PLACE_PER_SEC) {
            e.setCancelled(true);
            flag(p, "FastPlace", 1, d.places + " blocks/s");
        }
    }

    @EventHandler(priority = EventPriority.LOWEST, ignoreCancelled = true)
    public void onBreak(BlockBreakEvent e) {
        Player p = e.getPlayer();
        if (plugin.bots().isBot(p)) {
            return; // bots move and click server-side
        }
        if (!enabled() || p.getGameMode() == GameMode.CREATIVE) {
            return;
        }
        Data d = of(p);
        long second = System.currentTimeMillis() / 1000;
        if (second != d.breakSecond) {
            d.breakSecond = second;
            d.breaks = 0;
        }
        if (++d.breaks > MAX_BREAK_PER_SEC) {
            e.setCancelled(true);
            flag(p, "FastBreak", 1, d.breaks + " blocks/s");
        }
        double dist = p.getEyeLocation().toVector().distance(e.getBlock().getLocation().add(0.5, 0.5, 0.5).toVector());
        if (dist > 6.5) {
            e.setCancelled(true);
            flag(p, "Nuker", 2, String.format("%.1f blocks away", dist));
        }
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent e) {
        data.remove(e.getPlayer().getUniqueId());
    }

    /** Players currently with any violation level, for /fc ac. */
    public Map<UUID, Double> totals() {
        Map<UUID, Double> out = new HashMap<>();
        data.forEach((id, d) -> {
            double sum = d.vl.values().stream().mapToDouble(Double::doubleValue).sum();
            if (sum >= 1) {
                out.put(id, sum);
            }
        });
        return out;
    }
}
