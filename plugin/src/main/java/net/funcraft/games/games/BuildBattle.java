package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.entity.Player;
import org.bukkit.event.block.Action;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockFromToEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.event.player.PlayerMoveEvent;
import org.bukkit.inventory.ItemStack;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Everyone builds the same theme on their own plot, then everybody votes. */
public final class BuildBattle extends Game {

    private static final int FLOOR_Y = 64;
    private static final int SIZE = 21;
    private static final int HEIGHT = 30;
    private static final int SPACING = 40;
    private static final String[] VOTE_NAMES = {"<dark_red>Super Poop", "<red>Poop", "<green>OK", "<dark_green>Good", "<dark_purple>Epic", "<gold>Legendary"};
    private static final Material[] VOTE_ITEMS = {Material.BROWN_TERRACOTTA, Material.RED_TERRACOTTA, Material.LIME_TERRACOTTA,
            Material.GREEN_TERRACOTTA, Material.PURPLE_TERRACOTTA, Material.YELLOW_TERRACOTTA};
    private static final List<String> DEFAULT_THEMES = List.of(
            "Castle", "Pirate Ship", "Treehouse", "Volcano", "Rocket", "Haunted House", "Dragon", "Underwater City",
            "Candy Land", "Robot", "Train", "Lighthouse", "Fast Food", "Space Station", "Jungle Temple", "Snowman",
            "Giant Cake", "Airplane", "Farm", "Waterfall", "Spider", "Car", "Mushroom House", "Ice Cream",
            "Windmill", "Bridge", "Garden", "Dinosaur", "Igloo", "Gaming Setup", "Treasure Chest", "Sword",
            "Hot Air Balloon", "Cat", "Rainbow", "Statue", "Fountain", "Japanese Temple", "Desert Oasis", "Skyscraper");

    private enum Phase { BUILDING, VOTING, RESULTS }

    private record Plot(UUID owner, String ownerName, int x0, int z0) {
        boolean contains(Block b) {
            return b.getX() >= x0 && b.getX() < x0 + SIZE && b.getZ() >= z0 && b.getZ() < z0 + SIZE
                    && b.getY() >= FLOOR_Y && b.getY() < FLOOR_Y + HEIGHT;
        }

        boolean near(Location l) {
            return l.getX() >= x0 - 4 && l.getX() < x0 + SIZE + 4 && l.getZ() >= z0 - 4 && l.getZ() < z0 + SIZE + 4
                    && l.getY() >= FLOOR_Y - 3 && l.getY() < FLOOR_Y + HEIGHT + 6;
        }
    }

    private final Map<UUID, Plot> plots = new LinkedHashMap<>();
    private final List<Plot> voteOrder = new ArrayList<>();
    private final Map<UUID, Integer> scores = new HashMap<>();
    private final Map<UUID, Integer> currentVotes = new HashMap<>();
    private Phase phase = Phase.BUILDING;
    private String theme;
    private int phaseTimer;
    private int voteIndex = -1;

    public BuildBattle(FunCraft plugin, int id) {
        super(plugin, id, GameType.BUILD_BATTLE);
    }

    private int buildSeconds() {
        return Math.max(60, plugin.getConfig().getInt("games.buildbattle.build-seconds", 300));
    }

    private int voteSeconds() {
        return Math.max(5, plugin.getConfig().getInt("games.buildbattle.vote-seconds", 15));
    }

    @Override
    protected int[] mapArea() {
        int count = Math.max(4, online().size());
        int perRow = (int) Math.ceil(Math.sqrt(count));
        int rows = (int) Math.ceil(count / (double) perRow);
        return new int[]{-8, -8, (perRow - 1) * SPACING + SIZE + 8, (rows - 1) * SPACING + SIZE + 8};
    }

    @Override
    protected void buildMap() {
        List<String> themes = plugin.getConfig().getStringList("games.buildbattle.themes");
        if (themes.isEmpty()) {
            themes = DEFAULT_THEMES;
        }
        theme = themes.get(random.nextInt(themes.size()));
        List<Player> list = online();
        int count = list.isEmpty() ? 4 : list.size();
        int perRow = (int) Math.ceil(Math.sqrt(count));
        for (int i = 0; i < count; i++) {
            int x0 = (i % perRow) * SPACING;
            int z0 = (i / perRow) * SPACING;
            buildPlot(x0, z0);
            if (i < list.size()) {
                Player p = list.get(i);
                plots.put(p.getUniqueId(), new Plot(p.getUniqueId(), p.getName(), x0, z0));
            }
        }
    }

    private void buildPlot(int x0, int z0) {
        Build.fill(world, x0, FLOOR_Y, z0, x0 + SIZE - 1, FLOOR_Y, z0 + SIZE - 1, Material.GRASS_BLOCK);
        Build.fill(world, x0, FLOOR_Y - 1, z0, x0 + SIZE - 1, FLOOR_Y - 2, z0 + SIZE - 1, Material.DIRT);
        Build.fill(world, x0, FLOOR_Y - 3, z0, x0 + SIZE - 1, FLOOR_Y - 3, z0 + SIZE - 1, Material.BEDROCK);
        Build.walls(world, x0 - 1, FLOOR_Y - 3, z0 - 1, x0 + SIZE, FLOOR_Y, z0 + SIZE, Material.SMOOTH_QUARTZ);
        Build.walls(world, x0 - 2, FLOOR_Y - 3, z0 - 2, x0 + SIZE + 1, FLOOR_Y, z0 + SIZE + 1, Material.POLISHED_BLACKSTONE);
    }

    private Location plotSpawn(Plot plot) {
        Location center = new Location(world, plot.x0() + SIZE / 2.0, FLOOR_Y + 1, plot.z0() + SIZE / 2.0);
        return Build.lookAt(center.clone().add(0, 0, -SIZE / 2.0 + 2), center);
    }

    private Location viewPoint(Plot plot) {
        Location center = new Location(world, plot.x0() + SIZE / 2.0, FLOOR_Y + 4, plot.z0() + SIZE / 2.0);
        Location eye = new Location(world, plot.x0() + SIZE / 2.0, FLOOR_Y + 12, plot.z0() - 6);
        return Build.lookAt(eye, center);
    }

    @Override
    protected void onStart(List<Player> list) {
        phase = Phase.BUILDING;
        phaseTimer = buildSeconds();
        for (Player p : list) {
            Plot plot = plots.get(p.getUniqueId());
            if (plot == null) {
                continue;
            }
            p.setGameMode(GameMode.CREATIVE);
            p.teleport(plotSpawn(plot));
            p.setAllowFlight(true);
            Msg.title(p, "<light_purple><bold>" + Msg.escape(theme), "<gray>You have " + Msg.time(phaseTimer) + " to build it!", 10, 70, 20);
        }
        Msg.all(list, "<white>The theme is <light_purple><bold>" + Msg.escape(theme) + "</bold><white>! Build it on your plot.");
        Msg.all(list, "<gray>Tip: you are in creative mode - grab any block you like.");
    }

    @Override
    protected void onSecond() {
        phaseTimer--;
        switch (phase) {
            case BUILDING -> {
                if (phaseTimer == 60 || phaseTimer == 30 || phaseTimer == 10 || (phaseTimer <= 5 && phaseTimer > 0)) {
                    Msg.all(online(), "<yellow>" + phaseTimer + " seconds of building left!");
                    Msg.sound(online(), "block.note_block.pling", 1f);
                }
                for (Player p : alivePlayers()) {
                    Msg.actionBar(p, "<white>Theme: <light_purple>" + Msg.escape(theme) + " <dark_gray>| <white>Time: <yellow>" + Msg.time(phaseTimer));
                }
                if (phaseTimer <= 0) {
                    startVoting();
                }
            }
            case VOTING -> {
                for (Player p : online()) {
                    Msg.actionBar(p, "<white>Theme: <light_purple>" + Msg.escape(theme) + " <dark_gray>| <white>Vote with the blocks in your hotbar! <yellow>" + phaseTimer + "s");
                }
                if (phaseTimer <= 0) {
                    finishPlotVote();
                    nextPlot();
                }
            }
            case RESULTS -> {
            }
        }
    }

    private void startVoting() {
        phase = Phase.VOTING;
        voteOrder.clear();
        for (Plot plot : plots.values()) {
            if (players.contains(plot.owner())) {
                voteOrder.add(plot);
            }
        }
        if (voteOrder.isEmpty()) {
            end(null, List.of());
            return;
        }
        Msg.title(online(), "<gold><bold>Time's up!", "<gray>Now vote on every build");
        for (Player p : online()) {
            p.setGameMode(GameMode.ADVENTURE);
            p.setAllowFlight(true);
            p.setFlying(true);
            p.getInventory().clear();
            for (int i = 0; i < VOTE_ITEMS.length; i++) {
                p.getInventory().setItem(i + 1, ItemBuilder.of(VOTE_ITEMS[i]).name(VOTE_NAMES[i] + " <gray>(" + (i + 1) + " pts)").build());
            }
        }
        voteIndex = -1;
        nextPlot();
    }

    private void nextPlot() {
        voteIndex++;
        currentVotes.clear();
        if (voteIndex >= voteOrder.size()) {
            showResults();
            return;
        }
        phaseTimer = voteSeconds();
        Plot plot = voteOrder.get(voteIndex);
        Location view = viewPoint(plot);
        for (Player p : online()) {
            p.teleport(view);
            p.setFlying(true);
            boolean own = p.getUniqueId().equals(plot.owner());
            Msg.title(p, "<white>Build " + (voteIndex + 1) + "/" + voteOrder.size(),
                    own ? "<yellow>This is your build!" : "<gray>Vote with your hotbar", 5, 30, 5);
        }
    }

    private void finishPlotVote() {
        Plot plot = voteOrder.get(voteIndex);
        int total = 0;
        for (int v : currentVotes.values()) {
            total += v;
        }
        scores.put(plot.owner(), total);
        Msg.all(online(), "<gray>That was <yellow>" + plot.ownerName() + "</yellow>'s build.");
    }

    private void showResults() {
        phase = Phase.RESULTS;
        List<Plot> ranking = new ArrayList<>(voteOrder);
        ranking.sort((a, b) -> scores.getOrDefault(b.owner(), 0) - scores.getOrDefault(a.owner(), 0));
        Msg.all(online(), "<gold><bold>Build Battle results</bold> <gray>(theme: " + Msg.escape(theme) + ")");
        String[] medals = {"<gold>1st", "<gray>2nd", "<#cd7f32>3rd"};
        for (int i = 0; i < ranking.size() && i < 3; i++) {
            Plot plot = ranking.get(i);
            Msg.all(online(), medals[i] + " <white>" + plot.ownerName() + " <dark_gray>- <yellow>" + scores.getOrDefault(plot.owner(), 0) + " points");
        }
        Plot best = ranking.get(0);
        int top = scores.getOrDefault(best.owner(), 0);
        List<UUID> winners = new ArrayList<>();
        List<String> names = new ArrayList<>();
        for (Plot plot : ranking) {
            if (scores.getOrDefault(plot.owner(), 0) == top) {
                winners.add(plot.owner());
                names.add(plot.ownerName());
            }
        }
        Location view = viewPoint(best);
        for (Player p : online()) {
            p.teleport(view);
            p.getInventory().clear();
        }
        end(String.join(" & ", names), winners);
    }

    @Override
    protected boolean onSkip() {
        if (phase == Phase.RESULTS) {
            return false;
        }
        phaseTimer = 1;
        return true;
    }

    // ------------------------------------------------------------- events

    @Override
    public void onInteract(PlayerInteractEvent event) {
        if (phase == Phase.BUILDING) {
            ItemStack item = event.getItem();
            if (item != null) {
                String n = item.getType().name();
                if (n.equals("WITHER_SPAWN_EGG") || n.equals("ENDER_DRAGON_SPAWN_EGG") || n.endsWith("_MINECART")
                        || n.equals("END_CRYSTAL")) {
                    event.setCancelled(true);
                }
            }
            return;
        }
        event.setCancelled(true);
        if (phase != Phase.VOTING || event.getItem() == null || event.getAction() == Action.PHYSICAL) {
            return;
        }
        int vote = -1;
        for (int i = 0; i < VOTE_ITEMS.length; i++) {
            if (event.getItem().getType() == VOTE_ITEMS[i]) {
                vote = i;
            }
        }
        if (vote < 0) {
            return;
        }
        Player p = event.getPlayer();
        Plot plot = voteOrder.get(voteIndex);
        if (p.getUniqueId().equals(plot.owner())) {
            Msg.send(p, "<red>You can't vote for your own build!");
            return;
        }
        currentVotes.put(p.getUniqueId(), vote + 1);
        Msg.actionBar(p, "<white>You voted " + VOTE_NAMES[vote]);
        Msg.sound(p, "block.note_block.bell", 0.6f + vote * 0.2f);
    }

    @Override
    public void onInventoryClick(InventoryClickEvent event) {
        if (phase != Phase.BUILDING) {
            event.setCancelled(true);
        }
    }

    @Override
    public void onBlockPlace(BlockPlaceEvent event) {
        Plot plot = plots.get(event.getPlayer().getUniqueId());
        if (phase != Phase.BUILDING || plot == null || !plot.contains(event.getBlock())) {
            event.setCancelled(true);
        }
    }

    @Override
    public void onBlockBreak(BlockBreakEvent event) {
        Plot plot = plots.get(event.getPlayer().getUniqueId());
        if (phase != Phase.BUILDING || plot == null || !plot.contains(event.getBlock())) {
            event.setCancelled(true);
        }
    }

    @Override
    public void onFlow(BlockFromToEvent event) {
        for (Plot plot : plots.values()) {
            if (plot.contains(event.getToBlock())) {
                return;
            }
        }
        event.setCancelled(true);
    }

    @Override
    public void onMove(PlayerMoveEvent event) {
        if (phase != Phase.BUILDING) {
            return;
        }
        Plot plot = plots.get(event.getPlayer().getUniqueId());
        if (plot != null && !plot.near(event.getTo())) {
            event.setTo(plotSpawn(plot));
            Msg.actionBar(event.getPlayer(), "<red>Stay on your own plot!");
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        event.setCancelled(true);
    }

    @Override
    protected void onDeath(Player victim, Player killer) {
        // nobody dies in build battle
    }

    @Override
    public void handleVoid(Player player) {
        Plot plot = plots.get(player.getUniqueId());
        if (phase == Phase.BUILDING && plot != null) {
            player.teleport(plotSpawn(plot));
        } else if (voteIndex >= 0 && voteIndex < voteOrder.size()) {
            player.teleport(viewPoint(voteOrder.get(voteIndex)));
        }
    }

    @Override
    protected void onLeaveRunning(Player player) {
        alive.remove(player.getUniqueId());
        Msg.all(online(), "<gray>" + player.getName() + " left the game.");
        if (phase == Phase.VOTING && voteIndex >= 0 && voteIndex < voteOrder.size()
                && voteOrder.get(voteIndex).owner().equals(player.getUniqueId())) {
            phaseTimer = Math.min(phaseTimer, 1);
        }
        if (online().size() <= 1 && startingPlayers > 1 && phase != Phase.RESULTS) {
            Bukkit.getScheduler().runTask(plugin, () -> {
                if (state == State.RUNNING) {
                    List<Player> rest = online();
                    rest.removeIf(p -> p.getUniqueId().equals(player.getUniqueId()));
                    if (rest.isEmpty()) {
                        end(null, List.of());
                    } else {
                        Player last = rest.get(0);
                        end(last.getName(), List.of(last.getUniqueId()));
                    }
                }
            });
        }
    }

    @Override
    protected void checkWin() {
        // decided by votes
    }

    @Override
    protected double voidLevel() {
        return FLOOR_Y - 20;
    }

    @Override
    protected Location spectatorSpawn() {
        if (voteIndex >= 0 && voteIndex < voteOrder.size()) {
            return viewPoint(voteOrder.get(voteIndex));
        }
        return new Location(world, 10, FLOOR_Y + 15, 10);
    }

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        lines.add("<white>Theme:");
        lines.add("<light_purple>" + Msg.escape(theme == null ? "?" : theme));
        lines.add("  ");
        switch (phase) {
            case BUILDING -> lines.add("<white>Build time: <yellow>" + Msg.time(phaseTimer));
            case VOTING -> {
                lines.add("<white>Voting: <yellow>" + (voteIndex + 1) + "/" + voteOrder.size());
                lines.add("<white>Time: <yellow>" + phaseTimer + "s");
                Integer mine = currentVotes.get(player.getUniqueId());
                lines.add("<white>Your vote: " + (mine == null ? "<gray>none" : VOTE_NAMES[mine - 1]));
            }
            case RESULTS -> lines.add("<gold>Results are in!");
        }
        lines.add("   ");
        lines.add("<white>Builders: <green>" + online().size());
        return lines;
    }
}
