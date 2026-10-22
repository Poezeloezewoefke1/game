package net.funcraft.games.util;

import org.bukkit.Bukkit;
import org.bukkit.Difficulty;
import org.bukkit.World;
import org.bukkit.WorldCreator;
import org.bukkit.plugin.Plugin;

import java.io.File;
import java.io.IOException;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.logging.Level;

/** Creates throw-away void worlds for matches and deletes them again afterwards. */
public final class Worlds {

    public static final String GAME_WORLD_PREFIX = "fc_match_";

    private Worlds() {
    }

    public static World createVoid(String name) {
        World world = new WorldCreator(name)
                .generator(new VoidGenerator())
                .environment(World.Environment.NORMAL)
                .generateStructures(false)
                .createWorld();
        if (world == null) {
            throw new IllegalStateException("Could not create world " + name);
        }
        world.setAutoSave(false);
        world.setDifficulty(Difficulty.NORMAL);
        world.setTime(6000);
        world.setStorm(false);
        world.setThundering(false);
        world.setClearWeatherDuration(Integer.MAX_VALUE);
        return world;
    }

    /** Unloads the world without saving and removes its folder off the main thread. */
    public static void delete(Plugin plugin, World world) {
        if (world == null) {
            return;
        }
        File folder = world.getWorldFolder();
        World fallback = Bukkit.getWorlds().get(0);
        world.getPlayers().forEach(p -> p.teleport(fallback.getSpawnLocation()));
        if (!Bukkit.unloadWorld(world, false)) {
            plugin.getLogger().warning("Could not unload " + world.getName() + ", it will be cleaned on next restart.");
            return;
        }
        Bukkit.getScheduler().runTaskAsynchronously(plugin, () -> deleteFolder(plugin, folder));
    }

    /** Removes match worlds left behind by a crash or hard stop. */
    public static void cleanLeftovers(Plugin plugin) {
        File[] files = Bukkit.getWorldContainer().listFiles();
        if (files == null) {
            return;
        }
        for (File file : files) {
            if (file.isDirectory() && file.getName().startsWith(GAME_WORLD_PREFIX) && Bukkit.getWorld(file.getName()) == null) {
                deleteFolder(plugin, file);
            }
        }
    }

    private static void deleteFolder(Plugin plugin, File folder) {
        if (!folder.exists()) {
            return;
        }
        try {
            Files.walkFileTree(folder.toPath(), new SimpleFileVisitor<>() {
                @Override
                public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
                    Files.deleteIfExists(file);
                    return FileVisitResult.CONTINUE;
                }

                @Override
                public FileVisitResult postVisitDirectory(Path dir, IOException exc) throws IOException {
                    Files.deleteIfExists(dir);
                    return FileVisitResult.CONTINUE;
                }
            });
        } catch (IOException e) {
            plugin.getLogger().log(Level.WARNING, "Failed to delete " + folder, e);
        }
    }
}
