package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.entity.Player;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.player.PlayerToggleFlightEvent;
import org.bukkit.util.Vector;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** The floor vanishes a moment after you step on it. Three layers, then the void. */
public final class TntRun extends LastStanding {

    private static final int[] LAYERS = {84, 74, 64};
    private static final Material[][] COLORS = {
            {Material.RED_WOOL, Material.ORANGE_WOOL},
            {Material.YELLOW_WOOL, Material.LIME_WOOL},
            {Material.LIGHT_BLUE_WOOL, Material.MAGENTA_WOOL}};
    private static final int RADIUS = 15;
    private static final int REMOVE_DELAY = 7;
    private static final int GRACE_SECONDS = 3;
    private static final int DOUBLE_JUMPS = 3;

    private final Map<Block, Integer> scheduled = new HashMap<>();
    private final Map<UUID, Integer> jumps = new HashMap<>();
    private int tick;

    public TntRun(FunCraft plugin, int id) {
        super(plugin, id, GameType.TNT_RUN);
    }

    @Override
    protected void buildMap() {
        center = new Location(world, 0.5, LAYERS[0] + 1, 0.5);
        for (int i = 0; i < LAYERS.length; i++) {
            int y = LAYERS[i];
            for (int x = -RADIUS; x <= RADIUS; x++) {
                for (int z = -RADIUS; z <= RADIUS; z++) {
                    if (x * x + z * z <= RADIUS * RADIUS) {
                        boolean checker = ((x >> 1) + (z >> 1)) % 2 == 0;
                        Build.set(world, x, y, z, COLORS[i][checker ? 0 : 1]);
                    }
                }
            }
        }
        for (int i = 0; i < 6; i++) {
            double a = Math.toRadians(i * 60);
            int x = (int) Math.round(Math.cos(a) * (RADIUS + 4));
            int z = (int) Math.round(Math.sin(a) * (RADIUS + 4));
            Build.fill(world, x, LAYERS[2] - 6, z, x, LAYERS[0] + 6, z, Material.QUARTZ_PILLAR);
            Build.set(world, x, LAYERS[0] + 7, z, Material.SEA_LANTERN);
        }
        spawnRing(LAYERS[0] + 1, RADIUS - 4, Math.max(2, online().isEmpty() ? 8 : online().size()));
    }

    @Override
    protected void equip(Player player) {
        jumps.put(player.getUniqueId(), DOUBLE_JUMPS);
        player.setGameMode(GameMode.ADVENTURE);
        player.setAllowFlight(true);
        player.getInventory().setItem(4, ItemBuilder.of(Material.FEATHER, DOUBLE_JUMPS)
                .name("<yellow>Double Jump <gray>(press jump twice)").build());
    }

    @Override
    protected boolean wantsTicks() {
        return true;
    }

    @Override
    protected void onTick() {
        tick++;
        if (elapsed >= GRACE_SECONDS) {
            for (Player p : alivePlayers()) {
                if (p.getGameMode() == GameMode.SPECTATOR) {
                    continue;
                }
                Location l = p.getLocation();
                for (double dx : new double[]{-0.3, 0.3}) {
                    for (double dz : new double[]{-0.3, 0.3}) {
                        for (double dy : new double[]{0.1, 1.1}) {
                            Block b = world.getBlockAt((int) Math.floor(l.getX() + dx), (int) Math.floor(l.getY() - dy), (int) Math.floor(l.getZ() + dz));
                            if (b.getType().name().endsWith("_WOOL") && !scheduled.containsKey(b)) {
                                scheduled.put(b, tick + REMOVE_DELAY);
                            }
                        }
                    }
                }
            }
        }
        Iterator<Map.Entry<Block, Integer>> it = scheduled.entrySet().iterator();
        while (it.hasNext()) {
            Map.Entry<Block, Integer> e = it.next();
            if (e.getValue() <= tick) {
                e.getKey().setType(Material.AIR, false);
                it.remove();
            }
        }
    }

    @Override
    public void onToggleFlight(PlayerToggleFlightEvent event) {
        Player p = event.getPlayer();
        if (p.getGameMode() != GameMode.ADVENTURE) {
            return;
        }
        event.setCancelled(true);
        int left = jumps.getOrDefault(p.getUniqueId(), 0);
        if (left <= 0) {
            p.setAllowFlight(false);
            return;
        }
        left--;
        jumps.put(p.getUniqueId(), left);
        Vector dir = p.getLocation().getDirection().setY(0).normalize().multiply(0.9);
        p.setVelocity(dir.setY(0.75));
        Msg.sound(p, "entity.bat.takeoff", 1.2f);
        if (left == 0) {
            p.getInventory().setItem(4, null);
            p.setAllowFlight(false);
        } else {
            p.getInventory().setItem(4, ItemBuilder.of(Material.FEATHER, left)
                    .name("<yellow>Double Jump <gray>(press jump twice)").build());
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (event.getCause() != EntityDamageEvent.DamageCause.VOID) {
            event.setCancelled(true);
        }
    }

    @Override
    protected void onSecond() {
        super.onSecond();
        if (elapsed == GRACE_SECONDS) {
            Msg.title(alivePlayers(), "<red><bold>RUN!", "<gray>The floor is disappearing");
        }
    }

    @Override
    protected List<String> extraSidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<white>Double jumps: <yellow>" + jumps.getOrDefault(player.getUniqueId(), 0));
        return lines;
    }

    @Override
    protected int timeLimit() {
        return 420;
    }

    @Override
    protected String objective() {
        return "Keep moving - the floor vanishes!";
    }

    @Override
    protected double voidLevel() {
        return LAYERS[2] - 8;
    }

    @Override
    protected Location spectatorSpawn() {
        return center.clone().add(0, 8, 0);
    }

    @Override
    protected void cleanup() {
        scheduled.clear();
    }
}
