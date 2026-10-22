package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.Kits;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.Explosives;
import net.funcraft.games.util.Msg;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.entity.Player;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityExplodeEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Free-for-all gladiator arena (PvP), the 1v1 version (Duels) and the op-started FFA event.
 * Players fight with a kit from kits.yml. Blocks placed by players can be broken again,
 * the arena itself is indestructible.
 */
public final class PvpArena extends LastStanding {

    private static final int FLOOR_Y = 64;

    /** Visual styles for the arena; one is picked at random per match. */
    private enum Style {
        COLOSSEUM("Colosseum", new Material[]{Material.STONE_BRICKS, Material.STONE_BRICKS, Material.CRACKED_STONE_BRICKS,
                Material.MOSSY_STONE_BRICKS, Material.ANDESITE, Material.POLISHED_ANDESITE},
                Material.STONE_BRICKS, Material.CHISELED_STONE_BRICKS, Material.SMOOTH_STONE,
                Material.POLISHED_BLACKSTONE_BRICKS, Material.POLISHED_BLACKSTONE_BRICKS),
        DESERT("Desert Temple", new Material[]{Material.SANDSTONE, Material.SMOOTH_SANDSTONE, Material.CUT_SANDSTONE,
                Material.SANDSTONE, Material.CHISELED_SANDSTONE},
                Material.SMOOTH_SANDSTONE, Material.CHISELED_SANDSTONE, Material.SANDSTONE,
                Material.ORANGE_TERRACOTTA, Material.CUT_RED_SANDSTONE),
        NETHER("Nether Fortress", new Material[]{Material.NETHER_BRICKS, Material.NETHER_BRICKS, Material.RED_NETHER_BRICKS,
                Material.CRACKED_NETHER_BRICKS, Material.BLACKSTONE},
                Material.NETHER_BRICKS, Material.CHISELED_NETHER_BRICKS, Material.POLISHED_BLACKSTONE,
                Material.GILDED_BLACKSTONE, Material.RED_NETHER_BRICKS),
        OCEAN("Ocean Monument", new Material[]{Material.PRISMARINE, Material.PRISMARINE_BRICKS, Material.DARK_PRISMARINE,
                Material.PRISMARINE_BRICKS},
                Material.PRISMARINE_BRICKS, Material.DARK_PRISMARINE, Material.PRISMARINE,
                Material.DARK_PRISMARINE, Material.PRISMARINE_BRICKS),
        DEEP_DARK("Deep Dark", new Material[]{Material.DEEPSLATE_TILES, Material.DEEPSLATE_BRICKS, Material.COBBLED_DEEPSLATE,
                Material.POLISHED_DEEPSLATE, Material.CRACKED_DEEPSLATE_TILES},
                Material.DEEPSLATE_BRICKS, Material.CHISELED_DEEPSLATE, Material.POLISHED_DEEPSLATE,
                Material.SCULK, Material.DEEPSLATE_TILES);

        final String displayName;
        final Material[] floor;
        final Material wall;
        final Material top;
        final Material stands;
        final Material ring;
        final Material pillar;

        Style(String displayName, Material[] floor, Material wall, Material top, Material stands, Material ring, Material pillar) {
            this.displayName = displayName;
            this.floor = floor;
            this.wall = wall;
            this.top = top;
            this.stands = stands;
            this.ring = ring;
            this.pillar = pillar;
        }
    }
    private static final int BUILD_HEIGHT = 30;
    private int radius;
    private Kits.Kit kit;
    private boolean event;
    private final Set<Block> placed = new HashSet<>();
    private final Explosives explosives = new Explosives();

    public PvpArena(FunCraft plugin, int id, GameType type) {
        super(plugin, id, type);
    }

    public static PvpArena pvp(FunCraft plugin, int id) {
        return new PvpArena(plugin, id, GameType.PVP);
    }

    public static PvpArena duels(FunCraft plugin, int id) {
        return new PvpArena(plugin, id, GameType.DUELS);
    }

    public void setKit(Kits.Kit kit) {
        this.kit = kit;
    }

    public void setEvent(boolean event) {
        this.event = event;
    }

    private boolean duel() {
        return type == GameType.DUELS;
    }

    private Kits.Kit kit() {
        if (kit == null) {
            kit = plugin.kits().getOrDefault(plugin.getConfig().getString("games." + type.key() + ".kit", Kits.DEFAULT));
        }
        return kit;
    }

    private int arenaRadius() {
        return duel() ? 14 : (int) Math.max(22, 12 + online().size() * 1.5);
    }

    @Override
    protected int[] mapArea() {
        int r = arenaRadius() + 12;
        return new int[]{-r, -r, r, r};
    }

    @Override
    protected void buildMap() {
        int players = online().size();
        radius = arenaRadius();
        center = new Location(world, 0.5, FLOOR_Y + 1, 0.5);
        Style style = Style.values()[random.nextInt(Style.values().length)];
        mapName = style.displayName;
        Material[] floor = style.floor;
        for (int x = -radius; x <= radius; x++) {
            for (int z = -radius; z <= radius; z++) {
                if (x * x + z * z <= radius * radius) {
                    Build.set(world, x, FLOOR_Y, z, floor[random.nextInt(floor.length)]);
                    Build.set(world, x, FLOOR_Y - 1, z, Material.STONE);
                }
            }
        }
        Build.ring(world, 0, FLOOR_Y, 0, radius * 0.45, radius * 0.45 + 1, style.ring);
        Build.disc(world, 0, FLOOR_Y, 0, 2.5, style.top);
        // walls and stands
        for (int y = FLOOR_Y; y <= FLOOR_Y + 6; y++) {
            Build.ring(world, 0, y, 0, radius, radius + 2, y == FLOOR_Y + 6 ? style.top : style.wall);
        }
        for (int i = 0; i < 4; i++) {
            Build.ring(world, 0, FLOOR_Y + 6 + i, 0, radius + 2 + i * 2, radius + 4 + i * 2, style.stands);
        }
        // lights in the wall
        for (int i = 0; i < 16; i++) {
            double a = Math.toRadians(i * 22.5);
            int x = (int) Math.round(Math.cos(a) * (radius + 1));
            int z = (int) Math.round(Math.sin(a) * (radius + 1));
            Build.set(world, x, FLOOR_Y + 3, z, Material.SEA_LANTERN);
        }
        // pillars for cover
        if (!duel()) {
            for (int i = 0; i < 4; i++) {
                double a = Math.toRadians(i * 90 + 45);
                int x = (int) Math.round(Math.cos(a) * radius * 0.6);
                int z = (int) Math.round(Math.sin(a) * radius * 0.6);
                Build.fill(world, x, FLOOR_Y + 1, z, x + 1, FLOOR_Y + 4, z + 1, style.pillar);
                Build.fill(world, x, FLOOR_Y + 5, z, x + 1, FLOOR_Y + 5, z + 1, Material.GLOWSTONE);
            }
        }
        int count = Math.max(2, Math.max(players, duel() ? 2 : 8));
        spawnRing(FLOOR_Y + 1, radius - 3, count);
    }

    @Override
    protected String playAgainCommand(Player player) {
        if (!duel()) {
            return super.playAgainCommand(player);
        }
        for (Player other : online()) {
            if (!other.equals(player)) {
                return "/duel " + other.getName() + " " + kit().id();
            }
        }
        return null;
    }

    @Override
    protected String playAgainLabel() {
        return duel() ? "REMATCH" : super.playAgainLabel();
    }

    @Override
    protected void onStart(List<Player> list) {
        super.onStart(list);
        Msg.all(list, "<gray>Kit: " + kit().name() + (event ? " <dark_gray>| <gold>FFA event - if you die you spectate!" : ""));
    }

    @Override
    protected void equip(Player p) {
        kit().apply(p);
        p.addPotionEffect(new PotionEffect(PotionEffectType.RESISTANCE, 60, 4, false, false));
    }

    @Override
    public void onBlockPlace(BlockPlaceEvent e) {
        Block b = e.getBlock();
        if (b.getY() > FLOOR_Y + BUILD_HEIGHT || b.getX() * b.getX() + b.getZ() * b.getZ() > radius * radius) {
            e.setCancelled(true);
            return;
        }
        if (b.getType() == Material.TNT) {
            Explosives.primeNextTick(plugin, b, e.getPlayer());
            return;
        }
        placed.add(b);
    }

    @Override
    public void onInteract(PlayerInteractEvent e) {
        explosives.handleFireball(e);
    }

    @Override
    public void onBlockBreak(BlockBreakEvent e) {
        if (!placed.remove(e.getBlock())) {
            e.setCancelled(true);
        }
    }

    @Override
    public void onExplode(EntityExplodeEvent e) {
        e.blockList().removeIf(b -> !placed.contains(b));
        e.blockList().forEach(placed::remove);
    }

    @Override
    protected boolean allowHunger() {
        return true;
    }

    @Override
    protected boolean allowItemDrops() {
        return true;
    }

    @Override
    protected int timeLimit() {
        return duel() ? 300 : event ? 900 : 480;
    }

    @Override
    protected String objective() {
        return duel() ? "Win the 1v1!" : "Last one standing wins!";
    }

    @Override
    protected void onSecond() {
        super.onSecond();
        if (timeLimit() - elapsed == 90) {
            Msg.all(online(), "<red>Sudden death! Everyone is now glowing.");
            for (Player p : alivePlayers()) {
                p.setGlowing(true);
            }
        }
    }

    @Override
    protected double voidLevel() {
        return FLOOR_Y - 10;
    }

    @Override
    protected List<String> extraSidebar(Player player) {
        return List.of("<white>Kit: " + kit().name(), "<white>Health: <red>" + (int) Math.ceil(player.getHealth()) + " ❤");
    }

    @Override
    protected void cleanup() {
        placed.clear();
    }
}
