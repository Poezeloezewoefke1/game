package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Structures;
import net.funcraft.games.util.Theme;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.block.BlockFace;
import org.bukkit.block.Chest;
import org.bukkit.enchantments.Enchantment;
import org.bukkit.entity.Player;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.inventory.Inventory;
import org.bukkit.inventory.ItemStack;
import org.bukkit.potion.PotionEffectType;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.function.Supplier;

/** Solo SkyWars: own island, loot chests, bridge to the middle, last one alive wins. */
public final class SkyWars extends Game {

    private static final int Y = 64;
    private static final int RING = 58;
    private static final int MID_RADIUS = 22;
    private static final int MAP_HALF = 86;
    private static final int TOTAL_ISLANDS = 40;
    private static final int CAGE_SECONDS = 5;
    private static final int REFILL_AT = 240;
    private static final int DEATHMATCH_AT = 600;
    private static final int END_AT = 900;
    private static final int BUILD_LIMIT = 110;

    private final List<Location> spawns = new ArrayList<>();
    private final List<Block> islandChests = new ArrayList<>();
    private final List<Block> starterChests = new ArrayList<>();
    private final List<Block> centerChests = new ArrayList<>();
    private boolean cagesOpen;
    private Theme theme;

    public SkyWars(FunCraft plugin, int id) {
        super(plugin, id, GameType.SKYWARS);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-MAP_HALF, -MAP_HALF, MAP_HALF, MAP_HALF};
    }

    private record Isle(int x, int z, double r) {
    }

    @Override
    protected void buildMap() {
        int n = online().isEmpty() ? 8 : Math.max(2, Math.min(12, online().size()));
        theme = Theme.random(random);
        mapName = theme.displayName() + " Archipelago";
        List<Isle> isles = new ArrayList<>();

        // huge middle island with a castle full of loot
        theme.island(world, 0, Y, 0, MID_RADIUS, random);
        isles.add(new Isle(0, 0, MID_RADIUS));
        centerChests.addAll(Structures.castle(world, 0, Y + 1, 0, 9, theme, random));
        int[][] around = {{14, 0}, {-14, 0}, {0, 14}, {0, -14}, {11, 11}, {-11, -11}};
        for (int[] c : around) {
            Build.directional(world, c[0], Y + 1, c[1], Material.CHEST, BlockFace.NORTH);
            centerChests.add(world.getBlockAt(c[0], Y + 1, c[1]));
        }
        for (int i = 0; i < 6; i++) {
            double a = Math.toRadians(i * 60 + 30);
            theme.tree(world, (int) Math.round(Math.cos(a) * 18), Y + 1, (int) Math.round(Math.sin(a) * 18), random);
        }
        theme.plants(world, 0, Y, 0, MID_RADIUS - 1, 40, random);

        // player islands on the outer ring, each with a starter chest, a building and a cage
        for (int i = 0; i < n; i++) {
            double a = Math.toRadians(i * 360.0 / n);
            int x = (int) Math.round(Math.cos(a) * RING);
            int z = (int) Math.round(Math.sin(a) * RING);
            theme.island(world, x, Y, z, 6.5, random);
            isles.add(new Isle(x, z, 6.5));
            theme.plants(world, x, Y, z, 5.5, 4, random);
            int ox = (int) Math.round(Math.cos(a) * 3);
            int oz = (int) Math.round(Math.sin(a) * 3);
            Build.directional(world, x - ox, Y + 1, z - oz, Material.CHEST, BlockFace.NORTH);
            starterChests.add(world.getBlockAt(x - ox, Y + 1, z - oz));
            Block houseChest = Structures.house(world, x + ox * 4 / 3, Y + 1, z + oz * 4 / 3, theme, random);
            islandChests.add(houseChest);
            Build.cage(world, x, Y + 9, z, Material.GLASS);
            spawns.add(Build.lookAt(new Location(world, x + 0.5, Y + 9, z + 0.5), new Location(world, 0.5, Y + 9, 0.5)));
        }

        // lots of loot islands scattered around at different heights
        int target = TOTAL_ISLANDS - isles.size();
        int made = 0;
        for (int attempt = 0; attempt < 3000 && made < target; attempt++) {
            double a = random.nextDouble() * Math.PI * 2;
            double d = MID_RADIUS + 8 + random.nextDouble() * (MAP_HALF - MID_RADIUS - 16);
            int x = (int) Math.round(Math.cos(a) * d);
            int z = (int) Math.round(Math.sin(a) * d);
            double r = 3 + random.nextDouble() * 3;
            boolean free = true;
            for (Isle o : isles) {
                double gap = Math.hypot(o.x() - x, o.z() - z) - o.r() - r;
                if (gap < 5) {
                    free = false;
                    break;
                }
            }
            if (!free) {
                continue;
            }
            int y = Y - 8 + random.nextInt(17);
            theme.island(world, x, y, z, r, random);
            isles.add(new Isle(x, z, r));
            made++;
            if (r >= 5 && random.nextInt(2) == 0) {
                Block chest = Structures.random(world, x, y + 1, z, theme, random);
                if (chest != null) {
                    islandChests.add(chest);
                    continue;
                }
            } else if (random.nextInt(3) == 0) {
                theme.tree(world, x + 1, y + 1, z + 1, random);
            }
            Build.directional(world, x, y + 1, z, Material.CHEST, BlockFace.NORTH);
            islandChests.add(world.getBlockAt(x, y + 1, z));
            theme.plants(world, x, y, z, r - 1, 2, random);
        }
        fillChests();
    }

    private void fillChests() {
        for (Block b : starterChests) {
            fill(b, false, true);
        }
        for (Block b : islandChests) {
            fill(b, false, false);
        }
        for (Block b : centerChests) {
            fill(b, true, false);
        }
    }

    private void fill(Block block, boolean center, boolean starter) {
        if (!(block.getState() instanceof Chest chest)) {
            return;
        }
        Inventory inv = chest.getBlockInventory();
        inv.clear();
        List<ItemStack> items = new ArrayList<>();
        if (starter) {
            items.add(new ItemStack(random.nextBoolean() ? Material.STONE : Material.OAK_PLANKS, 48));
            items.add(ItemBuilder.of(random.nextBoolean() ? Material.STONE_SWORD : Material.IRON_SWORD).build());
            items.add(new ItemStack(pick(Material.IRON_CHESTPLATE, Material.CHAINMAIL_CHESTPLATE, Material.IRON_LEGGINGS)));
            items.add(new ItemStack(Material.STONE_PICKAXE));
            items.add(new ItemStack(Material.COOKED_BEEF, 8));
        }
        int rolls = center ? 6 + random.nextInt(3) : 4 + random.nextInt(3);
        for (int i = 0; i < rolls; i++) {
            items.add(center ? centerLoot() : normalLoot());
        }
        List<Integer> slots = new ArrayList<>();
        for (int i = 0; i < inv.getSize(); i++) {
            slots.add(i);
        }
        Collections.shuffle(slots, random);
        for (int i = 0; i < items.size() && i < slots.size(); i++) {
            inv.setItem(slots.get(i), items.get(i));
        }
    }

    private Material pick(Material... options) {
        return options[random.nextInt(options.length)];
    }

    private ItemStack normalLoot() {
        List<Supplier<ItemStack>> table = List.of(
                () -> new ItemStack(pick(Material.STONE, Material.OAK_PLANKS, Material.COBBLESTONE), 16 + random.nextInt(33)),
                () -> new ItemStack(pick(Material.STONE, Material.OAK_PLANKS), 32),
                () -> new ItemStack(pick(Material.STONE_SWORD, Material.IRON_SWORD, Material.STONE_AXE)),
                () -> new ItemStack(pick(Material.LEATHER_HELMET, Material.CHAINMAIL_HELMET, Material.IRON_HELMET, Material.GOLDEN_HELMET)),
                () -> new ItemStack(pick(Material.LEATHER_CHESTPLATE, Material.CHAINMAIL_CHESTPLATE, Material.IRON_CHESTPLATE)),
                () -> new ItemStack(pick(Material.LEATHER_LEGGINGS, Material.CHAINMAIL_LEGGINGS, Material.IRON_LEGGINGS)),
                () -> new ItemStack(pick(Material.LEATHER_BOOTS, Material.CHAINMAIL_BOOTS, Material.IRON_BOOTS)),
                () -> new ItemStack(Material.SNOWBALL, 8 + random.nextInt(9)),
                () -> new ItemStack(Material.EGG, 8 + random.nextInt(9)),
                () -> new ItemStack(pick(Material.COOKED_BEEF, Material.BREAD, Material.COOKED_PORKCHOP, Material.APPLE), 3 + random.nextInt(6)),
                () -> new ItemStack(Material.ARROW, 6 + random.nextInt(10)),
                () -> new ItemStack(Material.BOW),
                () -> new ItemStack(Material.IRON_PICKAXE),
                () -> new ItemStack(Material.WATER_BUCKET),
                () -> new ItemStack(Material.LAVA_BUCKET),
                () -> new ItemStack(Material.GOLDEN_APPLE),
                () -> new ItemStack(Material.FISHING_ROD),
                () -> new ItemStack(Material.EXPERIENCE_BOTTLE, 4));
        return table.get(random.nextInt(table.size())).get();
    }

    private ItemStack centerLoot() {
        List<Supplier<ItemStack>> table = List.of(
                () -> new ItemStack(pick(Material.DIAMOND_HELMET, Material.DIAMOND_BOOTS, Material.IRON_HELMET)),
                () -> new ItemStack(pick(Material.DIAMOND_CHESTPLATE, Material.DIAMOND_LEGGINGS, Material.IRON_CHESTPLATE)),
                () -> ItemBuilder.of(Material.DIAMOND_SWORD).build(),
                () -> ItemBuilder.of(Material.IRON_SWORD).enchant(Enchantment.SHARPNESS, 2).build(),
                () -> ItemBuilder.of(Material.BOW).enchant(Enchantment.POWER, 2).build(),
                () -> ItemBuilder.of(Material.BOW).enchant(Enchantment.PUNCH, 1).build(),
                () -> new ItemStack(Material.ARROW, 16),
                () -> new ItemStack(Material.ENDER_PEARL, 1 + random.nextInt(2)),
                () -> new ItemStack(Material.GOLDEN_APPLE, 1 + random.nextInt(2)),
                () -> new ItemStack(Material.OAK_PLANKS, 64),
                () -> new ItemStack(Material.TNT, 2 + random.nextInt(3)),
                () -> new ItemStack(Material.FLINT_AND_STEEL),
                () -> ItemBuilder.of(Material.DIAMOND_PICKAXE).enchant(Enchantment.EFFICIENCY, 2).build(),
                () -> ItemBuilder.of(Material.SPLASH_POTION).name("<red>Splash Potion of Healing")
                        .potion(PotionEffectType.INSTANT_HEALTH, 1, 1).build(),
                () -> ItemBuilder.of(Material.POTION).name("<aqua>Potion of Speed")
                        .potion(PotionEffectType.SPEED, 60, 1).build(),
                () -> new ItemStack(Material.COOKED_BEEF, 10));
        return table.get(random.nextInt(table.size())).get();
    }

    /** Small starter kits picked in the queue, handed out when the cages open. */
    private enum StarterKit {
        FIGHTER("Fighter", Material.STONE_SWORD, Material.LEATHER_CHESTPLATE, "Stone sword + leather chestplate"),
        ARCHER("Archer", Material.BOW, null, "Bow + 12 arrows"),
        BUILDER("Builder", Material.BRICKS, null, "64 bricks + stone pickaxe"),
        ENDERMAN("Enderman", Material.ENDER_PEARL, null, "2 ender pearls"),
        HEALER("Healer", Material.GOLDEN_APPLE, null, "3 golden apples"),
        BOMBER("Bomber", Material.TNT, null, "5 TNT + flint and steel");

        final String name;
        final Material icon;
        final Material armor;
        final String description;

        StarterKit(String name, Material icon, Material armor, String description) {
            this.name = name;
            this.icon = icon;
            this.armor = armor;
            this.description = description;
        }

        List<ItemStack> items() {
            return switch (this) {
                case FIGHTER -> List.of(new ItemStack(Material.STONE_SWORD));
                case ARCHER -> List.of(new ItemStack(Material.BOW), new ItemStack(Material.ARROW, 12));
                case BUILDER -> List.of(new ItemStack(Material.BRICKS, 64), new ItemStack(Material.STONE_PICKAXE));
                case ENDERMAN -> List.of(new ItemStack(Material.ENDER_PEARL, 2));
                case HEALER -> List.of(new ItemStack(Material.GOLDEN_APPLE, 3));
                case BOMBER -> List.of(new ItemStack(Material.TNT, 5), new ItemStack(Material.FLINT_AND_STEEL));
            };
        }
    }

    private final java.util.Map<java.util.UUID, StarterKit> chosenKit = new java.util.HashMap<>();

    @Override
    protected void onQueueJoin(Player player) {
        StarterKit kit = chosenKit.getOrDefault(player.getUniqueId(), StarterKit.FIGHTER);
        player.getInventory().setItem(2, plugin.hub().tag(ItemBuilder.of(kit.icon).name("<aqua><bold>Choose Kit</bold> <gray>(right click)")
                .lore("<gray>Selected: <white>" + kit.name).build(), "sw_kit"));
    }

    @Override
    public void onQueueItem(Player player, String id) {
        if (!id.equals("sw_kit")) {
            return;
        }
        net.funcraft.games.util.Gui gui = new net.funcraft.games.util.Gui(1, "<dark_gray>SkyWars kit");
        StarterKit current = chosenKit.getOrDefault(player.getUniqueId(), StarterKit.FIGHTER);
        StarterKit[] kits = StarterKit.values();
        for (int i = 0; i < kits.length; i++) {
            StarterKit kit = kits[i];
            ItemBuilder b = ItemBuilder.of(kit.icon).name("<bold><aqua>" + kit.name).lore("<gray>" + kit.description, "",
                    kit == current ? "<green>Selected" : "<yellow>Click to select").flags();
            if (kit == current) {
                b.glow();
            }
            gui.set(i + 1, b.build(), (p, click) -> {
                chosenKit.put(p.getUniqueId(), kit);
                onQueueJoin(p);
                Msg.send(p, "<gray>SkyWars kit: <aqua>" + kit.name);
                p.closeInventory();
            });
        }
        gui.open(player);
    }

    @Override
    protected void onStart(List<Player> list) {
        Collections.shuffle(spawns, random);
        for (int i = 0; i < list.size(); i++) {
            Player p = list.get(i);
            p.teleport(spawns.get(i % spawns.size()));
            Msg.title(p, "<aqua><bold>SkyWars", "<gray>Cages open in " + CAGE_SECONDS + " seconds", 5, 40, 10);
            Msg.send(p, "<gray>Your kit: <aqua>" + chosenKit.getOrDefault(p.getUniqueId(), StarterKit.FIGHTER).name
                    + " <dark_gray>(you get it when the cages open)");
        }
    }

    @Override
    protected void onSecond() {
        if (!cagesOpen) {
            int left = CAGE_SECONDS - elapsed;
            if (left > 0) {
                Msg.title(alivePlayers(), "<yellow>" + left, "<gray>Get ready...");
                Msg.sound(alivePlayers(), "block.note_block.hat", 1.5f);
                return;
            }
            cagesOpen = true;
            for (Location s : spawns) {
                Build.removeCage(world, s.getBlockX(), s.getBlockY(), s.getBlockZ());
            }
            for (Player p : alivePlayers()) {
                StarterKit kit = chosenKit.getOrDefault(p.getUniqueId(), StarterKit.FIGHTER);
                for (ItemStack item : kit.items()) {
                    p.getInventory().addItem(item);
                }
                if (kit.armor != null) {
                    p.getInventory().setChestplate(new ItemStack(kit.armor));
                }
            }
            Msg.title(alivePlayers(), "<green><bold>GO!", "<gray>Loot your chests and fight!");
            Msg.sound(alivePlayers(), "entity.player.levelup", 1f);
            return;
        }
        int t = elapsed;
        int nextAt = t < REFILL_AT ? REFILL_AT : t < DEATHMATCH_AT ? DEATHMATCH_AT : END_AT;
        String nextName = t < REFILL_AT ? "Chest refill" : t < DEATHMATCH_AT ? "Deathmatch" : "Game end";
        int prevAt = t < REFILL_AT ? 0 : t < DEATHMATCH_AT ? REFILL_AT : DEATHMATCH_AT;
        bossBar("<white>" + nextName + " in <aqua>" + Msg.time(nextAt - t) + " <dark_gray>| <green>" + alive.size() + " alive",
                1f - (float) (t - prevAt) / (nextAt - prevAt), net.kyori.adventure.bossbar.BossBar.Color.BLUE);
        if (t == REFILL_AT) {
            fillChests();
            Msg.all(online(), "<gold>All chests have been refilled!");
            Msg.sound(online(), "block.chest.open", 1f);
        } else if (t == DEATHMATCH_AT) {
            Msg.all(online(), "<red><bold>Deathmatch!</bold> <gray>Everyone glows and gets Speed I.");
            for (Player p : alivePlayers()) {
                p.setGlowing(true);
                p.addPotionEffect(new org.bukkit.potion.PotionEffect(PotionEffectType.SPEED, 20 * 600, 0));
            }
        } else if (t >= END_AT) {
            end(null, List.of());
        }
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        deathMessage(victim, killer, null);
        Location at = victim.getLocation();
        if (at.getY() > voidLevel() + 2) {
            for (ItemStack item : victim.getInventory().getContents()) {
                if (item != null && item.getType() != Material.AIR) {
                    world.dropItemNaturally(at, item);
                }
            }
        }
        eliminate(victim, true);
        if (alive.size() > 1) {
            Msg.all(online(), "<gray>" + alive.size() + " players remaining.");
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (!cagesOpen && event.getCause() != EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(true);
        } else if (event.getCause() == EntityDamageEvent.DamageCause.FALL && elapsed <= CAGE_SECONDS + 5) {
            event.setCancelled(true); // the drop out of the cage
        }
    }

    @Override
    public void onBlockBreak(BlockBreakEvent event) {
        if (!cagesOpen) {
            event.setCancelled(true);
        }
    }

    @Override
    public void onBlockPlace(BlockPlaceEvent event) {
        if (!cagesOpen || event.getBlock().getY() > BUILD_LIMIT) {
            event.setCancelled(true);
        }
    }

    @Override
    protected boolean allowHunger() {
        return true;
    }

    @Override
    protected boolean allowItemDrops() {
        return true;
    }

    @Override
    protected double voidLevel() {
        return 20;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 0.5, Y + 35, -30.5, 0, 45);
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        lines.add("<white>Players left: <green>" + alive.size());
        String next;
        if (elapsed < REFILL_AT) {
            next = "Refill " + Msg.time(REFILL_AT - elapsed);
        } else if (elapsed < DEATHMATCH_AT) {
            next = "Deathmatch " + Msg.time(DEATHMATCH_AT - elapsed);
        } else {
            next = "Game end " + Msg.time(END_AT - elapsed);
        }
        lines.add("<white>Next: <yellow>" + next);
        lines.add("  ");
        lines.add("<white>Kills: <red>" + kills.getOrDefault(player.getUniqueId(), 0));
        return lines;
    }
}
