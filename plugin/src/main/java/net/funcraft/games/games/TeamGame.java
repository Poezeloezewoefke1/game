package net.funcraft.games.games;

import net.funcraft.games.FunCraft;
import net.funcraft.games.Kits;
import net.funcraft.games.Parties;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import net.kyori.adventure.text.format.NamedTextColor;
import org.bukkit.Bukkit;
import org.bukkit.Color;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.entity.Player;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.entity.EntityExplodeEvent;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.inventory.InventoryType;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.PlayerInventory;
import org.bukkit.inventory.meta.LeatherArmorMeta;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Base for Red vs Blue games (Bed Fight, Fireball Fight, The Bridge): automatic balanced teams
 * (party members stay together), kits recoloured to your team, no friendly fire, 1.8-style
 * spam-click combat, respawn timers and "only player-placed blocks can be broken".
 */
public abstract class TeamGame extends Game {

    /** One of the two teams. */
    public static final class Side {
        public final String name;
        public final String mm;
        public final NamedTextColor text;
        public final String dye;
        public final Color leather;
        public final Set<UUID> members = new LinkedHashSet<>();
        public Location spawn;
        public int score;
        public boolean bedAlive = true;
        public Block bedFoot;
        public Block bedHead;

        Side(String name, String mm, NamedTextColor text, String dye, Color leather) {
            this.name = name;
            this.mm = mm;
            this.text = text;
            this.dye = dye;
            this.leather = leather;
        }

        public String colored() {
            return mm + name;
        }

        public boolean isBed(Block b) {
            return b.equals(bedFoot) || b.equals(bedHead);
        }
    }

    protected final Side red = new Side("Red", "<red>", NamedTextColor.RED, "RED", Color.fromRGB(0xFF5555));
    protected final Side blue = new Side("Blue", "<blue>", NamedTextColor.BLUE, "BLUE", Color.fromRGB(0x5555FF));
    protected final List<Side> sides = List.of(red, blue);
    protected final Map<UUID, Side> sideOf = new HashMap<>();
    protected final Map<UUID, Integer> respawning = new HashMap<>();
    protected final Set<Block> placed = new HashSet<>();

    protected TeamGame(FunCraft plugin, int id, GameType type) {
        super(plugin, id, type);
    }

    /** kits.yml id of the kit everyone gets. */
    protected abstract String kitId();

    protected int respawnSeconds() {
        return 3;
    }

    @Override
    protected boolean legacyCombat() {
        return true;
    }

    // ------------------------------------------------------------------ teams

    /** Splits players into two balanced teams, keeping parties together where possible. */
    protected void splitTeams(List<Player> list) {
        List<List<Player>> groups = new ArrayList<>();
        Set<UUID> grouped = new HashSet<>();
        List<Player> shuffled = new ArrayList<>(list);
        Collections.shuffle(shuffled, random);
        for (Player p : shuffled) {
            if (grouped.contains(p.getUniqueId())) {
                continue;
            }
            List<Player> group = new ArrayList<>();
            Parties.Party party = plugin.parties().of(p);
            for (Player q : shuffled) {
                if (q.equals(p) || (party != null && party.members().contains(q.getUniqueId()))) {
                    group.add(q);
                    grouped.add(q.getUniqueId());
                }
            }
            groups.add(group);
        }
        groups.sort((a, b) -> b.size() - a.size());
        int cap = (int) Math.ceil(list.size() / 2.0);
        for (List<Player> group : groups) {
            for (Player p : group) {
                Side side = red.members.size() <= blue.members.size() ? red : blue;
                // keep the group on the team its first member went to, while it has room
                Side mate = sideOf.get(group.get(0).getUniqueId());
                if (mate != null && mate.members.size() < cap) {
                    side = mate;
                }
                side.members.add(p.getUniqueId());
                sideOf.put(p.getUniqueId(), side);
            }
        }
    }

    public Side side(Player p) {
        return sideOf.get(p.getUniqueId());
    }

    protected Side enemy(Side side) {
        return side == red ? blue : red;
    }

    protected List<Player> members(Side side) {
        List<Player> list = new ArrayList<>();
        for (UUID uuid : side.members) {
            Player p = Bukkit.getPlayer(uuid);
            if (p != null && players.contains(uuid)) {
                list.add(p);
            }
        }
        return list;
    }

    @Override
    public String nameColor(Player player) {
        Side side = side(player);
        return side == null ? null : side.mm;
    }

    @Override
    protected void onStart(List<Player> list) {
        splitTeams(list);
        for (Player p : list) {
            Side side = side(p);
            p.teleport(side.spawn);
            giveKit(p);
            Msg.title(p, "<bold>" + side.colored() + " Team", "<gray>" + objective(), 5, 60, 10);
        }
        for (Player viewer : list) {
            for (Player other : list) {
                Side s = side(other);
                plugin.sidebars().of(viewer).nameColor(s.name.toLowerCase(Locale.ROOT), s.text,
                        s.mm + "<bold>" + s.name.charAt(0) + "</bold> ", other.getName());
            }
        }
        Msg.all(list, "<gray>Teams: " + teamList(red) + " <gray>vs " + teamList(blue));
    }

    private String teamList(Side side) {
        List<String> names = new ArrayList<>();
        for (Player p : members(side)) {
            names.add(p.getName());
        }
        return side.mm + String.join(", ", names);
    }

    protected abstract String objective();

    /** Gives the kit, with wool/terracotta/glass/concrete and leather armour in the team colour. */
    protected void giveKit(Player p) {
        Side side = side(p);
        Kits.Kit kit = plugin.kits().getOrDefault(kitId());
        kit.apply(p);
        PlayerInventory inv = p.getInventory();
        for (int i = 0; i < inv.getSize(); i++) {
            ItemStack item = inv.getItem(i);
            if (item != null) {
                inv.setItem(i, recolor(item, side));
            }
        }
        if (inv.getItemInOffHand().getType() != Material.AIR) {
            inv.setItemInOffHand(recolor(inv.getItemInOffHand(), side));
        }
        if (inv.getHelmet() == null) {
            inv.setHelmet(ItemBuilder.of(Material.LEATHER_HELMET).color(side.leather).unbreakable().build());
        }
        p.addPotionEffect(new PotionEffect(PotionEffectType.RESISTANCE, 40, 4, false, false));
    }

    private static final String[] DYES = {"WHITE", "ORANGE", "MAGENTA", "LIGHT_BLUE", "YELLOW", "LIME", "PINK", "GRAY",
            "LIGHT_GRAY", "CYAN", "PURPLE", "BLUE", "BROWN", "GREEN", "RED", "BLACK"};

    protected static ItemStack recolor(ItemStack item, Side side) {
        String name = item.getType().name();
        for (String suffix : new String[]{"_WOOL", "_TERRACOTTA", "_STAINED_GLASS", "_CONCRETE", "_CARPET"}) {
            if (name.endsWith(suffix)) {
                for (String dye : DYES) {
                    if (name.equals(dye + suffix)) {
                        Material m = Material.matchMaterial(side.dye + suffix);
                        if (m != null) {
                            ItemStack copy = item.withType(m);
                            return copy;
                        }
                    }
                }
            }
        }
        if (item.getItemMeta() instanceof LeatherArmorMeta meta) {
            meta.setColor(side.leather);
            item.setItemMeta(meta);
        }
        return item;
    }

    // -------------------------------------------------------------- respawns

    /** Puts a player in spectator for a few seconds, then back at their spawn with a fresh kit. */
    protected void startRespawn(Player p) {
        p.getInventory().clear();
        p.setGameMode(GameMode.SPECTATOR);
        p.teleport(spectatorSpawn());
        respawning.put(p.getUniqueId(), respawnSeconds());
        Msg.title(p, "<red><bold>YOU DIED", "<gray>Respawning in " + respawnSeconds() + "...", 0, 25, 5);
    }

    protected void respawn(Player p) {
        Side side = side(p);
        if (side == null) {
            return;
        }
        p.setGameMode(GameMode.SURVIVAL);
        p.teleport(side.spawn);
        p.setHealth(20);
        p.setFoodLevel(20);
        p.setFallDistance(0);
        giveKit(p);
    }

    @Override
    protected void onSecond() {
        for (Map.Entry<UUID, Integer> e : new ArrayList<>(respawning.entrySet())) {
            Player p = Bukkit.getPlayer(e.getKey());
            if (p == null || !isAlive(p)) {
                respawning.remove(e.getKey());
            } else if (e.getValue() <= 1) {
                respawning.remove(e.getKey());
                respawn(p);
            } else {
                respawning.put(e.getKey(), e.getValue() - 1);
                Msg.title(p, "<red><bold>YOU DIED", "<gray>Respawning in " + (e.getValue() - 1) + "...", 0, 25, 5);
            }
        }
    }

    @Override
    protected void checkWin() {
        if (state != State.RUNNING) {
            return;
        }
        boolean redIn = red.members.stream().anyMatch(alive::contains);
        boolean blueIn = blue.members.stream().anyMatch(alive::contains);
        if (!redIn && !blueIn) {
            end(null, List.of());
        } else if (startingPlayers > 1 && (!redIn || !blueIn)) {
            Side winner = redIn ? red : blue;
            end("Team " + winner.colored(), new ArrayList<>(winner.members));
        }
    }

    @Override
    protected void onLeaveRunning(Player player) {
        respawning.remove(player.getUniqueId());
        super.onLeaveRunning(player);
    }

    // ---------------------------------------------------------------- blocks

    @Override
    public void onBlockPlace(BlockPlaceEvent event) {
        placed.add(event.getBlock());
    }

    @Override
    public void onBlockBreak(BlockBreakEvent event) {
        if (!placed.remove(event.getBlock())) {
            event.setCancelled(true);
            Msg.actionBar(event.getPlayer(), "<red>You can only break blocks placed by players.");
        }
    }

    @Override
    public void onExplode(EntityExplodeEvent event) {
        event.blockList().removeIf(b -> !placed.contains(b) || b.getType() == Material.END_STONE || b.getType() == Material.OBSIDIAN);
        event.blockList().forEach(placed::remove);
    }

    @Override
    public void onInventoryClick(InventoryClickEvent event) {
        if (event.getSlotType() == InventoryType.SlotType.ARMOR) {
            event.setCancelled(true);
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (attacker != null && !attacker.equals(victim) && side(attacker) == side(victim)) {
            event.setCancelled(true);
        }
    }

    @Override
    protected boolean allowHunger() {
        return false;
    }

    @Override
    protected void cleanup() {
        respawning.clear();
        placed.clear();
    }
}
