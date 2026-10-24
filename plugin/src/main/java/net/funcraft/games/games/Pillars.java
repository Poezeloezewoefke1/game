package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.Explosives;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.enchantments.Enchantment;
import org.bukkit.entity.Player;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityExplodeEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

/**
 * Pillars of Fortune: everyone stands on a tall bedrock pillar over the void and gets a random
 * item every few seconds - blocks, weapons, TNT, pearls, a knockback stick... Build, bridge
 * and knock each other off. After a few minutes items come twice as fast. Last one standing wins.
 */
public final class Pillars extends LastStanding {

    private static final int TOP = 64;
    private static final int BOTTOM = 40;
    private static final int ITEM_SECONDS = 4;
    private static final int FAST_AFTER = 300;
    private static final int TIME_LIMIT = 540;
    private static final int BUILD_LIMIT = 26;

    private static final String[] WOOL = {"WHITE", "ORANGE", "MAGENTA", "LIGHT_BLUE", "YELLOW", "LIME", "PINK",
            "CYAN", "PURPLE", "BLUE", "RED", "GREEN"};

    private record Loot(int weight, Supplier<ItemStack> item) {
    }

    private final List<Loot> loot = new ArrayList<>();
    private final Explosives explosives = new Explosives(1.5);
    private int totalWeight;

    public Pillars(FunCraft plugin, int id) {
        super(plugin, id, GameType.PILLARS);
        add(12, () -> new ItemStack(Material.valueOf(WOOL[random.nextInt(WOOL.length)] + "_WOOL"), 16));
        add(6, () -> new ItemStack(Material.COBBLESTONE, 12));
        add(5, () -> new ItemStack(Material.OAK_PLANKS, 16));
        add(2, () -> new ItemStack(Material.LADDER, 8));
        add(2, () -> new ItemStack(Material.SLIME_BLOCK, 3));
        add(5, () -> new ItemStack(Material.SNOWBALL, 8));
        add(3, () -> new ItemStack(Material.EGG, 8));
        add(4, () -> new ItemStack(Material.ARROW, 6));
        add(3, () -> new ItemStack(Material.BOW));
        add(1, () -> new ItemStack(Material.CROSSBOW));
        add(4, () -> new ItemStack(Material.STONE_SWORD));
        add(2, () -> new ItemStack(Material.IRON_SWORD));
        add(1, () -> ItemBuilder.of(Material.DIAMOND_SWORD).enchant(Enchantment.SHARPNESS, 1).build());
        add(3, () -> ItemBuilder.of(Material.STICK).name("<gold>Knockback Stick").enchant(Enchantment.KNOCKBACK, 2).build());
        add(1, () -> ItemBuilder.of(Material.MACE).build());
        add(3, () -> new ItemStack(Material.FISHING_ROD));
        add(2, () -> new ItemStack(Material.SHIELD));
        add(2, () -> new ItemStack(Material.IRON_CHESTPLATE));
        add(2, () -> new ItemStack(Material.CHAINMAIL_HELMET));
        add(2, () -> new ItemStack(Material.CHAINMAIL_BOOTS));
        add(1, () -> new ItemStack(Material.DIAMOND_LEGGINGS));
        add(3, () -> new ItemStack(Material.GOLDEN_APPLE));
        add(3, () -> new ItemStack(Material.COOKED_BEEF, 4));
        add(3, () -> new ItemStack(Material.ENDER_PEARL));
        add(3, () -> new ItemStack(Material.WIND_CHARGE, 4));
        add(4, () -> new ItemStack(Material.TNT, 2));
        add(3, () -> new ItemStack(Material.FIRE_CHARGE, 2));
        add(2, () -> new ItemStack(Material.COBWEB, 2));
        add(2, () -> new ItemStack(Material.WATER_BUCKET));
        add(1, () -> new ItemStack(Material.LAVA_BUCKET));
        add(2, () -> ItemBuilder.of(Material.POTION).name("<aqua>Speed Potion").potion(PotionEffectType.SPEED, 30, 1).build());
        add(2, () -> ItemBuilder.of(Material.POTION).name("<green>Jump Potion").potion(PotionEffectType.JUMP_BOOST, 30, 2).build());
        add(1, () -> new ItemStack(Material.TOTEM_OF_UNDYING));
    }

    private void add(int weight, Supplier<ItemStack> item) {
        loot.add(new Loot(weight, item));
        totalWeight += weight;
    }

    private ItemStack roll() {
        int r = random.nextInt(totalWeight);
        for (Loot l : loot) {
            r -= l.weight();
            if (r < 0) {
                return l.item().get();
            }
        }
        return new ItemStack(Material.COBBLESTONE, 8);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-BUILD_LIMIT - 4, -BUILD_LIMIT - 4, BUILD_LIMIT + 4, BUILD_LIMIT + 4};
    }

    @Override
    protected void buildMap() {
        int count = Math.max(2, Math.min(12, online().isEmpty() ? 8 : online().size()));
        double radius = Math.max(9, count * 1.7);
        center = new Location(world, 0.5, TOP + 1, 0.5);
        spawnRing(TOP + 1, radius, count);
        for (Location spawn : spawns) {
            int x = spawn.getBlockX();
            int z = spawn.getBlockZ();
            Build.fill(world, x, BOTTOM, z, x, TOP, z, Material.BEDROCK);
            // centre the player on the 1x1 top
            spawn.setX(x + 0.5);
            spawn.setZ(z + 0.5);
        }
        // a small floating rock in the middle to fight over
        Build.island(world, 0, TOP - 4, 0, 2.5, Material.MOSS_BLOCK, random);
        Build.set(world, 0, TOP - 3, 0, Material.CHEST);
    }

    @Override
    protected void equip(Player player) {
        player.getInventory().clear();
        player.addPotionEffect(new PotionEffect(PotionEffectType.RESISTANCE, 20 * 3, 4, false, false));
    }

    @Override
    protected void onStart(List<Player> list) {
        super.onStart(list);
        // the middle rock's chest holds a little treasure
        if (world.getBlockAt(0, TOP - 3, 0).getState() instanceof org.bukkit.block.Chest chest) {
            chest.getInventory().addItem(ItemBuilder.of(Material.DIAMOND_SWORD).enchant(Enchantment.KNOCKBACK, 1).build(),
                    new ItemStack(Material.ENDER_PEARL, 2), new ItemStack(Material.GOLDEN_APPLE, 2));
        }
        Msg.all(list, "<gray>You get a <gold>random item</gold> every " + ITEM_SECONDS
                + " seconds. Build, bridge and knock everyone off their pillar!");
    }

    @Override
    protected void onSecond() {
        super.onSecond();
        if (state != State.RUNNING) {
            return;
        }
        int every = elapsed >= FAST_AFTER ? ITEM_SECONDS / 2 : ITEM_SECONDS;
        if (elapsed == FAST_AFTER) {
            Msg.all(online(), "<red><bold>SUDDEN LUCK!</bold> <yellow>Items now come twice as fast!");
            Msg.sound(online(), "entity.ender_dragon.growl", 1.5f);
        }
        if (elapsed > 0 && elapsed % every == 0) {
            for (Player p : alivePlayers()) {
                if (p.getGameMode() != org.bukkit.GameMode.SURVIVAL) {
                    continue;
                }
                ItemStack item = roll();
                Map<Integer, ItemStack> left = p.getInventory().addItem(item.clone());
                left.values().forEach(rest -> p.getWorld().dropItemNaturally(p.getLocation(), rest));
                Msg.actionBar(p, "<gold>+ <white>" + item.getAmount() + "x " + pretty(item.getType()));
                Msg.sound(p, "entity.item.pickup", 1.4f);
            }
        }
    }

    private static String pretty(Material m) {
        String s = m.name().toLowerCase(java.util.Locale.ROOT).replace('_', ' ');
        return Character.toUpperCase(s.charAt(0)) + s.substring(1);
    }

    @Override
    public void onBlockPlace(BlockPlaceEvent event) {
        Block b = event.getBlock();
        if (Math.abs(b.getX()) > BUILD_LIMIT || Math.abs(b.getZ()) > BUILD_LIMIT || b.getY() > TOP + 20) {
            event.setCancelled(true);
            Msg.actionBar(event.getPlayer(), "<red>You can't build this far out!");
            return;
        }
        if (b.getType() == Material.TNT) {
            Explosives.primeNextTick(plugin, b, event.getPlayer());
        }
    }

    @Override
    public void onBlockBreak(BlockBreakEvent event) {
        event.setDropItems(false);
    }

    @Override
    public void onInteract(PlayerInteractEvent event) {
        explosives.handleFireball(event);
    }

    @Override
    public void onExplode(EntityExplodeEvent event) {
        event.blockList().removeIf(b -> b.getType() == Material.BEDROCK || b.getType() == Material.CHEST);
        event.setYield(0);
    }

    @Override
    protected int timeLimit() {
        return TIME_LIMIT;
    }

    @Override
    protected String objective() {
        return "Use your random items - last one standing wins!";
    }

    @Override
    protected double voidLevel() {
        return BOTTOM - 10;
    }

    @Override
    protected List<String> extraSidebar(Player player) {
        int every = elapsed >= FAST_AFTER ? ITEM_SECONDS / 2 : ITEM_SECONDS;
        int next = every - (elapsed % every);
        return List.of("<white>Next item: <gold>" + next + "s");
    }
}
