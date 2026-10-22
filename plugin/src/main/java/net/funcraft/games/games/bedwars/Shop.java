package net.funcraft.games.games.bedwars;

import net.funcraft.games.util.Gui;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import org.bukkit.Color;
import org.bukkit.Material;
import org.bukkit.enchantments.Enchantment;
import org.bukkit.entity.Player;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.PlayerInventory;
import org.bukkit.potion.PotionEffectType;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Function;
import java.util.function.Predicate;

/** Item shop and team upgrade menus for BedWars. */
final class Shop {

    private static final String[] CATEGORIES = {"Blocks", "Melee", "Armor", "Tools", "Ranged", "Utility"};
    private static final Material[] CATEGORY_ICONS = {Material.TERRACOTTA, Material.GOLDEN_SWORD, Material.CHAINMAIL_BOOTS,
            Material.STONE_PICKAXE, Material.BOW, Material.TNT};

    /** One thing you can buy. {@code buy} returns false if the purchase is not allowed. */
    private record Offer(Function<Player, ItemStack> icon, Material currency, int price, Predicate<Player> buy) {
    }

    private final BedWars game;

    Shop(BedWars game) {
        this.game = game;
    }

    // ------------------------------------------------------------- helpers

    static boolean isCurrency(Material m) {
        return m == Material.IRON_INGOT || m == Material.GOLD_INGOT || m == Material.DIAMOND || m == Material.EMERALD;
    }

    static String currencyName(Material m) {
        return switch (m) {
            case IRON_INGOT -> "Iron";
            case GOLD_INGOT -> "Gold";
            case DIAMOND -> "Diamond";
            case EMERALD -> "Emerald";
            default -> m.name();
        };
    }

    static String currencyColor(Material m) {
        return switch (m) {
            case IRON_INGOT -> "<white>";
            case GOLD_INGOT -> "<gold>";
            case DIAMOND -> "<aqua>";
            case EMERALD -> "<green>";
            default -> "<gray>";
        };
    }

    private static int count(Player p, Material m) {
        int total = 0;
        for (ItemStack item : p.getInventory().getStorageContents()) {
            if (item != null && item.getType() == m) {
                total += item.getAmount();
            }
        }
        return total;
    }

    private static void take(Player p, Material m, int amount) {
        p.getInventory().removeItem(new ItemStack(m, amount));
    }

    static ItemStack pickaxe(int tier) {
        Material m = switch (tier) {
            case 1 -> Material.WOODEN_PICKAXE;
            case 2 -> Material.IRON_PICKAXE;
            case 3 -> Material.GOLDEN_PICKAXE;
            default -> Material.DIAMOND_PICKAXE;
        };
        return ItemBuilder.of(m).enchant(Enchantment.EFFICIENCY, Math.min(3, tier)).unbreakable().build();
    }

    static ItemStack axe(int tier) {
        Material m = switch (tier) {
            case 1 -> Material.WOODEN_AXE;
            case 2 -> Material.STONE_AXE;
            case 3 -> Material.IRON_AXE;
            default -> Material.DIAMOND_AXE;
        };
        return ItemBuilder.of(m).enchant(Enchantment.EFFICIENCY, Math.min(3, tier)).unbreakable().build();
    }

    private static int pickaxePrice(int tier) {
        return tier <= 2 ? 10 : tier == 3 ? 3 : 6;
    }

    private static Material pickaxeCurrency(int tier) {
        return tier <= 2 ? Material.IRON_INGOT : Material.GOLD_INGOT;
    }

    private static ItemStack withPrice(ItemStack item, Material currency, int price) {
        ItemStack copy = item.clone();
        copy.editMeta(meta -> {
            List<net.kyori.adventure.text.Component> lore = meta.lore() == null ? new ArrayList<>() : new ArrayList<>(meta.lore());
            lore.add(Msg.mm(""));
            lore.add(Msg.mm("<gray>Cost: " + currencyColor(currency) + price + " " + currencyName(currency)));
            meta.lore(lore);
        });
        return copy;
    }

    /** Gives an item, swapping out the wooden sword when a better sword is bought. */
    private void giveItem(Player p, ItemStack item) {
        PlayerInventory inv = p.getInventory();
        if (item.getType().name().endsWith("_SWORD")) {
            inv.remove(Material.WOODEN_SWORD);
        }
        if (!inv.addItem(item).isEmpty()) {
            p.getWorld().dropItem(p.getLocation(), item);
        }
    }

    // ---------------------------------------------------------------- offers

    private List<Offer> offers(Player viewer, int category) {
        Team team = game.team(viewer);
        Material wool = team == null ? Material.WHITE_WOOL : team.color.wool;
        Material glass = team == null ? Material.GLASS : team.color.glass;
        List<Offer> list = new ArrayList<>();
        switch (category) {
            case 0 -> {
                list.add(simple(new ItemStack(wool, 16), Material.IRON_INGOT, 4));
                list.add(simple(new ItemStack(Material.TERRACOTTA, 16), Material.IRON_INGOT, 12));
                list.add(simple(ItemBuilder.of(glass, 4).name("<white>Blast-Proof Glass").build(), Material.IRON_INGOT, 12));
                list.add(simple(new ItemStack(Material.END_STONE, 12), Material.IRON_INGOT, 24));
                list.add(simple(new ItemStack(Material.LADDER, 8), Material.IRON_INGOT, 4));
                list.add(simple(new ItemStack(Material.OAK_PLANKS, 16), Material.GOLD_INGOT, 4));
                list.add(simple(new ItemStack(Material.OBSIDIAN, 4), Material.EMERALD, 4));
            }
            case 1 -> {
                list.add(sword(Material.STONE_SWORD, Material.IRON_INGOT, 10));
                list.add(sword(Material.IRON_SWORD, Material.GOLD_INGOT, 7));
                list.add(sword(Material.DIAMOND_SWORD, Material.EMERALD, 4));
                list.add(simple(ItemBuilder.of(Material.STICK).name("<white>Knockback Stick")
                        .enchant(Enchantment.KNOCKBACK, 1).build(), Material.GOLD_INGOT, 5));
            }
            case 2 -> {
                list.add(armorOffer(1, Material.CHAINMAIL_BOOTS, "Permanent Chainmail Armor", Material.IRON_INGOT, 24));
                list.add(armorOffer(2, Material.IRON_BOOTS, "Permanent Iron Armor", Material.GOLD_INGOT, 12));
                list.add(armorOffer(3, Material.DIAMOND_BOOTS, "Permanent Diamond Armor", Material.EMERALD, 6));
            }
            case 3 -> {
                BedWars.Kit kit = game.kit(viewer);
                int nextPick = Math.min(4, kit.pickaxe + 1);
                list.add(new Offer(p -> {
                    BedWars.Kit k = game.kit(p);
                    return k.pickaxe >= 4 ? ItemBuilder.of(Material.DIAMOND_PICKAXE).name("<green>Pickaxe maxed").build()
                            : ItemBuilder.of(pickaxe(k.pickaxe + 1).getType()).name("<white>Pickaxe tier " + (k.pickaxe + 1))
                            .lore("<gray>Upgradable, you keep it on death", "<gray>(it drops one tier when you die)").build();
                }, pickaxeCurrency(nextPick), pickaxePrice(nextPick), p -> {
                    BedWars.Kit k = game.kit(p);
                    if (k.pickaxe >= 4) {
                        return false;
                    }
                    k.pickaxe++;
                    replaceTool(p, "_PICKAXE", pickaxe(k.pickaxe));
                    return true;
                }));
                int nextAxe = Math.min(4, kit.axe + 1);
                list.add(new Offer(p -> {
                    BedWars.Kit k = game.kit(p);
                    return k.axe >= 4 ? ItemBuilder.of(Material.DIAMOND_AXE).name("<green>Axe maxed").build()
                            : ItemBuilder.of(axe(k.axe + 1).getType()).name("<white>Axe tier " + (k.axe + 1))
                            .lore("<gray>Upgradable, you keep it on death").build();
                }, pickaxeCurrency(nextAxe), pickaxePrice(nextAxe), p -> {
                    BedWars.Kit k = game.kit(p);
                    if (k.axe >= 4) {
                        return false;
                    }
                    k.axe++;
                    replaceTool(p, "_AXE", axe(k.axe));
                    return true;
                }));
                list.add(new Offer(p -> ItemBuilder.of(Material.SHEARS).name("<white>Permanent Shears").build(),
                        Material.IRON_INGOT, 20, p -> {
                    BedWars.Kit k = game.kit(p);
                    if (k.shears) {
                        return false;
                    }
                    k.shears = true;
                    giveItem(p, ItemBuilder.of(Material.SHEARS).unbreakable().build());
                    return true;
                }));
            }
            case 4 -> {
                list.add(simple(new ItemStack(Material.ARROW, 6), Material.GOLD_INGOT, 2));
                list.add(simple(ItemBuilder.of(Material.BOW).unbreakable().build(), Material.GOLD_INGOT, 12));
                list.add(simple(ItemBuilder.of(Material.BOW).enchant(Enchantment.POWER, 1).unbreakable().build(), Material.GOLD_INGOT, 20));
                list.add(simple(ItemBuilder.of(Material.BOW).enchant(Enchantment.POWER, 1).enchant(Enchantment.PUNCH, 1)
                        .unbreakable().build(), Material.EMERALD, 6));
            }
            default -> {
                list.add(simple(new ItemStack(Material.GOLDEN_APPLE), Material.GOLD_INGOT, 3));
                list.add(simple(ItemBuilder.of(Material.FIRE_CHARGE).name("<gold>Fireball").lore("<gray>Right click to launch").build(), Material.IRON_INGOT, 40));
                list.add(simple(new ItemStack(Material.TNT), Material.GOLD_INGOT, 4));
                list.add(simple(new ItemStack(Material.ENDER_PEARL), Material.EMERALD, 4));
                list.add(simple(ItemBuilder.of(Material.POTION).name("<aqua>Speed II Potion (45s)")
                        .potion(PotionEffectType.SPEED, 45, 1).potionColor(Color.AQUA).build(), Material.EMERALD, 1));
                list.add(simple(ItemBuilder.of(Material.POTION).name("<green>Jump V Potion (45s)")
                        .potion(PotionEffectType.JUMP_BOOST, 45, 4).potionColor(Color.LIME).build(), Material.EMERALD, 1));
                list.add(simple(ItemBuilder.of(Material.POTION).name("<gray>Invisibility Potion (30s)")
                        .potion(PotionEffectType.INVISIBILITY, 30, 0).potionColor(Color.GRAY).build(), Material.EMERALD, 2));
            }
        }
        return list;
    }

    private Offer simple(ItemStack item, Material currency, int price) {
        return new Offer(p -> item, currency, price, p -> {
            giveItem(p, item.clone());
            return true;
        });
    }

    private Offer sword(Material material, Material currency, int price) {
        return new Offer(p -> new ItemStack(material), currency, price, p -> {
            giveItem(p, game.sword(material, game.team(p)));
            return true;
        });
    }

    private Offer armorOffer(int tier, Material icon, String name, Material currency, int price) {
        return new Offer(p -> ItemBuilder.of(icon).name("<white>" + name).lore("<gray>Leggings and boots, kept on death").build(),
                currency, price, p -> {
            BedWars.Kit k = game.kit(p);
            if (k.armor >= tier) {
                return false;
            }
            k.armor = tier;
            game.dressArmor(p);
            return true;
        });
    }

    private void replaceTool(Player p, String suffix, ItemStack replacement) {
        PlayerInventory inv = p.getInventory();
        for (int i = 0; i < inv.getSize(); i++) {
            ItemStack item = inv.getItem(i);
            if (item != null && item.getType().name().endsWith(suffix)) {
                inv.setItem(i, replacement);
                return;
            }
        }
        giveItem(p, replacement);
    }

    // ------------------------------------------------------------------ menus

    void openShop(Player player, int category) {
        Gui gui = new Gui(6, "<dark_gray>Item Shop - " + CATEGORIES[category]);
        for (int i = 0; i < CATEGORIES.length; i++) {
            int cat = i;
            ItemBuilder b = ItemBuilder.of(CATEGORY_ICONS[i]).name((i == category ? "<green>" : "<yellow>") + CATEGORIES[i]).flags();
            if (i == category) {
                b.glow();
            }
            gui.set(i + 1, b.build(), (p, click) -> openShop(p, cat));
        }
        ItemStack line = ItemBuilder.of(Material.GRAY_STAINED_GLASS_PANE).name(" ").build();
        for (int i = 9; i < 18; i++) {
            gui.set(i, line);
        }
        List<Offer> offers = offers(player, category);
        int[] slots = {19, 20, 21, 22, 23, 24, 25, 28, 29, 30, 31, 32, 33, 34};
        for (int i = 0; i < offers.size() && i < slots.length; i++) {
            Offer offer = offers.get(i);
            gui.set(slots[i], withPrice(offer.icon().apply(player), offer.currency(), offer.price()), (p, click) -> {
                purchase(p, offer);
                openShop(p, category);
            });
        }
        gui.set(49, ItemBuilder.of(Material.BOOK).name("<gray>Your resources")
                .lore("<white>Iron: " + count(player, Material.IRON_INGOT), "<gold>Gold: " + count(player, Material.GOLD_INGOT),
                        "<aqua>Diamonds: " + count(player, Material.DIAMOND), "<green>Emeralds: " + count(player, Material.EMERALD)).build());
        gui.open(player);
    }

    private void purchase(Player p, Offer offer) {
        if (count(p, offer.currency()) < offer.price()) {
            Msg.send(p, "<red>You need " + offer.price() + " " + currencyName(offer.currency()) + "!");
            Msg.sound(p, "entity.villager.no", 1f);
            return;
        }
        if (!offer.buy().test(p)) {
            Msg.send(p, "<red>You already have that.");
            Msg.sound(p, "entity.villager.no", 1f);
            return;
        }
        take(p, offer.currency(), offer.price());
        Msg.sound(p, "entity.experience_orb.pickup", 1.2f);
    }

    void openUpgrades(Player player) {
        Team team = game.team(player);
        if (team == null) {
            return;
        }
        Gui gui = new Gui(3, "<dark_gray>Team Upgrades");
        gui.set(10, upgradeIcon(Material.IRON_SWORD, "Sharpened Swords", "All swords get Sharpness I",
                team.sharpness ? -1 : 4), (p, c) -> buyUpgrade(p, team, 0));
        gui.set(11, upgradeIcon(Material.IRON_CHESTPLATE, "Reinforced Armor " + roman(team.protection + 1),
                "Protection on all team armor", team.protection >= 4 ? -1 : 2 << team.protection), (p, c) -> buyUpgrade(p, team, 1));
        gui.set(12, upgradeIcon(Material.GOLDEN_PICKAXE, "Maniac Miner " + roman(team.haste + 1),
                "Permanent Haste for the team", team.haste >= 2 ? -1 : 2 + team.haste * 2), (p, c) -> buyUpgrade(p, team, 2));
        gui.set(13, upgradeIcon(Material.FURNACE, "Iron Forge " + roman(team.forge + 1),
                team.forge == 2 ? "Faster generator + emeralds" : "Faster island generator", team.forge >= 3 ? -1 : 2 + team.forge * 2),
                (p, c) -> buyUpgrade(p, team, 3));
        gui.set(14, upgradeIcon(Material.BEACON, "Heal Pool", "Regeneration near your island",
                team.healPool ? -1 : 1), (p, c) -> buyUpgrade(p, team, 4));
        gui.set(16, ItemBuilder.of(Material.DIAMOND).name("<aqua>You have " + count(player, Material.DIAMOND) + " diamonds").build());
        gui.fill(ItemBuilder.of(Material.GRAY_STAINED_GLASS_PANE).name(" ").build());
        gui.open(player);
    }

    private static String roman(int n) {
        return switch (n) {
            case 1 -> "I";
            case 2 -> "II";
            case 3 -> "III";
            case 4 -> "IV";
            default -> String.valueOf(n);
        };
    }

    private ItemStack upgradeIcon(Material icon, String name, String description, int price) {
        ItemBuilder b = ItemBuilder.of(icon).name((price < 0 ? "<green>" : "<yellow>") + name).flags();
        b.lore("<gray>" + description, "");
        b.lore(price < 0 ? "<green>Unlocked (max)" : "<gray>Cost: <aqua>" + price + " Diamonds");
        return b.build();
    }

    private void buyUpgrade(Player p, Team team, int which) {
        int price = switch (which) {
            case 0 -> team.sharpness ? -1 : 4;
            case 1 -> team.protection >= 4 ? -1 : 2 << team.protection;
            case 2 -> team.haste >= 2 ? -1 : 2 + team.haste * 2;
            case 3 -> team.forge >= 3 ? -1 : 2 + team.forge * 2;
            default -> team.healPool ? -1 : 1;
        };
        if (price < 0) {
            Msg.send(p, "<gray>Your team already has that upgrade.");
            return;
        }
        if (count(p, Material.DIAMOND) < price) {
            Msg.send(p, "<red>You need " + price + " diamonds!");
            Msg.sound(p, "entity.villager.no", 1f);
            return;
        }
        take(p, Material.DIAMOND, price);
        String name;
        switch (which) {
            case 0 -> {
                team.sharpness = true;
                name = "Sharpened Swords";
            }
            case 1 -> {
                team.protection++;
                name = "Reinforced Armor " + roman(team.protection);
            }
            case 2 -> {
                team.haste++;
                name = "Maniac Miner " + roman(team.haste);
            }
            case 3 -> {
                team.forge++;
                name = "Iron Forge " + roman(team.forge);
            }
            default -> {
                team.healPool = true;
                name = "Heal Pool";
            }
        }
        game.refreshTeam(team);
        for (Player member : game.members(team)) {
            Msg.send(member, "<green>" + p.getName() + " bought <gold>" + name + "<green>!");
            Msg.sound(member, "block.note_block.pling", 1.6f);
        }
        openUpgrades(p);
    }
}
