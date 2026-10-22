package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.Explosives;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Structures;
import net.funcraft.games.util.Theme;
import net.kyori.adventure.bossbar.BossBar;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.block.BlockFace;
import org.bukkit.entity.Player;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.inventory.ItemStack;

import java.util.ArrayList;
import java.util.List;

/**
 * Red vs Blue on two islands, each with a bed. While your bed stands you respawn; break the
 * enemy bed and then finish them off.
 * <ul>
 *   <li><b>Bed Fight</b>: islands close together with a small middle island, bridge across.</li>
 *   <li><b>Fireball Fight</b>: islands far apart. Fireballs only knock back, so you fireball-jump
 *   across and build. Fireballs and wool regenerate.</li>
 * </ul>
 */
public final class BedDuel extends TeamGame {

    private static final int Y = 64;
    private static final int TIME_LIMIT = 900;

    private final boolean fireball;
    private final Explosives explosives;
    private int islandX;

    private BedDuel(FunCraft plugin, int id, GameType type) {
        super(plugin, id, type);
        this.fireball = type == GameType.FIREBALL_FIGHT;
        this.explosives = new Explosives(fireball ? 1.9 : 1.3);
    }

    public static BedDuel bedFight(FunCraft plugin, int id) {
        return new BedDuel(plugin, id, GameType.BED_FIGHT);
    }

    public static BedDuel fireballFight(FunCraft plugin, int id) {
        return new BedDuel(plugin, id, GameType.FIREBALL_FIGHT);
    }

    @Override
    protected String kitId() {
        return fireball ? "fireballfight" : "bedfight";
    }

    @Override
    protected String objective() {
        return fireball ? "Fireball-jump over and break their bed!" : "Break the enemy bed, then finish them!";
    }

    @Override
    protected int[] mapArea() {
        int half = fireball ? 62 : 44;
        return new int[]{-half, -24, half, 24};
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + (fireball ? " Skies" : " Duel");
        islandX = fireball ? 44 : 24;
        for (Side side : sides) {
            int dir = side == red ? -1 : 1;
            int cx = dir * islandX;
            theme.island(world, cx, Y, 0, 10.5, random);
            theme.plants(world, cx, Y, 0, 9, 8, random);
            // bed at the back, lying sideways, on a small plinth
            int bx = cx + dir * 5;
            Build.fill(world, bx - 1, Y, -2, bx + 1, Y, 2, theme.trim);
            side.bedFoot = Build.bed(world, bx, Y + 1, 0, side == red ? Material.RED_BED : Material.BLUE_BED, BlockFace.SOUTH);
            side.bedHead = side.bedFoot.getRelative(BlockFace.SOUTH);
            // base buildings
            Structures.house(world, cx + dir * 4, Y + 1, 5, theme, random);
            Structures.tower(world, cx + dir * 4, Y + 1, -6, 5, theme);
            Structures.lamp(world, cx - dir * 6, Y + 1, 4, theme);
            Structures.lamp(world, cx - dir * 6, Y + 1, -4, theme);
            Location spawn = new Location(world, cx - dir * 3 + 0.5, Y + 1, 0.5);
            side.spawn = Build.lookAt(spawn, new Location(world, 0.5, Y + 1, 0.5));
        }
        if (fireball) {
            // a few tiny stepping rocks far apart - you still need fireball jumps
            for (int x : new int[]{-14, 14}) {
                theme.island(world, x, Y - 3, random.nextInt(9) - 4, 2.5, random);
            }
        } else {
            theme.island(world, 0, Y, 0, 5.5, random);
            Structures.ruins(world, 0, Y + 1, 0, theme, random);
        }
    }

    @Override
    protected void onStart(List<Player> list) {
        super.onStart(list);
        Msg.all(list, fireball
                ? "<gold>Fireballs only knock back! <gray>Right click a fire charge at your feet to launch yourself."
                : "<gray>Bridge over with your wool and break the other bed. No bed = no respawn!");
    }

    @Override
    public void onBlockBreak(BlockBreakEvent event) {
        Block b = event.getBlock();
        Player p = event.getPlayer();
        for (Side side : sides) {
            if (side.isBed(b)) {
                event.setDropItems(false);
                if (side(p) == side) {
                    event.setCancelled(true);
                    Msg.actionBar(p, "<red>You can't break your own bed!");
                    return;
                }
                side.bedAlive = false;
                Msg.all(online(), "<bold>BED DESTRUCTION</bold> <dark_gray>»</dark_gray> " + side.colored() + " bed <gray>was destroyed by "
                        + side(p).mm + p.getName() + "<gray>!");
                Msg.sound(online(), "entity.ender_dragon.growl", 1.3f);
                for (Player member : members(side)) {
                    Msg.title(member, "<red><bold>BED DESTROYED!", "<gray>You will no longer respawn!", 5, 60, 10);
                }
                return;
            }
        }
        super.onBlockBreak(event);
    }

    @Override
    public void onBlockPlace(BlockPlaceEvent event) {
        Block b = event.getBlock();
        if (Math.abs(b.getZ()) > 22 || b.getY() > Y + 25 || b.getY() < Y - 20) {
            event.setCancelled(true);
            return;
        }
        for (Side side : sides) {
            if (side.spawn.getBlock().getLocation().distanceSquared(b.getLocation()) < 3) {
                event.setCancelled(true);
                return;
            }
        }
        if (b.getType() == Material.TNT) {
            Explosives.primeNextTick(plugin, b, event.getPlayer());
            return;
        }
        super.onBlockPlace(event);
    }

    @Override
    public void onInteract(PlayerInteractEvent event) {
        explosives.handleFireball(event);
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        super.onDamage(event, victim, attacker);
        if (event.isCancelled()) {
            // friendly fireballs still launch you
            if (fireball) {
                event.setCancelled(false);
                if (!Explosives.fireballHit(plugin, event, victim, 0, 1.9)) {
                    event.setCancelled(true);
                }
            }
            return;
        }
        if (fireball) {
            Explosives.fireballHit(plugin, event, victim, 0, 1.9);
            if (event.getCause() == EntityDamageEvent.DamageCause.FALL) {
                event.setCancelled(true);
            }
        } else {
            Explosives.fireballHit(plugin, event, victim, 0.3, 1.3);
        }
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        Side side = side(victim);
        boolean finalKill = side == null || !side.bedAlive;
        deathMessage(victim, killer, finalKill ? "<aqua><bold>FINAL KILL!" : null);
        if (finalKill) {
            eliminate(victim, true);
        } else {
            startRespawn(victim);
        }
    }

    @Override
    protected void onSecond() {
        super.onSecond();
        // regenerate building blocks (and fireballs in Fireball Fight)
        for (Player p : alivePlayers()) {
            Side side = side(p);
            if (side == null || p.getGameMode() != org.bukkit.GameMode.SURVIVAL) {
                continue;
            }
            Material wool = Material.matchMaterial(side.dye + "_WOOL");
            if (elapsed % 4 == 0 && wool != null && count(p, wool) < 64) {
                p.getInventory().addItem(new ItemStack(wool, 8));
            }
            if (fireball && elapsed % 3 == 0 && count(p, Material.FIRE_CHARGE) < 8) {
                p.getInventory().addItem(new ItemStack(Material.FIRE_CHARGE));
            }
        }
        int left = TIME_LIMIT - elapsed;
        bossBar(red.colored() + " " + (red.bedAlive ? "<green>✔" : "<red>✘") + " <dark_gray>| <white>" + Msg.time(left)
                + " <dark_gray>| " + blue.colored() + " " + (blue.bedAlive ? "<green>✔" : "<red>✘"),
                (float) left / TIME_LIMIT, fireball ? BossBar.Color.YELLOW : BossBar.Color.RED);
        if (left == 300) {
            Msg.all(online(), "<red>5 minutes left - then it's a draw!");
        }
        if (left <= 0) {
            end(null, List.of());
        }
    }

    private static int count(Player p, Material m) {
        int n = 0;
        for (ItemStack item : p.getInventory().getContents()) {
            if (item != null && item.getType() == m) {
                n += item.getAmount();
            }
        }
        return n;
    }

    @Override
    protected double voidLevel() {
        return Y - 25;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 0.5, Y + 22, 0.5, 90, 60);
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        for (Side side : sides) {
            long aliveCount = side.members.stream().filter(alive::contains).count();
            String status = side.bedAlive ? "<green>✔ bed" : aliveCount > 0 ? "<yellow>" + aliveCount + " left" : "<red>✘";
            lines.add(side.mm + "<bold>" + side.name.charAt(0) + "</bold> <white>" + side.name + ": " + status
                    + (side(player) == side ? " <gray>YOU" : ""));
        }
        lines.add("  ");
        lines.add("<white>Kills: <green>" + kills.getOrDefault(player.getUniqueId(), 0));
        lines.add("<white>Time: <yellow>" + Msg.time(TIME_LIMIT - elapsed));
        return lines;
    }
}
