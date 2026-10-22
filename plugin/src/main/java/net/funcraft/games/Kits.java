package net.funcraft.games;

import io.papermc.paper.registry.RegistryAccess;
import io.papermc.paper.registry.RegistryKey;
import net.funcraft.games.util.ItemBuilder;
import org.bukkit.Color;
import org.bukkit.Material;
import org.bukkit.NamespacedKey;
import org.bukkit.Registry;
import org.bukkit.configuration.ConfigurationSection;
import org.bukkit.configuration.file.YamlConfiguration;
import org.bukkit.enchantments.Enchantment;
import org.bukkit.entity.Player;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.PlayerInventory;
import org.bukkit.inventory.meta.CrossbowMeta;
import org.bukkit.inventory.meta.PotionMeta;
import org.bukkit.potion.PotionType;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** PvP kits loaded from kits.yml. */
public final class Kits {

    public static final String DEFAULT = "classic";

    /** {@code deep}: the kit is played on a deep, fully destructible terrain map (crystals, creepers). */
    public record Kit(String id, String name, Material icon, String description, ItemStack helmet, ItemStack chestplate,
                      ItemStack leggings, ItemStack boots, ItemStack offhand, Map<Integer, ItemStack> items, boolean deep) {

        public void apply(Player player) {
            PlayerInventory inv = player.getInventory();
            inv.clear();
            inv.setHelmet(copy(helmet));
            inv.setChestplate(copy(chestplate));
            inv.setLeggings(copy(leggings));
            inv.setBoots(copy(boots));
            inv.setItemInOffHand(copy(offhand));
            for (Map.Entry<Integer, ItemStack> e : items.entrySet()) {
                inv.setItem(e.getKey(), e.getValue().clone());
            }
            inv.setHeldItemSlot(0);
        }

        private static ItemStack copy(ItemStack item) {
            return item == null ? null : item.clone();
        }
    }

    private final FunCraft plugin;
    private final Map<String, Kit> kits = new LinkedHashMap<>();

    public Kits(FunCraft plugin) {
        this.plugin = plugin;
    }

    public void load() {
        File file = new File(plugin.getDataFolder(), "kits.yml");
        if (!file.exists()) {
            plugin.saveResource("kits.yml", false);
        }
        kits.clear();
        YamlConfiguration yaml = YamlConfiguration.loadConfiguration(file);
        ConfigurationSection section = yaml.getConfigurationSection("kits");
        if (section != null) {
            for (String id : section.getKeys(false)) {
                ConfigurationSection k = section.getConfigurationSection(id);
                if (k == null) {
                    continue;
                }
                try {
                    kits.put(id.toLowerCase(Locale.ROOT), parseKit(id.toLowerCase(Locale.ROOT), k));
                } catch (Exception e) {
                    plugin.getLogger().warning("Skipping kit '" + id + "': " + e.getMessage());
                }
            }
        }
        if (!kits.containsKey(DEFAULT)) {
            Map<Integer, ItemStack> items = new HashMap<>();
            items.put(0, new ItemStack(Material.IRON_SWORD));
            kits.put(DEFAULT, new Kit(DEFAULT, "<gold>Classic", Material.IRON_SWORD, "", new ItemStack(Material.IRON_HELMET),
                    new ItemStack(Material.IRON_CHESTPLATE), new ItemStack(Material.IRON_LEGGINGS), new ItemStack(Material.IRON_BOOTS),
                    null, items, false));
        }
        plugin.getLogger().info("Loaded " + kits.size() + " PvP kits.");
    }

    private Kit parseKit(String id, ConfigurationSection k) {
        Material icon = Material.matchMaterial(k.getString("icon", "iron_sword"));
        Map<Integer, ItemStack> items = new HashMap<>();
        ConfigurationSection itemSection = k.getConfigurationSection("items");
        if (itemSection != null) {
            for (String slot : itemSection.getKeys(false)) {
                int index = Integer.parseInt(slot);
                ItemStack item = parseItem(itemSection.getString(slot, ""));
                if (item != null && index >= 0 && index < 36) {
                    items.put(index, item);
                }
            }
        }
        return new Kit(id, k.getString("name", id), icon == null ? Material.IRON_SWORD : icon, k.getString("description", ""),
                parseItem(k.getString("helmet")), parseItem(k.getString("chestplate")), parseItem(k.getString("leggings")),
                parseItem(k.getString("boots")), parseItem(k.getString("offhand")), items,
                "deep".equalsIgnoreCase(k.getString("map", "")));
    }

    /**
     * Parses "material [xCOUNT] [enchant:level ...] [potion:type] [unbreakable] [color:#RRGGBB] [charged:potion]".
     * Unknown parts are skipped.
     */
    private ItemStack parseItem(String spec) {
        if (spec == null || spec.isBlank()) {
            return null;
        }
        String[] parts = spec.trim().split("\\s+");
        Material material = Material.matchMaterial(parts[0]);
        if (material == null || !material.isItem()) {
            plugin.getLogger().warning("Unknown item '" + parts[0] + "' in kits.yml (not on this Minecraft version?)");
            return null;
        }
        int amount = 1;
        List<String[]> enchants = new ArrayList<>();
        String potion = null;
        String charged = null;
        Color color = null;
        boolean unbreakable = false;
        for (int i = 1; i < parts.length; i++) {
            String p = parts[i].toLowerCase(Locale.ROOT);
            if (p.startsWith("x") && p.length() > 1 && p.substring(1).chars().allMatch(Character::isDigit)) {
                amount = Integer.parseInt(p.substring(1));
            } else if (p.startsWith("potion:")) {
                potion = p.substring(7);
            } else if (p.startsWith("charged:")) {
                charged = p.substring(8);
            } else if (p.startsWith("color:")) {
                try {
                    color = Color.fromRGB(Integer.parseInt(p.substring(6).replace("#", ""), 16) & 0xFFFFFF);
                } catch (NumberFormatException e) {
                    plugin.getLogger().warning("Bad color '" + p + "' in kits.yml (use color:#RRGGBB)");
                }
            } else if (p.equals("unbreakable")) {
                unbreakable = true;
            } else if (p.contains(":")) {
                enchants.add(p.split(":", 2));
            }
        }
        ItemBuilder builder = ItemBuilder.of(material, Math.min(amount, material.getMaxStackSize()));
        for (String[] e : enchants) {
            Enchantment enchantment = RegistryAccess.registryAccess().getRegistry(RegistryKey.ENCHANTMENT).get(NamespacedKey.minecraft(e[0]));
            if (enchantment == null) {
                plugin.getLogger().warning("Unknown enchantment '" + e[0] + "' in kits.yml");
                continue;
            }
            builder.enchant(enchantment, Integer.parseInt(e[1]));
        }
        if (unbreakable) {
            builder.unbreakable();
        }
        if (color != null) {
            builder.color(color);
        }
        ItemStack item = builder.build();
        if (potion != null) {
            applyPotion(item, potion);
        }
        if (charged != null && item.getItemMeta() instanceof CrossbowMeta meta) {
            ItemStack arrow = new ItemStack(charged.equals("arrow") ? Material.ARROW : Material.TIPPED_ARROW);
            if (arrow.getType() == Material.TIPPED_ARROW) {
                applyPotion(arrow, charged);
            }
            meta.addChargedProjectile(arrow);
            item.setItemMeta(meta);
        }
        return item;
    }

    private void applyPotion(ItemStack item, String potion) {
        if (item.getItemMeta() instanceof PotionMeta meta) {
            PotionType type = Registry.POTION.get(NamespacedKey.minecraft(potion));
            if (type != null) {
                meta.setBasePotionType(type);
                item.setItemMeta(meta);
            } else {
                plugin.getLogger().warning("Unknown potion '" + potion + "' in kits.yml");
            }
        }
    }

    public Kit get(String id) {
        return id == null ? null : kits.get(id.toLowerCase(Locale.ROOT));
    }

    public Kit getOrDefault(String id) {
        Kit kit = get(id);
        return kit != null ? kit : kits.get(DEFAULT);
    }

    public List<Kit> all() {
        return new ArrayList<>(kits.values());
    }
}
