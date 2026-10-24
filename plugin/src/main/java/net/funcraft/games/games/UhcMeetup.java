package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Arenas;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Theme;
import org.bukkit.GameRule;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.WorldBorder;
import org.bukkit.enchantments.Enchantment;
import org.bukkit.entity.Player;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.PlayerInventory;

import java.util.List;

/**
 * UHC Meetup: everyone gets a random UHC kit (iron and diamond gear, gapples, buckets, blocks) on a
 * hilly island. No natural regeneration - only golden apples heal - and the world border closes
 * in until there's nowhere left to hide. Last one alive wins.
 */
public final class UhcMeetup extends LastStanding {

    private static final int Y = 64;
    private static final int RADIUS = 44;
    private static final int SHRINK_AT = 60;
    private static final int SHRINK_SECONDS = 240;
    private static final double FINAL_SIZE = 14;

    private int[][] heights;

    public UhcMeetup(FunCraft plugin, int id) {
        super(plugin, id, GameType.UHC_MEETUP);
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-RADIUS - 4, -RADIUS - 4, RADIUS + 4, RADIUS + 4};
    }

    @Override
    protected void buildMap() {
        Theme theme = random.nextBoolean() ? Theme.PLAINS : Theme.random(random);
        mapName = theme.displayName() + " Meetup";
        heights = Arenas.hills(world, theme, random, Y, RADIUS, 7, 10);
        for (int i = 0; i < 60; i++) {
            int x = random.nextInt(RADIUS * 2 - 8) - RADIUS + 4;
            int z = random.nextInt(RADIUS * 2 - 8) - RADIUS + 4;
            int h = Arenas.height(heights, RADIUS, x, z);
            if (h > 0 && x * x + z * z < (RADIUS - 5) * (RADIUS - 5)) {
                theme.tree(world, x, h + 1, z, random);
            }
        }
        theme.plants(world, 0, Y, 0, RADIUS, 200, random);
        center = new Location(world, 0.5, Y + 1, 0.5);
        int count = Math.max(2, online().isEmpty() ? 8 : online().size());
        spawns.clear();
        for (int i = 0; i < count; i++) {
            double a = Math.toRadians(i * 360.0 / count);
            int x = (int) Math.round(Math.cos(a) * (RADIUS - 12));
            int z = (int) Math.round(Math.sin(a) * (RADIUS - 12));
            int h = Math.max(Y, Arenas.height(heights, RADIUS, x, z));
            net.funcraft.games.util.Build.fill(world, x, h + 1, z, x, h + 4, z, Material.AIR);
            spawns.add(net.funcraft.games.util.Build.lookAt(new Location(world, x + 0.5, h + 1, z + 0.5), center));
        }
    }

    @Override
    protected void equip(Player p) {
        PlayerInventory inv = p.getInventory();
        inv.clear();
        inv.setHelmet(armor(random.nextInt(10) < 3 ? Material.DIAMOND_HELMET : Material.IRON_HELMET));
        inv.setChestplate(armor(random.nextInt(10) < 3 ? Material.DIAMOND_CHESTPLATE : Material.IRON_CHESTPLATE));
        inv.setLeggings(armor(random.nextInt(10) < 3 ? Material.DIAMOND_LEGGINGS : Material.IRON_LEGGINGS));
        inv.setBoots(armor(random.nextInt(10) < 4 ? Material.DIAMOND_BOOTS : Material.IRON_BOOTS));
        inv.setItem(0, random.nextBoolean()
                ? ItemBuilder.of(Material.DIAMOND_SWORD).enchant(Enchantment.SHARPNESS, 1 + random.nextInt(2)).build()
                : ItemBuilder.of(Material.IRON_SWORD).enchant(Enchantment.SHARPNESS, 2 + random.nextInt(2)).build());
        inv.setItem(1, ItemBuilder.of(Material.BOW).enchant(Enchantment.POWER, 1 + random.nextInt(2)).build());
        inv.setItem(2, new ItemStack(Material.GOLDEN_APPLE, 2 + random.nextInt(3)));
        inv.setItem(3, new ItemStack(Material.LAVA_BUCKET));
        inv.setItem(4, new ItemStack(Material.WATER_BUCKET));
        inv.setItem(5, new ItemStack(Material.COBBLESTONE, 64));
        inv.setItem(6, new ItemStack(Material.OAK_PLANKS, 32));
        inv.setItem(7, ItemBuilder.of(Material.DIAMOND_AXE).enchant(Enchantment.EFFICIENCY, 2).build());
        inv.setItem(8, new ItemStack(Material.COOKED_BEEF, 16));
        inv.setItem(9, new ItemStack(Material.ARROW, 24));
        inv.setItem(10, new ItemStack(Material.FISHING_ROD));
        inv.setItem(11, ItemBuilder.of(Material.GOLDEN_APPLE).name("<gold><bold>Golden Head").build());
        inv.setItemInOffHand(new ItemStack(Material.SHIELD));
    }

    private ItemStack armor(Material m) {
        return ItemBuilder.of(m).enchant(Enchantment.PROTECTION, 1 + random.nextInt(2)).build();
    }

    @Override
    protected void onStart(List<Player> list) {
        super.onStart(list);
        world.setGameRule(GameRule.NATURAL_REGENERATION, false);
        WorldBorder border = world.getWorldBorder();
        border.setCenter(0.5, 0.5);
        border.setSize(RADIUS * 2);
        border.setDamageAmount(1);
        border.setWarningDistance(6);
        Msg.all(list, "<gray>No natural regeneration - only golden apples heal. The border starts closing in after "
                + SHRINK_AT + " seconds!");
    }

    @Override
    protected void onSecond() {
        super.onSecond();
        if (state != State.RUNNING) {
            return;
        }
        if (elapsed == SHRINK_AT) {
            world.getWorldBorder().setSize(FINAL_SIZE, SHRINK_SECONDS);
            Msg.all(online(), "<red><bold>The border is closing in!");
            Msg.sound(online(), "entity.ender_dragon.growl", 1.2f);
        }
    }

    @Override
    public void onBlockPlace(BlockPlaceEvent event) {
        if (event.getBlock().getY() > Y + 40) {
            event.setCancelled(true);
        }
    }

    @Override
    public void onBlockBreak(BlockBreakEvent event) {
        if (event.getBlock().getY() < Y - 9) {
            event.setCancelled(true); // keep a floor under the island
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
    public boolean botsBuild() {
        return true;
    }

    @Override
    protected int timeLimit() {
        return 600;
    }

    @Override
    protected String objective() {
        return "Random UHC gear, no regen - last one alive wins!";
    }

    @Override
    protected double voidLevel() {
        return Y - 20;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 0.5, Y + 30, 0.5, 0, 70);
    }

    @Override
    protected List<String> extraSidebar(Player player) {
        return List.of("<white>Border: <red>" + (int) world.getWorldBorder().getSize() / 2 + " blocks");
    }
}
