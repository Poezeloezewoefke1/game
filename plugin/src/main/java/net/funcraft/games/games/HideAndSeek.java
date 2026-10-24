package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Arenas;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Theme;
import net.kyori.adventure.bossbar.BossBar;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.Particle;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * Hide and Seek in a big village. Hiders get 30 seconds to hide while the seekers wait in a box in
 * the sky. Seekers glow and carry a sword; one hit finds a hider, who then becomes a seeker too.
 * Name tags are hidden. Hiders win if anyone is still hidden when time runs out.
 */
public final class HideAndSeek extends Game {

    private static final int Y = 64;
    private static final int RADIUS = 30;
    private static final int HIDE_SECONDS = 30;
    private static final int SEEK_SECONDS = 240;
    private static final int BOX_Y = Y + 40;

    private final Set<UUID> seekers = new LinkedHashSet<>();
    private final Set<UUID> firstSeekers = new LinkedHashSet<>();
    private final List<Location> spawns = new ArrayList<>();
    private int hideLeft;

    public HideAndSeek(FunCraft plugin, int id) {
        super(plugin, id, GameType.HIDE_AND_SEEK);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-RADIUS - 6, -RADIUS - 6, RADIUS + 6, RADIUS + 6};
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + " Hamlet";
        spawns.addAll(Arenas.village(world, theme, random, Y, RADIUS));
        // the seekers' waiting box, high up
        Build.fill(world, -3, BOX_Y - 1, -3, 3, BOX_Y + 3, 3, Material.BLACK_CONCRETE);
        Build.fill(world, -2, BOX_Y, -2, 2, BOX_Y + 2, 2, Material.AIR);
    }

    private boolean isSeeker(Player p) {
        return seekers.contains(p.getUniqueId());
    }

    @Override
    protected void onStart(List<Player> list) {
        List<Player> shuffled = new ArrayList<>(list);
        Collections.shuffle(shuffled, random);
        int count = list.size() >= 8 ? 2 : 1;
        for (int i = 0; i < count && i < shuffled.size(); i++) {
            seekers.add(shuffled.get(i).getUniqueId());
            firstSeekers.add(shuffled.get(i).getUniqueId());
        }
        for (Player viewer : list) {
            for (Player other : list) {
                plugin.sidebars().of(viewer).hideNameTag(other.getName());
            }
        }
        int i = 0;
        for (Player p : shuffled) {
            if (isSeeker(p)) {
                p.teleport(new Location(world, 0.5, BOX_Y, 0.5));
                p.addPotionEffect(new PotionEffect(PotionEffectType.BLINDNESS, 20 * (HIDE_SECONDS + 1), 0, false, false));
                Msg.title(p, "<red><bold>You are a SEEKER", "<gray>Wait " + HIDE_SECONDS + " seconds, then find them all!", 5, 60, 10);
            } else {
                p.teleport(spawns.get(i++ % spawns.size()));
                p.addPotionEffect(new PotionEffect(PotionEffectType.SPEED, 20 * HIDE_SECONDS, 1, false, false));
                Msg.title(p, "<green><bold>You are a HIDER", "<gray>You have " + HIDE_SECONDS + " seconds to hide!", 5, 60, 10);
            }
        }
        Msg.all(list, "<gray>Seekers: <red>" + names(seekers) + "<gray>. Hiders, go hide! Name tags are hidden.");
        hideLeft = HIDE_SECONDS;
    }

    private String names(Set<UUID> ids) {
        List<String> names = new ArrayList<>();
        for (UUID id : ids) {
            Player p = Bukkit.getPlayer(id);
            if (p != null) {
                names.add(p.getName());
            }
        }
        return String.join(", ", names);
    }

    private void arm(Player seeker) {
        seeker.getInventory().clear();
        seeker.getInventory().setItem(0, ItemBuilder.of(Material.IRON_SWORD).name("<red>Seeker's Sword").unbreakable().build());
        seeker.addPotionEffect(new PotionEffect(PotionEffectType.GLOWING, PotionEffect.INFINITE_DURATION, 0, false, false));
        seeker.addPotionEffect(new PotionEffect(PotionEffectType.SPEED, PotionEffect.INFINITE_DURATION, 0, false, false));
    }

    private void release() {
        for (Player p : alivePlayers()) {
            if (isSeeker(p)) {
                p.removePotionEffect(PotionEffectType.BLINDNESS);
                p.teleport(new Location(world, 0.5, Y + 1, 5.5));
                arm(p);
            }
        }
        Msg.title(online(), "<red><bold>READY OR NOT...", "<gray>Here they come!");
        Msg.sound(online(), "entity.wither.spawn", 1.5f);
    }

    private List<Player> hiders() {
        List<Player> list = new ArrayList<>();
        for (Player p : alivePlayers()) {
            if (!isSeeker(p)) {
                list.add(p);
            }
        }
        return list;
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        event.setCancelled(true);
        if (event.getCause() == EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(false);
            return;
        }
        if (hideLeft > 0 || attacker == null || event.getCause() != EntityDamageEvent.DamageCause.ENTITY_ATTACK
                || !isSeeker(attacker) || isSeeker(victim)) {
            return;
        }
        seekers.add(victim.getUniqueId());
        kills.merge(attacker.getUniqueId(), 1, Integer::sum);
        plugin.stats().addKill(attacker, type);
        plugin.stats().addDeath(victim, type);
        int left = hiders().size();
        Msg.all(online(), "<red>" + victim.getName() + " <gray>was found by <red>" + attacker.getName() + "<gray>! "
                + (left == 0 ? "" : "<green>" + left + " hider" + (left == 1 ? "" : "s") + " left."));
        Msg.title(victim, "<red><bold>FOUND!", "<gray>Now you're a seeker - go find the rest!", 0, 40, 10);
        world.spawnParticle(Particle.ANGRY_VILLAGER, victim.getLocation().add(0, 2, 0), 5, 0.3, 0.3, 0.3);
        Msg.sound(online(), "entity.villager.no", 1f);
        arm(victim);
        checkWin();
    }

    @Override
    protected void checkWin() {
        if (state != State.RUNNING) {
            return;
        }
        boolean anySeeker = alivePlayers().stream().anyMatch(this::isSeeker);
        List<Player> hidersLeft = hiders();
        if (hidersLeft.isEmpty()) {
            List<UUID> winners = new ArrayList<>(firstSeekers);
            winners.retainAll(players);
            end("The Seekers", winners);
        } else if (!anySeeker && startingPlayers > 1) {
            end("The Hiders", hidersLeft.stream().map(Player::getUniqueId).toList());
        }
    }

    @Override
    protected void onSecond() {
        if (hideLeft > 0) {
            bossBar("<green>Hide! <white>Seekers come out in " + hideLeft + "s", (float) hideLeft / HIDE_SECONDS, BossBar.Color.GREEN);
            if (hideLeft <= 5) {
                Msg.sound(online(), "block.note_block.hat", 1.5f);
            }
            if (--hideLeft == 0) {
                release();
            }
            return;
        }
        int seeking = elapsed - HIDE_SECONDS;
        int left = SEEK_SECONDS - seeking;
        List<Player> hidersLeft = hiders();
        bossBar("<red>Seekers are out! <dark_gray>| <green>" + hidersLeft.size() + " hiding <dark_gray>| <white>" + Msg.time(left),
                (float) Math.max(0, left) / SEEK_SECONDS, BossBar.Color.RED);
        // in the last minute, hiders give themselves away every 15 seconds
        if (left <= 60 && left > 0 && left % 15 == 0) {
            for (Player h : hidersLeft) {
                world.spawnParticle(Particle.FIREWORK, h.getLocation().add(0, 2.5, 0), 40, 0.2, 1.5, 0.2, 0.05);
                world.playSound(h.getLocation(), "entity.firework_rocket.twinkle", 2f, 1f);
            }
            Msg.all(online(), "<yellow>The hiders made a noise! Listen and look for sparkles!");
        }
        if (left <= 0) {
            end("The Hiders", hidersLeft.stream().map(Player::getUniqueId).toList());
        }
    }

    /** /fc skip: let the seekers out now. */
    @Override
    protected boolean onSkip() {
        if (hideLeft > 1) {
            hideLeft = 1;
            return true;
        }
        return false;
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        // only the void can kill here; just put them back in the village
        victim.teleport(spawns.get(random.nextInt(spawns.size())));
    }

    @Override
    protected double voidLevel() {
        return Y - 25;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 0.5, Y + 25, 0.5, 0, 80);
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        lines.add(isSeeker(player) ? "<red><bold>SEEKER" : "<green><bold>HIDER");
        lines.add("  ");
        lines.add("<white>Hiders left: <green>" + hiders().size());
        lines.add("<white>Seekers: <red>" + (alive.size() - hiders().size()));
        lines.add("<white>Time: <yellow>" + Msg.time(hideLeft > 0 ? hideLeft : SEEK_SECONDS - (elapsed - HIDE_SECONDS)));
        if (isSeeker(player)) {
            lines.add("   ");
            lines.add("<white>Found: <red>" + kills.getOrDefault(player.getUniqueId(), 0));
        }
        return lines;
    }

    @Override
    protected void cleanup() {
        seekers.clear();
        firstSeekers.clear();
    }

    @Override
    public void botTick(Player bot, net.funcraft.games.bots.BotBrain brain) {
        if (isSeeker(bot)) {
            if (hideLeft > 0) {
                return;
            }
            Player hider = null;
            double best = Double.MAX_VALUE;
            for (Player p : hiders()) {
                double d = p.getLocation().distanceSquared(bot.getLocation());
                if (d < best) {
                    best = d;
                    hider = p;
                }
            }
            if (hider == null) {
                return;
            }
            // seekers only "find" what they could plausibly see or hear
            if (best < 20 * 20 && (brain.canSee(hider) || best < 6 * 6)) {
                brain.fight(hider);
            } else {
                if (brain.timer <= 0 || !(brain.memo instanceof Location)) {
                    brain.memo = spawns.get(brain.random().nextInt(spawns.size()));
                    brain.timer = 160;
                }
                brain.moveTo((Location) brain.memo, true);
            }
            return;
        }
        if (hideLeft > 0) {
            if (!(brain.memo instanceof Location)) {
                brain.memo = spawns.get(brain.random().nextInt(spawns.size())).clone()
                        .add(brain.random().nextInt(5) - 2, 0, brain.random().nextInt(5) - 2);
            }
            brain.moveTo((Location) brain.memo, true);
            return;
        }
        for (Player p : alivePlayers()) {
            if (isSeeker(p) && p.getLocation().distanceSquared(bot.getLocation()) < 10 * 10 && brain.canSee(p)) {
                brain.moveAway(p.getLocation(), true);
                return;
            }
        }
        bot.setSneaking(true);
    }
}
