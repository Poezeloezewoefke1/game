package net.funcraft.games.util;

import org.bukkit.Material;
import org.bukkit.World;
import org.bukkit.block.Block;
import org.bukkit.block.data.BlockData;
import org.bukkit.block.data.type.Leaves;

import java.util.Random;

/** Block palettes for floating-island maps, so every match looks a little different. */
public enum Theme {

    PLAINS("Plains", Material.GRASS_BLOCK, Material.DIRT, Material.STONE, Material.ANDESITE, Material.POLISHED_ANDESITE,
            Material.STONE_BRICKS, Tree.OAK, Material.POPPY, Material.DANDELION, Material.CORNFLOWER),
    DESERT("Desert", Material.SAND, Material.SANDSTONE, Material.SANDSTONE, Material.TERRACOTTA, Material.SMOOTH_SANDSTONE,
            Material.CUT_SANDSTONE, Tree.CACTUS, Material.DEAD_BUSH),
    SNOWY("Snowy", Material.SNOW_BLOCK, Material.DIRT, Material.STONE, Material.PACKED_ICE, Material.POLISHED_DIORITE,
            Material.PACKED_ICE, Tree.SPRUCE),
    NETHER("Nether", Material.CRIMSON_NYLIUM, Material.NETHERRACK, Material.NETHERRACK, Material.BLACKSTONE,
            Material.POLISHED_BLACKSTONE_BRICKS, Material.NETHER_BRICKS, Tree.FUNGUS, Material.CRIMSON_ROOTS, Material.CRIMSON_FUNGUS),
    END("The End", Material.END_STONE, Material.END_STONE, Material.END_STONE, Material.OBSIDIAN, Material.PURPUR_BLOCK,
            Material.END_STONE_BRICKS, Tree.CHORUS),
    MUSHROOM("Mushroom", Material.MYCELIUM, Material.DIRT, Material.STONE, Material.TUFF, Material.POLISHED_TUFF,
            Material.TUFF_BRICKS, Tree.MUSHROOM, Material.RED_MUSHROOM, Material.BROWN_MUSHROOM),
    CHERRY("Cherry Blossom", Material.GRASS_BLOCK, Material.DIRT, Material.STONE, Material.CALCITE, Material.SMOOTH_QUARTZ,
            Material.QUARTZ_BRICKS, Tree.CHERRY, Material.PINK_TULIP, Material.ALLIUM, Material.LILY_OF_THE_VALLEY);

    public enum Tree { OAK, SPRUCE, CACTUS, FUNGUS, CHORUS, MUSHROOM, CHERRY }

    private final String displayName;
    public final Material top;
    public final Material soil;
    public final Material stone;
    public final Material accent;
    /** Paved plazas. */
    public final Material path;
    /** Borders and trims. */
    public final Material trim;
    public final Tree tree;
    private final Material[] plants;

    Theme(String displayName, Material top, Material soil, Material stone, Material accent, Material path, Material trim,
          Tree tree, Material... plants) {
        this.displayName = displayName;
        this.top = top;
        this.soil = soil;
        this.stone = stone;
        this.accent = accent;
        this.path = path;
        this.trim = trim;
        this.tree = tree;
        this.plants = plants;
    }

    public String displayName() {
        return displayName;
    }

    public static Theme random(Random random) {
        Theme[] all = values();
        return all[random.nextInt(all.length)];
    }

    /** A floating island in this theme. */
    public void island(World w, int cx, int y, int cz, double radius, Random random) {
        int depth = (int) Math.max(3, radius * 0.9);
        for (int d = 0; d <= depth; d++) {
            double t = (double) d / depth;
            double r = radius * Math.pow(1 - t, 0.75);
            if (r < 0.6) {
                break;
            }
            int ir = (int) Math.ceil(r);
            for (int x = -ir; x <= ir; x++) {
                for (int z = -ir; z <= ir; z++) {
                    double jitter = d == 0 ? 0 : random.nextDouble() * 1.2;
                    if (x * x + z * z <= (r - jitter) * (r - jitter) + 0.5) {
                        Material m = d == 0 ? top : d <= 2 ? soil : random.nextInt(6) == 0 ? accent : stone;
                        w.getBlockAt(cx + x, y - d, cz + z).setType(m, false);
                    }
                }
            }
        }
    }

    /** Scatters plants on the island's top layer. */
    public void plants(World w, int cx, int y, int cz, double radius, int count, Random random) {
        if (plants.length == 0) {
            return;
        }
        for (int i = 0; i < count; i++) {
            int x = cx + (int) Math.round((random.nextDouble() * 2 - 1) * radius);
            int z = cz + (int) Math.round((random.nextDouble() * 2 - 1) * radius);
            if (w.getBlockAt(x, y, z).getType() == top && w.getBlockAt(x, y + 1, z).getType().isAir()) {
                w.getBlockAt(x, y + 1, z).setType(plants[random.nextInt(plants.length)], false);
            }
        }
    }

    /** A decoration tree standing on (x, y-1, z). */
    public void tree(World w, int x, int y, int z, Random random) {
        switch (tree) {
            case OAK -> Build.tree(w, x, y, z, random);
            case SPRUCE -> {
                int h = 6 + random.nextInt(2);
                Build.fill(w, x, y, z, x, y + h - 1, z, Material.SPRUCE_LOG);
                for (int dy = 2; dy <= h; dy++) {
                    int r = dy == h ? 0 : (h - dy) % 2 == 0 ? 1 : 2;
                    leaves(w, x, y + dy, z, r, Material.SPRUCE_LEAVES, false);
                }
                w.getBlockAt(x, y + h, z).setBlockData(persistent(Material.SPRUCE_LEAVES), false);
            }
            case CACTUS -> {
                w.getBlockAt(x, y - 1, z).setType(Material.SAND, false);
                Build.fill(w, x, y, z, x, y + 1 + random.nextInt(2), z, Material.CACTUS);
            }
            case FUNGUS -> {
                int h = 4 + random.nextInt(2);
                Build.fill(w, x, y, z, x, y + h - 1, z, Material.CRIMSON_STEM);
                leaves(w, x, y + h - 1, z, 2, Material.NETHER_WART_BLOCK, true);
                leaves(w, x, y + h, z, 1, Material.NETHER_WART_BLOCK, false);
                w.getBlockAt(x + 1, y + h - 2, z).setType(Material.SHROOMLIGHT, false);
            }
            case CHORUS -> {
                int h = 3 + random.nextInt(3);
                Build.fill(w, x, y, z, x, y + h - 1, z, Material.PURPUR_PILLAR);
                w.getBlockAt(x, y + h, z).setType(Material.END_ROD, false);
            }
            case MUSHROOM -> {
                int h = 4 + random.nextInt(2);
                Build.fill(w, x, y, z, x, y + h - 1, z, Material.MUSHROOM_STEM);
                leaves(w, x, y + h, z, 2, random.nextBoolean() ? Material.RED_MUSHROOM_BLOCK : Material.BROWN_MUSHROOM_BLOCK, true);
            }
            case CHERRY -> {
                int h = 4 + random.nextInt(2);
                Build.fill(w, x, y, z, x, y + h - 1, z, Material.CHERRY_LOG);
                leaves(w, x, y + h - 1, z, 2, Material.CHERRY_LEAVES, true);
                leaves(w, x, y + h, z, 1, Material.CHERRY_LEAVES, false);
            }
        }
    }

    private static void leaves(World w, int x, int y, int z, int r, Material m, boolean roundCorners) {
        BlockData data = persistent(m);
        for (int dx = -r; dx <= r; dx++) {
            for (int dz = -r; dz <= r; dz++) {
                if (roundCorners && r > 0 && Math.abs(dx) == r && Math.abs(dz) == r) {
                    continue;
                }
                Block b = w.getBlockAt(x + dx, y, z + dz);
                if (b.getType().isAir()) {
                    b.setBlockData(data, false);
                }
            }
        }
    }

    private static BlockData persistent(Material m) {
        BlockData data = m.createBlockData();
        if (data instanceof Leaves l) {
            l.setPersistent(true);
        }
        return data;
    }
}
