package net.funcraft.games.bots;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.entity.Player;
import org.bukkit.event.player.PlayerMoveEvent;
import org.bukkit.potion.PotionEffectType;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.logging.Level;

/**
 * Bots: fake players that hang out in the hub and top up game queues when real players are
 * waiting, so a game can start even with only one or two people online. Bots play through the
 * normal game code; each game can give them smarter behaviour in {@link Game#botTick}.
 */
public final class Bots {

    private static final String[] NAMES = {"SteveBot", "AlexBot", "NoobBot", "ProBot", "CookieBot", "PixelBot", "TurboBot",
            "NinjaBot", "LuckyBot", "ZapBot", "MangoBot", "RocketBot", "BlockBot", "WaffleBot", "SparkyBot", "TacoBot",
            "BlazeBot", "FrostBot", "CactusBot", "PandaBot", "NachoBot", "BeanBot", "OreoBot", "DinoBot"};

    private final FunCraft plugin;
    private final Map<UUID, Bot> bots = new LinkedHashMap<>();
    private boolean broken;
    private String brokenReason;
    /** null until measured: does the server's own movement code move these players? */
    private Boolean nativeMovement;
    private int calibrateTicks;
    private double calibrateStartY;
    private UUID calibrating;
    private int fillTicks;

    private static final class Bot {
        final FakePlayer fake;
        final BotBrain brain;
        Location last;
        int idleTicks;
        int deadTicks;

        Bot(FakePlayer fake) {
            this.fake = fake;
            this.brain = new BotBrain(fake.player);
            this.last = fake.player.getLocation();
        }
    }

    public Bots(FunCraft plugin) {
        this.plugin = plugin;
    }

    public void start() {
        // configs written by an earlier version still have the old, smaller defaults: bump them
        var cfg = plugin.getConfig();
        if (cfg.getInt("bots.hub", 8) == 4 && cfg.getInt("bots.fill-to", 8) == 4 && cfg.getInt("bots.max", 24) == 16) {
            cfg.set("bots.hub", 8);
            cfg.set("bots.fill-to", 8);
            cfg.set("bots.max", 24);
            plugin.saveConfig();
            plugin.getLogger().info("Bots: updated config.yml to the new defaults (8 in the hub, queues filled to 8).");
        }
        Bukkit.getScheduler().runTaskTimer(plugin, () -> tick(), 1L, 1L);
        Bukkit.getScheduler().runTaskLater(plugin, () -> {
            if (!plugin.getConfig().getBoolean("bots.enabled", true)) {
                plugin.getLogger().info("Bots are turned off in config.yml (bots.enabled: false).");
            } else if (!filling()) {
                plugin.getLogger().info("Bots are paused (/fc bots fill on to start them).");
            } else {
                ensureIdle();
                if (!broken) {
                    plugin.getLogger().info("Spawned " + bots.size() + " lobby bots. Manage them with /fc bots.");
                }
            }
        }, 40L);
    }

    public boolean enabled() {
        return plugin.getConfig().getBoolean("bots.enabled", true) && !broken;
    }

    public boolean filling() {
        return plugin.getConfig().getBoolean("bots.fill-queues", true);
    }

    public void setFilling(boolean on) {
        plugin.getConfig().set("bots.fill-queues", on);
        plugin.saveConfig();
    }

    public boolean isBot(Player p) {
        return p != null && bots.containsKey(p.getUniqueId());
    }

    public boolean isBot(UUID id) {
        return bots.containsKey(id);
    }

    public int count() {
        return bots.size();
    }

    public List<Player> list() {
        List<Player> list = new ArrayList<>();
        for (Bot b : bots.values()) {
            list.add(b.fake.player);
        }
        return list;
    }

    public String failure() {
        return broken ? brokenReason : null;
    }

    public String status() {
        if (!plugin.getConfig().getBoolean("bots.enabled", true)) {
            return "<red>Bots are turned off in config.yml (bots.enabled: false).";
        }
        if (broken) {
            return "<red>Bots couldn't be created on this server: <gray>" + brokenReason + " <dark_gray>(" + Bukkit.getVersion() + ")";
        }
        int busy = 0;
        for (Bot b : bots.values()) {
            if (plugin.games().gameOf(b.fake.player) != null) {
                busy++;
            }
        }
        return "<white>" + bots.size() + " bots online <gray>(" + busy + " in games). Queue filling: "
                + (filling() ? "<green>on" : "<red>off") + (nativeMovement == null ? "" : nativeMovement ? " <dark_gray>[vanilla movement]" : " <dark_gray>[own movement]");
    }

    // -------------------------------------------------------------- spawning

    /** Adds a bot. Returns null if bots can't be created on this server. */
    public Player add() {
        return add(false);
    }

    /** @param retry try again even if an earlier attempt failed (for /fc bots add) */
    public Player add(boolean retry) {
        if (broken && !retry) {
            return null;
        }
        broken = false;
        String name = null;
        for (String n : NAMES) {
            if (Bukkit.getPlayerExact(n) == null) {
                name = n;
                break;
            }
        }
        if (name == null) {
            name = "Bot" + (1000 + bots.size());
        }
        UUID uuid = UUID.nameUUIDFromBytes(("FunCraftBot:" + name).getBytes(StandardCharsets.UTF_8));
        try {
            // registered before joining so the join listener already knows it's a bot
            bots.put(uuid, null);
            FakePlayer fake = FakePlayer.spawn(name, uuid, plugin.hub().world());
            Bot bot = new Bot(fake);
            bots.put(uuid, bot);
            if (nativeMovement == null && calibrating == null) {
                // the first bot gets dropped from a little height to see whether vanilla moves it for us
                calibrateTicks = 0;
                calibrating = uuid;
            }
            return fake.player;
        } catch (Throwable t) {
            bots.remove(uuid);
            broken = true;
            brokenReason = t.getClass().getSimpleName() + ": " + t.getMessage();
            plugin.getLogger().log(Level.WARNING, "Couldn't create a bot on " + Bukkit.getName() + " " + Bukkit.getVersion()
                    + " - " + brokenReason, t);
            return null;
        }
    }

    public void remove(Player p) {
        if (p.getUniqueId().equals(calibrating) && nativeMovement == null) {
            calibrating = null; // the next bot will measure again
        }
        Bot bot = bots.remove(p.getUniqueId());
        if (bot != null) {
            plugin.games().quit(p);
            bot.fake.remove();
        }
    }

    public int remove(int n) {
        int removed = 0;
        for (Bot b : new ArrayList<>(bots.values())) {
            if (removed >= n) {
                break;
            }
            if (b != null && plugin.games().gameOf(b.fake.player) == null) {
                remove(b.fake.player);
                removed++;
            }
        }
        return removed;
    }

    public void clear() {
        for (Bot b : new ArrayList<>(bots.values())) {
            if (b != null) {
                remove(b.fake.player);
            }
        }
        bots.clear();
    }

    private void ensureIdle() {
        int want = Math.max(0, plugin.getConfig().getInt("bots.hub", 8));
        while (bots.size() < want && !broken) {
            if (add() == null) {
                break;
            }
        }
    }

    // ---------------------------------------------------------------- ticking

    private void tick() {
        if (++fillTicks % 40 == 0 && enabled()) {
            fillQueues();
        }
        for (Bot bot : new ArrayList<>(bots.values())) {
            if (bot == null) {
                continue;
            }
            Player p = bot.fake.player;
            if (!p.isOnline()) {
                bots.remove(p.getUniqueId());
                continue;
            }
            try {
                tick(bot);
            } catch (Throwable t) {
                if (bot.brain.ticks % 200 == 1) {
                    plugin.getLogger().log(Level.WARNING, "Bot " + p.getName() + " tick failed", t);
                }
            }
        }
    }

    private void tick(Bot bot) throws ReflectiveOperationException {
        Player p = bot.fake.player;
        BotBrain brain = bot.brain;
        if (p.isDead()) {
            if (++bot.deadTicks > 20) {
                p.spigot().respawn();
                bot.deadTicks = 0;
            }
            return;
        }
        brain.beginTick();
        if (brain.ticks % 5 == 1) {
            bot.fake.markLoaded();
        }
        boolean moving = p.getGameMode() != GameMode.SPECTATOR;
        if (nativeMovement == null) {
            // calibration: no input, just see if the server lets the first bot fall
            bot.fake.input(0, 0, false);
            bot.fake.tick();
            if (!p.getUniqueId().equals(calibrating)) {
                bot.last = p.getLocation();
                return;
            }
            calibrateTicks++;
            if (calibrateTicks == 5) {
                Location up = plugin.hub().spawn().add(2, 3, 2);
                p.teleport(up);
                calibrateStartY = up.getY();
            } else if (calibrateTicks > 14) {
                nativeMovement = p.getLocation().getY() < calibrateStartY - 0.3;
                calibrateTicks = 0;
                plugin.getLogger().info("Bots: using " + (nativeMovement ? "vanilla" : "plugin") + " movement.");
                p.teleport(plugin.hub().spawn());
            }
            bot.last = p.getLocation();
            return;
        }
        if (moving) {
            think(bot);
            brain.autoJump();
            boolean bridge = brain.forward > 0 && mayBridge(p);
            brain.edgeCheck(bridge);
        }
        bot.fake.rotate(brain.yaw, brain.pitch);
        p.setSprinting(brain.sprint && brain.forward > 0);
        if (Boolean.TRUE.equals(nativeMovement) || !moving) {
            bot.fake.input(moving ? brain.forward : 0, moving ? brain.strafe : 0, moving && brain.jump);
            bot.fake.tick();
        } else {
            bot.fake.input(0, 0, false);
            bot.fake.tick();
            physics(bot);
        }
        if (brain.ticks % 10 == 0) {
            bot.fake.updateChunks();
        }
        if (brain.ticks % 20 == 0) {
            bot.fake.flushPackets();
        }
        moveEvent(bot);
    }

    /** Our own movement step on top of the vanilla collision code (used when vanilla doesn't move players). */
    private void physics(Bot bot) throws ReflectiveOperationException {
        Player p = bot.fake.player;
        BotBrain b = bot.brain;
        double[] v = bot.fake.velocity();
        boolean ground = bot.fake.onGround();
        double yaw = Math.toRadians(b.yaw);
        double fx = -Math.sin(yaw);
        double fz = Math.cos(yaw);
        double ix = fx * b.forward + Math.cos(yaw) * b.strafe;
        double iz = fz * b.forward + Math.sin(yaw) * b.strafe;
        double len = Math.sqrt(ix * ix + iz * iz);
        if (len > 1) {
            ix /= len;
            iz /= len;
        }
        double speedMul = 1 + 0.2 * (p.hasPotionEffect(PotionEffectType.SPEED) ? p.getPotionEffect(PotionEffectType.SPEED).getAmplifier() + 1 : 0);
        boolean sprinting = b.sprint && b.forward > 0;
        double accel = (ground ? (sprinting ? 0.23 : 0.18) : (sprinting ? 0.026 : 0.02)) * speedMul;
        if (b.jump && ground) {
            int boost = p.hasPotionEffect(PotionEffectType.JUMP_BOOST) ? p.getPotionEffect(PotionEffectType.JUMP_BOOST).getAmplifier() + 1 : 0;
            v[1] = 0.42 + 0.1 * boost;
            if (sprinting) {
                v[0] += fx * 0.2;
                v[2] += fz * 0.2;
            }
        }
        v[0] += ix * accel;
        v[2] += iz * accel;
        bot.fake.setVelocity(v[0], v[1], v[2]);
        bot.fake.move(v[0], v[1], v[2]);
        double[] after = bot.fake.velocity();
        boolean nowGround = bot.fake.onGround();
        double friction = nowGround ? 0.546 : 0.91;
        double vy = after[1];
        if (nowGround && vy < 0) {
            vy = 0;
        }
        vy = (vy - 0.08) * 0.98;
        bot.fake.setVelocity(after[0] * friction, vy, after[2] * friction);
    }

    /** Lets the games see bots move (void deaths, goals, checkpoints, launch pads...). */
    private void moveEvent(Bot bot) {
        Player p = bot.fake.player;
        Location now = p.getLocation();
        Location from = bot.last;
        bot.last = now;
        if (from == null || from.getWorld() != now.getWorld() || from.distanceSquared(now) < 1e-6) {
            return;
        }
        PlayerMoveEvent event = new PlayerMoveEvent(p, from, now.clone());
        Bukkit.getPluginManager().callEvent(event);
        if (event.isCancelled()) {
            p.teleport(from);
            bot.last = from;
        } else if (event.getTo() != null && !event.getTo().equals(now)) {
            p.teleport(event.getTo());
            bot.last = event.getTo();
        }
    }

    private boolean mayBridge(Player p) {
        Game game = plugin.games().gameOf(p);
        return game != null && game.state() == Game.State.RUNNING && game.botsBuild();
    }

    private void think(Bot bot) {
        Player p = bot.fake.player;
        BotBrain brain = bot.brain;
        Game game = plugin.games().gameOf(p);
        if (game != null && game.state() == Game.State.RUNNING && game.isAlive(p) && p.getWorld() == game.world()) {
            bot.idleTicks = 0;
            game.botTick(p, brain);
            return;
        }
        if (bot.idleTicks++ == 0) {
            brain.forget();
        }
        // in the hub or a queue: stroll around the plaza
        if (p.getWorld() == plugin.hub().world()) {
            brain.wander(plugin.hub().spawn(), 9, false);
        }
    }

    // ---------------------------------------------------------- queue filling

    private void fillQueues() {
        if (!filling()) {
            return; // "/fc bots fill off" also stops the automatic hub bots
        }
        ensureIdle();
        for (Game game : new ArrayList<>(plugin.games().games())) {
            if (game.isPrivate() || game.isLoading()
                    || (game.state() != Game.State.WAITING && game.state() != Game.State.STARTING)) {
                continue;
            }
            int real = 0;
            List<Player> botsIn = new ArrayList<>();
            for (UUID id : game.players()) {
                if (isBot(id)) {
                    Player b = Bukkit.getPlayer(id);
                    if (b != null) {
                        botsIn.add(b);
                    }
                } else if (Bukkit.getPlayer(id) != null) {
                    real++;
                }
            }
            if (real == 0) {
                // nobody real is waiting any more - the bots go back to the hub
                for (Player b : botsIn) {
                    game.removePlayer(b);
                    plugin.hub().giveHubItems(b);
                }
                continue;
            }
            GameType type = game.type();
            int target = Math.max(type.minPlayers(plugin), plugin.getConfig().getInt("bots.fill-to", 8));
            target = Math.min(target, game.maxPlayers());
            // up to two bots join per round, so a queue fills in a few seconds but not all at once
            for (int i = 0; i < 2 && real + botsIn.size() + i < target; i++) {
                Player idle = idleBot();
                if (idle == null && bots.size() < plugin.getConfig().getInt("bots.max", 24)) {
                    idle = add();
                }
                if (idle == null || !game.addPlayer(idle)) {
                    break;
                }
            }
        }
    }

    private Player idleBot() {
        for (Bot b : bots.values()) {
            if (b != null && b.fake.player.isOnline() && plugin.games().gameOf(b.fake.player) == null
                    && b.fake.player.getWorld() == plugin.hub().world()) {
                return b.fake.player;
            }
        }
        return null;
    }

    /** Bots say gg when a game they played ends. */
    public void gameEnded(Collection<Player> players) {
        for (Player p : players) {
            if (isBot(p) && Math.random() < 0.6) {
                String[] lines = {"gg", "gg wp", "gg!", "ggs", "good game", "gg ez", "that was fun"};
                String line = lines[(int) (Math.random() * lines.length)];
                Bukkit.getScheduler().runTaskLater(plugin, () -> {
                    if (p.isOnline()) {
                        try {
                            p.chat(line);
                        } catch (RuntimeException ignored) {
                            // chat isn't essential
                        }
                    }
                }, 20L + (long) (Math.random() * 60));
            }
        }
    }
}
