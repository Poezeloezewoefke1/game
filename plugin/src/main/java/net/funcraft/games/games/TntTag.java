package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Structures;
import net.funcraft.games.util.Theme;
import net.kyori.adventure.bossbar.BossBar;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.Particle;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.inventory.InventoryType;
import org.bukkit.inventory.ItemStack;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;
import org.bukkit.util.Vector;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * TNT Tag: a few players get the TNT. Hit someone to pass it on - when the timer runs out,
 * everyone still holding TNT blows up. Rounds get shorter; the last survivor wins.
 */
public final class TntTag extends LastStanding {

    private static final int Y = 64;
    private static final double RADIUS = 17;
    private static final int BREAK_SECONDS = 4;
    private static final long TAG_BACK_MS = 600;

    private final Set<UUID> it = new HashSet<>();
    private final Map<UUID, Long> taggedAt = new HashMap<>();
    private int round;
    private int roundLength;
    private int roundLeft;
    private int breakLeft;

    public TntTag(FunCraft plugin, int id) {
        super(plugin, id, GameType.TNT_TAG);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-24, -24, 24, 24};
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + " Tag Arena";
        center = new Location(world, 0.5, Y + 1, 0.5);
        theme.island(world, 0, Y, 0, RADIUS, random);
        // flatten the top so nobody gets stuck, then add things to run around
        Build.disc(world, 0, Y, 0, RADIUS - 0.5, theme.top);
        Build.ring(world, 0, Y, 0, 3, 4.5, theme.path);
        Structures.ruins(world, 0, Y + 1, 0, theme, random);
        Structures.tower(world, 9, Y + 1, 0, 4, theme);
        Structures.tower(world, -9, Y + 1, 0, 4, theme);
        Structures.lamp(world, 0, Y + 1, 9, theme);
        Structures.lamp(world, 0, Y + 1, -9, theme);
        Structures.well(world, 7, Y + 1, 7, theme);
        Structures.lamp(world, -7, Y + 1, -7, theme);
        theme.plants(world, 0, Y, 0, RADIUS - 2, 14, random);
        // an invisible wall so the chase stays on the island
        for (int y = Y + 1; y <= Y + 10; y++) {
            Build.ring(world, 0, y, 0, RADIUS - 0.5, RADIUS + 1, Material.BARRIER);
        }
        // spawns go outside the buildings, inside the wall
        spawnRing(Y + 1, RADIUS - 3, Math.max(2, online().isEmpty() ? 8 : online().size()));
    }

    @Override
    protected boolean legacyCombat() {
        return true;
    }

    @Override
    protected void equip(Player player) {
        player.getInventory().clear();
        runner(player);
    }

    @Override
    protected void onStart(List<Player> list) {
        super.onStart(list);
        Msg.all(list, "<red>Got the TNT? <gray>Hit someone to pass it on before it explodes. Don't be holding it at zero!");
        breakLeft = BREAK_SECONDS;
    }

    // ------------------------------------------------------------- tagging

    private boolean isIt(Player p) {
        return it.contains(p.getUniqueId());
    }

    private void runner(Player p) {
        it.remove(p.getUniqueId());
        p.getInventory().clear();
        p.removePotionEffect(PotionEffectType.GLOWING);
        p.addPotionEffect(new PotionEffect(PotionEffectType.SPEED, PotionEffect.INFINITE_DURATION, 0, false, false));
    }

    private void tag(Player p) {
        it.add(p.getUniqueId());
        taggedAt.put(p.getUniqueId(), System.currentTimeMillis());
        ItemStack tnt = ItemBuilder.of(Material.TNT).name("<red><bold>You're IT!</bold> <gray>Hit someone to pass it").build();
        for (int slot = 0; slot < 9; slot++) {
            p.getInventory().setItem(slot, tnt);
        }
        p.getInventory().setHelmet(new ItemStack(Material.TNT));
        p.addPotionEffect(new PotionEffect(PotionEffectType.GLOWING, PotionEffect.INFINITE_DURATION, 0, false, false));
        p.addPotionEffect(new PotionEffect(PotionEffectType.SPEED, PotionEffect.INFINITE_DURATION, 1, false, false));
        Msg.title(p, "<red><bold>YOU'RE IT!", "<gray>Hit someone to pass the TNT!", 0, 30, 5);
        Msg.sound(p, "entity.tnt.primed", 1.2f);
    }

    private void startRound() {
        List<Player> players = alivePlayers();
        if (players.size() < 2) {
            checkWin();
            return;
        }
        round++;
        roundLength = Math.max(15, 35 - 5 * (round - 1));
        roundLeft = roundLength;
        int taggers = Math.max(1, Math.min(players.size() - 1, (int) Math.round(players.size() / 4.0)));
        Collections.shuffle(players, random);
        for (Player p : players) {
            runner(p);
        }
        List<String> names = new ArrayList<>();
        for (int i = 0; i < taggers; i++) {
            tag(players.get(i));
            names.add(players.get(i).getName());
        }
        Msg.all(online(), "<yellow><bold>Round " + round + "</bold> <gray>(" + roundLength + "s) - <red>"
                + String.join(", ", names) + " <gray>" + (taggers == 1 ? "has" : "have") + " the TNT!");
        Msg.sound(online(), "entity.tnt.primed", 0.8f);
    }

    private void explode() {
        List<Player> boom = new ArrayList<>();
        for (Player p : alivePlayers()) {
            if (isIt(p)) {
                boom.add(p);
            }
        }
        for (Player p : boom) {
            Location loc = p.getLocation();
            world.spawnParticle(Particle.EXPLOSION_EMITTER, loc, 1);
            world.playSound(loc, "entity.generic.explode", 1.5f, 1f);
            // the blast throws everyone nearby around a bit
            for (Player near : alivePlayers()) {
                if (!near.equals(p) && near.getLocation().distanceSquared(loc) < 25) {
                    Vector push = near.getLocation().toVector().subtract(loc.toVector()).setY(0);
                    if (push.lengthSquared() < 0.01) {
                        push = new Vector(1, 0, 0);
                    }
                    plugin.antiCheat().exempt(near, 2500);
                    near.setVelocity(push.normalize().multiply(1.1).setY(0.6));
                }
            }
            it.remove(p.getUniqueId());
            plugin.stats().addDeath(p, type);
            Msg.all(online(), "<red>💥 " + p.getName() + " <gray>blew up!");
        }
        for (Player p : boom) {
            if (state == State.RUNNING) {
                eliminate(p, false);
                Msg.title(p, "<red><bold>BOOM!", "<gray>You blew up - you can spectate or type <yellow>/leave", 5, 50, 10);
            }
        }
        if (state == State.RUNNING) {
            breakLeft = BREAK_SECONDS;
            if (alive.size() > 1) {
                Msg.all(online(), "<gray>" + alive.size() + " players left. Next round in " + BREAK_SECONDS + "...");
            }
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (event.getCause() == EntityDamageEvent.DamageCause.VOID) {
            return;
        }
        if (event.getCause() != EntityDamageEvent.DamageCause.ENTITY_ATTACK || attacker == null || attacker.equals(victim)) {
            event.setCancelled(true);
            return;
        }
        // hits only knock back; a hair of damage makes sure the knockback is applied
        event.setDamage(0.01);
        Bukkit.getScheduler().runTask(plugin, () -> {
            if (victim.isOnline() && !victim.isDead()) {
                victim.setHealth(20);
            }
        });
        if (roundLeft > 0 && isIt(attacker) && !isIt(victim) && victim.getGameMode() == GameMode.SURVIVAL) {
            long since = System.currentTimeMillis() - taggedAt.getOrDefault(attacker.getUniqueId(), 0L);
            if (since < TAG_BACK_MS) {
                return; // just got it - no instant tag-backs
            }
            runner(attacker);
            tag(victim);
            Msg.all(online(), "<red>" + attacker.getName() + " <gray>passed the TNT to <red>" + victim.getName() + "<gray>!");
            Msg.actionBar(attacker, "<green>Phew! You passed the TNT.");
        }
    }

    @Override
    public void onInventoryClick(InventoryClickEvent event) {
        if (event.getSlotType() == InventoryType.SlotType.ARMOR || isItSlot(event)) {
            event.setCancelled(true);
        }
    }

    private boolean isItSlot(InventoryClickEvent event) {
        return event.getCurrentItem() != null && event.getCurrentItem().getType() == Material.TNT;
    }

    @Override
    protected void onSecond() {
        if (state != State.RUNNING) {
            return;
        }
        if (breakLeft > 0) {
            bossBar("<yellow>Next round in <white>" + breakLeft + "s <dark_gray>| <green>" + alive.size() + " alive",
                    1f, BossBar.Color.YELLOW);
            if (--breakLeft == 0) {
                startRound();
            }
            return;
        }
        if (roundLeft <= 0) {
            return;
        }
        roundLeft--;
        bossBar("<red><bold>TNT</bold> <white>explodes in " + roundLeft + "s <dark_gray>| <yellow>Round " + round
                + " <dark_gray>| <green>" + alive.size() + " alive", (float) roundLeft / roundLength, BossBar.Color.RED);
        for (Player p : alivePlayers()) {
            Msg.actionBar(p, isIt(p) ? "<red><bold>YOU HAVE THE TNT!</bold> <white>" + roundLeft + "s - hit someone!"
                    : "<green>Run! <white>" + roundLeft + "s");
        }
        if (roundLeft <= 5 && roundLeft > 0) {
            Msg.sound(online(), "block.note_block.hat", 2f - roundLeft * 0.2f);
        }
        if (roundLeft == 0) {
            explode();
        }
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        // only the void can kill here (the barrier wall keeps everyone on the island)
        boolean hadTnt = it.remove(victim.getUniqueId());
        super.onDeath(victim, killer);
        if (hadTnt) {
            reassignIfNeeded();
        }
    }

    @Override
    protected void onLeaveRunning(Player player) {
        boolean hadTnt = it.remove(player.getUniqueId());
        super.onLeaveRunning(player);
        if (hadTnt) {
            reassignIfNeeded();
        }
    }

    /** Someone holding the TNT left - hand it to somebody else so the round still means something. */
    private void reassignIfNeeded() {
        if (state != State.RUNNING || roundLeft <= 2 || !it.isEmpty()) {
            return;
        }
        List<Player> left = alivePlayers();
        if (left.size() > 1) {
            Player next = left.get(random.nextInt(left.size()));
            tag(next);
            Msg.all(online(), "<red>" + next.getName() + " <gray>got the TNT!");
        }
    }

    /** /fc skip: end the break, or blow up the TNT holders right now. */
    @Override
    protected boolean onSkip() {
        if (breakLeft > 0) {
            breakLeft = 1;
        } else if (roundLeft > 0) {
            roundLeft = 1;
        } else {
            return false;
        }
        return true;
    }

    @Override
    protected int timeLimit() {
        return 0;
    }

    @Override
    protected String objective() {
        return "Pass the TNT before it blows!";
    }

    @Override
    protected double voidLevel() {
        return Y - 20;
    }

    @Override
    protected Location spectatorSpawn() {
        return center.clone().add(0, 14, 0);
    }

    @Override
    protected List<String> extraSidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<white>Round: <yellow>" + Math.max(1, round));
        if (isAlive(player) && player.getGameMode() == GameMode.SURVIVAL) {
            lines.add(isIt(player) ? "<red><bold>YOU HAVE THE TNT" : "<green>Runner");
        }
        return lines;
    }

    @Override
    protected void cleanup() {
        super.cleanup();
        it.clear();
        taggedAt.clear();
    }
}
