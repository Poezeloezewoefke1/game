package net.funcraft.games.listener;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Gui;
import net.funcraft.games.util.Msg;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.Material;
import org.bukkit.World;
import org.bukkit.entity.Entity;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.block.Action;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockBurnEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.block.BlockSpreadEvent;
import org.bukkit.event.block.LeavesDecayEvent;
import org.bukkit.event.entity.CreatureSpawnEvent;
import org.bukkit.event.entity.EntityDamageByEntityEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.entity.FoodLevelChangeEvent;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.inventory.InventoryDragEvent;
import org.bukkit.event.player.PlayerDropItemEvent;
import org.bukkit.event.player.PlayerInteractAtEntityEvent;
import org.bukkit.event.player.PlayerInteractEntityEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerMoveEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.event.player.PlayerSwapHandItemsEvent;
import org.bukkit.event.player.PlayerToggleFlightEvent;
import org.bukkit.event.weather.WeatherChangeEvent;
import org.bukkit.inventory.EquipmentSlot;
import org.bukkit.util.Vector;

import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

/** Hub protection, hub items, NPCs, menus and world-wide rules for plugin worlds. */
public final class HubListener implements Listener {

    private final FunCraft plugin;
    private final Set<UUID> builders = new HashSet<>();

    public HubListener(FunCraft plugin) {
        this.plugin = plugin;
    }

    public boolean toggleBuild(Player player) {
        if (!builders.remove(player.getUniqueId())) {
            builders.add(player.getUniqueId());
            return true;
        }
        return false;
    }

    private boolean inHub(Entity entity) {
        return entity.getWorld().equals(plugin.hub().world());
    }

    private boolean canBuild(Player player) {
        return builders.contains(player.getUniqueId()) && player.getGameMode() == GameMode.CREATIVE;
    }

    private static boolean pluginWorld(World world) {
        return world.getName().startsWith("fc_");
    }

    @EventHandler
    public void onJoin(PlayerJoinEvent event) {
        Player player = event.getPlayer();
        event.joinMessage(plugin.bots().isBot(player) ? null : Msg.mm("<dark_gray>[<green>+</green>]</dark_gray> <gray>" + player.getName()));
        Bukkit.getScheduler().runTask(plugin, () -> {
            if (player.isOnline()) {
                plugin.hub().send(player);
                Msg.title(player, "<gradient:#ffb300:#ff5e00><bold>" + plugin.serverName(), "<gray>Pick a game with the compass!", 10, 60, 20);
            }
        });
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        event.quitMessage(plugin.bots().isBot(event.getPlayer()) ? null
                : Msg.mm("<dark_gray>[<red>-</red>]</dark_gray> <gray>" + event.getPlayer().getName()));
        plugin.games().quit(event.getPlayer());
        plugin.sidebars().remove(event.getPlayer());
        plugin.duels().clear(event.getPlayer());
        plugin.parties().quit(event.getPlayer());
        plugin.chat().remove(event.getPlayer());
        builders.remove(event.getPlayer().getUniqueId());
    }

    // --------------------------------------------------------------- items

    @EventHandler(priority = EventPriority.LOW)
    public void onUseItem(PlayerInteractEvent event) {
        if (event.getAction() == Action.PHYSICAL || event.getHand() != EquipmentSlot.HAND) {
            return;
        }
        String id = plugin.hub().hubItem(event.getItem());
        if (id == null) {
            if (inHub(event.getPlayer()) && !canBuild(event.getPlayer())) {
                event.setCancelled(true);
            }
            return;
        }
        event.setCancelled(true);
        Player p = event.getPlayer();
        switch (id) {
            case "selector" -> plugin.hub().openSelector(p);
            case "stats" -> plugin.hub().openStats(p, p.getUniqueId());
            case "spawn" -> p.teleport(plugin.hub().spawn());
            case "leave" -> plugin.games().leave(p);
            default -> {
                Game game = plugin.games().gameOf(p);
                if (game != null) {
                    game.onQueueItem(p, id);
                }
            }
        }
    }

    @EventHandler
    public void onNpc(PlayerInteractEntityEvent event) {
        GameType type = plugin.hub().npcGame(event.getRightClicked());
        if (type != null) {
            event.setCancelled(true);
            if (event.getHand() == EquipmentSlot.HAND) {
                plugin.games().join(event.getPlayer(), type);
            }
        }
    }

    @EventHandler
    public void onNpcAt(PlayerInteractAtEntityEvent event) {
        if (plugin.hub().npcGame(event.getRightClicked()) != null) {
            event.setCancelled(true);
        }
    }

    @EventHandler(priority = EventPriority.LOW)
    public void onHitNpc(EntityDamageByEntityEvent event) {
        GameType type = plugin.hub().npcGame(event.getEntity());
        if (type != null) {
            event.setCancelled(true);
            if (event.getDamager() instanceof Player p) {
                plugin.games().join(p, type);
            }
        }
    }

    // ------------------------------------------------------------- menus

    @EventHandler(priority = EventPriority.LOW)
    public void onClick(InventoryClickEvent event) {
        if (event.getInventory().getHolder() instanceof Gui gui) {
            event.setCancelled(true);
            if (event.getWhoClicked() instanceof Player p && event.getClickedInventory() == event.getView().getTopInventory()) {
                int slot = event.getRawSlot();
                org.bukkit.event.inventory.ClickType click = event.getClick();
                // run next tick: actions may close or open inventories
                Bukkit.getScheduler().runTask(plugin, () -> gui.click(p, slot, click));
            }
            return;
        }
        if (event.getWhoClicked() instanceof Player p && inHub(p) && !canBuild(p)) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onDrag(InventoryDragEvent event) {
        if (event.getInventory().getHolder() instanceof Gui
                || (event.getWhoClicked() instanceof Player p && inHub(p) && !canBuild(p))) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onSwap(PlayerSwapHandItemsEvent event) {
        if (inHub(event.getPlayer()) && !canBuild(event.getPlayer())) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onDrop(PlayerDropItemEvent event) {
        if (inHub(event.getPlayer()) && !canBuild(event.getPlayer())) {
            event.setCancelled(true);
        }
    }

    // -------------------------------------------------------- protection

    @EventHandler(priority = EventPriority.LOW)
    public void onBreak(BlockBreakEvent event) {
        if (inHub(event.getPlayer()) && !canBuild(event.getPlayer())) {
            event.setCancelled(true);
        }
    }

    @EventHandler(priority = EventPriority.LOW)
    public void onPlace(BlockPlaceEvent event) {
        if (inHub(event.getPlayer()) && !canBuild(event.getPlayer())) {
            event.setCancelled(true);
        }
    }

    @EventHandler(priority = EventPriority.LOW)
    public void onDamage(EntityDamageEvent event) {
        if (inHub(event.getEntity())) {
            event.setCancelled(true);
            if (event.getEntity() instanceof Player p && event.getCause() == EntityDamageEvent.DamageCause.VOID) {
                p.teleport(plugin.hub().spawn());
            }
        }
    }

    @EventHandler
    public void onHunger(FoodLevelChangeEvent event) {
        if (inHub(event.getEntity())) {
            event.setCancelled(true);
            event.getEntity().setFoodLevel(20);
        }
    }

    @EventHandler(ignoreCancelled = true)
    public void onMove(PlayerMoveEvent event) {
        Player p = event.getPlayer();
        if (!inHub(p)) {
            return;
        }
        if (event.getTo().getY() < 35) {
            p.teleport(plugin.hub().spawn());
            p.setFallDistance(0);
        } else if (p.getGameMode() == GameMode.ADVENTURE && !p.getAllowFlight() && ((org.bukkit.entity.Entity) p).isOnGround()
                && !plugin.parkour().isRunning(p)) {
            p.setAllowFlight(true); // recharge double jump on landing
        }
    }

    /** Double jump in the hub: pressing jump twice launches you instead of flying. */
    @EventHandler
    public void onDoubleJump(PlayerToggleFlightEvent event) {
        Player p = event.getPlayer();
        if (!inHub(p) || p.getGameMode() != GameMode.ADVENTURE) {
            return;
        }
        event.setCancelled(true);
        plugin.antiCheat().exempt(p, 2500);
        p.setAllowFlight(false);
        p.setFlying(false);
        p.setVelocity(p.getLocation().getDirection().setY(0).normalize().multiply(1.1).setY(0.9));
        Msg.sound(p, "entity.bat.takeoff", 1.3f);
    }

    /** Launch pads (heavy pressure plates) fling you up and back towards the spawn. */
    @EventHandler
    public void onLaunchPad(PlayerInteractEvent event) {
        if (event.getAction() != Action.PHYSICAL || event.getClickedBlock() == null
                || event.getClickedBlock().getType() != Material.HEAVY_WEIGHTED_PRESSURE_PLATE || !inHub(event.getPlayer())) {
            return;
        }
        Player p = event.getPlayer();
        plugin.antiCheat().exempt(p, 4000);
        Vector toSpawn = plugin.hub().spawn().toVector().subtract(p.getLocation().toVector()).setY(0);
        p.setVelocity(toSpawn.normalize().multiply(1.6).setY(1.4));
        p.setFallDistance(0);
        Msg.sound(p, "entity.firework_rocket.launch", 1f);
    }

    // ------------------------------------------------- plugin world rules

    @EventHandler
    public void onSpawn(CreatureSpawnEvent event) {
        if (!pluginWorld(event.getLocation().getWorld())) {
            return;
        }
        switch (event.getSpawnReason()) {
            case CUSTOM, SPAWNER_EGG, COMMAND, BUILD_IRONGOLEM, BUILD_SNOWMAN, DISPENSE_EGG -> {
            }
            default -> event.setCancelled(true);
        }
    }

    @EventHandler
    public void onWeather(WeatherChangeEvent event) {
        if (pluginWorld(event.getWorld()) && event.toWeatherState()) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onLeaves(LeavesDecayEvent event) {
        if (pluginWorld(event.getBlock().getWorld())) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onBurn(BlockBurnEvent event) {
        if (pluginWorld(event.getBlock().getWorld())) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onSpread(BlockSpreadEvent event) {
        if (pluginWorld(event.getBlock().getWorld())) {
            event.setCancelled(true);
        }
    }
}
