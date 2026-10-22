package net.funcraft.games.util;

import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.World;
import org.bukkit.block.Block;
import org.bukkit.block.BlockFace;
import org.bukkit.block.data.BlockData;
import org.bukkit.block.data.Directional;
import org.bukkit.block.data.type.Bed;
import org.bukkit.block.data.type.Leaves;

import java.util.Random;

/** Procedural building blocks used to generate every map in code. */
public final class Build {

    private Build() {
    }

    public static void set(World w, int x, int y, int z, Material m) {
        w.getBlockAt(x, y, z).setType(m, false);
    }

    public static void fill(World w, int x1, int y1, int z1, int x2, int y2, int z2, Material m) {
        for (int x = Math.min(x1, x2); x <= Math.max(x1, x2); x++) {
            for (int y = Math.min(y1, y2); y <= Math.max(y1, y2); y++) {
                for (int z = Math.min(z1, z2); z <= Math.max(z1, z2); z++) {
                    w.getBlockAt(x, y, z).setType(m, false);
                }
            }
        }
    }

    /** Hollow box walls (no floor/ceiling). */
    public static void walls(World w, int x1, int y1, int z1, int x2, int y2, int z2, Material m) {
        fill(w, x1, y1, z1, x2, y2, z1, m);
        fill(w, x1, y1, z2, x2, y2, z2, m);
        fill(w, x1, y1, z1, x1, y2, z2, m);
        fill(w, x2, y1, z1, x2, y2, z2, m);
    }

    /** Flat filled disc. */
    public static void disc(World w, int cx, int y, int cz, double radius, Material m) {
        int r = (int) Math.ceil(radius);
        for (int x = -r; x <= r; x++) {
            for (int z = -r; z <= r; z++) {
                if (x * x + z * z <= radius * radius) {
                    w.getBlockAt(cx + x, y, cz + z).setType(m, false);
                }
            }
        }
    }

    /** Ring between inner and outer radius. */
    public static void ring(World w, int cx, int y, int cz, double inner, double outer, Material m) {
        int r = (int) Math.ceil(outer);
        for (int x = -r; x <= r; x++) {
            for (int z = -r; z <= r; z++) {
                double d = x * x + z * z;
                if (d <= outer * outer && d > inner * inner) {
                    w.getBlockAt(cx + x, y, cz + z).setType(m, false);
                }
            }
        }
    }

    /**
     * A floating island: flat top of {@code top}, a couple of dirt layers and a rough
     * stone underside that tapers to a point.
     */
    public static void island(World w, int cx, int y, int cz, double radius, Material top, Random random) {
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
                        Material m;
                        if (d == 0) {
                            m = top;
                        } else if (d <= 2) {
                            m = top == Material.GRASS_BLOCK ? Material.DIRT : top;
                        } else {
                            m = random.nextInt(6) == 0 ? Material.ANDESITE : Material.STONE;
                        }
                        w.getBlockAt(cx + x, y - d, cz + z).setType(m, false);
                    }
                }
            }
        }
    }

    /** Small oak tree with persistent leaves (they will not decay). */
    public static void tree(World w, int x, int y, int z, Random random) {
        int height = 4 + random.nextInt(2);
        for (int i = 0; i < height; i++) {
            set(w, x, y + i, z, Material.OAK_LOG);
        }
        BlockData leaves = Material.OAK_LEAVES.createBlockData();
        if (leaves instanceof Leaves l) {
            l.setPersistent(true);
        }
        int top = y + height;
        for (int dy = -2; dy <= 1; dy++) {
            int r = dy >= 0 ? 1 : 2;
            for (int dx = -r; dx <= r; dx++) {
                for (int dz = -r; dz <= r; dz++) {
                    if (Math.abs(dx) == r && Math.abs(dz) == r && (dy >= 0 || random.nextBoolean())) {
                        continue;
                    }
                    Block b = w.getBlockAt(x + dx, top + dy, z + dz);
                    if (b.getType().isAir()) {
                        b.setBlockData(leaves, false);
                    }
                }
            }
        }
    }

    /** Places a two-block bed whose head points in {@code facing}. Returns the foot block. */
    public static Block bed(World w, int x, int y, int z, Material bedMaterial, BlockFace facing) {
        Block foot = w.getBlockAt(x, y, z);
        Block head = foot.getRelative(facing);
        Bed footData = (Bed) bedMaterial.createBlockData();
        footData.setFacing(facing);
        footData.setPart(Bed.Part.FOOT);
        Bed headData = (Bed) bedMaterial.createBlockData();
        headData.setFacing(facing);
        headData.setPart(Bed.Part.HEAD);
        foot.setBlockData(footData, false);
        head.setBlockData(headData, false);
        return foot;
    }

    public static void directional(World w, int x, int y, int z, Material m, BlockFace facing) {
        BlockData data = m.createBlockData();
        if (data instanceof Directional d) {
            d.setFacing(facing);
        }
        w.getBlockAt(x, y, z).setBlockData(data, false);
    }

    /** Glass cage with an open-able floor, used for SkyWars spawns. */
    public static void cage(World w, int x, int y, int z, Material glass) {
        fill(w, x - 1, y - 1, z - 1, x + 1, y + 3, z + 1, glass);
        fill(w, x, y, z, x, y + 2, z, Material.AIR);
    }

    public static void removeCage(World w, int x, int y, int z) {
        fill(w, x - 1, y - 1, z - 1, x + 1, y + 3, z + 1, Material.AIR);
    }

    /** Horizontal block face for a yaw angle (degrees). */
    public static BlockFace faceFromYaw(float yaw) {
        float y = ((yaw % 360) + 360) % 360;
        if (y >= 45 && y < 135) {
            return BlockFace.WEST;
        } else if (y >= 135 && y < 225) {
            return BlockFace.NORTH;
        } else if (y >= 225 && y < 315) {
            return BlockFace.EAST;
        }
        return BlockFace.SOUTH;
    }

    /** Location looking from {@code from} towards {@code to}. */
    public static Location lookAt(Location from, Location to) {
        Location l = from.clone();
        l.setDirection(to.toVector().subtract(from.toVector()));
        return l;
    }

    public static Location center(World w, double x, double y, double z) {
        return new Location(w, x + 0.5, y, z + 0.5);
    }
}
