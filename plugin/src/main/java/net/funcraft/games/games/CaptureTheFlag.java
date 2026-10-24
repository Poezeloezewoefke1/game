package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.funcraft.games.util.Structures;
import net.funcraft.games.util.Theme;
import net.kyori.adventure.bossbar.BossBar;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.entity.Player;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.player.PlayerMoveEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Capture the Flag: Red vs Blue. Grab the enemy banner from their base and carry it back to your
 * own - while your own flag is safe at home. The carrier glows; kill them and the flag drops, and
 * touching your dropped flag sends it home. First team to 3 captures wins.
 */
public final class CaptureTheFlag extends TeamGame {

    private static final int Y = 64;
    private static final int HALF_X = 42;
    private static final int HALF_Z = 22;
    private static final int GOAL = 3;
    private static final int TIME_LIMIT = 600;

    private final Map<Side, Location> home = new HashMap<>();
    private final Map<Side, UUID> carrier = new HashMap<>();
    private final Map<Side, Location> dropped = new HashMap<>();

    public CaptureTheFlag(FunCraft plugin, int id) {
        super(plugin, id, GameType.CTF);
    }

    @Override
    protected String kitId() {
        return "ctf";
    }

    @Override
    protected String objective() {
        return "Steal their flag and bring it home - first to " + GOAL + "!";
    }

    @Override
    protected int respawnSeconds() {
        return 5;
    }

    @Override
    protected int[] mapArea() {
        return new int[]{-HALF_X - 4, -HALF_Z - 4, HALF_X + 4, HALF_Z + 4};
    }

    @Override
    protected void buildMap() {
        Theme theme = Theme.random(random);
        mapName = theme.displayName() + " Fields";
        Build.fill(world, -HALF_X - 2, Y - 3, -HALF_Z - 2, HALF_X + 2, Y - 1, HALF_Z + 2, theme.stone);
        Build.fill(world, -HALF_X - 2, Y, -HALF_Z - 2, HALF_X + 2, Y, HALF_Z + 2, theme.top);
        for (Side side : sides) {
            int dir = side == red ? -1 : 1;
            int bx = dir * (HALF_X - 5);
            Material base = side == red ? Material.RED_CONCRETE : Material.BLUE_CONCRETE;
            Build.disc(world, bx, Y, 0, 5.5, base);
            Build.disc(world, bx, Y + 1, 0, 1.5, theme.trim);
            Build.set(world, bx, Y + 1, 0, theme.trim);
            home.put(side, new Location(world, bx + 0.5, Y + 2, 0.5));
            Structures.tower(world, bx, Y + 1, 9, 5, theme);
            Structures.tower(world, bx, Y + 1, -9, 5, theme);
            Structures.lamp(world, bx - dir * 7, Y + 1, 4, theme);
            Structures.lamp(world, bx - dir * 7, Y + 1, -4, theme);
            side.spawn = Build.lookAt(new Location(world, dir * (HALF_X - 2) + 0.5, Y + 1, 0.5), new Location(world, 0.5, Y + 1, 0.5));
        }
        // mirrored cover and a ruin in the middle
        for (int i = 0; i < 26; i++) {
            int x = 6 + random.nextInt(HALF_X - 16);
            int z = -HALF_Z + 2 + random.nextInt(HALF_Z * 2 - 3);
            int len = 2 + random.nextInt(4);
            int h = 1 + random.nextInt(2);
            boolean alongZ = random.nextBoolean();
            Material m = random.nextInt(3) == 0 ? theme.accent : theme.trim;
            for (int j = 0; j < len; j++) {
                int cx = alongZ ? x : x + j;
                int cz = alongZ ? z + j : z;
                if (Math.abs(cz) < HALF_Z && cx < HALF_X - 12) {
                    Build.fill(world, cx, Y + 1, cz, cx, Y + h, cz, m);
                    Build.fill(world, -cx, Y + 1, cz, -cx, Y + h, cz, m);
                }
            }
        }
        Structures.ruins(world, 0, Y + 1, 0, theme, random);
        for (int i = 0; i < 8; i++) {
            int x = random.nextInt(HALF_X - 14) + 4;
            int z = random.nextInt(HALF_Z * 2 - 6) - HALF_Z + 3;
            theme.tree(world, x, Y + 1, z, random);
            theme.tree(world, -x, Y + 1, z, random);
        }
        Build.walls(world, -HALF_X - 1, Y + 1, -HALF_Z - 1, HALF_X + 1, Y + 14, HALF_Z + 1, Material.BARRIER);
        for (Side side : sides) {
            placeFlag(side, home.get(side));
        }
    }

    private Material banner(Side side) {
        return side == red ? Material.RED_BANNER : Material.BLUE_BANNER;
    }

    private void placeFlag(Side side, Location at) {
        at.getBlock().setType(banner(side), false);
    }

    private Location flagSpot(Side side) {
        return dropped.containsKey(side) ? dropped.get(side) : home.get(side);
    }

    private boolean atHome(Side side) {
        return !carrier.containsKey(side) && !dropped.containsKey(side);
    }

    @Override
    protected void giveKit(Player p) {
        Side side = side(p);
        p.getInventory().clear();
        p.getInventory().setItem(0, ItemBuilder.of(Material.STONE_SWORD).unbreakable().build());
        p.getInventory().setItem(1, ItemBuilder.of(Material.BOW).unbreakable().build());
        p.getInventory().setItem(2, new ItemStack(Material.GOLDEN_APPLE, 2));
        p.getInventory().setItem(3, new ItemStack(Material.COOKED_BEEF, 8));
        p.getInventory().setItem(8, new ItemStack(Material.ARROW, 16));
        p.getInventory().setHelmet(ItemBuilder.of(Material.LEATHER_HELMET).color(side.leather).unbreakable().build());
        p.getInventory().setChestplate(ItemBuilder.of(Material.LEATHER_CHESTPLATE).color(side.leather).unbreakable().build());
        p.getInventory().setLeggings(ItemBuilder.of(Material.CHAINMAIL_LEGGINGS).unbreakable().build());
        p.getInventory().setBoots(ItemBuilder.of(Material.LEATHER_BOOTS).color(side.leather).unbreakable().build());
        p.addPotionEffect(new PotionEffect(PotionEffectType.RESISTANCE, 40, 4, false, false));
    }

    @Override
    protected void onStart(List<Player> list) {
        super.onStart(list);
        Msg.all(list, "<gray>Grab the enemy <white>banner</white> and bring it to your base while your own flag is home!");
    }

    // ----------------------------------------------------------- the flags

    @Override
    public void onMove(PlayerMoveEvent event) {
        Player p = event.getPlayer();
        Side mine = side(p);
        if (mine == null || p.getGameMode() != GameMode.SURVIVAL || state != State.RUNNING) {
            return;
        }
        Location to = event.getTo();
        Side enemy = enemy(mine);
        // touch the enemy flag: take it
        if (!carrier.containsKey(enemy) && close(to, flagSpot(enemy), 1.7)) {
            take(p, enemy);
        }
        // touch your own dropped flag: send it home
        if (dropped.containsKey(mine) && close(to, dropped.get(mine), 1.7)) {
            dropped.remove(mine).getBlock().setType(Material.AIR);
            placeFlag(mine, home.get(mine));
            Msg.all(online(), mine.mm + p.getName() + " <gray>returned the " + mine.colored() + " <gray>flag!");
            Msg.sound(online(), "block.note_block.chime", 1.4f);
        }
        // bring theirs home while yours is safe: capture
        if (p.getUniqueId().equals(carrier.get(enemy)) && atHome(mine) && close(to, home.get(mine), 2.6)) {
            capture(p, mine, enemy);
        }
    }

    private static boolean close(Location a, Location b, double d) {
        return a.getWorld() == b.getWorld() && a.distanceSquared(b.clone().add(0, -1, 0)) < d * d + 1;
    }

    private void take(Player p, Side flag) {
        Location spot = flagSpot(flag);
        spot.getBlock().setType(Material.AIR);
        dropped.remove(flag);
        carrier.put(flag, p.getUniqueId());
        p.getInventory().setHelmet(new ItemStack(banner(flag)));
        p.addPotionEffect(new PotionEffect(PotionEffectType.GLOWING, PotionEffect.INFINITE_DURATION, 0, false, false));
        Side mine = side(p);
        Msg.all(online(), mine.mm + p.getName() + " <gray>has the " + flag.colored() + " <gray>flag!");
        Msg.title(p, "<gold><bold>YOU HAVE THE FLAG!", "<gray>Bring it back to your base", 0, 40, 10);
        Msg.sound(online(), "entity.ender_dragon.flap", 1.3f);
    }

    private void capture(Player p, Side mine, Side flag) {
        carrier.remove(flag);
        placeFlag(flag, home.get(flag));
        p.removePotionEffect(PotionEffectType.GLOWING);
        p.getInventory().setHelmet(ItemBuilder.of(Material.LEATHER_HELMET).color(mine.leather).unbreakable().build());
        mine.score++;
        kills.merge(p.getUniqueId(), 1, Integer::sum);
        plugin.stats().addKill(p, type);
        Msg.all(online(), mine.mm + "<bold>" + p.getName() + " captured the flag!</bold> " + red.mm + red.score + " <gray>- " + blue.mm + blue.score);
        Msg.title(online(), mine.mm + "<bold>CAPTURE!", "<gray>" + p.getName() + " scored for " + mine.colored());
        Msg.sound(online(), "ui.toast.challenge_complete", 1.2f);
        firework(p.getLocation());
        if (mine.score >= GOAL) {
            end("Team " + mine.colored(), new ArrayList<>(mine.members));
        }
    }

    /** The carrier died or left: the flag drops where they were. */
    private void dropFlagOf(Player p) {
        for (Side flag : sides) {
            if (p.getUniqueId().equals(carrier.get(flag))) {
                carrier.remove(flag);
                p.removePotionEffect(PotionEffectType.GLOWING);
                Location at = p.getLocation().getBlock().getLocation().add(0.5, 0, 0.5);
                while (at.getY() > Y + 1 && at.clone().subtract(0, 1, 0).getBlock().isPassable()) {
                    at.subtract(0, 1, 0);
                }
                if (at.getY() < Y + 1 || !at.getBlock().isPassable()) {
                    placeFlag(flag, home.get(flag)); // nowhere sensible to drop it: back home
                    Msg.all(online(), flag.colored() + " <gray>flag went back to base.");
                    return;
                }
                dropped.put(flag, at);
                placeFlag(flag, at);
                Msg.all(online(), "<gray>" + p.getName() + " dropped the " + flag.colored() + " <gray>flag!");
            }
        }
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        dropFlagOf(victim);
        deathMessage(victim, killer, null);
        startRespawn(victim);
    }

    @Override
    protected void onLeaveRunning(Player player) {
        dropFlagOf(player);
        super.onLeaveRunning(player);
    }

    @Override
    public void onBlockPlace(BlockPlaceEvent event) {
        event.setCancelled(true);
    }

    @Override
    public void onBlockBreak(BlockBreakEvent event) {
        event.setCancelled(true);
    }

    @Override
    public boolean botsBuild() {
        return false;
    }

    @Override
    public void botTick(Player bot, net.funcraft.games.bots.BotBrain brain) {
        Side mine = side(bot);
        if (mine == null) {
            brain.play(this);
            return;
        }
        Side enemy = enemy(mine);
        brain.eatIfHurt();
        if (bot.getUniqueId().equals(carrier.get(enemy))) {
            brain.moveTo(home.get(mine), true);
            return;
        }
        Player thief = carrier.containsKey(mine) ? Bukkit.getPlayer(carrier.get(mine)) : null;
        if (thief != null && isAlive(thief)) {
            brain.fight(thief);
            return;
        }
        Player near = brain.nearestEnemy(this, 8);
        if (near != null) {
            brain.fight(near);
            return;
        }
        if (dropped.containsKey(mine)) {
            brain.moveTo(dropped.get(mine), true);
            return;
        }
        boolean attacker = (bot.getName().hashCode() & 1) == 0 || mine.members.size() <= 1;
        if (attacker && !carrier.containsKey(enemy)) {
            brain.moveTo(flagSpot(enemy), true);
        } else {
            brain.wander(home.get(mine), 6, false);
        }
    }

    @Override
    protected void onSecond() {
        super.onSecond();
        int left = TIME_LIMIT - elapsed;
        bossBar(red.colored() + " " + red.score + " <dark_gray>| <white>" + Msg.time(left) + " <dark_gray>| " + blue.mm + blue.score + " " + blue.colored(),
                (float) left / TIME_LIMIT, BossBar.Color.WHITE);
        if (left <= 0) {
            if (red.score == blue.score) {
                end(null, List.of());
            } else {
                Side winner = red.score > blue.score ? red : blue;
                end("Team " + winner.colored(), new ArrayList<>(winner.members));
            }
        }
    }

    private String status(Side side) {
        if (carrier.containsKey(side)) {
            Player c = Bukkit.getPlayer(carrier.get(side));
            return "<red>taken" + (c == null ? "" : " by " + c.getName());
        }
        return dropped.containsKey(side) ? "<yellow>dropped" : "<green>home";
    }

    @Override
    protected double voidLevel() {
        return Y - 10;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 0.5, Y + 22, HALF_Z + 4.5, 180, 45);
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        lines.add(red.mm + "<bold>R</bold> <white>Red: " + red.mm + red.score + "/" + GOAL + (side(player) == red ? " <gray>YOU" : ""));
        lines.add("<gray>  flag " + status(red));
        lines.add(blue.mm + "<bold>B</bold> <white>Blue: " + blue.mm + blue.score + "/" + GOAL + (side(player) == blue ? " <gray>YOU" : ""));
        lines.add("<gray>  flag " + status(blue));
        lines.add("  ");
        lines.add("<white>Time: <yellow>" + Msg.time(TIME_LIMIT - elapsed));
        return lines;
    }

    @Override
    protected void cleanup() {
        super.cleanup();
        carrier.clear();
        dropped.clear();
    }
}
