package net.funcraft.games.listener;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import org.bukkit.entity.Player;
import org.bukkit.entity.Projectile;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockExplodeEvent;
import org.bukkit.event.block.BlockFromToEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.entity.EntityExplodeEvent;
import org.bukkit.event.entity.EntityPickupItemEvent;
import org.bukkit.event.entity.FoodLevelChangeEvent;
import org.bukkit.event.entity.PlayerDeathEvent;
import org.bukkit.event.entity.ProjectileHitEvent;
import org.bukkit.event.inventory.CraftItemEvent;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.player.PlayerBedEnterEvent;
import org.bukkit.event.player.PlayerChangedWorldEvent;
import org.bukkit.event.player.PlayerDropItemEvent;
import org.bukkit.event.player.PlayerInteractEntityEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.event.player.PlayerMoveEvent;
import org.bukkit.event.player.PlayerRespawnEvent;
import org.bukkit.event.player.PlayerToggleFlightEvent;

/** Routes Bukkit events for players inside a match to that match. */
public final class GameListener implements Listener {

    private final FunCraft plugin;

    public GameListener(FunCraft plugin) {
        this.plugin = plugin;
    }

    private Game game(Player player) {
        return plugin.games().activeGameOf(player);
    }

    @EventHandler(priority = EventPriority.HIGH)
    public void onDamage(EntityDamageEvent event) {
        if (event.getEntity() instanceof Player player) {
            Game game = game(player);
            if (game != null) {
                game.handleDamage(event, player);
            }
        }
    }

    @EventHandler(priority = EventPriority.HIGH)
    public void onBreak(BlockBreakEvent event) {
        Game game = game(event.getPlayer());
        if (game != null) {
            if (game.state() != Game.State.RUNNING || !game.isAlive(event.getPlayer())) {
                event.setCancelled(true);
                return;
            }
            game.onBlockBreak(event);
        }
    }

    @EventHandler(priority = EventPriority.HIGH)
    public void onPlace(BlockPlaceEvent event) {
        Game game = game(event.getPlayer());
        if (game != null) {
            if (game.state() != Game.State.RUNNING || !game.isAlive(event.getPlayer())) {
                event.setCancelled(true);
                return;
            }
            game.onBlockPlace(event);
        }
    }

    @EventHandler(priority = EventPriority.HIGH)
    public void onInteract(PlayerInteractEvent event) {
        Game game = game(event.getPlayer());
        if (game != null && game.state() == Game.State.RUNNING && game.isAlive(event.getPlayer())) {
            game.onInteract(event);
        }
    }

    @EventHandler(priority = EventPriority.HIGH)
    public void onInteractEntity(PlayerInteractEntityEvent event) {
        Game game = game(event.getPlayer());
        if (game != null && game.state() == Game.State.RUNNING && game.isAlive(event.getPlayer())) {
            game.onInteractEntity(event);
        }
    }

    @EventHandler(priority = EventPriority.HIGH)
    public void onInventoryClick(InventoryClickEvent event) {
        if (event.getWhoClicked() instanceof Player player) {
            Game game = game(player);
            if (game != null && game.state() == Game.State.RUNNING) {
                game.onInventoryClick(event);
            }
        }
    }

    @EventHandler(ignoreCancelled = true)
    public void onMove(PlayerMoveEvent event) {
        Player player = event.getPlayer();
        Game game = game(player);
        if (game == null) {
            return;
        }
        if (event.getTo().getY() < game.voidY()) {
            game.handleVoid(player);
            return;
        }
        if (game.state() == Game.State.RUNNING && game.isAlive(player)) {
            game.onMove(event);
        }
    }

    @EventHandler
    public void onHunger(FoodLevelChangeEvent event) {
        if (event.getEntity() instanceof Player player) {
            Game game = game(player);
            if (game != null && (!game.allowsHunger() || game.state() != Game.State.RUNNING)
                    && event.getFoodLevel() < player.getFoodLevel()) {
                event.setCancelled(true);
            }
        }
    }

    @EventHandler
    public void onDrop(PlayerDropItemEvent event) {
        Game game = game(event.getPlayer());
        if (game != null && (!game.allowsItemDrops() || game.state() != Game.State.RUNNING)) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onPickup(EntityPickupItemEvent event) {
        if (event.getEntity() instanceof Player player) {
            Game game = game(player);
            if (game != null && (!game.isAlive(player) || game.state() != Game.State.RUNNING)) {
                event.setCancelled(true);
            } else if (game != null) {
                game.onPickup(event, player);
            }
        }
    }

    @EventHandler
    public void onCraft(CraftItemEvent event) {
        if (event.getWhoClicked() instanceof Player player && game(player) != null) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onBed(PlayerBedEnterEvent event) {
        if (game(event.getPlayer()) != null) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onProjectileHit(ProjectileHitEvent event) {
        Projectile projectile = event.getEntity();
        Game game = plugin.games().gameOf(projectile.getWorld());
        if (game != null && game.state() == Game.State.RUNNING) {
            game.onProjectileHit(event);
        }
    }

    @EventHandler
    public void onExplode(EntityExplodeEvent event) {
        Game game = plugin.games().gameOf(event.getEntity().getWorld());
        if (game != null) {
            game.onExplode(event);
            net.funcraft.games.util.Explosives.onExplode(plugin, event);
        }
    }

    @EventHandler
    public void onBlockExplode(BlockExplodeEvent event) {
        if (plugin.games().gameOf(event.getBlock().getWorld()) != null) {
            event.blockList().clear();
        }
    }

    @EventHandler
    public void onToggleFlight(PlayerToggleFlightEvent event) {
        Game game = game(event.getPlayer());
        if (game != null && game.state() == Game.State.RUNNING && game.isAlive(event.getPlayer())) {
            game.onToggleFlight(event);
        }
    }

    @EventHandler(ignoreCancelled = true)
    public void onConsume(org.bukkit.event.player.PlayerItemConsumeEvent event) {
        Game game = game(event.getPlayer());
        if (game != null && game.state() == Game.State.RUNNING && game.isAlive(event.getPlayer())) {
            game.onConsume(event);
        }
    }

    @EventHandler(ignoreCancelled = true)
    public void onCreatureSpawn(org.bukkit.event.entity.CreatureSpawnEvent event) {
        Game game = plugin.games().gameOf(event.getLocation().getWorld());
        if (game != null && game.state() == Game.State.RUNNING) {
            game.onCreatureSpawn(event);
        }
    }

    @EventHandler
    public void onMobDeath(org.bukkit.event.entity.EntityDeathEvent event) {
        if (event.getEntity() instanceof Player) {
            return;
        }
        Game game = plugin.games().gameOf(event.getEntity().getWorld());
        if (game != null && game.state() == Game.State.RUNNING) {
            game.onMobDeath(event);
        }
    }

    @EventHandler
    public void onPortal(org.bukkit.event.player.PlayerPortalEvent event) {
        if (event.getFrom().getWorld().getName().startsWith("fc_")) {
            event.setCancelled(true); // end portals are goals in The Bridge, never real portals
        }
    }

    @EventHandler
    public void onEntityPortal(org.bukkit.event.entity.EntityPortalEvent event) {
        if (event.getFrom().getWorld().getName().startsWith("fc_")) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onFlow(BlockFromToEvent event) {
        Game game = plugin.games().gameOf(event.getBlock().getWorld());
        if (game != null) {
            game.onFlow(event);
        }
    }

    /** Safety net: should never happen because lethal damage is intercepted. */
    @EventHandler
    public void onDeath(PlayerDeathEvent event) {
        Game game = plugin.games().gameOf(event.getEntity());
        if (game != null) {
            event.getDrops().clear();
            event.setKeepInventory(false);
            event.deathMessage(null);
        }
    }

    @EventHandler
    public void onRespawn(PlayerRespawnEvent event) {
        Player player = event.getPlayer();
        Game game = plugin.games().gameOf(player);
        if (game == null || game.world() == null) {
            event.setRespawnLocation(plugin.hub().spawn());
            plugin.getServer().getScheduler().runTask(plugin, () -> plugin.hub().send(player));
            return;
        }
        event.setRespawnLocation(game.spectatorLocation());
        plugin.getServer().getScheduler().runTask(plugin, () -> game.handleRealDeath(player));
    }

    /** Players who end up outside their match world (e.g. via a command) leave the match. */
    @EventHandler
    public void onWorldChange(PlayerChangedWorldEvent event) {
        Player player = event.getPlayer();
        Game game = plugin.games().gameOf(player);
        if (game != null && game.world() != null && event.getFrom().equals(game.world())
                && !player.getWorld().equals(game.world())) {
            game.removePlayer(player);
            if (!player.getWorld().equals(plugin.hub().world())) {
                plugin.hub().send(player);
            }
        }
    }
}
