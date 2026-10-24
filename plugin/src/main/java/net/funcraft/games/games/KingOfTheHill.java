package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Arenas;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Theme;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.Particle;
import org.bukkit.entity.Player;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.PlayerInventory;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * King of the Hill: a raised hill in the middle of the map. Every second you stand on it alone you
 * score a point; if several players are on it, nobody scores. First to 100 points wins.
 */
public final class KingOfTheHill extends RespawnGame {

    private static final int GOAL = 100;
    private static final int HILL_TOP = Y + 4;
    private static final double HILL_RADIUS = 4.5;

    private final Map<UUID, Integer> points = new HashMap<>();
    private UUID king;

    public KingOfTheHill(FunCraft plugin, int id) {
        super(plugin, id, GameType.KING_OF_THE_HILL);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-34, -34, 34, 34};
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + " Hill";
        spawns.addAll(Arenas.village(world, theme, random, Y, 26));
        // the hill: stepped mound with a glowing top, replacing the village well
        Build.fill(world, -7, Y + 1, -7, 7, Y + 8, 7, Material.AIR);
        for (int step = 0; step < 4; step++) {
            double r = HILL_RADIUS + 3 - step;
            for (int y = Y + 1; y <= Y + 1 + step; y++) {
                Build.disc(world, 0, y, 0, r, step == 3 ? theme.path : theme.stone);
            }
        }
        Build.disc(world, 0, HILL_TOP, 0, HILL_RADIUS, Material.GOLD_BLOCK);
        Build.ring(world, 0, HILL_TOP, 0, HILL_RADIUS - 1, HILL_RADIUS, Material.YELLOW_CONCRETE);
        Build.set(world, 0, HILL_TOP, 0, Material.BEACON);
        Build.fill(world, -1, HILL_TOP - 1, -1, 1, HILL_TOP - 1, 1, Material.IRON_BLOCK);
    }

    @Override
    protected void loadout(Player p) {
        PlayerInventory inv = p.getInventory();
        inv.setItem(0, ItemBuilder.of(Material.STONE_SWORD).unbreakable().build());
        inv.setItem(1, ItemBuilder.of(Material.BOW).unbreakable().build());
        inv.setItem(2, ItemBuilder.of(Material.STICK).name("<gold>Knockback Stick")
                .enchant(org.bukkit.enchantments.Enchantment.KNOCKBACK, 1).build());
        inv.setItem(3, new ItemStack(Material.GOLDEN_APPLE, 2));
        inv.setItem(4, new ItemStack(Material.COOKED_BEEF, 8));
        inv.setItem(8, new ItemStack(Material.ARROW, 16));
        inv.setHelmet(ItemBuilder.of(Material.CHAINMAIL_HELMET).unbreakable().build());
        inv.setChestplate(ItemBuilder.of(Material.IRON_CHESTPLATE).unbreakable().build());
        inv.setLeggings(ItemBuilder.of(Material.CHAINMAIL_LEGGINGS).unbreakable().build());
        inv.setBoots(ItemBuilder.of(Material.CHAINMAIL_BOOTS).unbreakable().build());
    }

    private boolean onHill(Player p) {
        Location l = p.getLocation();
        double dx = l.getX() - 0.5;
        double dz = l.getZ() - 0.5;
        return p.getGameMode() == GameMode.SURVIVAL && dx * dx + dz * dz <= (HILL_RADIUS + 0.5) * (HILL_RADIUS + 0.5)
                && l.getY() >= HILL_TOP + 0.9 && l.getY() < HILL_TOP + 4;
    }

    @Override
    protected void tickGame() {
        List<Player> on = new ArrayList<>();
        for (Player p : alivePlayers()) {
            if (onHill(p)) {
                on.add(p);
            }
        }
        UUID newKing = on.size() == 1 ? on.get(0).getUniqueId() : null;
        if (on.size() == 1) {
            Player k = on.get(0);
            int pts = points.merge(newKing, 1, Integer::sum);
            Msg.actionBar(k, "<gold><bold>KING!</bold> <yellow>" + pts + "/" + GOAL + " points");
            world.spawnParticle(Particle.WAX_ON, k.getLocation().add(0, 2.2, 0), 6, 0.3, 0.2, 0.3, 0);
            if (!newKing.equals(king)) {
                Msg.all(online(), "<gold>" + k.getName() + " <yellow>is the King of the Hill!");
                Msg.sound(online(), "block.bell.use", 1.2f);
            }
            if (pts % 25 == 0 && pts < GOAL) {
                Msg.all(online(), "<gold>" + k.getName() + " <yellow>has " + pts + " points!");
            }
            checkGoal(k);
        } else if (on.size() > 1) {
            for (Player p : on) {
                Msg.actionBar(p, "<red>Contested! <gray>Knock them off the hill!");
            }
        }
        king = newKing;
    }

    @Override
    protected String bossText(String leader) {
        Player k = king == null ? null : org.bukkit.Bukkit.getPlayer(king);
        return "<gold>King: <white>" + (k == null ? "<gray>nobody" : k.getName()) + " <dark_gray>| <white>Leader: <gold>" + leader;
    }

    @Override
    protected int score(UUID player) {
        return points.getOrDefault(player, 0);
    }

    @Override
    protected int goal() {
        return GOAL;
    }

    @Override
    protected String scoreName() {
        return "points";
    }

    @Override
    protected String objective() {
        return "Stand on the hill alone to score - first to " + GOAL + "!";
    }

    @Override
    protected int timeLimit() {
        return 480;
    }

    @Override
    protected void cleanup() {
        super.cleanup();
        points.clear();
        king = null;
    }
}
