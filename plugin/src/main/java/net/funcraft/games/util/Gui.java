package net.funcraft.games.util;

import org.bukkit.Bukkit;
import org.bukkit.entity.Player;
import org.bukkit.event.inventory.ClickType;
import org.bukkit.inventory.Inventory;
import org.bukkit.inventory.InventoryHolder;
import org.bukkit.inventory.ItemStack;

import java.util.HashMap;
import java.util.Map;
import java.util.function.BiConsumer;

/** Chest menu whose buttons run code. Clicks are routed by {@code GuiListener}. */
public final class Gui implements InventoryHolder {

    private final Inventory inventory;
    private final Map<Integer, BiConsumer<Player, ClickType>> actions = new HashMap<>();

    public Gui(int rows, String title) {
        this.inventory = Bukkit.createInventory(this, rows * 9, Msg.mm(title));
    }

    public Gui set(int slot, ItemStack item, BiConsumer<Player, ClickType> action) {
        inventory.setItem(slot, item);
        if (action != null) {
            actions.put(slot, action);
        } else {
            actions.remove(slot);
        }
        return this;
    }

    public Gui set(int slot, ItemStack item) {
        return set(slot, item, null);
    }

    public Gui fill(ItemStack filler) {
        for (int i = 0; i < inventory.getSize(); i++) {
            if (inventory.getItem(i) == null) {
                inventory.setItem(i, filler);
            }
        }
        return this;
    }

    public void open(Player player) {
        player.openInventory(inventory);
    }

    public void click(Player player, int slot, ClickType type) {
        BiConsumer<Player, ClickType> action = actions.get(slot);
        if (action != null) {
            action.accept(player, type);
        }
    }

    @Override
    public Inventory getInventory() {
        return inventory;
    }
}
