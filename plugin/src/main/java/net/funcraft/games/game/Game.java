package net.funcraft.games.game;

import net.funcraft.games.FunCraft;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Worlds;
import org.bukkit.Bukkit;
import org.bukkit.Chunk;
import org.bukkit.Color;
import org.bukkit.FireworkEffect;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.World;
import org.bukkit.entity.Entity;
import org.bukkit.entity.Firework;
import org.bukkit.entity.Player;
import org.bukkit.entity.Projectile;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockFromToEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityDamageByEntityEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.entity.EntityExplodeEvent;
import org.bukkit.event.entity.ProjectileHitEvent;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.player.PlayerInteractEntityEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.event.player.PlayerMoveEvent;
import org.bukkit.event.player.PlayerToggleFlightEvent;
import org.bukkit.inventory.meta.FireworkMeta;
import org.bukkit.scheduler.BukkitTask;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Random;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.logging.Level;

/**
 * One match of a minigame. Players wait in the hub while the match is WAITING/STARTING;
 * when the countdown ends a fresh void world is created, the map is generated and the
 * match runs until {@link #end} is called. The world is deleted afterwards.
 */
public abstract class Game {

    public enum State { WAITING, STARTING, RUNNING, ENDING }

    protected final FunCraft plugin;
    protected final GameType type;
    protected final int id;
    protected final Random random = new Random();

    protected State state = State.WAITING;
    protected World world;
    /** Everyone in the match, including eliminated spectators. */
    protected final Set<UUID> players = new LinkedHashSet<>();
    /** Players still in the running. */
    protected final Set<UUID> alive = new LinkedHashSet<>();
    protected final Map<UUID, Integer> kills = new HashMap<>();
    private final Map<UUID, UUID> lastAttacker = new HashMap<>();
    private final Map<UUID, Long> lastAttackTime = new HashMap<>();
    private final Map<UUID, Integer> streaks = new HashMap<>();

    /** Shown to players when the match starts, e.g. "Desert Isles". */
    protected String mapName;
    protected int countdown;
    protected int elapsed;
    protected int startingPlayers;
    private int endTimer;
    private boolean privateMatch;
    private int maxOverride;
    private boolean loading;
    /** Force-started by an admin: keep counting down even below the minimum players. */
    private boolean forced;
    private BukkitTask tickTask;

    protected Game(FunCraft plugin, int id, GameType type) {
        this.plugin = plugin;
        this.id = id;
        this.type = type;
    }

    // ------------------------------------------------------------------ hooks

    /** Generate the map into the freshly created void world. */
    protected abstract void buildMap();

    /**
     * Block area {minX, minZ, maxX, maxZ} the map will cover. Its chunks are loaded
     * asynchronously before {@link #buildMap()} runs so starting a game never freezes the server.
     */
    protected int[] mapArea() {
        return new int[]{-48, -48, 48, 48};
    }

    /** Teleport and equip players; the map exists at this point. */
    protected abstract void onStart(List<Player> players);

    /** A player lost all their health or fell into the void. */
    protected abstract void onDeath(Player victim, Player killer);

    /** A player joined the queue; give game-specific queue items here. */
    protected void onQueueJoin(Player player) {
    }

    /** A queue item with this id was used (see {@link net.funcraft.games.Hub#tag}). */
    public void onQueueItem(Player player, String id) {
    }

    /** Called every second while running. */
    protected void onSecond() {
    }

    /** Called every tick while running; enable with {@link #wantsTicks()}. */
    protected void onTick() {
    }

    protected boolean wantsTicks() {
        return false;
    }

    /** Lines under the title of the sidebar while running. */
    protected abstract List<String> sidebar(Player player);

    /** Where spectators and eliminated players are put. */
    protected abstract Location spectatorSpawn();

    /** Y level below which an alive player dies. */
    protected double voidLevel() {
        return 30;
    }

    protected boolean allowHunger() {
        return false;
    }

    protected boolean allowItemDrops() {
        return false;
    }

    protected int countdownSeconds() {
        return plugin.getConfig().getInt("countdown-seconds", 20);
    }

    /** Called before damage is applied; cancel the event to block it. */
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
    }

    public void onBlockBreak(BlockBreakEvent event) {
        event.setCancelled(true);
    }

    public void onBlockPlace(BlockPlaceEvent event) {
        event.setCancelled(true);
    }

    public void onInteract(PlayerInteractEvent event) {
    }

    public void onInteractEntity(PlayerInteractEntityEvent event) {
    }

    public void onInventoryClick(InventoryClickEvent event) {
    }

    public void onMove(PlayerMoveEvent event) {
    }

    public void onProjectileHit(ProjectileHitEvent event) {
    }

    public void onExplode(EntityExplodeEvent event) {
        event.blockList().clear();
    }

    public void onToggleFlight(PlayerToggleFlightEvent event) {
    }

    /** Liquids flowing; cancel to stop them. */
    public void onFlow(BlockFromToEvent event) {
    }

    /** Called when a match player disconnects or leaves while the match runs. */
    protected void onLeaveRunning(Player player) {
        if (alive.contains(player.getUniqueId())) {
            Msg.all(online(), "<gray>" + player.getName() + " left the game.");
            alive.remove(player.getUniqueId());
            checkWin();
        }
    }

    /** Default solo win check: last player alive wins. */
    protected void checkWin() {
        if (state != State.RUNNING) {
            return;
        }
        if (alive.isEmpty()) {
            end(null, List.of());
        } else if (alive.size() == 1 && startingPlayers > 1) {
            UUID winner = alive.iterator().next();
            Player p = Bukkit.getPlayer(winner);
            end(p == null ? "?" : p.getName(), List.of(winner));
        }
    }

    // --------------------------------------------------------------- queueing

    public boolean addPlayer(Player player) {
        if (state != State.WAITING && state != State.STARTING || loading) {
            return false;
        }
        if (players.size() >= maxPlayers()) {
            return false;
        }
        players.add(player.getUniqueId());
        plugin.games().track(player, this);
        plugin.hub().giveQueueItems(player);
        onQueueJoin(player);
        Msg.all(online(), "<yellow>" + player.getName() + " <gray>joined the <white>" + type.displayName()
                + "</white> queue <dark_gray>(" + players.size() + "/" + maxPlayers() + ")");
        Msg.sound(player, "block.note_block.pling", 1.4f);
        updateCountdown();
        return true;
    }

    /** Lets someone watch a running match. They are sent back to the hub when it ends. */
    public boolean addSpectator(Player player) {
        if (state != State.RUNNING || world == null || players.contains(player.getUniqueId())) {
            return false;
        }
        players.add(player.getUniqueId());
        plugin.games().track(player, this);
        plugin.games().prepare(player, GameMode.SPECTATOR);
        player.teleport(spectatorSpawn());
        Msg.all(online(), "<gray>" + player.getName() + " is now spectating.");
        Msg.send(player, "<gray>You are spectating " + name() + ". Type <yellow>/leave</yellow> to go back to the hub.");
        return true;
    }

    public void removePlayer(Player player) {
        UUID id = player.getUniqueId();
        if (!players.contains(id)) {
            return;
        }
        if (state == State.RUNNING) {
            onLeaveRunning(player);
        }
        players.remove(id);
        alive.remove(id);
        plugin.games().untrack(player);
        if (state == State.WAITING || state == State.STARTING) {
            Msg.all(online(), "<yellow>" + player.getName() + " <gray>left the queue.");
            updateCountdown();
            if (players.isEmpty()) {
                plugin.games().remove(this);
            }
        } else if (state == State.RUNNING && online().isEmpty()) {
            finish();
        }
    }

    private void updateCountdown() {
        int min = type.minPlayers(plugin);
        if (state == State.WAITING && players.size() >= min) {
            state = State.STARTING;
            countdown = countdownSeconds();
            Msg.all(online(), "<green>Enough players! Starting in <white>" + countdown + "</white> seconds.");
        } else if (state == State.STARTING && players.size() < min && !privateMatch && !forced) {
            state = State.WAITING;
            Msg.all(online(), "<red>Not enough players, countdown cancelled.");
        }
        if (state == State.STARTING && players.size() >= maxPlayers() && countdown > 5) {
            countdown = 5;
        }
    }

    /** Admin shortcut: ends the countdown or the current phase of the match. Returns false if nothing to skip. */
    public boolean skip() {
        if (state == State.WAITING || state == State.STARTING) {
            forceStart();
            countdown = Math.min(countdown, 1);
            return true;
        }
        return state == State.RUNNING && onSkip();
    }

    /** Skip the current phase (e.g. Build Battle build time). */
    protected boolean onSkip() {
        return false;
    }

    /** Starts the countdown immediately, even below the minimum player count. */
    public void forceStart() {
        if (state == State.WAITING || state == State.STARTING) {
            state = State.STARTING;
            countdown = Math.min(countdown > 0 ? countdown : 5, 5);
            forced = true;
        }
    }

    public int maxPlayers() {
        return maxOverride > 0 ? maxOverride : type.maxPlayers(plugin);
    }

    /** Overrides the player cap (used by the server-wide FFA event). */
    public void setMaxPlayers(int max) {
        this.maxOverride = max;
    }

    public void setPrivate(boolean value) {
        this.privateMatch = value;
    }

    public boolean isPrivate() {
        return privateMatch;
    }

    // -------------------------------------------------------------- lifecycle

    /** Driven once per second by the game manager. */
    public void second() {
        try {
            switch (state) {
                case WAITING -> {
                    for (Player p : online()) {
                        Msg.actionBar(p, "<gray>Waiting for players <white>" + players.size() + "/"
                                + type.minPlayers(plugin) + "</white> <dark_gray>|</dark_gray> <yellow>/leave</yellow> <gray>to leave");
                    }
                }
                case STARTING -> {
                    if (loading) {
                        for (Player p : online()) {
                            Msg.actionBar(p, "<yellow>Generating the map...");
                        }
                        return;
                    }
                    if (countdown <= 0) {
                        begin();
                        return;
                    }
                    for (Player p : online()) {
                        Msg.actionBar(p, "<green>" + type.displayName() + " starts in <white>" + countdown + "s");
                    }
                    if (countdown <= 5 || countdown == 10) {
                        Msg.title(online(), "<yellow>" + countdown, "<gray>" + type.displayName() + " is starting");
                        Msg.sound(online(), "block.note_block.hat", 1f);
                    }
                    countdown--;
                }
                case RUNNING -> {
                    elapsed++;
                    onSecond();
                }
                case ENDING -> {
                    if (--endTimer <= 0) {
                        finish();
                    } else if (endTimer % 2 == 0) {
                        for (UUID uuid : winners) {
                            Player p = Bukkit.getPlayer(uuid);
                            if (p != null && p.getWorld() == world) {
                                firework(p.getLocation());
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            plugin.getLogger().log(Level.SEVERE, "Error in " + name(), e);
            if (state == State.RUNNING) {
                end(null, List.of());
            }
        }
    }

    /** Creates the world and loads the map's chunks off the main thread, then calls {@link #launch()}. */
    private void begin() {
        List<Player> list = online();
        if (list.isEmpty()) {
            plugin.games().remove(this);
            return;
        }
        Msg.all(list, "<gray>Generating the map...");
        loading = true;
        try {
            world = Worlds.createVoid(Worlds.GAME_WORLD_PREFIX + type.key() + "_" + id);
        } catch (Exception e) {
            loading = false;
            failStart(e);
            return;
        }
        preload().whenComplete((ignored, error) -> Bukkit.getScheduler().runTask(plugin, () -> {
            loading = false;
            if (error != null) {
                failStart(error);
            } else {
                launch();
            }
        }));
    }

    /** Loads every chunk of {@link #mapArea()} asynchronously. */
    private CompletableFuture<Void> preload() {
        int[] area = mapArea();
        List<CompletableFuture<Chunk>> futures = new ArrayList<>();
        for (int cx = area[0] >> 4; cx <= area[2] >> 4; cx++) {
            for (int cz = area[1] >> 4; cz <= area[3] >> 4; cz++) {
                futures.add(world.getChunkAtAsync(cx, cz, true));
            }
        }
        return CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]));
    }

    /** Keeps the (already loaded) map chunks loaded until the world is deleted. Main thread only. */
    private void ticketArea() {
        int[] area = mapArea();
        // a world border just outside the map keeps elytras and pearls from leaving it
        org.bukkit.WorldBorder border = world.getWorldBorder();
        border.setCenter((area[0] + area[2]) / 2.0, (area[1] + area[3]) / 2.0);
        border.setSize(Math.max(area[2] - area[0], area[3] - area[1]) + 24);
        border.setWarningDistance(4);
        for (int cx = area[0] >> 4; cx <= area[2] >> 4; cx++) {
            for (int cz = area[1] >> 4; cz <= area[3] >> 4; cz++) {
                world.getChunkAt(cx, cz).addPluginChunkTicket(plugin);
            }
        }
    }

    private void failStart(Throwable e) {
        plugin.getLogger().log(Level.SEVERE, "Could not build map for " + name(), e);
        Msg.all(online(), "<red>Something went wrong while building the map, sorry!");
        state = State.ENDING;
        finish();
    }

    private void launch() {
        List<Player> list = online();
        if (state != State.STARTING || list.isEmpty()) {
            // everybody left (or the countdown was cancelled) while the map was loading
            Worlds.delete(plugin, world);
            world = null;
            if (players.isEmpty()) {
                plugin.games().remove(this);
            }
            return;
        }
        try {
            ticketArea();
            buildMap();
        } catch (Exception e) {
            failStart(e);
            return;
        }
        state = State.RUNNING;
        startingPlayers = list.size();
        alive.clear();
        for (Player p : list) {
            alive.add(p.getUniqueId());
            plugin.stats().addGame(p, type);
            plugin.games().prepare(p, GameMode.SURVIVAL);
        }
        onStart(list);
        if (mapName != null) {
            Msg.all(list, "<gray>Map: <white>" + mapName);
        }
        Msg.sound(list, "entity.ender_dragon.growl", 1.2f);
        if (wantsTicks()) {
            tickTask = Bukkit.getScheduler().runTaskTimer(plugin, () -> {
                if (state == State.RUNNING) {
                    try {
                        onTick();
                    } catch (Exception e) {
                        plugin.getLogger().log(Level.SEVERE, "Tick error in " + name(), e);
                    }
                }
            }, 1L, 1L);
        }
    }

    private final List<UUID> winners = new ArrayList<>();

    /**
     * Ends the match. {@code winnerName} is shown in the title, null means a draw.
     */
    public void end(String winnerName, Collection<UUID> winnerIds) {
        if (state != State.RUNNING) {
            return;
        }
        state = State.ENDING;
        endTimer = 10;
        winners.clear();
        winners.addAll(winnerIds);
        List<Player> online = online();
        for (UUID uuid : winnerIds) {
            Player p = Bukkit.getPlayer(uuid);
            if (p != null) {
                plugin.stats().addWin(p, type);
            }
        }
        if (winnerName == null) {
            Msg.title(online, "<yellow><bold>GAME OVER", "<gray>Nobody won this time");
        } else {
            for (Player p : online) {
                boolean won = winnerIds.contains(p.getUniqueId());
                Msg.title(p, won ? "<gold><bold>VICTORY!" : "<red><bold>GAME OVER",
                        "<yellow>" + winnerName + " <gray>won the game", 5, 80, 20);
            }
        }
        Msg.all(online, "<gold><bold>" + type.displayName().toUpperCase() + "</bold> <dark_gray>»</dark_gray> "
                + (winnerName == null ? "<gray>The game ended in a draw." : "<yellow>" + winnerName + " <green>won the game!"));
        List<Map.Entry<UUID, Integer>> top = new ArrayList<>(kills.entrySet());
        top.sort((a, b) -> b.getValue() - a.getValue());
        if (!top.isEmpty() && top.get(0).getValue() > 0) {
            Player best = Bukkit.getPlayer(top.get(0).getKey());
            String name = best != null ? best.getName() : Objects.requireNonNullElse(Bukkit.getOfflinePlayer(top.get(0).getKey()).getName(), "?");
            Msg.all(online, "<gray>Most kills: <red>" + name + " <dark_gray>(" + top.get(0).getValue() + ")");
        }
        Msg.sound(online, "ui.toast.challenge_complete", 1f);
        for (Player p : online) {
            if (!winnerIds.contains(p.getUniqueId())) {
                p.setGameMode(GameMode.SPECTATOR);
            } else {
                p.setInvulnerable(true);
                p.setAllowFlight(true);
            }
        }
        Msg.all(online, "<gray>Returning to the hub in 10 seconds...");
        for (Player p : online) {
            String again = playAgainCommand(p);
            if (again != null) {
                Msg.raw(p, "<click:run_command:'" + again + "'><hover:show_text:'<gray>Go again!'>"
                        + "<green><bold>[" + playAgainLabel() + "]</bold></green></hover></click>  "
                        + "<click:run_command:'/games'><hover:show_text:'<gray>Pick another game'><aqua><bold>[OTHER GAMES]</bold></aqua></hover></click>");
            }
        }
        if (tickTask != null) {
            tickTask.cancel();
            tickTask = null;
        }
    }

    /** Sends everyone back to the hub and deletes the world. */
    public void finish() {
        if (tickTask != null) {
            tickTask.cancel();
            tickTask = null;
        }
        state = State.ENDING;
        for (Player p : online()) {
            plugin.games().untrack(p);
            p.setInvulnerable(false);
            plugin.hub().send(p);
        }
        players.clear();
        alive.clear();
        cleanup();
        if (world != null) {
            Worlds.delete(plugin, world);
            world = null;
        }
        plugin.games().remove(this);
    }

    /** Command behind the end-of-game button, or null for none. */
    protected String playAgainCommand(Player player) {
        return privateMatch ? null : "/play " + type.key();
    }

    protected String playAgainLabel() {
        return "PLAY AGAIN";
    }

    /** Hook for subclasses to cancel their own tasks. */
    protected void cleanup() {
    }

    /** Builds the map and runs a few seconds of game logic without players, then deletes it. */
    public CompletableFuture<Void> selfTest() {
        world = Worlds.createVoid(Worlds.GAME_WORLD_PREFIX + "test_" + type.key() + "_" + System.currentTimeMillis());
        CompletableFuture<Void> result = new CompletableFuture<>();
        preload().whenComplete((ignored, error) -> Bukkit.getScheduler().runTask(plugin, () -> {
            try {
                if (error != null) {
                    throw new IllegalStateException("Chunk loading failed", error);
                }
                runSelfTest();
                result.complete(null);
            } catch (Throwable t) {
                result.completeExceptionally(t);
            }
        }));
        return result;
    }

    private void runSelfTest() {
        try {
            ticketArea();
            buildMap();
            state = State.RUNNING;
            onStart(List.of());
            for (int i = 0; i < 3 && state == State.RUNNING; i++) {
                elapsed++;
                onSecond();
                if (wantsTicks()) {
                    onTick();
                }
            }
            if (spectatorSpawn() == null) {
                throw new IllegalStateException("No spectator spawn");
            }
        } finally {
            state = State.ENDING;
            cleanup();
            Worlds.delete(plugin, world);
            world = null;
        }
    }

    // ------------------------------------------------------------ death logic

    /** Routed from the listener for every damage event on a player in this match. */
    public void handleDamage(EntityDamageEvent event, Player victim) {
        if (state != State.RUNNING || !alive.contains(victim.getUniqueId()) || victim.getGameMode() == GameMode.SPECTATOR) {
            event.setCancelled(true);
            if (event.getCause() == EntityDamageEvent.DamageCause.VOID && world != null) {
                victim.teleport(spectatorSpawn());
            }
            return;
        }
        Player attacker = attackerOf(event);
        if (attacker != null) {
            if (attacker.equals(victim) && event.getCause() != EntityDamageEvent.DamageCause.PROJECTILE) {
                attacker = null;
            } else if (!alive.contains(attacker.getUniqueId())) {
                event.setCancelled(true);
                return;
            }
        }
        onDamage(event, victim, attacker);
        if (event.isCancelled()) {
            return;
        }
        if (attacker != null && !attacker.equals(victim)) {
            lastAttacker.put(victim.getUniqueId(), attacker.getUniqueId());
            lastAttackTime.put(victim.getUniqueId(), System.currentTimeMillis());
            Player hitter = attacker;
            Bukkit.getScheduler().runTask(plugin, () -> showHealth(hitter, victim));
        }
        if (event.getCause() == EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(true);
            kill(victim, attacker);
            return;
        }
        if (victim.getHealth() - event.getFinalDamage() <= 0) {
            if (holdsTotem(victim)) {
                return; // let vanilla pop the totem of undying
            }
            event.setCancelled(true);
            kill(victim, attacker);
        }
    }

    private static boolean holdsTotem(Player p) {
        return p.getInventory().getItemInMainHand().getType() == Material.TOTEM_OF_UNDYING
                || p.getInventory().getItemInOffHand().getType() == Material.TOTEM_OF_UNDYING;
    }

    /** A real vanilla death slipped through (e.g. a totem that did not save them). */
    public void handleRealDeath(Player player) {
        if (state == State.RUNNING && alive.contains(player.getUniqueId())) {
            Player killer = player.getKiller();
            kill(player, killer);
        }
    }

    public Location spectatorLocation() {
        return spectatorSpawn();
    }

    private static Player attackerOf(EntityDamageEvent event) {
        if (event instanceof EntityDamageByEntityEvent byEntity) {
            Entity damager = byEntity.getDamager();
            if (damager instanceof Player p) {
                return p;
            }
            if (damager instanceof Projectile projectile && projectile.getShooter() instanceof Player p) {
                return p;
            }
            if (damager instanceof org.bukkit.entity.TNTPrimed tnt && tnt.getSource() instanceof Player p) {
                return p;
            }
        }
        return null;
    }

    /** Kills a player through the game's rules (no vanilla death screen). */
    public void kill(Player victim, Player killer) {
        if (!alive.contains(victim.getUniqueId()) || state != State.RUNNING || victim.getGameMode() == GameMode.SPECTATOR) {
            return;
        }
        if (killer == null) {
            UUID last = lastAttacker.get(victim.getUniqueId());
            Long time = lastAttackTime.get(victim.getUniqueId());
            if (last != null && time != null && System.currentTimeMillis() - time < 12_000) {
                killer = Bukkit.getPlayer(last);
            }
        }
        lastAttacker.remove(victim.getUniqueId());
        Integer lostStreak = streaks.remove(victim.getUniqueId());
        if (lostStreak != null && lostStreak >= 3 && killer != null && !killer.equals(victim)) {
            Msg.all(online(), "<gold>" + killer.getName() + " <yellow>ended <gold>" + victim.getName() + "</gold>'s " + lostStreak + " kill streak!");
        }
        if (killer != null && !killer.equals(victim)) {
            kills.merge(killer.getUniqueId(), 1, Integer::sum);
            int streak = streaks.merge(killer.getUniqueId(), 1, Integer::sum);
            plugin.stats().addKill(killer, type);
            Msg.sound(killer, "entity.experience_orb.pickup", 1f);
            Msg.actionBar(killer, "<green><bold>+1 Kill</bold> <gray>killed <white>" + victim.getName()
                    + (streak > 1 ? " <dark_gray>| <gold>" + streak + " streak" : ""));
            String streakName = switch (streak) {
                case 3 -> "<yellow>is on a <gold>3 kill streak<yellow>!";
                case 5 -> "<gold>is <bold>UNSTOPPABLE</bold> <yellow>(5 kills)!";
                case 7 -> "<red>is <bold>GODLIKE</bold> <yellow>(7 kills)!";
                case 10 -> "<dark_red><bold>is LEGENDARY</bold> <yellow>(10 kills)!";
                default -> null;
            };
            if (streakName != null) {
                Msg.all(online(), "<white>" + killer.getName() + " " + streakName);
                Msg.sound(online(), "entity.ender_dragon.ambient", 1.6f);
            }
        }
        Msg.sound(victim, "entity.player.hurt", 0.8f);
        plugin.stats().addDeath(victim, type);
        victim.setFireTicks(0);
        victim.setFallDistance(0);
        victim.setHealth(20);
        onDeath(victim, killer != null && killer.equals(victim) ? null : killer);
    }

    /** Shows the attacker how much health their target has left. */
    private void showHealth(Player attacker, Player victim) {
        if (!attacker.isOnline() || !victim.isOnline() || !isAlive(victim) || victim.getGameMode() == GameMode.SPECTATOR) {
            return;
        }
        double hp = Math.max(0, victim.getHealth());
        int full = (int) Math.round(hp / 2);
        StringBuilder bar = new StringBuilder("<white>" + victim.getName() + " <red>");
        bar.append("❤".repeat(Math.max(0, full))).append("<dark_gray>").append("❤".repeat(Math.max(0, 10 - full)));
        bar.append(" <white>").append(String.format("%.1f", hp));
        Msg.actionBar(attacker, bar.toString());
    }

    private static final String[] KILL_VERBS = {"was slain by", "was destroyed by", "got outplayed by",
            "was sent to the shadow realm by", "was no match for", "got clapped by", "was eliminated by"};
    private static final String[] VOID_VERBS = {"was knocked into the void by", "was thrown off the map by",
            "took a long fall thanks to"};

    protected void deathMessage(Player victim, Player killer, String suffix) {
        String msg;
        boolean fell = victim.getLocation().getY() < voidLevel() + 5;
        if (killer != null) {
            String[] verbs = fell ? VOID_VERBS : KILL_VERBS;
            msg = "<red>" + victim.getName() + " <gray>" + verbs[random.nextInt(verbs.length)] + " <green>" + killer.getName();
        } else if (fell) {
            msg = "<red>" + victim.getName() + " <gray>fell into the void";
        } else {
            msg = "<red>" + victim.getName() + " <gray>died";
        }
        Msg.all(online(), msg + (suffix == null ? "" : " " + suffix));
    }

    /** Turns a player into a spectator of this match. */
    protected void eliminate(Player player, boolean announce) {
        alive.remove(player.getUniqueId());
        if (announce && player.getLocation().getY() > voidLevel()) {
            player.getWorld().strikeLightningEffect(player.getLocation());
        }
        makeSpectator(player);
        if (announce) {
            Msg.title(player, "<red><bold>ELIMINATED", "<gray>You can spectate or type <yellow>/leave", 5, 50, 10);
            Msg.sound(player, "entity.wither.spawn", 1.4f);
        }
        checkWin();
    }

    protected void makeSpectator(Player player) {
        player.getInventory().clear();
        player.setGameMode(GameMode.SPECTATOR);
        player.teleport(spectatorSpawn());
    }

    public void handleVoid(Player player) {
        if (state == State.RUNNING && alive.contains(player.getUniqueId()) && player.getGameMode() != GameMode.SPECTATOR) {
            kill(player, null);
        } else if (world != null) {
            player.teleport(spectatorSpawn());
        }
    }

    // ---------------------------------------------------------------- helpers

    public List<Player> online() {
        List<Player> list = new ArrayList<>();
        for (UUID uuid : players) {
            Player p = Bukkit.getPlayer(uuid);
            if (p != null) {
                list.add(p);
            }
        }
        return list;
    }

    public List<Player> alivePlayers() {
        List<Player> list = new ArrayList<>();
        for (UUID uuid : alive) {
            Player p = Bukkit.getPlayer(uuid);
            if (p != null) {
                list.add(p);
            }
        }
        return list;
    }

    public boolean isAlive(Player player) {
        return alive.contains(player.getUniqueId());
    }

    protected void firework(Location loc) {
        Firework fw = loc.getWorld().spawn(loc.clone().add(0, 1, 0), Firework.class);
        FireworkMeta meta = fw.getFireworkMeta();
        Color[] colors = {Color.RED, Color.ORANGE, Color.YELLOW, Color.LIME, Color.AQUA, Color.FUCHSIA};
        meta.addEffect(FireworkEffect.builder()
                .with(FireworkEffect.Type.values()[random.nextInt(FireworkEffect.Type.values().length)])
                .withColor(colors[random.nextInt(colors.length)], colors[random.nextInt(colors.length)])
                .withFade(Color.WHITE).trail(true).flicker(random.nextBoolean()).build());
        meta.setPower(1);
        fw.setFireworkMeta(meta);
    }

    public List<String> sidebarFor(Player player) {
        if (state == State.WAITING || state == State.STARTING) {
            List<String> lines = new ArrayList<>();
            lines.add("<dark_gray>#" + id);
            lines.add(" ");
            lines.add("<white>Players: <green>" + players.size() + "/" + maxPlayers());
            lines.add(state == State.STARTING ? "<white>Starting in <green>" + countdown + "s" : "<white>Waiting for <yellow>" + Math.max(0, type.minPlayers(plugin) - players.size()) + "</yellow> more");
            lines.add("  ");
            lines.add("<gray>Type <yellow>/leave</yellow> to leave");
            lines.add(plugin.footer());
            return lines;
        }
        List<String> lines = new ArrayList<>(sidebar(player));
        lines.add("   ");
        lines.add(plugin.footer());
        return lines;
    }

    public String sidebarTitle() {
        return "<bold>" + type.colored() + "</bold>";
    }

    public State state() {
        return state;
    }

    public GameType type() {
        return type;
    }

    public int id() {
        return id;
    }

    public World world() {
        return world;
    }

    public Set<UUID> players() {
        return players;
    }

    public boolean isLoading() {
        return loading;
    }

    public boolean allowsHunger() {
        return allowHunger();
    }

    public boolean allowsItemDrops() {
        return allowItemDrops();
    }

    public double voidY() {
        return voidLevel();
    }

    public String name() {
        return type.displayName() + " #" + id;
    }
}
