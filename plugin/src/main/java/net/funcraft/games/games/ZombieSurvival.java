package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Arenas;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Theme;
import net.kyori.adventure.bossbar.BossBar;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.GameRule;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.attribute.Attribute;
import org.bukkit.attribute.AttributeInstance;
import org.bukkit.enchantments.Enchantment;
import org.bukkit.entity.AbstractSkeleton;
import org.bukkit.entity.EntityType;
import org.bukkit.entity.LivingEntity;
import org.bukkit.entity.Mob;
import org.bukkit.entity.Player;
import org.bukkit.entity.Zombie;
import org.bukkit.event.entity.CreatureSpawnEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.PlayerInventory;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * Zombie Survival: everyone teams up against 10 waves of monsters at night. Fallen players come
 * back at the start of the next wave, and every cleared wave upgrades everyone's gear. Bosses on
 * waves 5 and 10. If everyone is down at once, the monsters win.
 */
public final class ZombieSurvival extends Game {

    private static final int Y = 64;
    private static final int RADIUS = 24;
    private static final int WAVES = 10;
    private static final int BREAK_SECONDS = 8;

    private final List<Location> spawns = new ArrayList<>();
    private final Set<UUID> mobs = new HashSet<>();
    private final Set<UUID> down = new HashSet<>();
    private int wave;
    private int breakLeft;
    private int toSpawn;

    public ZombieSurvival(FunCraft plugin, int id) {
        super(plugin, id, GameType.ZOMBIES);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-RADIUS - 6, -RADIUS - 6, RADIUS + 6, RADIUS + 6};
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + " Outpost";
        spawns.addAll(Arenas.village(world, theme, random, Y, RADIUS));
        world.setTime(18000);
        world.setGameRule(GameRule.DO_DAYLIGHT_CYCLE, false);
    }

    @Override
    protected void onStart(List<Player> list) {
        for (int i = 0; i < list.size(); i++) {
            Player p = list.get(i);
            p.teleport(spawns.get((i * 2 + 1) % spawns.size()));
            kit(p);
            Msg.title(p, "<dark_green><bold>Zombie Survival", "<gray>Survive " + WAVES + " waves together!", 5, 60, 10);
        }
        Msg.all(list, "<gray>Work together! If you fall you're back next wave - but if everyone is down, it's over.");
        breakLeft = 5;
    }

    private void kit(Player p) {
        PlayerInventory inv = p.getInventory();
        inv.setItem(0, ItemBuilder.of(Material.STONE_SWORD).unbreakable().build());
        inv.setItem(1, ItemBuilder.of(Material.BOW).unbreakable().build());
        inv.setItem(2, new ItemStack(Material.COOKED_BEEF, 16));
        inv.setItem(8, new ItemStack(Material.ARROW, 32));
        inv.setItemInOffHand(ItemBuilder.of(Material.SHIELD).unbreakable().build());
        inv.setHelmet(ItemBuilder.of(Material.LEATHER_HELMET).unbreakable().build());
        inv.setChestplate(ItemBuilder.of(Material.LEATHER_CHESTPLATE).unbreakable().build());
        inv.setLeggings(ItemBuilder.of(Material.LEATHER_LEGGINGS).unbreakable().build());
        inv.setBoots(ItemBuilder.of(Material.LEATHER_BOOTS).unbreakable().build());
    }

    /** Gear everyone gets after clearing a wave. */
    private void reward(Player p, int cleared) {
        PlayerInventory inv = p.getInventory();
        switch (cleared) {
            case 1 -> inv.setChestplate(ItemBuilder.of(Material.CHAINMAIL_CHESTPLATE).unbreakable().build());
            case 2 -> inv.setItem(0, ItemBuilder.of(Material.IRON_SWORD).unbreakable().build());
            case 3 -> {
                inv.setHelmet(ItemBuilder.of(Material.IRON_HELMET).unbreakable().build());
                inv.setBoots(ItemBuilder.of(Material.IRON_BOOTS).unbreakable().build());
            }
            case 4 -> inv.setItem(1, ItemBuilder.of(Material.BOW).enchant(Enchantment.POWER, 2).unbreakable().build());
            case 5 -> {
                inv.setChestplate(ItemBuilder.of(Material.IRON_CHESTPLATE).unbreakable().build());
                inv.setLeggings(ItemBuilder.of(Material.IRON_LEGGINGS).unbreakable().build());
            }
            case 6 -> inv.setItem(0, ItemBuilder.of(Material.DIAMOND_SWORD).unbreakable().build());
            case 7 -> inv.setChestplate(ItemBuilder.of(Material.DIAMOND_CHESTPLATE).unbreakable().build());
            case 8 -> inv.setItem(0, ItemBuilder.of(Material.DIAMOND_SWORD).enchant(Enchantment.SHARPNESS, 3).unbreakable().build());
            case 9 -> inv.setHelmet(ItemBuilder.of(Material.DIAMOND_HELMET).unbreakable().build());
            default -> {
            }
        }
        inv.addItem(new ItemStack(Material.ARROW, 16), new ItemStack(Material.GOLDEN_APPLE, cleared >= 4 ? 2 : 1));
        p.setHealth(20);
        p.setFoodLevel(20);
    }

    private List<Player> up() {
        List<Player> list = new ArrayList<>();
        for (Player p : alivePlayers()) {
            if (!down.contains(p.getUniqueId()) && p.getGameMode() == GameMode.SURVIVAL) {
                list.add(p);
            }
        }
        return list;
    }

    // ---------------------------------------------------------------- waves

    private void startWave() {
        wave++;
        int players = Math.max(1, alivePlayers().size());
        toSpawn = 3 + wave * 2 + (players - 1) * (1 + wave / 2);
        Msg.title(online(), "<dark_red><bold>WAVE " + wave, wave == WAVES ? "<red>The final wave!" : wave == 5 ? "<red>A brute approaches..." : "");
        Msg.sound(online(), "entity.zombie_villager.converted", 0.7f);
        if (wave == 5 || wave == WAVES) {
            spawnBoss(wave == WAVES);
        }
    }

    private Location edgeSpot() {
        for (int tries = 0; tries < 20; tries++) {
            double a = random.nextDouble() * Math.PI * 2;
            int x = (int) Math.round(Math.cos(a) * (RADIUS - 2));
            int z = (int) Math.round(Math.sin(a) * (RADIUS - 2));
            if (world.getBlockAt(x, Y + 1, z).getType().isAir() && world.getBlockAt(x, Y + 2, z).getType().isAir()) {
                return new Location(world, x + 0.5, Y + 1, z + 0.5);
            }
        }
        return new Location(world, 0.5, Y + 1, RADIUS - 3.5);
    }

    private void spawnOne() {
        EntityType kind = EntityType.ZOMBIE;
        int r = random.nextInt(10);
        if (wave >= 3 && r < 3) {
            kind = EntityType.SKELETON;
        } else if (wave >= 4 && r == 3) {
            kind = EntityType.SPIDER;
        } else if (wave >= 6 && r == 4) {
            kind = EntityType.CREEPER;
        } else if (wave >= 7 && r == 5) {
            kind = EntityType.HUSK;
        }
        LivingEntity mob = (LivingEntity) world.spawnEntity(edgeSpot(), kind, CreatureSpawnEvent.SpawnReason.CUSTOM);
        setup(mob);
        if (mob instanceof Zombie z && wave >= 4 && random.nextInt(3) == 0) {
            z.getEquipment().setHelmet(new ItemStack(Material.IRON_HELMET));
            z.getEquipment().setHelmetDropChance(0);
        }
    }

    private void setup(LivingEntity mob) {
        mob.setRemoveWhenFarAway(false);
        mob.setPersistent(true);
        AttributeInstance range = mob.getAttribute(Attribute.FOLLOW_RANGE);
        if (range != null) {
            range.setBaseValue(64);
        }
        if (mob instanceof Zombie z) {
            z.setShouldBurnInDay(false);
            z.setAdult();
        } else if (mob instanceof AbstractSkeleton s) {
            s.setShouldBurnInDay(false);
        }
        if (mob.getEquipment() != null) {
            mob.getEquipment().setItemInMainHandDropChance(0);
        }
        mobs.add(mob.getUniqueId());
        target(mob);
    }

    private void spawnBoss(boolean king) {
        Zombie boss = (Zombie) world.spawnEntity(edgeSpot(), EntityType.ZOMBIE, CreatureSpawnEvent.SpawnReason.CUSTOM);
        setup(boss);
        double health = king ? 120 + 40 * alivePlayers().size() : 60 + 20 * alivePlayers().size();
        AttributeInstance max = boss.getAttribute(Attribute.MAX_HEALTH);
        if (max != null) {
            max.setBaseValue(health);
            boss.setHealth(health);
        }
        AttributeInstance scale = boss.getAttribute(Attribute.SCALE);
        if (scale != null) {
            scale.setBaseValue(king ? 2.2 : 1.6);
        }
        AttributeInstance damage = boss.getAttribute(Attribute.ATTACK_DAMAGE);
        if (damage != null) {
            damage.setBaseValue(king ? 9 : 6);
        }
        boss.customName(Msg.mm(king ? "<dark_red><bold>Zombie King" : "<red><bold>Zombie Brute"));
        boss.setCustomNameVisible(true);
        boss.getEquipment().setItemInMainHand(new ItemStack(king ? Material.NETHERITE_AXE : Material.IRON_AXE));
        boss.getEquipment().setHelmet(new ItemStack(king ? Material.GOLDEN_HELMET : Material.IRON_HELMET));
        boss.getEquipment().setHelmetDropChance(0);
        Msg.all(online(), king ? "<dark_red><bold>The Zombie King has arrived!" : "<red><bold>A Zombie Brute is coming!");
        Msg.sound(online(), "entity.wither.spawn", 0.6f);
    }

    private void target(LivingEntity mob) {
        if (!(mob instanceof Mob m)) {
            return;
        }
        Player nearest = null;
        double best = Double.MAX_VALUE;
        for (Player p : up()) {
            double d = p.getLocation().distanceSquared(mob.getLocation());
            if (d < best) {
                best = d;
                nearest = p;
            }
        }
        if (nearest != null && (m.getTarget() == null || !(m.getTarget() instanceof Player t) || down.contains(t.getUniqueId())
                || t.getGameMode() != GameMode.SURVIVAL)) {
            m.setTarget(nearest);
        }
    }

    private int mobsLeft() {
        int n = 0;
        for (UUID id : new ArrayList<>(mobs)) {
            if (Bukkit.getEntity(id) instanceof LivingEntity mob && mob.isValid() && !mob.isDead()) {
                n++;
            } else {
                mobs.remove(id);
            }
        }
        return n;
    }

    @Override
    protected void onSecond() {
        if (state != State.RUNNING) {
            return;
        }
        if (breakLeft > 0) {
            bossBar("<green>Wave " + (wave + 1) + " in <white>" + breakLeft + "s", 1f, BossBar.Color.GREEN);
            if (--breakLeft == 0) {
                startWave();
            }
            return;
        }
        // monsters arrive in groups over a few seconds
        for (int i = 0; i < 3 && toSpawn > 0; i++, toSpawn--) {
            spawnOne();
        }
        for (UUID id : mobs) {
            if (Bukkit.getEntity(id) instanceof LivingEntity mob) {
                if (mob.isDead()) {
                    continue;
                }
                if (elapsed % 3 == 0) {
                    target(mob);
                }
                if (mob.getLocation().getY() < Y - 10) {
                    mob.remove(); // fell off the island
                }
            }
        }
        int left = mobsLeft() + toSpawn;
        bossBar("<dark_red><bold>Wave " + wave + "/" + WAVES + "</bold> <dark_gray>| <red>" + left + " monsters left <dark_gray>| <green>"
                + up().size() + " standing", Math.min(1f, left / (float) Math.max(1, left + 1)), BossBar.Color.RED);
        if (left == 0) {
            waveCleared();
        }
    }

    private void waveCleared() {
        if (wave >= WAVES) {
            Msg.all(online(), "<gold><bold>You survived all " + WAVES + " waves!");
            end("Everyone", new ArrayList<>(alive));
            return;
        }
        Msg.all(online(), "<green><bold>Wave " + wave + " cleared!</bold> <gray>Everyone gets new gear.");
        Msg.sound(online(), "ui.toast.challenge_complete", 1f);
        for (Player p : alivePlayers()) {
            if (down.remove(p.getUniqueId())) {
                p.setGameMode(GameMode.SURVIVAL);
                p.teleport(spawns.get(random.nextInt(spawns.size())));
                Msg.title(p, "<green><bold>BACK IN!", "<gray>You've been revived", 0, 30, 10);
            }
            reward(p, wave);
        }
        breakLeft = BREAK_SECONDS;
    }

    @Override
    public void onMobDeath(org.bukkit.event.entity.EntityDeathEvent event) {
        event.getDrops().clear();
        event.setDroppedExp(0);
        Player killer = event.getEntity().getKiller();
        if (killer != null && mobs.remove(event.getEntity().getUniqueId()) && isAlive(killer)) {
            kills.merge(killer.getUniqueId(), 1, Integer::sum);
            plugin.stats().addKill(killer, type);
            Msg.actionBar(killer, "<green>+1 <gray>" + (event.getEntity().customName() != null ? "BOSS DOWN!" : "monster"));
        }
    }

    @Override
    public void onCreatureSpawn(CreatureSpawnEvent event) {
        if (event.getSpawnReason() != CreatureSpawnEvent.SpawnReason.CUSTOM) {
            event.setCancelled(true);
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (attacker != null && !attacker.equals(victim)) {
            event.setCancelled(true); // no friendly fire
        }
        if (down.contains(victim.getUniqueId())) {
            event.setCancelled(true);
        }
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        down.add(victim.getUniqueId());
        victim.setGameMode(GameMode.SPECTATOR);
        victim.teleport(spectatorSpawn());
        Msg.all(online(), "<red>" + victim.getName() + " <gray>went down! <yellow>(back next wave)");
        Msg.title(victim, "<red><bold>YOU'RE DOWN", "<gray>You'll be back when this wave is cleared", 5, 50, 10);
        checkWin();
    }

    @Override
    protected void checkWin() {
        if (state != State.RUNNING) {
            return;
        }
        if (up().isEmpty()) {
            Msg.all(online(), "<dark_red><bold>The monsters won! <gray>You made it to wave " + wave + ".");
            end(null, List.of());
        }
    }

    @Override
    protected boolean allowHunger() {
        return true;
    }

    @Override
    protected double voidLevel() {
        return Y - 25;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 0.5, Y + 20, 0.5, 0, 70);
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        lines.add("<white>Wave: <red>" + Math.max(1, wave) + "/" + WAVES);
        lines.add("<white>Monsters: <red>" + (mobs.size() + toSpawn));
        lines.add("<white>Standing: <green>" + up().size() + "/" + alive.size());
        lines.add("  ");
        lines.add("<white>Your kills: <green>" + kills.getOrDefault(player.getUniqueId(), 0));
        if (down.contains(player.getUniqueId())) {
            lines.add("<red>You're down - back next wave");
        }
        return lines;
    }

    @Override
    protected void cleanup() {
        for (UUID id : mobs) {
            if (Bukkit.getEntity(id) != null) {
                Bukkit.getEntity(id).remove();
            }
        }
        mobs.clear();
        down.clear();
    }

    @Override
    public void botTick(Player bot, net.funcraft.games.bots.BotBrain brain) {
        if (down.contains(bot.getUniqueId())) {
            return;
        }
        brain.eatIfHurt();
        LivingEntity mob = brain.nearestMonster(40);
        if (mob != null) {
            brain.fight(mob);
        } else {
            brain.wander(new Location(world, 0.5, Y + 1, 0.5), 8, false);
        }
    }
}
