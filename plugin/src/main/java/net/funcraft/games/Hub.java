package net.funcraft.games;

import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.Gui;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.VoidGenerator;
import org.bukkit.Bukkit;
import org.bukkit.Difficulty;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.NamespacedKey;
import org.bukkit.OfflinePlayer;
import org.bukkit.World;
import org.bukkit.WorldCreator;
import org.bukkit.entity.Display;
import org.bukkit.entity.Entity;
import org.bukkit.entity.Player;
import org.bukkit.entity.TextDisplay;
import org.bukkit.entity.Villager;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.meta.SkullMeta;
import org.bukkit.persistence.PersistentDataType;

import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

/** The lobby world: a floating island with an NPC for every game, plus hub items and menus. */
public final class Hub {

    public static final String WORLD_NAME = "fc_hub";
    public static final String NPC_TAG = "fc_npc";
    private static final int NPC_RADIUS = 13;

    private final FunCraft plugin;
    private final NamespacedKey itemKey;
    private final NamespacedKey npcKey;
    private final Map<GameType, TextDisplay> npcLabels = new EnumMap<>(GameType.class);
    private TextDisplay leaderboard;
    private World world;

    public Hub(FunCraft plugin) {
        this.plugin = plugin;
        this.itemKey = new NamespacedKey(plugin, "hub_item");
        this.npcKey = new NamespacedKey(plugin, "npc_game");
    }

    public void load() {
        world = Bukkit.getWorld(WORLD_NAME);
        if (world == null) {
            world = new WorldCreator(WORLD_NAME).generator(new VoidGenerator())
                    .environment(World.Environment.NORMAL).generateStructures(false).createWorld();
        }
        if (world == null) {
            throw new IllegalStateException("Could not create the hub world");
        }
        world.setDifficulty(Difficulty.PEACEFUL);
        world.setTime(6000);
        world.setStorm(false);
        world.setClearWeatherDuration(Integer.MAX_VALUE);
        for (int cx = -3; cx <= 2; cx++) {
            for (int cz = -3; cz <= 2; cz++) {
                world.getChunkAt(cx, cz).addPluginChunkTicket(plugin);
            }
        }
        if (world.getBlockAt(0, 64, 0).getType() != Material.SEA_LANTERN) {
            plugin.getLogger().info("Building the hub island...");
            build();
        }
        spawnNpcs();
    }

    public World world() {
        return world;
    }

    public Location spawn() {
        return new Location(world, 0.5, 66, 0.5, 180, 0);
    }

    /** Builds the hub island. Only runs once (or on /fc rebuildhub). */
    public void build() {
        Random r = new Random(42);
        Build.fill(world, -40, 40, -40, 40, 90, 40, Material.AIR);
        Build.island(world, 0, 64, 0, 32, Material.GRASS_BLOCK, r);
        // plaza
        Build.disc(world, 0, 64, 0, 21, Material.POLISHED_ANDESITE);
        Build.ring(world, 0, 64, 0, 19.5, 21, Material.STONE_BRICKS);
        Build.ring(world, 0, 64, 0, 9, 10.2, Material.SMOOTH_QUARTZ);
        Build.ring(world, 0, 64, 0, 15, 16, Material.POLISHED_DIORITE);
        // center spawn pedestal
        Build.disc(world, 0, 65, 0, 3.5, Material.SMOOTH_QUARTZ);
        Build.ring(world, 0, 65, 0, 2.5, 3.5, Material.QUARTZ_BRICKS);
        Build.set(world, 0, 64, 0, Material.SEA_LANTERN);
        for (int[] l : new int[][]{{3, 0}, {-3, 0}, {0, 3}, {0, -3}}) {
            Build.set(world, l[0], 65, l[1], Material.SEA_LANTERN);
        }
        // light posts around the plaza edge
        for (int i = 0; i < 12; i++) {
            double a = Math.toRadians(i * 30 + 15);
            int x = (int) Math.round(Math.cos(a) * 20);
            int z = (int) Math.round(Math.sin(a) * 20);
            Build.fill(world, x, 65, z, x, 67, z, Material.STONE_BRICK_WALL);
            Build.set(world, x, 68, z, Material.SEA_LANTERN);
        }
        // NPC pads
        Material[] pads = {Material.RED_CONCRETE, Material.LIGHT_BLUE_CONCRETE, Material.MAGENTA_CONCRETE,
                Material.ORANGE_CONCRETE, Material.YELLOW_CONCRETE, Material.WHITE_CONCRETE,
                Material.BLACK_CONCRETE, Material.LIME_CONCRETE};
        GameType[] types = GameType.values();
        for (int i = 0; i < types.length; i++) {
            Location pad = npcLocation(i, types.length);
            Build.disc(world, pad.getBlockX(), 64, pad.getBlockZ(), 2.2, pads[i % pads.length]);
            Build.set(world, pad.getBlockX(), 64, pad.getBlockZ(), Material.GLOWSTONE);
        }
        // trees and flowers on the grass ring
        Material[] flowers = {Material.POPPY, Material.DANDELION, Material.CORNFLOWER, Material.OXEYE_DAISY, Material.ALLIUM};
        for (int i = 0; i < 400; i++) {
            int x = r.nextInt(61) - 30;
            int z = r.nextInt(61) - 30;
            double d = Math.sqrt(x * x + z * z);
            if (d > 22.5 && d < 29 && world.getBlockAt(x, 64, z).getType() == Material.GRASS_BLOCK
                    && world.getBlockAt(x, 65, z).getType().isAir()) {
                if (i % 25 == 0) {
                    Build.tree(world, x, 65, z, r);
                } else if (r.nextInt(3) == 0) {
                    Build.set(world, x, 65, z, flowers[r.nextInt(flowers.length)]);
                }
            }
        }
        world.setSpawnLocation(spawn());
    }

    private Location npcLocation(int index, int total) {
        double angle = Math.toRadians(index * (360.0 / total) - 90);
        int x = (int) Math.round(Math.cos(angle) * NPC_RADIUS);
        int z = (int) Math.round(Math.sin(angle) * NPC_RADIUS);
        Location loc = new Location(world, x + 0.5, 65, z + 0.5);
        return Build.lookAt(loc, new Location(world, 0.5, 65, 0.5));
    }

    private void spawnNpcs() {
        for (Entity e : world.getEntities()) {
            if (e.getScoreboardTags().contains(NPC_TAG)) {
                e.remove();
            }
        }
        GameType[] types = GameType.values();
        for (int i = 0; i < types.length; i++) {
            GameType type = types[i];
            if (!type.enabled(plugin)) {
                continue;
            }
            Location loc = npcLocation(i, types.length);
            world.spawn(loc, Villager.class, v -> {
                v.setAI(false);
                v.setInvulnerable(true);
                v.setSilent(true);
                v.setPersistent(false);
                v.setRemoveWhenFarAway(false);
                v.setCollidable(false);
                v.setProfession(professionFor(type));
                v.addScoreboardTag(NPC_TAG);
                v.getPersistentDataContainer().set(npcKey, PersistentDataType.STRING, type.name());
                v.customName(Msg.mm(type.colored()));
                v.setCustomNameVisible(false);
                v.setRotation(loc.getYaw(), 0);
            });
            TextDisplay label = world.spawn(loc.clone().add(0, 2.35, 0), TextDisplay.class, t -> {
                t.setBillboard(Display.Billboard.CENTER);
                t.setPersistent(false);
                t.addScoreboardTag(NPC_TAG);
                t.setShadowed(true);
            });
            npcLabels.put(type, label);
        }
        leaderboard = world.spawn(new Location(world, 0.5, 69.5, 0.5), TextDisplay.class, t -> {
            t.setBillboard(Display.Billboard.CENTER);
            t.setPersistent(false);
            t.addScoreboardTag(NPC_TAG);
            t.setShadowed(true);
        });
        refreshLabels();
    }

    private static Villager.Profession professionFor(GameType type) {
        return switch (type) {
            case BEDWARS -> Villager.Profession.ARMORER;
            case SKYWARS -> Villager.Profession.CARTOGRAPHER;
            case BUILD_BATTLE -> Villager.Profession.MASON;
            case PVP -> Villager.Profession.WEAPONSMITH;
            case DUELS -> Villager.Profession.TOOLSMITH;
            case SPLEEF -> Villager.Profession.SHEPHERD;
            case TNT_RUN -> Villager.Profession.CLERIC;
            case SUMO -> Villager.Profession.BUTCHER;
        };
    }

    /** Updates the floating text above the NPCs and the leaderboard. */
    public void refreshLabels() {
        for (Map.Entry<GameType, TextDisplay> e : npcLabels.entrySet()) {
            if (!e.getValue().isValid()) {
                continue;
            }
            GameType type = e.getKey();
            e.getValue().text(Msg.mm("<bold>" + type.colored() + "</bold>\n<gray>" + plugin.games().playing(type)
                    + " playing</gray>\n<yellow>Click to play!"));
        }
        if (leaderboard != null && leaderboard.isValid()) {
            StringBuilder sb = new StringBuilder("<gold><bold>Top Wins</bold></gold>");
            List<Stats.Entry> top = plugin.stats().top("total", "wins", 5);
            if (top.isEmpty()) {
                sb.append("\n<gray>No winners yet - go play!");
            }
            for (int i = 0; i < top.size(); i++) {
                sb.append("\n<yellow>").append(i + 1).append(". <white>").append(Msg.escape(top.get(i).name()))
                        .append(" <gray>- <green>").append(top.get(i).value());
            }
            leaderboard.text(Msg.mm(sb.toString()));
        }
    }

    public GameType npcGame(Entity entity) {
        String value = entity.getPersistentDataContainer().get(npcKey, PersistentDataType.STRING);
        if (value == null) {
            return null;
        }
        try {
            return GameType.valueOf(value);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    // ---------------------------------------------------------------- players

    /** Teleports a player to the hub and resets them. */
    public void send(Player player) {
        plugin.games().prepare(player, GameMode.ADVENTURE);
        player.teleport(spawn());
        giveHubItems(player);
        plugin.sidebars().reset(player);
    }

    public void giveHubItems(Player player) {
        player.getInventory().clear();
        player.getInventory().setItem(0, tag(ItemBuilder.of(Material.COMPASS).name("<gold><bold>Game Selector</bold> <gray>(right click)")
                .lore("<gray>Pick a minigame to play!").build(), "selector"));
        player.getInventory().setItem(4, tag(head(player, "<aqua><bold>Your Stats</bold> <gray>(right click)"), "stats"));
        player.getInventory().setItem(8, tag(ItemBuilder.of(Material.NETHER_STAR).name("<yellow><bold>Back to Spawn</bold> <gray>(right click)").build(), "spawn"));
        player.getInventory().setHeldItemSlot(0);
    }

    public void giveQueueItems(Player player) {
        giveHubItems(player);
        player.getInventory().setItem(8, tag(ItemBuilder.of(Material.RED_BED).name("<red><bold>Leave Queue</bold> <gray>(right click)").build(), "leave"));
    }

    private ItemStack head(Player player, String name) {
        ItemStack item = ItemBuilder.of(Material.PLAYER_HEAD).name(name).lore("<gray>See your wins, kills and more.").build();
        if (item.getItemMeta() instanceof SkullMeta meta) {
            meta.setOwningPlayer(player);
            item.setItemMeta(meta);
        }
        return item;
    }

    private ItemStack tag(ItemStack item, String id) {
        item.editMeta(meta -> meta.getPersistentDataContainer().set(itemKey, PersistentDataType.STRING, id));
        return item;
    }

    public String hubItem(ItemStack item) {
        if (item == null || !item.hasItemMeta()) {
            return null;
        }
        return item.getItemMeta().getPersistentDataContainer().get(itemKey, PersistentDataType.STRING);
    }

    // ------------------------------------------------------------------ menus

    public void openSelector(Player player) {
        Gui gui = new Gui(3, "<dark_gray>Choose a game");
        int[] slots = {10, 11, 12, 13, 14, 15, 16, 22};
        GameType[] types = GameType.values();
        Game current = plugin.games().gameOf(player);
        for (int i = 0; i < types.length && i < slots.length; i++) {
            GameType type = types[i];
            List<String> lore = new ArrayList<>();
            for (String line : type.description()) {
                lore.add("<gray>" + line);
            }
            lore.add("");
            lore.add("<white>Players: <green>" + type.minPlayers(plugin) + "-" + type.maxPlayers(plugin));
            lore.add("<white>In queue: <yellow>" + plugin.games().queued(type) + "  <white>Playing: <yellow>" + plugin.games().playing(type));
            lore.add("");
            boolean enabled = type.enabled(plugin);
            boolean inThis = current != null && current.type() == type;
            lore.add(!enabled ? "<red>Disabled" : inThis ? "<green>You are in this queue" : "<yellow>Click to join!");
            ItemBuilder b = ItemBuilder.of(type.icon()).name("<bold>" + type.colored()).lore(lore).flags();
            if (inThis) {
                b.glow();
            }
            gui.set(slots[i], b.build(), (p, click) -> {
                p.closeInventory();
                plugin.games().join(p, type);
            });
        }
        gui.fill(ItemBuilder.of(Material.GRAY_STAINED_GLASS_PANE).name(" ").build());
        gui.open(player);
    }

    public void openStats(Player viewer, UUID target) {
        Stats stats = plugin.stats();
        OfflinePlayer off = Bukkit.getOfflinePlayer(target);
        String name = stats.has(target) ? stats.nameOf(target) : off.getName();
        Gui gui = new Gui(3, "<dark_gray>Stats of " + Msg.escape(name == null ? "?" : name));
        gui.set(4, ItemBuilder.of(Material.GOLD_BLOCK).name("<gold><bold>Overall")
                .lore(statLines(target, "total")).build());
        int[] slots = {10, 11, 12, 13, 14, 15, 16, 22};
        GameType[] types = GameType.values();
        for (int i = 0; i < types.length && i < slots.length; i++) {
            gui.set(slots[i], ItemBuilder.of(types[i].icon()).name("<bold>" + types[i].colored())
                    .lore(statLines(target, types[i].key())).flags().build());
        }
        gui.fill(ItemBuilder.of(Material.BLACK_STAINED_GLASS_PANE).name(" ").build());
        gui.open(viewer);
    }

    private List<String> statLines(UUID uuid, String scope) {
        Stats s = plugin.stats();
        int kills = s.get(uuid, scope, "kills");
        int deaths = s.get(uuid, scope, "deaths");
        String kd = deaths == 0 ? String.valueOf(kills) : String.format("%.2f", (double) kills / deaths);
        return List.of(
                "<white>Wins: <green>" + s.get(uuid, scope, "wins"),
                "<white>Games played: <yellow>" + s.get(uuid, scope, "games"),
                "<white>Kills: <red>" + kills,
                "<white>Deaths: <gray>" + deaths,
                "<white>K/D: <aqua>" + kd);
    }
}
