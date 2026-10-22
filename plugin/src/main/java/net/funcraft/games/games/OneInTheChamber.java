package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
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
import org.bukkit.entity.AbstractArrow;
import org.bukkit.entity.Arrow;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDamageByEntityEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.entity.ProjectileHitEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * One in the Chamber: a sword, a bow and a single arrow. Arrows kill in one hit and every kill
 * gives you another arrow. You respawn after dying; first to {@link #KILLS_TO_WIN} kills wins.
 */
public final class OneInTheChamber extends Game {

    private static final int Y = 64;
    private static final int RADIUS = 26;
    private static final int KILLS_TO_WIN = 15;
    private static final int TIME_LIMIT = 420;
    private static final int RESPAWN_SECONDS = 3;

    private final List<Location> spawns = new ArrayList<>();
    private final Map<UUID, Integer> respawning = new HashMap<>();

    public OneInTheChamber(FunCraft plugin, int id) {
        super(plugin, id, GameType.OITC);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-RADIUS - 10, -RADIUS - 10, RADIUS + 10, RADIUS + 10};
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + " Ruins";
        theme.island(world, 0, Y, 0, RADIUS + 3, random);
        // scattered ruins for cover
        for (int i = 0; i < 26; i++) {
            double a = random.nextDouble() * Math.PI * 2;
            double d = 5 + random.nextDouble() * (RADIUS - 7);
            int x = (int) Math.round(Math.cos(a) * d);
            int z = (int) Math.round(Math.sin(a) * d);
            int h = 2 + random.nextInt(3);
            boolean wallAlongX = random.nextBoolean();
            int len = 2 + random.nextInt(4);
            for (int j = 0; j < len; j++) {
                int bx = wallAlongX ? x + j : x;
                int bz = wallAlongX ? z : z + j;
                int bh = Math.max(1, h - random.nextInt(2));
                Build.fill(world, bx, Y + 1, bz, bx, Y + bh, bz, random.nextInt(4) == 0 ? theme.accent : theme.trim);
            }
        }
        for (int i = 0; i < 4; i++) {
            double a = Math.toRadians(i * 90 + 45);
            int x = (int) Math.round(Math.cos(a) * RADIUS * 0.55);
            int z = (int) Math.round(Math.sin(a) * RADIUS * 0.55);
            if (i % 2 == 0) {
                Structures.house(world, x, Y + 1, z, theme, random);
            } else {
                Structures.tower(world, x, Y + 1, z, 5, theme);
            }
        }
        for (int i = 0; i < 6; i++) {
            double a = Math.toRadians(i * 60 + 30);
            theme.tree(world, (int) Math.round(Math.cos(a) * (RADIUS - 2)), Y + 1, (int) Math.round(Math.sin(a) * (RADIUS - 2)), random);
        }
        theme.plants(world, 0, Y, 0, RADIUS, 40, random);
        // spawn points: open ground spread over the map
        for (int i = 0; i < 16; i++) {
            double a = Math.toRadians(i * 22.5);
            double d = i % 2 == 0 ? RADIUS - 5 : RADIUS / 2.0;
            int x = (int) Math.round(Math.cos(a) * d);
            int z = (int) Math.round(Math.sin(a) * d);
            Build.fill(world, x, Y + 1, z, x, Y + 3, z, Material.AIR);
            spawns.add(Build.lookAt(new Location(world, x + 0.5, Y + 1, z + 0.5), new Location(world, 0.5, Y + 1, 0.5)));
        }
    }

    @Override
    protected void onStart(List<Player> list) {
        for (Player p : list) {
            spawn(p);
            Msg.title(p, "<gold><bold>One in the Chamber", "<gray>Arrows kill in one hit - first to " + KILLS_TO_WIN + " kills", 5, 60, 10);
        }
        Msg.all(list, "<gray>Every kill gives you another arrow. Don't miss!");
    }

    private void spawn(Player p) {
        Location far = spawns.get(random.nextInt(spawns.size()));
        double best = -1;
        for (Location s : spawns) {
            double nearest = Double.MAX_VALUE;
            for (Player other : alivePlayers()) {
                if (!other.equals(p) && other.getWorld() == world && other.getGameMode() != GameMode.SPECTATOR) {
                    nearest = Math.min(nearest, other.getLocation().distanceSquared(s));
                }
            }
            if (nearest > best) {
                best = nearest;
                far = s;
            }
        }
        plugin.games().prepare(p, GameMode.SURVIVAL);
        p.teleport(far);
        p.getInventory().setItem(0, ItemBuilder.of(Material.STONE_SWORD).unbreakable().build());
        p.getInventory().setItem(1, ItemBuilder.of(Material.BOW).name("<gold>The Chamber").unbreakable().build());
        p.getInventory().setItem(8, new ItemStack(Material.ARROW, 1));
        p.addPotionEffect(new PotionEffect(PotionEffectType.RESISTANCE, 40, 4, false, false));
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (event.getCause() == EntityDamageEvent.DamageCause.FALL) {
            event.setCancelled(true);
            return;
        }
        if (event instanceof EntityDamageByEntityEvent byEntity && byEntity.getDamager() instanceof Arrow
                && attacker != null && !attacker.equals(victim)) {
            event.setDamage(1000); // one shot
        }
    }

    @Override
    public void onProjectileHit(ProjectileHitEvent event) {
        if (event.getEntity() instanceof AbstractArrow arrow) {
            // next tick, so the hit still counts; arrows can't be picked back up
            Bukkit.getScheduler().runTask(plugin, arrow::remove);
        }
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        deathMessage(victim, killer, null);
        if (killer != null && isAlive(killer)) {
            killer.getInventory().addItem(new ItemStack(Material.ARROW));
            int k = kills.getOrDefault(killer.getUniqueId(), 0);
            if (k >= KILLS_TO_WIN) {
                end(killer.getName(), List.of(killer.getUniqueId()));
                return;
            }
            if (k == KILLS_TO_WIN - 3) {
                Msg.all(online(), "<gold>" + killer.getName() + " <yellow>needs just 3 more kills!");
            }
        }
        victim.getInventory().clear();
        victim.setGameMode(GameMode.SPECTATOR);
        victim.teleport(spectatorSpawn());
        respawning.put(victim.getUniqueId(), RESPAWN_SECONDS);
        Msg.title(victim, "<red><bold>YOU DIED", "<gray>Respawning in " + RESPAWN_SECONDS + "...", 0, 30, 5);
    }

    @Override
    protected void onSecond() {
        for (Map.Entry<UUID, Integer> e : new ArrayList<>(respawning.entrySet())) {
            Player p = Bukkit.getPlayer(e.getKey());
            if (p == null || !isAlive(p)) {
                respawning.remove(e.getKey());
            } else if (e.getValue() <= 1) {
                respawning.remove(e.getKey());
                spawn(p);
            } else {
                respawning.put(e.getKey(), e.getValue() - 1);
            }
        }
        int left = TIME_LIMIT - elapsed;
        UUID leader = leader();
        Player lp = leader == null ? null : Bukkit.getPlayer(leader);
        bossBar("<white>Leader: <gold>" + (lp == null ? "-" : lp.getName() + " (" + kills.get(leader) + ")")
                + " <dark_gray>| <yellow>" + Msg.time(left), (float) left / TIME_LIMIT, BossBar.Color.RED);
        if (left <= 0) {
            if (lp == null) {
                end(null, List.of());
            } else {
                end(lp.getName(), List.of(leader));
            }
        }
    }

    private UUID leader() {
        UUID best = null;
        int most = 0;
        for (Map.Entry<UUID, Integer> e : kills.entrySet()) {
            if (e.getValue() > most && players.contains(e.getKey())) {
                most = e.getValue();
                best = e.getKey();
            }
        }
        return best;
    }

    @Override
    protected void checkWin() {
        // kill race: only ends when someone leaves everyone else
        if (state == State.RUNNING && alive.size() == 1 && startingPlayers > 1) {
            UUID last = alive.iterator().next();
            Player p = Bukkit.getPlayer(last);
            end(p == null ? "?" : p.getName(), List.of(last));
        }
    }

    @Override
    protected boolean allowHunger() {
        return false;
    }

    @Override
    protected double voidLevel() {
        return Y - 25;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 0.5, Y + 22, 0.5, 0, 70);
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        lines.add("<white>First to <gold>" + KILLS_TO_WIN + "</gold> kills");
        lines.add("  ");
        List<Map.Entry<UUID, Integer>> top = new ArrayList<>(kills.entrySet());
        top.removeIf(e -> !players.contains(e.getKey()));
        top.sort((a, b) -> b.getValue() - a.getValue());
        for (int i = 0; i < Math.min(5, top.size()); i++) {
            Player p = Bukkit.getPlayer(top.get(i).getKey());
            lines.add("<yellow>" + (i + 1) + ". <white>" + (p == null ? "?" : p.getName()) + " <gray>" + top.get(i).getValue());
        }
        lines.add("   ");
        lines.add("<white>Your kills: <green>" + kills.getOrDefault(player.getUniqueId(), 0));
        return lines;
    }

    @Override
    protected void cleanup() {
        respawning.clear();
    }
}
