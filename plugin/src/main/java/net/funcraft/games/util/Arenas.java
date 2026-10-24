package net.funcraft.games.util;

import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.World;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/** Ready-made arenas shared by several games. */
public final class Arenas {

    private Arenas() {
    }

    /**
     * A themed village on a floating island: a plaza with a well, houses and towers in a ring,
     * trees, broken walls for cover and an invisible wall at the edge. Returns spawn points spread
     * over open ground, all looking at the middle.
     *
     * @param y      the ground level (players stand at y + 1)
     * @param radius playable radius
     */
    public static List<Location> village(World w, Theme t, Random r, int y, int radius) {
        t.island(w, 0, y, 0, radius + 3, r);
        Build.disc(w, 0, y, 0, 4.5, t.path);
        Structures.well(w, 0, y + 1, 0, t);
        // houses and towers in a ring, with paths out from the plaza
        int buildings = Math.max(4, radius / 4);
        double ringRadius = radius * 0.55;
        for (int i = 0; i < buildings; i++) {
            double a = Math.toRadians(i * 360.0 / buildings + 22.5);
            int x = (int) Math.round(Math.cos(a) * ringRadius);
            int z = (int) Math.round(Math.sin(a) * ringRadius);
            for (double d = 4; d < ringRadius - 3; d += 1) {
                Build.set(w, (int) Math.round(Math.cos(a) * d), y, (int) Math.round(Math.sin(a) * d), t.path);
            }
            if (i % 3 == 2) {
                Structures.tower(w, x, y + 1, z, 5, t);
            } else {
                Structures.house(w, x, y + 1, z, t, r);
            }
        }
        // an outer ring of extra houses on big maps
        if (radius >= 26) {
            for (int i = 0; i < buildings; i++) {
                double a = Math.toRadians(i * 360.0 / buildings + 22.5 + 180.0 / buildings);
                Structures.house(w, (int) Math.round(Math.cos(a) * (radius - 7)), y + 1, (int) Math.round(Math.sin(a) * (radius - 7)), t, r);
            }
        }
        // broken walls for cover
        for (int i = 0; i < radius; i++) {
            double a = r.nextDouble() * Math.PI * 2;
            double d = 6 + r.nextDouble() * (radius - 8);
            int x = (int) Math.round(Math.cos(a) * d);
            int z = (int) Math.round(Math.sin(a) * d);
            if (!w.getBlockAt(x, y + 1, z).getType().isAir()) {
                continue;
            }
            boolean alongX = r.nextBoolean();
            int len = 2 + r.nextInt(3);
            for (int j = 0; j < len; j++) {
                int bx = alongX ? x + j : x;
                int bz = alongX ? z : z + j;
                if (w.getBlockAt(bx, y + 1, bz).getType().isAir()) {
                    Build.fill(w, bx, y + 1, bz, bx, y + 1 + r.nextInt(2), bz, r.nextInt(4) == 0 ? t.accent : t.trim);
                }
            }
        }
        for (int i = 0; i < radius / 3; i++) {
            double a = r.nextDouble() * Math.PI * 2;
            double d = radius - 3 - r.nextDouble() * 3;
            int x = (int) Math.round(Math.cos(a) * d);
            int z = (int) Math.round(Math.sin(a) * d);
            if (w.getBlockAt(x, y + 1, z).getType().isAir()) {
                t.tree(w, x, y + 1, z, r);
            }
        }
        for (int i = 0; i < 4; i++) {
            double a = Math.toRadians(i * 90);
            Structures.lamp(w, (int) Math.round(Math.cos(a) * 6), y + 1, (int) Math.round(Math.sin(a) * 6), t);
        }
        t.plants(w, 0, y, 0, radius, radius * 2, r);
        for (int yy = y + 1; yy <= y + 14; yy++) {
            Build.ring(w, 0, yy, 0, radius + 0.5, radius + 2, Material.BARRIER);
        }
        // spawns on open ground
        List<Location> spawns = new ArrayList<>();
        Location middle = new Location(w, 0.5, y + 1, 0.5);
        for (int i = 0; i < 16; i++) {
            double a = Math.toRadians(i * 22.5 + 11);
            double d = i % 2 == 0 ? radius - 3 : radius * 0.35;
            int x = (int) Math.round(Math.cos(a) * d);
            int z = (int) Math.round(Math.sin(a) * d);
            Build.fill(w, x, y + 1, z, x, y + 3, z, Material.AIR);
            Build.set(w, x, y, z, t.path);
            spawns.add(Build.lookAt(new Location(w, x + 0.5, y + 1, z + 0.5), middle));
        }
        return spawns;
    }

    /**
     * Rolling hills on a round island, filled solid down to {@code baseY - depth}. Returns the
     * ground height for every column, indexed {@code [x + radius][z + radius]} (or -1 off the island).
     */
    public static int[][] hills(World w, Theme t, Random r, int baseY, int radius, int amplitude, int depth) {
        int size = radius * 2 + 1;
        int[][] heights = new int[size][size];
        double p1 = r.nextDouble() * 10;
        double p2 = r.nextDouble() * 10;
        double p3 = r.nextDouble() * 10;
        for (int x = -radius; x <= radius; x++) {
            for (int z = -radius; z <= radius; z++) {
                double d = Math.sqrt(x * x + z * z);
                if (d > radius) {
                    heights[x + radius][z + radius] = -1;
                    continue;
                }
                double n = Math.sin(x / 7.0 + p1) * 0.5 + Math.cos(z / 9.0 + p2) * 0.35 + Math.sin((x + z) / 5.0 + p3) * 0.25
                        + Math.cos((x - z) / 11.0 + p1) * 0.3;
                double edge = Math.min(1, (radius - d) / 6.0); // slope down to the shore
                int h = baseY + (int) Math.round((n + 0.6) * amplitude * edge);
                heights[x + radius][z + radius] = h;
                for (int y = baseY - depth; y <= h; y++) {
                    Material m = y == h ? t.top : y > h - 3 ? t.soil : r.nextInt(14) == 0 ? t.accent : t.stone;
                    w.getBlockAt(x, y, z).setType(m, false);
                }
            }
        }
        return heights;
    }

    public static int height(int[][] heights, int radius, int x, int z) {
        if (x < -radius || x > radius || z < -radius || z > radius) {
            return -1;
        }
        return heights[x + radius][z + radius];
    }
}
