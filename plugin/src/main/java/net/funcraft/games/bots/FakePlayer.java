package net.funcraft.games.bots;

import org.bukkit.Bukkit;
import org.bukkit.Location;
import org.bukkit.World;
import org.bukkit.entity.Player;

import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.net.InetSocketAddress;
import java.util.UUID;

/**
 * A server-side player with no client behind it. It is created through the server's normal
 * join code, so to every plugin and game it is just another {@link Player}. Movement is driven
 * from here: either through the vanilla movement code (when the server runs it for players) or
 * with a small physics step of our own on top of the vanilla collision code.
 */
final class FakePlayer {

    final Object handle;
    final Player player;
    private final Object channel;
    private final Object server;

    private static Class<?> vec3;
    private static Object moverSelf;

    private FakePlayer(Object handle, Player player, Object channel, Object server) {
        this.handle = handle;
        this.player = player;
        this.channel = channel;
        this.server = server;
    }

    static FakePlayer spawn(String name, UUID uuid, World world) throws Exception {
        Object server = Bukkit.getServer().getClass().getMethod("getServer").invoke(Bukkit.getServer());
        Object level = world.getClass().getMethod("getHandle").invoke(world);
        Object profile = gameProfile(uuid, name);
        Class<?> clientInfoClass = Nms.cls("net.minecraft.server.level.ClientInformation");
        Object clientInfo = Nms.callStatic(clientInfoClass, "createDefault");

        Class<?> serverPlayerClass = Nms.cls("net.minecraft.server.level.ServerPlayer");
        Object handle = null;
        for (var ctor : serverPlayerClass.getConstructors()) {
            if (Nms.fits(ctor.getParameterTypes(), new Object[]{server, level, profile, clientInfo})) {
                handle = ctor.newInstance(server, level, profile, clientInfo);
                break;
            }
        }
        if (handle == null) {
            throw new IllegalStateException("No ServerPlayer(server, level, profile, clientInformation) constructor");
        }

        Class<?> flowClass = Nms.cls("net.minecraft.network.protocol.PacketFlow");
        @SuppressWarnings({"unchecked", "rawtypes"})
        Object serverbound = Enum.valueOf((Class<? extends Enum>) flowClass, "SERVERBOUND");
        Class<?> connectionClass = Nms.cls("net.minecraft.network.Connection");
        Object connection = connectionClass.getConstructor(flowClass).newInstance(serverbound);
        Object channel = Nms.cls("io.netty.channel.embedded.EmbeddedChannel").getConstructor().newInstance();
        Nms.fieldOfType(connectionClass, Nms.cls("io.netty.channel.Channel")).set(connection, channel);
        try {
            Nms.fieldOfType(connectionClass, java.net.SocketAddress.class).set(connection, new InetSocketAddress("127.0.0.1", 0));
        } catch (NoSuchFieldException ignored) {
            // older/newer versions keep the address elsewhere; only used for logging
        }

        Object cookie = cookie(profile, clientInfo);
        Object playerList = Nms.call(server, "getPlayerList");
        Method place = null;
        for (Method m : playerList.getClass().getMethods()) {
            if (m.getName().equals("placeNewPlayer") && m.getParameterCount() == 3) {
                place = m;
            }
        }
        if (place == null) {
            throw new IllegalStateException("PlayerList.placeNewPlayer not found");
        }
        place.invoke(playerList, connection, handle, cookie);
        Player player = (Player) Nms.call(handle, "getBukkitEntity");
        return new FakePlayer(handle, player, channel, server);
    }

    private static Object gameProfile(UUID uuid, String name) throws Exception {
        try {
            Object paperProfile = Bukkit.createProfile(uuid, name);
            Object gp = Nms.call(paperProfile, "getGameProfile");
            if (gp != null) {
                return gp;
            }
        } catch (ReflectiveOperationException ignored) {
            // fall back to building it ourselves
        }
        Class<?> gameProfileClass = Nms.cls("com.mojang.authlib.GameProfile");
        try {
            return gameProfileClass.getConstructor(UUID.class, String.class).newInstance(uuid, name);
        } catch (NoSuchMethodException e) {
            Class<?> propertyMap = Nms.cls("com.mojang.authlib.properties.PropertyMap");
            Object empty;
            try {
                empty = propertyMap.getField("EMPTY").get(null);
            } catch (NoSuchFieldException e2) {
                empty = propertyMap.getConstructor().newInstance();
            }
            return gameProfileClass.getConstructor(UUID.class, String.class, propertyMap).newInstance(uuid, name, empty);
        }
    }

    private static Object cookie(Object profile, Object clientInfo) throws Exception {
        Class<?> cookieClass = Nms.cls("net.minecraft.server.network.CommonListenerCookie");
        for (Method m : cookieClass.getMethods()) {
            if (Modifier.isStatic(m.getModifiers()) && m.getReturnType() == cookieClass && m.getName().equals("createInitial")) {
                Object[] args = new Object[m.getParameterCount()];
                Class<?>[] types = m.getParameterTypes();
                for (int i = 0; i < types.length; i++) {
                    args[i] = types[i].isInstance(profile) ? profile : types[i] == boolean.class ? false : null;
                }
                Object cookie = m.invoke(null, args);
                // use the real client settings rather than the defaults if the cookie has them
                return cookie;
            }
        }
        return Nms.construct(cookieClass, profile, clientInfo);
    }

    // --------------------------------------------------------------- ticking

    private static boolean loadedWarned;
    /** Per class: the "has the client loaded" members we found (setters taking a boolean, or boolean fields). */
    private static final java.util.Map<Class<?>, java.util.List<java.lang.reflect.Member>> LOADED_HOOKS = new java.util.HashMap<>();

    /**
     * Real clients tell the server when they have finished loading (after joining and after every
     * world change); until then the player can't be hurt. Bots have no client, so we say it for them -
     * otherwise they could never take damage or knockback. The member names change between versions,
     * so we look for them on the player and on its connection.
     */
    void markLoaded() {
        java.util.List<String> how = new java.util.ArrayList<>();
        try {
            Nms.call(handle, "hasChangedDimension");
            how.add("hasChangedDimension");
        } catch (ReflectiveOperationException ignored) {
            try {
                Nms.set(handle, "isChangingDimension", false);
                how.add("isChangingDimension");
            } catch (ReflectiveOperationException ignored2) {
                // nothing to reset
            }
        }
        Object listener = null;
        try {
            listener = Nms.get(handle, "connection");
        } catch (ReflectiveOperationException ignored) {
            // no game listener field by that name
        }
        for (Object target : new Object[]{handle, listener}) {
            if (target == null) {
                continue;
            }
            for (java.lang.reflect.Member m : LOADED_HOOKS.computeIfAbsent(target.getClass(), FakePlayer::findLoadedHooks)) {
                try {
                    if (m instanceof Method method) {
                        method.invoke(target, true);
                    } else {
                        java.lang.reflect.Field f = (java.lang.reflect.Field) m;
                        f.setBoolean(target, !waiting(f.getName()));
                    }
                    how.add(m.getName());
                } catch (ReflectiveOperationException | RuntimeException ignored) {
                    // try the others
                }
            }
        }
        if (!loadedWarned) {
            loadedWarned = true;
            if (how.size() <= 1) {
                Bukkit.getLogger().warning("[FunCraftGames] Bots: couldn't find the client-loaded flag; bots may not take damage on this version. "
                        + "Candidates: " + loadNames(handle) + (listener == null ? "" : " / " + loadNames(listener)));
            }
            Bukkit.getLogger().info("[FunCraftGames] Bots: marked as loaded via " + String.join(", ", how) + ".");
        }
    }

    private static boolean waiting(String name) {
        String n = name.toLowerCase(java.util.Locale.ROOT);
        return n.contains("wait") || n.contains("pending") || n.contains("not");
    }

    private static boolean loadName(String name) {
        String n = name.toLowerCase(java.util.Locale.ROOT);
        return n.contains("client") && n.contains("load") && !n.contains("timeout") && !n.contains("timer");
    }

    private static java.util.List<java.lang.reflect.Member> findLoadedHooks(Class<?> c) {
        java.util.List<java.lang.reflect.Member> found = new java.util.ArrayList<>();
        for (Class<?> k = c; k != null && k != Object.class; k = k.getSuperclass()) {
            for (Method m : k.getDeclaredMethods()) {
                if (!Modifier.isStatic(m.getModifiers()) && m.getParameterCount() == 1 && m.getParameterTypes()[0] == boolean.class
                        && m.getName().startsWith("set") && loadName(m.getName())) {
                    m.setAccessible(true);
                    found.add(m);
                }
            }
            for (java.lang.reflect.Field f : k.getDeclaredFields()) {
                if (!Modifier.isStatic(f.getModifiers()) && !Modifier.isFinal(f.getModifiers()) && f.getType() == boolean.class && loadName(f.getName())) {
                    f.setAccessible(true);
                    found.add(f);
                }
            }
        }
        return found;
    }

    /** Every member with "load" in its name, for the log when we can't find the flag. */
    private static String loadNames(Object target) {
        java.util.Set<String> names = new java.util.TreeSet<>();
        for (Class<?> k = target.getClass(); k != null && k != Object.class; k = k.getSuperclass()) {
            for (Method m : k.getDeclaredMethods()) {
                if (m.getName().toLowerCase(java.util.Locale.ROOT).contains("load")) {
                    names.add(m.getName() + "()");
                }
            }
            for (java.lang.reflect.Field f : k.getDeclaredFields()) {
                if (f.getName().toLowerCase(java.util.Locale.ROOT).contains("load")) {
                    names.add(f.getName());
                }
            }
        }
        return target.getClass().getSimpleName() + names;
    }

    /** Runs the player's own tick (health, effects, cooldowns, invulnerability timer, and - on some versions - movement). */
    void tick() throws ReflectiveOperationException {
        Nms.call(handle, "doTick");
    }

    /** Drops the packets the server "sent" to this player; nobody reads them. */
    void flushPackets() {
        try {
            Nms.call(channel, "releaseOutbound");
        } catch (ReflectiveOperationException ignored) {
            // nothing to release
        }
    }

    void updateChunks() {
        try {
            Object level = Nms.call(handle, "level");
            Object chunkSource = Nms.call(level, "getChunkSource");
            Nms.call(chunkSource, "move", handle);
        } catch (ReflectiveOperationException ignored) {
            // the chunk map catches up on its own on most versions
        }
    }

    /** Movement inputs for the vanilla movement code (forward/strafe in -1..1). */
    void input(float forward, float strafe, boolean jump) throws ReflectiveOperationException {
        Nms.set(handle, "zza", forward * 0.98f);
        Nms.set(handle, "xxa", strafe * 0.98f);
        Nms.call(handle, "setJumping", jump);
    }

    void rotate(float yaw, float pitch) throws ReflectiveOperationException {
        Nms.call(handle, "setYRot", yaw);
        Nms.call(handle, "setXRot", pitch);
        Nms.call(handle, "setYHeadRot", yaw);
        try {
            Nms.set(handle, "yBodyRot", yaw);
        } catch (NoSuchFieldException ignored) {
            // cosmetic only
        }
    }

    double[] velocity() throws ReflectiveOperationException {
        Object v = Nms.call(handle, "getDeltaMovement");
        return new double[]{(double) Nms.get(v, "x"), (double) Nms.get(v, "y"), (double) Nms.get(v, "z")};
    }

    void setVelocity(double x, double y, double z) throws ReflectiveOperationException {
        Nms.call(handle, "setDeltaMovement", vec(x, y, z));
    }

    /** Moves with vanilla collision (walls, floors, steps), updating onGround and fall distance. */
    void move(double x, double y, double z) throws ReflectiveOperationException {
        if (moverSelf == null) {
            Class<?> mover = Nms.cls("net.minecraft.world.entity.MoverType");
            @SuppressWarnings({"unchecked", "rawtypes"})
            Object self = Enum.valueOf((Class<? extends Enum>) mover, "SELF");
            moverSelf = self;
        }
        Nms.call(handle, "move", moverSelf, vec(x, y, z));
    }

    boolean onGround() throws ReflectiveOperationException {
        return (boolean) Nms.call(handle, "onGround");
    }

    boolean horizontalCollision() {
        try {
            return (boolean) Nms.get(handle, "horizontalCollision");
        } catch (ReflectiveOperationException e) {
            return false;
        }
    }

    private static Object vec(double x, double y, double z) throws ReflectiveOperationException {
        if (vec3 == null) {
            vec3 = Nms.cls("net.minecraft.world.phys.Vec3");
        }
        return vec3.getConstructor(double.class, double.class, double.class).newInstance(x, y, z);
    }

    // ---------------------------------------------------------------- leaving

    void remove() {
        try {
            Object playerList = Nms.call(server, "getPlayerList");
            Method remove = null;
            for (Method m : playerList.getClass().getMethods()) {
                if (m.getName().equals("remove") && m.getParameterCount() == 1 && m.getParameterTypes()[0].isInstance(handle)) {
                    remove = m;
                }
            }
            if (remove != null) {
                remove.invoke(playerList, handle);
            } else {
                player.kick();
            }
        } catch (ReflectiveOperationException | RuntimeException e) {
            player.kick();
        }
        try {
            Nms.call(channel, "close");
        } catch (ReflectiveOperationException ignored) {
            // already closed
        }
    }

    Location location() {
        return player.getLocation();
    }
}
