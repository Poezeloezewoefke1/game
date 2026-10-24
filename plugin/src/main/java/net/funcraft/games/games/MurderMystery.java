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
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.NamespacedKey;
import org.bukkit.entity.AbstractArrow;
import org.bukkit.entity.Arrow;
import org.bukkit.entity.Item;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDamageByEntityEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.entity.EntityPickupItemEvent;
import org.bukkit.event.entity.ProjectileHitEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.persistence.PersistentDataType;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

/**
 * Murder Mystery: one secret murderer with a sword, one detective with a bow, everyone else
 * innocent. Innocents collect gold (10 gold = a bow and an arrow). The murderer wins by killing
 * everyone; the innocents win by shooting the murderer or surviving until time runs out. Shoot an
 * innocent and you die too. If the detective dies, their bow drops for someone else to grab.
 */
public final class MurderMystery extends Game {

    private static final int Y = 64;
    private static final int RADIUS = 24;
    private static final int TIME_LIMIT = 270;
    private static final int SWORD_DELAY = 10;
    private static final int GOLD_FOR_BOW = 10;
    private static final int MAX_GOLD_ON_GROUND = 14;

    private final List<Location> spawns = new ArrayList<>();
    private final NamespacedKey bowKey;
    private UUID murderer;
    private UUID detective;
    private boolean bowDropped;
    private Item droppedBow;

    public MurderMystery(FunCraft plugin, int id) {
        super(plugin, id, GameType.MURDER_MYSTERY);
        this.bowKey = new NamespacedKey(plugin, "detective_bow");
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-RADIUS - 6, -RADIUS - 6, RADIUS + 6, RADIUS + 6};
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + " Manor";
        spawns.addAll(Arenas.village(world, theme, random, Y, RADIUS));
        world.setTime(13500); // dusk
    }

    private boolean isMurderer(Player p) {
        return p.getUniqueId().equals(murderer);
    }

    private ItemStack detectiveBow() {
        return ItemBuilder.of(Material.BOW).name("<aqua><bold>Detective's Bow").unbreakable().build();
    }

    @Override
    protected void onStart(List<Player> list) {
        List<Player> shuffled = new ArrayList<>(list);
        Collections.shuffle(shuffled, random);
        murderer = shuffled.get(0).getUniqueId();
        detective = shuffled.size() > 1 ? shuffled.get(1).getUniqueId() : null;
        for (Player viewer : list) {
            for (Player other : list) {
                plugin.sidebars().of(viewer).hideNameTag(other.getName());
            }
        }
        for (int i = 0; i < list.size(); i++) {
            Player p = list.get(i);
            p.teleport(spawns.get(i % spawns.size()));
            if (isMurderer(p)) {
                Msg.title(p, "<red><bold>MURDERER", "<gray>Kill everyone. Your sword arrives in " + SWORD_DELAY + "s", 5, 80, 10);
            } else if (p.getUniqueId().equals(detective)) {
                p.getInventory().setItem(1, detectiveBow());
                p.getInventory().setItem(8, new ItemStack(Material.ARROW));
                Msg.title(p, "<aqua><bold>DETECTIVE", "<gray>Find and shoot the murderer!", 5, 80, 10);
            } else {
                Msg.title(p, "<green><bold>INNOCENT", "<gray>Survive! Collect gold to get a bow", 5, 80, 10);
            }
        }
        Msg.all(list, "<gray>Someone here is a <red>murderer</red>. Collect <gold>gold</gold> ("
                + GOLD_FOR_BOW + " = a bow) and stay alive. Shoot an innocent and you die too!");
    }

    // ----------------------------------------------------------------- gold

    private void spawnGold() {
        int onGround = 0;
        for (Item item : world.getEntitiesByClass(Item.class)) {
            if (item.getItemStack().getType() == Material.GOLD_INGOT) {
                onGround++;
            }
        }
        if (onGround >= MAX_GOLD_ON_GROUND) {
            return;
        }
        for (int tries = 0; tries < 15; tries++) {
            int x = random.nextInt(RADIUS * 2 - 3) - RADIUS + 2;
            int z = random.nextInt(RADIUS * 2 - 3) - RADIUS + 2;
            if (x * x + z * z > (RADIUS - 2) * (RADIUS - 2)) {
                continue;
            }
            if (world.getBlockAt(x, Y + 1, z).getType().isAir() && !world.getBlockAt(x, Y, z).getType().isAir()) {
                Item gold = world.dropItem(new Location(world, x + 0.5, Y + 1.2, z + 0.5), new ItemStack(Material.GOLD_INGOT));
                gold.setVelocity(new org.bukkit.util.Vector());
                return;
            }
        }
    }

    @Override
    public void onPickup(EntityPickupItemEvent event, Player player) {
        ItemStack stack = event.getItem().getItemStack();
        if (stack.getType() == Material.BOW && stack.getItemMeta() != null
                && stack.getItemMeta().getPersistentDataContainer().has(bowKey, PersistentDataType.BYTE)) {
            if (isMurderer(player) || player.getInventory().contains(Material.BOW)) {
                event.setCancelled(true);
                return;
            }
            event.setCancelled(true);
            event.getItem().remove();
            droppedBow = null;
            player.getInventory().setItem(1, detectiveBow());
            player.getInventory().setItem(8, new ItemStack(Material.ARROW));
            Msg.all(online(), "<aqua>Someone picked up the detective's bow!");
            Msg.title(player, "<aqua><bold>You have the bow!", "<gray>Find the murderer", 0, 40, 10);
            return;
        }
        if (stack.getType() == Material.GOLD_INGOT) {
            Msg.sound(player, "entity.experience_orb.pickup", 1.6f);
            Bukkit.getScheduler().runTask(plugin, () -> checkGold(player));
        }
    }

    private void checkGold(Player p) {
        if (!p.isOnline() || isMurderer(p) || p.getGameMode() != GameMode.SURVIVAL) {
            return;
        }
        int gold = count(p, Material.GOLD_INGOT);
        if (gold >= GOLD_FOR_BOW) {
            p.getInventory().removeItem(new ItemStack(Material.GOLD_INGOT, GOLD_FOR_BOW));
            if (!p.getInventory().contains(Material.BOW)) {
                p.getInventory().setItem(1, ItemBuilder.of(Material.BOW).name("<green>Bow").unbreakable().build());
            }
            p.getInventory().addItem(new ItemStack(Material.ARROW));
            Msg.actionBar(p, "<green>" + GOLD_FOR_BOW + " gold: you got a bow and an arrow!");
            Msg.sound(p, "entity.player.levelup", 1.4f);
        }
    }

    private static int count(Player p, Material m) {
        int n = 0;
        for (ItemStack item : p.getInventory().getContents()) {
            if (item != null && item.getType() == m) {
                n += item.getAmount();
            }
        }
        return n;
    }

    // --------------------------------------------------------------- deaths

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        event.setCancelled(true);
        if (event.getCause() == EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(false);
            return;
        }
        if (attacker == null || attacker.equals(victim) || !isAlive(attacker) || attacker.getGameMode() != GameMode.SURVIVAL) {
            return;
        }
        boolean arrow = event instanceof EntityDamageByEntityEvent byEntity && byEntity.getDamager() instanceof Arrow;
        if (event.getCause() == EntityDamageEvent.DamageCause.ENTITY_ATTACK && isMurderer(attacker)
                && attacker.getInventory().getItemInMainHand().getType() == Material.IRON_SWORD) {
            murder(victim, attacker);
        } else if (arrow) {
            if (isMurderer(victim)) {
                Msg.all(online(), "<green><bold>" + attacker.getName() + " shot the murderer!");
                murder(victim, attacker);
            } else if (!isMurderer(attacker)) {
                murder(victim, attacker);
                if (state == State.RUNNING && isAlive(attacker)) {
                    Msg.all(online(), "<red>" + attacker.getName() + " <gray>shot an innocent and paid the price!");
                    murder(attacker, null);
                }
            }
        }
    }

    @Override
    public void onProjectileHit(ProjectileHitEvent event) {
        if (event.getEntity() instanceof AbstractArrow arrow) {
            Bukkit.getScheduler().runTask(plugin, arrow::remove);
        }
    }

    private void murder(Player victim, Player killer) {
        if (!isAlive(victim) || victim.getGameMode() == GameMode.SPECTATOR) {
            return;
        }
        boolean hadBow = victim.getInventory().contains(Material.BOW);
        boolean wasDetective = victim.getUniqueId().equals(detective);
        if (killer != null && !killer.equals(victim)) {
            kills.merge(killer.getUniqueId(), 1, Integer::sum);
            plugin.stats().addKill(killer, type);
        }
        plugin.stats().addDeath(victim, type);
        world.playSound(victim.getLocation(), "entity.player.death", 1f, 0.8f);
        if ((wasDetective || hadBow) && !isMurderer(victim) && !bowDropped && !hasBowElsewhere(victim)) {
            ItemStack bow = detectiveBow();
            var meta = bow.getItemMeta();
            meta.getPersistentDataContainer().set(bowKey, PersistentDataType.BYTE, (byte) 1);
            bow.setItemMeta(meta);
            droppedBow = world.dropItem(victim.getLocation().add(0, 0.5, 0), bow);
            droppedBow.setUnlimitedLifetime(true);
            droppedBow.setGlowing(true);
            bowDropped = wasDetective;
            Msg.all(online(), "<aqua>The " + (wasDetective ? "detective" : "bow holder") + " is dead! <gray>Their bow is on the ground - grab it!");
        }
        int innocentsLeft = (int) alivePlayers().stream().filter(p -> !p.equals(victim) && !isMurderer(p)).count();
        if (!isMurderer(victim)) {
            Msg.all(online(), "<red>" + victim.getName() + " <gray>was killed! <green>" + innocentsLeft + " innocent"
                    + (innocentsLeft == 1 ? "" : "s") + " left.");
        }
        Msg.title(victim, "<red><bold>YOU DIED", isMurderer(victim) ? "<gray>You were caught!" : "<gray>Spectate to see who did it", 5, 50, 10);
        eliminate(victim, false);
    }

    private boolean hasBowElsewhere(Player victim) {
        for (Player p : alivePlayers()) {
            if (!p.equals(victim) && !isMurderer(p) && p.getInventory().contains(Material.BOW)) {
                return true;
            }
        }
        return false;
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        murder(victim, null);
    }

    @Override
    protected void checkWin() {
        if (state != State.RUNNING) {
            return;
        }
        Player m = murderer == null ? null : Bukkit.getPlayer(murderer);
        boolean murdererIn = m != null && alive.contains(murderer);
        long innocents = alive.stream().filter(id -> !id.equals(murderer)).count();
        if (!murdererIn) {
            reveal();
            List<UUID> winners = new ArrayList<>(players);
            winners.remove(murderer);
            end("The Innocents", winners);
        } else if (innocents == 0) {
            reveal();
            end(m.getName() + " (the murderer)", List.of(murderer));
        }
    }

    private void reveal() {
        Player m = murderer == null ? null : Bukkit.getPlayer(murderer);
        Player d = detective == null ? null : Bukkit.getPlayer(detective);
        Msg.all(online(), "<gray>The murderer was <red><bold>" + (m == null ? "?" : m.getName())
                + "</bold><gray>" + (d == null ? "" : ", the detective was <aqua>" + d.getName()) + "<gray>.");
    }

    @Override
    protected void onSecond() {
        if (state != State.RUNNING) {
            return;
        }
        if (elapsed == SWORD_DELAY) {
            Player m = Bukkit.getPlayer(murderer);
            if (m != null && isAlive(m)) {
                m.getInventory().setItem(1, ItemBuilder.of(Material.IRON_SWORD).name("<red><bold>Knife").unbreakable().build());
                Msg.actionBar(m, "<red>You got your knife. Happy hunting...");
            }
            Msg.all(online(), "<red>The murderer has their knife...");
            Msg.sound(online(), "entity.wither.ambient", 1.4f);
        }
        if (elapsed % 3 == 0) {
            spawnGold();
        }
        // the detective's arrow comes back
        if (elapsed % 5 == 0) {
            for (Player p : alivePlayers()) {
                if (!isMurderer(p) && p.getInventory().contains(Material.BOW) && !p.getInventory().contains(Material.ARROW)
                        && p.getUniqueId().equals(detective)) {
                    p.getInventory().setItem(8, new ItemStack(Material.ARROW));
                }
            }
        }
        if (droppedBow != null && droppedBow.isValid() && elapsed % 2 == 0) {
            world.spawnParticle(org.bukkit.Particle.END_ROD, droppedBow.getLocation().add(0, 0.6, 0), 4, 0.1, 0.4, 0.1, 0.01);
        }
        int left = TIME_LIMIT - elapsed;
        long innocents = alive.stream().filter(id -> !id.equals(murderer)).count();
        bossBar("<white>Innocents left: <green>" + innocents + " <dark_gray>| <yellow>" + Msg.time(left),
                (float) left / TIME_LIMIT, BossBar.Color.WHITE);
        if (left == 60) {
            Msg.all(online(), "<yellow>One minute left! Innocents win if they survive!");
        }
        if (left <= 0) {
            Msg.all(online(), "<green>Time's up - the innocents survived!");
            reveal();
            List<UUID> winners = new ArrayList<>(alive);
            winners.remove(murderer);
            end("The Innocents", winners);
        }
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
        String role = isMurderer(player) ? "<red><bold>MURDERER" : player.getUniqueId().equals(detective) ? "<aqua><bold>DETECTIVE" : "<green><bold>INNOCENT";
        lines.add("<white>Role: " + (isAlive(player) ? role : "<gray>dead"));
        lines.add("  ");
        lines.add("<white>Innocents left: <green>" + alive.stream().filter(id -> !id.equals(murderer)).count());
        Player d = detective == null ? null : Bukkit.getPlayer(detective);
        lines.add("<white>Detective: " + (d != null && alive.contains(detective) ? "<aqua>alive" : droppedBow != null ? "<yellow>bow dropped" : "<red>dead"));
        lines.add("<white>Time: <yellow>" + Msg.time(TIME_LIMIT - elapsed));
        if (isAlive(player) && !isMurderer(player)) {
            lines.add("   ");
            lines.add("<white>Gold: <gold>" + count(player, Material.GOLD_INGOT) + "/" + GOLD_FOR_BOW);
        }
        return lines;
    }

    @Override
    protected void cleanup() {
        murderer = null;
        detective = null;
        droppedBow = null;
        bowDropped = false;
    }
}
