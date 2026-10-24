package net.funcraft.games.bots;

import net.funcraft.games.game.Game;
import org.bukkit.Bukkit;
import org.bukkit.FluidCollisionMode;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.block.BlockFace;
import org.bukkit.entity.AbstractArrow;
import org.bukkit.entity.Arrow;
import org.bukkit.entity.Entity;
import org.bukkit.entity.LivingEntity;
import org.bukkit.entity.Monster;
import org.bukkit.entity.Player;
import org.bukkit.entity.Projectile;
import org.bukkit.entity.Snowball;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.inventory.EquipmentSlot;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.PlayerInventory;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;
import org.bukkit.util.Vector;

import java.util.Random;

/**
 * What a bot wants to do this tick. Games call the helpers here from {@link Game#botTick}; the
 * bot manager then turns {@link #forward}, {@link #strafe}, {@link #jump}, {@link #sprint} and the
 * look direction into movement.
 */
public final class BotBrain {

    public final Player bot;
    final Random random = new Random();

    // ---- outputs for this tick
    float forward;
    float strafe;
    boolean jump;
    boolean sprint;
    float yaw;
    float pitch;
    /** Skip the "don't walk off edges" check this tick (parkour, deliberate jumps). */
    boolean daring;

    // ---- memory
    public int ticks;
    private int attackCooldown;
    private int shootCooldown;
    private int strafeTicks;
    private float strafeDir = 1;
    private int eatCooldown;
    private Location wanderTarget;
    private int wanderTicks;
    private int stuckTicks;
    private Location lastPos;
    /** Free slot for a game to remember things about this bot (cleared between games). */
    public Object memo;
    public int timer;

    BotBrain(Player bot) {
        this.bot = bot;
        this.yaw = bot.getLocation().getYaw();
    }

    void beginTick() {
        forward = 0;
        strafe = 0;
        jump = false;
        sprint = false;
        daring = false;
        ticks++;
        attackCooldown--;
        shootCooldown--;
        eatCooldown--;
        timer--;
    }

    void forget() {
        memo = null;
        timer = 0;
        wanderTarget = null;
    }

    public Random random() {
        return random;
    }

    /** Lets the bot walk off edges this tick (for deliberate jumps). */
    public void dare() {
        daring = true;
    }

    public boolean onGround() {
        return bot.isOnGround();
    }

    public void jump() {
        jump = true;
    }

    // ------------------------------------------------------------- looking

    public void lookAt(Location target) {
        Location eye = bot.getEyeLocation();
        Vector d = target.toVector().subtract(eye.toVector());
        double flat = Math.sqrt(d.getX() * d.getX() + d.getZ() * d.getZ());
        yaw = (float) Math.toDegrees(Math.atan2(-d.getX(), d.getZ()));
        pitch = (float) -Math.toDegrees(Math.atan2(d.getY(), Math.max(0.001, flat)));
    }

    public void face(Location target) {
        Location eye = bot.getEyeLocation();
        Vector d = target.toVector().subtract(eye.toVector());
        yaw = (float) Math.toDegrees(Math.atan2(-d.getX(), d.getZ()));
        pitch = 0;
    }

    // ------------------------------------------------------------ movement

    public double distance(Location l) {
        return l.getWorld() == bot.getWorld() ? bot.getLocation().distance(l) : Double.MAX_VALUE;
    }

    public double flatDistance(Location l) {
        Location b = bot.getLocation();
        double dx = l.getX() - b.getX();
        double dz = l.getZ() - b.getZ();
        return Math.sqrt(dx * dx + dz * dz);
    }

    /** Walks (or sprints) towards a spot, hopping up single blocks and stopping at edges. */
    public void moveTo(Location target, boolean run) {
        if (flatDistance(target) < 0.6) {
            return;
        }
        face(target);
        forward = 1;
        sprint = run;
        if (target.getY() > bot.getLocation().getY() + 0.6 && flatDistance(target) < 2.5) {
            jump = true;
        }
    }

    public void moveAway(Location from, boolean run) {
        Location b = bot.getLocation();
        Location away = b.clone().add(b.toVector().subtract(from.toVector()).setY(0).normalize().multiply(5));
        moveTo(away, run);
    }

    public void stop() {
        forward = 0;
        strafe = 0;
    }

    /** Strolls around a centre point, pausing now and then. */
    public void wander(Location center, double radius, boolean run) {
        if (wanderTarget == null || wanderTarget.getWorld() != bot.getWorld() || --wanderTicks <= 0 || flatDistance(wanderTarget) < 1) {
            wanderTicks = 40 + random.nextInt(80);
            if (random.nextInt(3) == 0) {
                wanderTarget = bot.getLocation(); // stand still for a bit
            } else {
                double a = random.nextDouble() * Math.PI * 2;
                double d = random.nextDouble() * radius;
                wanderTarget = center.clone().add(Math.cos(a) * d, 0, Math.sin(a) * d);
            }
        }
        moveTo(wanderTarget, run);
    }

    /** Jumps over a block in the way. Called by the manager after the game decided where to go. */
    void autoJump() {
        if (forward <= 0) {
            return;
        }
        Location loc = bot.getLocation();
        Vector dir = new Vector(-Math.sin(Math.toRadians(yaw)), 0, Math.cos(Math.toRadians(yaw)));
        Block ahead = loc.clone().add(dir.clone().multiply(0.8)).getBlock();
        if (ahead.getType().isSolid() && ahead.getRelative(BlockFace.UP).isPassable()
                && ahead.getRelative(BlockFace.UP, 2).isPassable()) {
            jump = true;
        }
        // stuck against something: hop and try a little sideways
        if (lastPos != null && lastPos.getWorld() == loc.getWorld() && lastPos.distanceSquared(loc) < 0.0025) {
            if (++stuckTicks > 15) {
                jump = true;
                strafe = strafeDir;
                if (stuckTicks > 40) {
                    strafeDir = -strafeDir;
                    stuckTicks = 0;
                }
            }
        } else {
            stuckTicks = 0;
        }
        lastPos = loc;
    }

    /** True if there is floor in front of the bot (within a few blocks down). */
    boolean groundAhead(double distance) {
        Location loc = bot.getLocation();
        Vector dir = new Vector(-Math.sin(Math.toRadians(yaw)), 0, Math.cos(Math.toRadians(yaw)));
        Location ahead = loc.clone().add(dir.multiply(distance));
        for (int dy = 0; dy <= 4; dy++) {
            if (!ahead.clone().subtract(0, dy + 0.1, 0).getBlock().isPassable()) {
                return true;
            }
        }
        return false;
    }

    /** Stops the bot walking off an edge, or builds a bridge if it has blocks. */
    void edgeCheck(boolean mayBridge) {
        if (daring || forward <= 0 || bot.getGameMode() == GameMode.CREATIVE) {
            return;
        }
        if (!groundAhead(1.0)) {
            if (mayBridge && bridge()) {
                sprint = false;
                return;
            }
            forward = 0;
            sprint = false;
            jump = false;
        }
    }

    /** Places a block in front of its feet, if it carries any. */
    public boolean bridge() {
        ItemStack blocks = null;
        PlayerInventory inv = bot.getInventory();
        for (ItemStack item : inv.getContents()) {
            if (item != null && item.getType().isBlock() && item.getType().isSolid() && !item.getType().name().endsWith("_BED")
                    && item.getType() != Material.TNT && !item.getType().name().contains("SHULKER")) {
                blocks = item;
                break;
            }
        }
        if (blocks == null) {
            return false;
        }
        Location loc = bot.getLocation();
        Vector dir = new Vector(-Math.sin(Math.toRadians(yaw)), 0, Math.cos(Math.toRadians(yaw)));
        Block target = loc.clone().add(dir.multiply(0.9)).subtract(0, 1, 0).getBlock();
        if (!target.isPassable()) {
            return true;
        }
        Block against = loc.clone().subtract(0, 1, 0).getBlock();
        return place(target, against, blocks);
    }

    public boolean place(Block target, Block against, ItemStack from) {
        if (!target.isPassable()) {
            return false;
        }
        var replaced = target.getState();
        Material type = from.getType();
        target.setType(type, false);
        BlockPlaceEvent event = new BlockPlaceEvent(target, replaced, against, from, bot, true, EquipmentSlot.HAND);
        Bukkit.getPluginManager().callEvent(event);
        if (event.isCancelled() || !event.canBuild()) {
            replaced.update(true, false);
            return false;
        }
        bot.swingMainHand();
        if (bot.getGameMode() != GameMode.CREATIVE) {
            from.setAmount(from.getAmount() - 1);
        }
        return true;
    }

    public boolean breakBlock(Block block) {
        if (block.isEmpty() || block.getType() == Material.BEDROCK || block.getType() == Material.BARRIER) {
            return false;
        }
        BlockBreakEvent event = new BlockBreakEvent(block, bot);
        Bukkit.getPluginManager().callEvent(event);
        if (event.isCancelled()) {
            return false;
        }
        bot.swingMainHand();
        block.setType(Material.AIR);
        return true;
    }

    // -------------------------------------------------------------- combat

    /** Nearest player that's still in the game, not on our team and not a spectator. */
    public Player nearestEnemy(Game game, double range) {
        Player best = null;
        double bestD = range * range;
        for (Player p : game.alivePlayers()) {
            if (p.equals(bot) || p.getWorld() != bot.getWorld() || game.isTeammate(bot, p)
                    || (p.getGameMode() != GameMode.SURVIVAL && p.getGameMode() != GameMode.ADVENTURE)) {
                continue;
            }
            double d = p.getLocation().distanceSquared(bot.getLocation());
            if (d < bestD) {
                bestD = d;
                best = p;
            }
        }
        return best;
    }

    public LivingEntity nearestMonster(double range) {
        LivingEntity best = null;
        double bestD = range * range;
        for (Entity e : bot.getNearbyEntities(range, range / 2, range)) {
            if (e instanceof Monster m && !m.isDead()) {
                double d = e.getLocation().distanceSquared(bot.getLocation());
                if (d < bestD) {
                    bestD = d;
                    best = m;
                }
            }
        }
        return best;
    }

    public boolean canSee(Entity target) {
        return bot.hasLineOfSight(target);
    }

    /** Chase and fight: melee up close, bow/crossbow/snowballs from range if it has them. */
    public void fight(LivingEntity target) {
        Location tl = target.getLocation();
        double d = distance(tl);
        lookAt(tl.clone().add(0, target.getHeight() * 0.7, 0));
        if (d > 8 && shootCooldown <= 0 && canSee(target) && shootBow(target)) {
            return;
        }
        if (d > 2.6) {
            moveTo(tl, true);
        } else {
            // circle around the target a bit, like real players do
            if (--strafeTicks <= 0) {
                strafeTicks = 15 + random.nextInt(30);
                strafeDir = random.nextBoolean() ? 1 : -1;
            }
            forward = d > 1.8 ? 0.7f : 0;
            strafe = strafeDir * 0.6f;
            sprint = true;
            if (random.nextInt(25) == 0) {
                jump = true;
            }
        }
        lookAt(tl.clone().add(0, target.getHeight() * 0.7, 0));
        if (d < 3.3 && attackCooldown <= 0 && canSee(target)) {
            melee(target);
        }
    }

    public void melee(LivingEntity target) {
        holdBestWeapon();
        bot.swingMainHand();
        bot.attack(target);
        var speed = bot.getAttribute(org.bukkit.attribute.Attribute.ATTACK_SPEED);
        boolean spam = speed != null && speed.getValue() > 50; // 1.8-style combat
        attackCooldown = spam ? 3 + random.nextInt(3) : 11 + random.nextInt(4);
    }

    /** Shoots an arrow at the target if the bot has a bow (or crossbow) and arrows. */
    public boolean shootBow(LivingEntity target) {
        PlayerInventory inv = bot.getInventory();
        boolean hasBow = inv.contains(Material.BOW) || inv.contains(Material.CROSSBOW);
        if (!hasBow || !inv.contains(Material.ARROW)) {
            return false;
        }
        ItemStack bow = null;
        for (ItemStack item : inv.getContents()) {
            if (item != null && (item.getType() == Material.BOW || item.getType() == Material.CROSSBOW)) {
                bow = item;
                break;
            }
        }
        boolean infinity = bow != null && bow.containsEnchantment(org.bukkit.enchantments.Enchantment.INFINITY);
        launch(Arrow.class, target.getLocation().add(0, target.getHeight() * 0.6, 0), 2.6);
        if (!infinity) {
            inv.removeItem(new ItemStack(Material.ARROW, 1));
        }
        shootCooldown = 25 + random.nextInt(20);
        return true;
    }

    /** Throws a snowball at a spot (paintball). */
    public boolean throwSnowball(Location at) {
        if (shootCooldown > 0 || !bot.getInventory().contains(Material.SNOWBALL)) {
            return false;
        }
        launch(Snowball.class, at, 1.6);
        bot.getInventory().removeItem(new ItemStack(Material.SNOWBALL, 1));
        shootCooldown = 8 + random.nextInt(8);
        return true;
    }

    /** Fires a projectile at a spot with a little drop compensation and some human inaccuracy. */
    public <T extends Projectile> T launch(Class<T> type, Location at, double speed) {
        Location eye = bot.getEyeLocation();
        Vector d = at.toVector().subtract(eye.toVector());
        double dist = d.length();
        d.setY(d.getY() + dist * dist * 0.006 * (type == Snowball.class ? 1.6 : 1));
        d.normalize();
        d.add(new Vector((random.nextDouble() - 0.5) * 0.06, (random.nextDouble() - 0.5) * 0.04, (random.nextDouble() - 0.5) * 0.06));
        lookAt(at);
        T p = bot.launchProjectile(type, d.normalize().multiply(speed));
        if (p instanceof AbstractArrow arrow) {
            arrow.setPickupStatus(AbstractArrow.PickupStatus.DISALLOWED);
        }
        bot.swingMainHand();
        return p;
    }

    public boolean readyToShoot() {
        return shootCooldown <= 0;
    }

    public void shotFired(int cooldownTicks) {
        shootCooldown = cooldownTicks;
    }

    private static int weaponScore(Material m) {
        String n = m.name();
        int tier = n.startsWith("NETHERITE") ? 6 : n.startsWith("DIAMOND") ? 5 : n.startsWith("IRON") ? 4 : n.startsWith("STONE") ? 3
                : n.startsWith("GOLDEN") ? 2 : n.startsWith("WOODEN") ? 1 : 0;
        if (n.endsWith("_SWORD")) {
            return 10 + tier * 2;
        } else if (n.endsWith("_AXE")) {
            return 9 + tier * 2;
        } else if (m == Material.MACE) {
            return 20;
        } else if (m == Material.TRIDENT) {
            return 16;
        } else if (n.endsWith("_SPEAR")) {
            return 9 + tier * 2;
        } else if (m == Material.STICK) {
            return 2;
        }
        return 0;
    }

    /** Switches to the best melee weapon in the hotbar. */
    public void holdBestWeapon() {
        PlayerInventory inv = bot.getInventory();
        int best = -1;
        int bestScore = 0;
        for (int i = 0; i < 9; i++) {
            ItemStack item = inv.getItem(i);
            if (item != null) {
                int s = weaponScore(item.getType());
                if (s > bestScore) {
                    bestScore = s;
                    best = i;
                }
            }
        }
        if (best >= 0 && inv.getHeldItemSlot() != best) {
            inv.setHeldItemSlot(best);
        }
    }

    /** Holds the first hotbar item of a type. */
    public boolean hold(Material type) {
        PlayerInventory inv = bot.getInventory();
        for (int i = 0; i < 9; i++) {
            ItemStack item = inv.getItem(i);
            if (item != null && item.getType() == type) {
                inv.setHeldItemSlot(i);
                return true;
            }
        }
        int slot = inv.first(type);
        if (slot >= 9) {
            ItemStack item = inv.getItem(slot);
            ItemStack swap = inv.getItem(0);
            inv.setItem(0, item);
            inv.setItem(slot, swap);
            inv.setHeldItemSlot(0);
            return true;
        }
        return false;
    }

    /** Eats a golden apple (or steak) when hurt. */
    public void eatIfHurt() {
        if (eatCooldown > 0 || bot.getHealth() > 9) {
            return;
        }
        PlayerInventory inv = bot.getInventory();
        if (inv.contains(Material.GOLDEN_APPLE)) {
            inv.removeItem(new ItemStack(Material.GOLDEN_APPLE, 1));
            bot.addPotionEffect(new PotionEffect(PotionEffectType.REGENERATION, 100, 1));
            bot.addPotionEffect(new PotionEffect(PotionEffectType.ABSORPTION, 2400, 0));
            bot.getWorld().playSound(bot.getLocation(), "entity.generic.eat", 1f, 1f);
            eatCooldown = 80;
        } else if (inv.contains(Material.COOKED_BEEF) && bot.getFoodLevel() < 18) {
            inv.removeItem(new ItemStack(Material.COOKED_BEEF, 1));
            bot.setFoodLevel(Math.min(20, bot.getFoodLevel() + 8));
            bot.setSaturation(12);
            eatCooldown = 60;
        }
    }

    /** The standard behaviour: fight the nearest enemy, or look around. */
    public void play(Game game) {
        eatIfHurt();
        Player enemy = nearestEnemy(game, 80);
        if (enemy != null) {
            fight(enemy);
        } else {
            wander(bot.getLocation(), 6, false);
        }
    }

    /** Is there air/void straight down below this spot (within a few blocks)? */
    public static boolean overVoid(Location l) {
        for (int dy = 1; dy <= 6; dy++) {
            if (!l.clone().subtract(0, dy, 0).getBlock().isPassable()) {
                return false;
            }
        }
        return true;
    }

    public boolean rayClear(Location to) {
        Location eye = bot.getEyeLocation();
        Vector d = to.toVector().subtract(eye.toVector());
        double len = d.length();
        if (len < 0.1) {
            return true;
        }
        return bot.getWorld().rayTraceBlocks(eye, d.normalize(), len, FluidCollisionMode.NEVER, true) == null;
    }
}
