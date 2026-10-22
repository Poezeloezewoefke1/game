package net.funcraft.games.util;

import org.bukkit.Material;
import org.bukkit.World;
import org.bukkit.block.Block;
import org.bukkit.block.BlockFace;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/**
 * Small buildings placed on generated maps so they don't look empty. Every method takes the
 * position of the ground block's top (the structure stands on y) and a {@link Theme} for materials.
 * Methods that build containers return the chest blocks so games can fill them.
 */
public final class Structures {

    private Structures() {
    }

    /** 5x5 cottage with a door gap, windows, a pitched roof and a lantern. Returns its chest. */
    public static Block house(World w, int x, int y, int z, Theme t, Random r) {
        Material wall = t.planks();
        Build.fill(w, x - 2, y - 1, z - 2, x + 2, y - 1, z + 2, t.path);
        Build.walls(w, x - 2, y, z - 2, x + 2, y + 2, z + 2, wall);
        for (int[] c : new int[][]{{-2, -2}, {2, -2}, {-2, 2}, {2, 2}}) {
            Build.fill(w, x + c[0], y, z + c[1], x + c[0], y + 2, z + c[1], t.log());
        }
        Build.fill(w, x - 1, y, z + 2, x - 1, y + 1, z + 2, Material.AIR); // door
        Build.set(w, x + 2, y + 1, z, Material.GLASS);
        Build.set(w, x - 2, y + 1, z, Material.GLASS);
        Build.set(w, x + 1, y + 1, z - 2, Material.GLASS);
        // roof: two stepped layers
        Build.fill(w, x - 3, y + 3, z - 3, x + 3, y + 3, z + 3, t.roof());
        Build.fill(w, x - 2, y + 4, z - 2, x + 2, y + 4, z + 2, t.roof());
        Build.fill(w, x - 1, y + 5, z - 1, x + 1, y + 5, z + 1, t.roof());
        Build.set(w, x, y + 6, z, t.light());
        Build.directional(w, x + 1, y, z - 1, Material.CHEST, BlockFace.SOUTH);
        Build.set(w, x - 1, y, z - 1, Material.CRAFTING_TABLE);
        return w.getBlockAt(x + 1, y, z - 1);
    }

    /** Hollow 3x3 tower with a ladder and a lookout platform. */
    public static void tower(World w, int x, int y, int z, int height, Theme t) {
        Build.walls(w, x - 1, y, z - 1, x + 1, y + height, z + 1, t.trim);
        Build.fill(w, x, y, z, x, y + height, z, Material.AIR);
        for (int i = 0; i <= height; i++) {
            Build.directional(w, x, y + i, z, Material.LADDER, BlockFace.SOUTH);
        }
        Build.set(w, x, y, z + 1, Material.AIR);
        Build.set(w, x, y + 1, z + 1, Material.AIR);
        int top = y + height + 1;
        Build.fill(w, x - 2, top, z - 2, x + 2, top, z + 2, t.planks());
        Build.set(w, x, top, z, Material.AIR);
        for (int[] c : new int[][]{{-2, -2}, {2, -2}, {-2, 2}, {2, 2}, {0, -2}, {0, 2}, {-2, 0}, {2, 0}}) {
            Build.set(w, x + c[0], top + 1, z + c[1], t.trim);
        }
        Build.set(w, x - 2, top + 2, z - 2, t.light());
        Build.set(w, x + 2, top + 2, z + 2, t.light());
    }

    /** A little well with water and a roof on posts. */
    public static void well(World w, int x, int y, int z, Theme t) {
        Build.fill(w, x - 1, y - 1, z - 1, x + 1, y - 1, z + 1, t.trim);
        Build.walls(w, x - 1, y, z - 1, x + 1, y, z + 1, t.trim);
        Build.set(w, x, y, z, Material.WATER);
        for (int[] c : new int[][]{{-1, -1}, {1, -1}, {-1, 1}, {1, 1}}) {
            Build.fill(w, x + c[0], y + 1, z + c[1], x + c[0], y + 2, z + c[1], t.log());
        }
        Build.fill(w, x - 1, y + 3, z - 1, x + 1, y + 3, z + 1, t.roof());
    }

    /** Crumbling walls and a broken arch. */
    public static void ruins(World w, int x, int y, int z, Theme t, Random r) {
        for (int i = -2; i <= 2; i++) {
            int h = 1 + r.nextInt(4);
            Build.fill(w, x + i, y, z - 2, x + i, y + h - 1, z - 2, r.nextInt(3) == 0 ? t.accent : t.trim);
            int h2 = 1 + r.nextInt(3);
            Build.fill(w, x - 2, y, z + i, x - 2, y + h2 - 1, z + i, r.nextInt(3) == 0 ? t.accent : t.trim);
        }
        Build.fill(w, x + 2, y, z + 2, x + 2, y + 3, z + 2, t.trim);
        Build.fill(w, x + 2, y + 3, z, x + 2, y + 3, z + 2, t.trim);
    }

    /** Lamp post. */
    public static void lamp(World w, int x, int y, int z, Theme t) {
        Build.fill(w, x, y, z, x, y + 2, z, t.log());
        Build.set(w, x, y + 3, z, t.light());
    }

    /**
     * A castle for the middle of a map: curtain wall with battlements, four corner towers, a gate on
     * each side and a central keep. Returns the chests (keep + towers).
     */
    public static List<Block> castle(World w, int cx, int y, int cz, int half, Theme t, Random r) {
        List<Block> chests = new ArrayList<>();
        Build.fill(w, cx - half, y - 1, cz - half, cx + half, y - 1, cz + half, t.path);
        Build.walls(w, cx - half, y, cz - half, cx + half, y + 3, cz + half, t.trim);
        for (int i = -half; i <= half; i += 2) {
            Build.set(w, cx + i, y + 4, cz - half, t.trim);
            Build.set(w, cx + i, y + 4, cz + half, t.trim);
            Build.set(w, cx - half, y + 4, cz + i, t.trim);
            Build.set(w, cx + half, y + 4, cz + i, t.trim);
        }
        // gates
        for (int[] g : new int[][]{{0, -half}, {0, half}, {-half, 0}, {half, 0}}) {
            Build.fill(w, cx + g[0] - (g[0] == 0 ? 1 : 0), y, cz + g[1] - (g[1] == 0 ? 1 : 0),
                    cx + g[0] + (g[0] == 0 ? 1 : 0), y + 2, cz + g[1] + (g[1] == 0 ? 1 : 0), Material.AIR);
        }
        for (int[] c : new int[][]{{-half, -half}, {half, -half}, {-half, half}, {half, half}}) {
            tower(w, cx + c[0], y, cz + c[1], 6, t);
        }
        // keep
        int k = Math.max(2, half / 3);
        Build.walls(w, cx - k, y, cz - k, cx + k, y + 6, cz + k, t.planks());
        for (int[] c : new int[][]{{-k, -k}, {k, -k}, {-k, k}, {k, k}}) {
            Build.fill(w, cx + c[0], y, cz + c[1], cx + c[0], y + 7, cz + c[1], t.log());
        }
        Build.fill(w, cx - k, y + 7, cz - k, cx + k, y + 7, cz + k, t.roof());
        Build.fill(w, cx - 1, y, cz + k, cx + 1, y + 2, cz + k, Material.AIR);
        Build.fill(w, cx - 1, y, cz - k, cx + 1, y + 2, cz - k, Material.AIR);
        Build.set(w, cx, y + 8, cz, t.light());
        Build.set(w, cx - k + 1, y + 3, cz - k + 1, t.light());
        Build.set(w, cx + k - 1, y + 3, cz + k - 1, t.light());
        Build.directional(w, cx - 1, y, cz, Material.CHEST, BlockFace.EAST);
        Build.directional(w, cx + 1, y, cz, Material.CHEST, BlockFace.WEST);
        chests.add(w.getBlockAt(cx - 1, y, cz));
        chests.add(w.getBlockAt(cx + 1, y, cz));
        // courtyard decoration
        lamp(w, cx - half + 3, y, cz - half + 3, t);
        lamp(w, cx + half - 3, y, cz + half - 3, t);
        lamp(w, cx - half + 3, y, cz + half - 3, t);
        lamp(w, cx + half - 3, y, cz - half + 3, t);
        return chests;
    }

    /** A random small structure that fits on an island of at least radius 4. Returns a chest or null. */
    public static Block random(World w, int x, int y, int z, Theme t, Random r) {
        switch (r.nextInt(4)) {
            case 0 -> {
                return house(w, x, y, z, t, r);
            }
            case 1 -> tower(w, x, y, z, 4 + r.nextInt(3), t);
            case 2 -> well(w, x, y, z, t);
            default -> ruins(w, x, y, z, t, r);
        }
        return null;
    }
}
