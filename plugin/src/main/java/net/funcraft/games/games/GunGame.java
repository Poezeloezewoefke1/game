package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Arenas;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Theme;
import org.bukkit.Material;
import org.bukkit.enchantments.Enchantment;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.PlayerInventory;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Supplier;

/**
 * Gun Game: every kill swaps your weapon for the next one on the list, from a netherite sword
 * down to a wooden one and finally a golden "knife". Get a kill with every weapon to win.
 */
public final class GunGame extends RespawnGame {

    private record Tier(String name, Supplier<ItemStack[]> items) {
    }

    private static final List<Tier> TIERS = List.of(
            new Tier("Netherite Sword", () -> new ItemStack[]{unbreakable(Material.NETHERITE_SWORD)}),
            new Tier("Power Bow", () -> new ItemStack[]{ItemBuilder.of(Material.BOW).enchant(Enchantment.POWER, 3).unbreakable().build(),
                    unbreakable(Material.WOODEN_SWORD), new ItemStack(Material.ARROW, 32)}),
            new Tier("Diamond Axe", () -> new ItemStack[]{unbreakable(Material.DIAMOND_AXE)}),
            new Tier("Trident", () -> new ItemStack[]{ItemBuilder.of(Material.TRIDENT).enchant(Enchantment.LOYALTY, 3).unbreakable().build()}),
            new Tier("Mace", () -> new ItemStack[]{unbreakable(Material.MACE), new ItemStack(Material.WIND_CHARGE, 8)}),
            new Tier("Crossbow", () -> new ItemStack[]{ItemBuilder.of(Material.CROSSBOW).enchant(Enchantment.QUICK_CHARGE, 2).unbreakable().build(),
                    unbreakable(Material.WOODEN_SWORD), new ItemStack(Material.ARROW, 24)}),
            new Tier("Iron Sword", () -> new ItemStack[]{unbreakable(Material.IRON_SWORD)}),
            new Tier("Iron Axe", () -> new ItemStack[]{unbreakable(Material.IRON_AXE)}),
            new Tier("Punch Bow", () -> new ItemStack[]{ItemBuilder.of(Material.BOW).enchant(Enchantment.PUNCH, 2).unbreakable().build(),
                    new ItemStack(Material.ARROW, 32)}),
            new Tier("Stone Sword", () -> new ItemStack[]{unbreakable(Material.STONE_SWORD)}),
            new Tier("Wooden Sword", () -> new ItemStack[]{unbreakable(Material.WOODEN_SWORD)}),
            new Tier("Golden Knife", () -> new ItemStack[]{ItemBuilder.of(Material.GOLDEN_SWORD).name("<gold><bold>Golden Knife")
                    .unbreakable().build()}));

    private final Map<UUID, Integer> tier = new HashMap<>();

    public GunGame(FunCraft plugin, int id) {
        super(plugin, id, GameType.GUN_GAME);
    }

    private static ItemStack unbreakable(Material m) {
        return ItemBuilder.of(m).unbreakable().build();
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-34, -34, 34, 34};
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + " Village";
        spawns.addAll(Arenas.village(world, theme, random, Y, 26));
    }

    @Override
    protected void loadout(Player p) {
        PlayerInventory inv = p.getInventory();
        inv.clear();
        int t = tier.getOrDefault(p.getUniqueId(), 0);
        ItemStack[] items = TIERS.get(Math.min(t, TIERS.size() - 1)).items().get();
        for (int i = 0; i < items.length; i++) {
            inv.setItem(i == items.length - 1 && items[i].getType() == Material.ARROW ? 8 : i, items[i]);
        }
        inv.setHelmet(unbreakable(Material.IRON_HELMET));
        inv.setChestplate(unbreakable(Material.CHAINMAIL_CHESTPLATE));
        inv.setLeggings(unbreakable(Material.CHAINMAIL_LEGGINGS));
        inv.setBoots(unbreakable(Material.IRON_BOOTS));
        inv.setItemInOffHand(new ItemStack(Material.COOKED_BEEF, 8));
    }

    @Override
    protected void onKill(Player killer, Player victim) {
        int next = tier.merge(killer.getUniqueId(), 1, Integer::sum);
        if (next < TIERS.size()) {
            loadout(killer);
            killer.setHealth(Math.min(20, killer.getHealth() + 6));
            Msg.title(killer, "", "<gold>" + TIERS.get(next).name() + " <gray>(" + (next + 1) + "/" + TIERS.size() + ")", 0, 25, 5);
            Msg.sound(killer, "entity.player.levelup", 1.6f);
            if (next == TIERS.size() - 1) {
                Msg.all(online(), "<gold>" + killer.getName() + " <yellow>is on the <gold>Golden Knife</gold> - one more kill wins!");
            }
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (event.getCause() == EntityDamageEvent.DamageCause.FALL) {
            event.setDamage(event.getDamage() / 2);
        }
    }

    @Override
    protected int score(UUID player) {
        return tier.getOrDefault(player, 0);
    }

    @Override
    protected int goal() {
        return TIERS.size();
    }

    @Override
    protected String scoreName() {
        return "levels";
    }

    @Override
    protected String objective() {
        return "Every kill upgrades your weapon!";
    }

    @Override
    protected int timeLimit() {
        return 600;
    }

    @Override
    protected List<String> extraSidebar(Player player) {
        int t = Math.min(score(player.getUniqueId()), TIERS.size() - 1);
        return List.of("<white>Weapon: <gold>" + TIERS.get(t).name(), "<white>Level: <green>" + (t + 1) + "/" + TIERS.size());
    }

    @Override
    protected void cleanup() {
        super.cleanup();
        tier.clear();
    }
}
