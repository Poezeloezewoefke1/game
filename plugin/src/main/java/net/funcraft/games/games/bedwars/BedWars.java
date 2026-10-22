package net.funcraft.games.games.bedwars;

import net.funcraft.games.FunCraft;
import net.funcraft.games.game.Game;
import net.funcraft.games.game.GameType;
import net.funcraft.games.util.Build;
import net.funcraft.games.util.Explosives;
import net.funcraft.games.util.ItemBuilder;
import net.funcraft.games.util.Msg;
import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.block.BlockFace;
import org.bukkit.enchantments.Enchantment;
import org.bukkit.entity.Display;
import org.bukkit.entity.Entity;
import org.bukkit.entity.Item;
import org.bukkit.entity.Player;
import org.bukkit.entity.TextDisplay;
import org.bukkit.entity.Villager;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.entity.EntityExplodeEvent;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.inventory.InventoryType;
import org.bukkit.event.player.PlayerInteractEntityEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.inventory.EquipmentSlot;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.PlayerInventory;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;
import org.bukkit.util.Vector;

import java.util.ArrayList;
import java.util.Collections;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Classic BedWars on a generated map: up to four team islands with a bed, an iron/gold
 * generator, an item shop and a team upgrade shop; four diamond islands and an emerald
 * centre island.
 */
public final class BedWars extends Game {

    static final int Y = 64;
    private static final int ISLAND_DISTANCE = 42;
    private static final int DIAMOND_DISTANCE = 25;
    private static final int RESPAWN_SECONDS = 5;
    private static final int BUILD_MAX_Y = Y + 30;
    private static final int BUILD_RADIUS = 75;
    private static final String SHOP_TAG = "fc_bw_shop";
    private static final String UPGRADE_TAG = "fc_bw_upgrades";
    private static final Set<Material> BLAST_PROOF = EnumSet.of(Material.END_STONE, Material.OBSIDIAN,
            Material.GLASS, Material.RED_STAINED_GLASS, Material.BLUE_STAINED_GLASS, Material.LIME_STAINED_GLASS,
            Material.YELLOW_STAINED_GLASS);

    /** Per player gear that survives death. */
    static final class Kit {
        int armor;      // 0 leather, 1 chain, 2 iron, 3 diamond
        int pickaxe;    // 0 none .. 4 diamond
        int axe;        // 0 none .. 4 diamond
        boolean shears;
    }

    private record Generator(Location location, Material material, TextDisplay label) {
    }

    private record TimedEvent(int at, String name, Runnable action) {
    }

    final List<Team> teams = new ArrayList<>();
    final Map<UUID, Team> teamOf = new HashMap<>();
    final Map<UUID, Kit> kits = new HashMap<>();
    private final Map<UUID, Integer> respawning = new HashMap<>();
    private final Map<UUID, Integer> finalKills = new HashMap<>();
    private final Map<UUID, Integer> bedsBroken = new HashMap<>();
    private final Explosives explosives = new Explosives();
    private final Set<Long> placed = new HashSet<>();
    private final List<Generator> diamondGens = new ArrayList<>();
    private final List<Generator> emeraldGens = new ArrayList<>();
    private final List<TimedEvent> timeline = new ArrayList<>();
    private int diamondTier = 1;
    private int emeraldTier = 1;
    private int diamondTimer;
    private int emeraldTimer;
    private final Shop shop = new Shop(this);

    public BedWars(FunCraft plugin, int id) {
        super(plugin, id, GameType.BEDWARS);
    }

    FunCraft plugin() {
        return plugin;
    }

    // ------------------------------------------------------------------ map

    @Override
    protected int[] mapArea() {
        return new int[]{-56, -56, 56, 56};
    }

    @Override
    protected void buildMap() {
        List<Player> list = online();
        int teamCount = list.isEmpty() ? 4 : Math.max(2, Math.min(4, list.size()));
        // cardinal directions; with 2 teams use opposite sides
        int[][] dirs = teamCount == 2 ? new int[][]{{0, -1}, {0, 1}} : new int[][]{{0, -1}, {1, 0}, {0, 1}, {-1, 0}};
        for (int i = 0; i < teamCount; i++) {
            Team team = new Team(Team.Color4.values()[i]);
            buildIsland(team, dirs[i][0], dirs[i][1]);
            teams.add(team);
        }
        // diamond islands on the diagonals
        int[][] diag = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}};
        for (int[] d : diag) {
            int x = d[0] * DIAMOND_DISTANCE;
            int z = d[1] * DIAMOND_DISTANCE;
            Build.island(world, x, Y, z, 4.5, Material.GRASS_BLOCK, random);
            Build.disc(world, x, Y, z, 1.5, Material.DIAMOND_BLOCK);
            diamondGens.add(new Generator(new Location(world, x + 0.5, Y + 1.2, z + 0.5), Material.DIAMOND,
                    label(new Location(world, x + 0.5, Y + 3.2, z + 0.5))));
        }
        // emerald centre
        Build.island(world, 0, Y, 0, 11, Material.GRASS_BLOCK, random);
        Build.disc(world, 0, Y, 0, 6.5, Material.POLISHED_ANDESITE);
        Build.ring(world, 0, Y, 0, 5.5, 6.5, Material.STONE_BRICKS);
        for (int[] e : new int[][]{{3, 0}, {-3, 0}}) {
            Build.disc(world, e[0], Y, e[1], 1.2, Material.EMERALD_BLOCK);
            emeraldGens.add(new Generator(new Location(world, e[0] + 0.5, Y + 1.2, e[1] + 0.5), Material.EMERALD,
                    label(new Location(world, e[0] + 0.5, Y + 3.2, e[1] + 0.5))));
        }
        Build.tree(world, 0, Y + 1, 8, random);
        Build.tree(world, 0, Y + 1, -8, random);
        diamondTimer = diamondInterval();
        emeraldTimer = emeraldInterval();
        timeline.add(new TimedEvent(6 * 60, "Diamond II", () -> diamondTier = 2));
        timeline.add(new TimedEvent(12 * 60, "Emerald II", () -> emeraldTier = 2));
        timeline.add(new TimedEvent(18 * 60, "Diamond III", () -> diamondTier = 3));
        timeline.add(new TimedEvent(24 * 60, "Emerald III", () -> emeraldTier = 3));
        timeline.add(new TimedEvent(30 * 60, "Bed destruction", this::destroyAllBeds));
        timeline.add(new TimedEvent(40 * 60, "Game end", () -> end(null, List.of())));
    }

    /** One team island, rotated so "back" points away from the centre. */
    private void buildIsland(Team team, int ux, int uz) {
        int cx = ux * ISLAND_DISTANCE;
        int cz = uz * ISLAND_DISTANCE;
        // perpendicular axis
        int vx = -uz;
        int vz = ux;
        Build.island(world, cx, Y, cz, 9.5, Material.GRASS_BLOCK, random);
        Build.disc(world, cx, Y, cz, 4.5, team.color.concrete);
        Build.disc(world, cx, Y, cz, 3.5, Material.SMOOTH_STONE);
        // generator at the back
        int gx = cx + ux * 6;
        int gz = cz + uz * 6;
        Build.fill(world, gx - 1, Y, gz - 1, gx + 1, Y, gz + 1, Material.IRON_BLOCK);
        Build.set(world, gx, Y, gz, Material.GOLD_BLOCK);
        team.generator = new Location(world, gx + 0.5, Y + 1.2, gz + 0.5);
        // spawn between generator and centre of island, looking towards the map centre
        Location spawn = new Location(world, cx + ux * 3 + 0.5, Y + 1, cz + uz * 3 + 0.5);
        team.spawn = Build.lookAt(spawn, new Location(world, 0.5, Y + 1, 0.5));
        team.islandCenter = new Location(world, cx + 0.5, Y + 1, cz + 0.5);
        // bed in front, lying sideways
        BlockFace side = faceOf(vx, vz);
        int bx = cx - ux * 3;
        int bz = cz - uz * 3;
        team.bedFoot = Build.bed(world, bx, Y + 1, bz, team.color.bed, side);
        team.bedHead = team.bedFoot.getRelative(side);
        // team chest beside the spawn
        Build.directional(world, cx + ux * 3 + vx * 2, Y + 1, cz + uz * 3 + vz * 2, Material.CHEST, faceOf(-vx, -vz));
        // shops on the sides
        Location shopLoc = new Location(world, cx + vx * 6 + 0.5, Y + 1, cz + vz * 6 + 0.5);
        Location upgLoc = new Location(world, cx - vx * 6 + 0.5, Y + 1, cz - vz * 6 + 0.5);
        Build.disc(world, shopLoc.getBlockX(), Y, shopLoc.getBlockZ(), 1.2, Material.SPRUCE_PLANKS);
        Build.disc(world, upgLoc.getBlockX(), Y, upgLoc.getBlockZ(), 1.2, Material.SPRUCE_PLANKS);
        npc(Build.lookAt(shopLoc, team.islandCenter), SHOP_TAG, "<gold><bold>ITEM SHOP", "<yellow>Right click", Villager.Profession.WEAPONSMITH);
        npc(Build.lookAt(upgLoc, team.islandCenter), UPGRADE_TAG, "<aqua><bold>TEAM UPGRADES", "<yellow>Right click", Villager.Profession.LIBRARIAN);
    }

    private static BlockFace faceOf(int x, int z) {
        if (x > 0) {
            return BlockFace.EAST;
        } else if (x < 0) {
            return BlockFace.WEST;
        } else if (z > 0) {
            return BlockFace.SOUTH;
        }
        return BlockFace.NORTH;
    }

    private void npc(Location loc, String tag, String title, String sub, Villager.Profession profession) {
        world.spawn(loc, Villager.class, v -> {
            v.setAI(false);
            v.setInvulnerable(true);
            v.setSilent(true);
            v.setCollidable(false);
            v.setProfession(profession);
            v.addScoreboardTag(tag);
            v.setRotation(loc.getYaw(), 0);
        });
        TextDisplay text = label(loc.clone().add(0, 2.4, 0));
        text.text(Msg.mm(title + "\n" + sub));
    }

    private TextDisplay label(Location loc) {
        return world.spawn(loc, TextDisplay.class, t -> {
            t.setBillboard(Display.Billboard.CENTER);
            t.setShadowed(true);
        });
    }

    // --------------------------------------------------------------- start

    @Override
    protected void onStart(List<Player> list) {
        List<Player> shuffled = new ArrayList<>(list);
        Collections.shuffle(shuffled, random);
        for (int i = 0; i < shuffled.size(); i++) {
            Team team = teams.get(i % teams.size());
            team.members.add(shuffled.get(i).getUniqueId());
            teamOf.put(shuffled.get(i).getUniqueId(), team);
        }
        // teams without players lose their bed straight away
        for (Team team : teams) {
            if (team.members.isEmpty() && !list.isEmpty()) {
                team.bedAlive = false;
                team.bedFoot.setType(Material.AIR, false);
                team.bedHead.setType(Material.AIR, false);
            }
        }
        for (Player p : list) {
            Team team = teamOf.get(p.getUniqueId());
            kits.put(p.getUniqueId(), new Kit());
            p.teleport(team.spawn);
            equip(p);
            Msg.title(p, "<bold>" + team.colored() + " Team", "<gray>Protect your bed and destroy the others!", 5, 60, 10);
        }
        for (Player viewer : list) {
            for (Player other : list) {
                Team t = teamOf.get(other.getUniqueId());
                plugin.sidebars().of(viewer).nameColor(t.color.name(), t.color.text, t.letter() + " ", other.getName());
            }
        }
        Msg.all(list, "<gray>Collect <white>iron</white> and <gold>gold</gold> at your generator, buy gear at the <gold>Item Shop</gold>.");
        Msg.all(list, "<gray>Your bed lets you respawn. Break enemy beds to eliminate them!");
    }

    /** Gives a player their (re)spawn kit, keeping permanent upgrades. */
    void equip(Player p) {
        Team team = teamOf.get(p.getUniqueId());
        Kit kit = kits.computeIfAbsent(p.getUniqueId(), k -> new Kit());
        PlayerInventory inv = p.getInventory();
        inv.clear();
        dressArmor(p);
        inv.setItem(0, sword(Material.WOODEN_SWORD, team));
        if (kit.pickaxe > 0) {
            inv.addItem(Shop.pickaxe(kit.pickaxe));
        }
        if (kit.axe > 0) {
            inv.addItem(Shop.axe(kit.axe));
        }
        if (kit.shears) {
            inv.addItem(ItemBuilder.of(Material.SHEARS).unbreakable().build());
        }
        applyEffects(p);
    }

    void dressArmor(Player p) {
        Team team = teamOf.get(p.getUniqueId());
        Kit kit = kits.computeIfAbsent(p.getUniqueId(), k -> new Kit());
        PlayerInventory inv = p.getInventory();
        inv.setHelmet(armor(Material.LEATHER_HELMET, team));
        inv.setChestplate(armor(Material.LEATHER_CHESTPLATE, team));
        Material legs = switch (kit.armor) {
            case 1 -> Material.CHAINMAIL_LEGGINGS;
            case 2 -> Material.IRON_LEGGINGS;
            case 3 -> Material.DIAMOND_LEGGINGS;
            default -> Material.LEATHER_LEGGINGS;
        };
        Material boots = switch (kit.armor) {
            case 1 -> Material.CHAINMAIL_BOOTS;
            case 2 -> Material.IRON_BOOTS;
            case 3 -> Material.DIAMOND_BOOTS;
            default -> Material.LEATHER_BOOTS;
        };
        inv.setLeggings(armor(legs, team));
        inv.setBoots(armor(boots, team));
    }

    private ItemStack armor(Material material, Team team) {
        ItemBuilder b = ItemBuilder.of(material).unbreakable().color(team.color.leather);
        if (team.protection > 0) {
            b.enchant(Enchantment.PROTECTION, team.protection);
        }
        return b.build();
    }

    ItemStack sword(Material material, Team team) {
        ItemBuilder b = ItemBuilder.of(material).unbreakable();
        if (team != null && team.sharpness) {
            b.enchant(Enchantment.SHARPNESS, 1);
        }
        return b.build();
    }

    void applyEffects(Player p) {
        Team team = teamOf.get(p.getUniqueId());
        if (team != null && team.haste > 0) {
            p.addPotionEffect(new PotionEffect(PotionEffectType.HASTE, 20 * 30, team.haste - 1, true, false));
        }
    }

    /** Re-applies team upgrades to every online member. */
    void refreshTeam(Team team) {
        for (UUID uuid : team.members) {
            Player p = Bukkit.getPlayer(uuid);
            if (p == null || !isAlive(p) || p.getGameMode() == GameMode.SPECTATOR) {
                continue;
            }
            dressArmor(p);
            for (ItemStack item : p.getInventory().getContents()) {
                if (item != null && item.getType().name().endsWith("_SWORD") && team.sharpness) {
                    item.addUnsafeEnchantment(Enchantment.SHARPNESS, 1);
                }
            }
            applyEffects(p);
        }
    }

    Team team(Player p) {
        return teamOf.get(p.getUniqueId());
    }

    Kit kit(Player p) {
        return kits.computeIfAbsent(p.getUniqueId(), k -> new Kit());
    }

    List<Player> members(Team team) {
        List<Player> list = new ArrayList<>();
        for (UUID uuid : team.members) {
            Player p = Bukkit.getPlayer(uuid);
            if (p != null && players.contains(uuid)) {
                list.add(p);
            }
        }
        return list;
    }

    // ------------------------------------------------------------- per second

    @Override
    protected void onSecond() {
        for (TimedEvent event : timeline) {
            if (event.at() == elapsed) {
                if (!event.name().equals("Game end") && !event.name().equals("Bed destruction")) {
                    Msg.all(online(), "<aqua>" + event.name() + " <gray>generators have been upgraded!");
                }
                event.action().run();
                if (state != State.RUNNING) {
                    return;
                }
            }
        }
        // team generators
        for (Team team : teams) {
            if (team.members.isEmpty() && !online().isEmpty()) {
                continue;
            }
            double speed = switch (team.forge) {
                case 1 -> 1.5;
                case 2 -> 2.0;
                case 3 -> 3.0;
                default -> 1.0;
            };
            team.ironProgress += 0.8 * speed;
            team.goldProgress += 0.16 * speed;
            while (team.ironProgress >= 1) {
                team.ironProgress -= 1;
                drop(team.generator, Material.IRON_INGOT, 48);
            }
            while (team.goldProgress >= 1) {
                team.goldProgress -= 1;
                drop(team.generator, Material.GOLD_INGOT, 16);
            }
            if (team.forge >= 3 && elapsed % 60 == 0) {
                drop(team.generator, Material.EMERALD, 4);
            }
            if (team.healPool) {
                for (Player p : members(team)) {
                    if (isAlive(p) && p.getWorld() == world && p.getLocation().distanceSquared(team.islandCenter) < 12 * 12) {
                        p.addPotionEffect(new PotionEffect(PotionEffectType.REGENERATION, 60, 0, true, false));
                    }
                }
            }
            if (team.haste > 0 && elapsed % 20 == 0) {
                members(team).forEach(this::applyEffects);
            }
        }
        // diamond + emerald generators
        if (--diamondTimer <= 0) {
            diamondTimer = diamondInterval();
            diamondGens.forEach(g -> drop(g.location(), Material.DIAMOND, 4));
        }
        if (--emeraldTimer <= 0) {
            emeraldTimer = emeraldInterval();
            emeraldGens.forEach(g -> drop(g.location(), Material.EMERALD, 3));
        }
        String roman = diamondTier == 1 ? "I" : diamondTier == 2 ? "II" : "III";
        for (Generator g : diamondGens) {
            g.label().text(Msg.mm("<aqua><bold>Diamond</bold>\n<yellow>Tier " + roman + "\n<gray>Spawns in <red>" + diamondTimer + "s"));
        }
        String eroman = emeraldTier == 1 ? "I" : emeraldTier == 2 ? "II" : "III";
        for (Generator g : emeraldGens) {
            g.label().text(Msg.mm("<green><bold>Emerald</bold>\n<yellow>Tier " + eroman + "\n<gray>Spawns in <red>" + emeraldTimer + "s"));
        }
        // respawns
        for (Map.Entry<UUID, Integer> e : new ArrayList<>(respawning.entrySet())) {
            Player p = Bukkit.getPlayer(e.getKey());
            if (p == null) {
                respawning.remove(e.getKey());
                continue;
            }
            int left = e.getValue() - 1;
            if (left <= 0) {
                respawning.remove(e.getKey());
                respawn(p);
            } else {
                respawning.put(e.getKey(), left);
                Msg.title(p, "<red><bold>YOU DIED", "<yellow>Respawning in " + left + "...", 0, 25, 0);
            }
        }
    }

    private int diamondInterval() {
        return diamondTier == 1 ? 30 : diamondTier == 2 ? 23 : 15;
    }

    private int emeraldInterval() {
        return emeraldTier == 1 ? 65 : emeraldTier == 2 ? 50 : 35;
    }

    private void drop(Location at, Material material, int cap) {
        int nearby = 0;
        for (Entity e : world.getNearbyEntities(at, 2.5, 2, 2.5)) {
            if (e instanceof Item item && item.getItemStack().getType() == material) {
                nearby += item.getItemStack().getAmount();
            }
        }
        if (nearby >= cap) {
            return;
        }
        Item item = world.dropItem(at, new ItemStack(material));
        item.setVelocity(new Vector(0, 0, 0));
    }

    private void respawn(Player p) {
        Team team = team(p);
        if (team == null) {
            return;
        }
        p.setGameMode(GameMode.SURVIVAL);
        p.teleport(team.spawn);
        p.setHealth(20);
        p.setFoodLevel(20);
        p.setFallDistance(0);
        equip(p);
        p.addPotionEffect(new PotionEffect(PotionEffectType.RESISTANCE, 60, 4, false, false));
        Msg.title(p, "<green><bold>RESPAWNED", "", 0, 20, 10);
    }

    private void destroyAllBeds() {
        for (Team team : teams) {
            if (team.bedAlive) {
                team.bedAlive = false;
                team.bedFoot.setType(Material.AIR, false);
                team.bedHead.setType(Material.AIR, false);
            }
        }
        Msg.title(online(), "<red><bold>BEDS DESTROYED", "<gray>All beds are gone - no more respawns!");
        Msg.sound(online(), "entity.ender_dragon.growl", 1f);
        Msg.all(online(), "<red><bold>All beds have been destroyed!");
    }

    // ---------------------------------------------------------------- death

    @Override
    protected void onDeath(Player victim, Player killer) {
        Team team = team(victim);
        boolean finalKill = team == null || !team.bedAlive;
        deathMessage(victim, killer, finalKill ? "<aqua><bold>FINAL KILL!" : null);
        // hand resources to the killer, everything else is lost
        Map<Material, Integer> loot = new HashMap<>();
        for (ItemStack item : victim.getInventory().getContents()) {
            if (item != null && Shop.isCurrency(item.getType())) {
                loot.merge(item.getType(), item.getAmount(), Integer::sum);
            }
        }
        if (killer != null && isAlive(killer)) {
            for (Map.Entry<Material, Integer> e : loot.entrySet()) {
                killer.getInventory().addItem(new ItemStack(e.getKey(), e.getValue()));
                Msg.raw(killer, Shop.currencyColor(e.getKey()) + "+" + e.getValue() + " " + Shop.currencyName(e.getKey()));
            }
            if (finalKill) {
                finalKills.merge(killer.getUniqueId(), 1, Integer::sum);
            }
        }
        Kit kit = kit(victim);
        kit.pickaxe = Math.max(kit.pickaxe > 0 ? 1 : 0, kit.pickaxe - 1);
        kit.axe = Math.max(kit.axe > 0 ? 1 : 0, kit.axe - 1);
        victim.getInventory().clear();
        victim.setVelocity(new Vector());
        if (finalKill) {
            eliminate(victim, true);
            if (team != null && members(team).stream().noneMatch(this::isAlive)) {
                Msg.all(online(), "<white>Team " + team.colored() + " <white>has been eliminated!");
            }
        } else {
            victim.setGameMode(GameMode.SPECTATOR);
            victim.teleport(spectatorSpawn());
            respawning.put(victim.getUniqueId(), RESPAWN_SECONDS + 1);
            Msg.title(victim, "<red><bold>YOU DIED", "<yellow>Respawning in " + RESPAWN_SECONDS + "...", 0, 25, 0);
        }
    }

    @Override
    protected void checkWin() {
        if (state != State.RUNNING) {
            return;
        }
        List<Team> standing = new ArrayList<>();
        for (Team team : teams) {
            for (UUID uuid : team.members) {
                if (alive.contains(uuid)) {
                    standing.add(team);
                    break;
                }
            }
        }
        if (standing.isEmpty()) {
            end(null, List.of());
        } else if (standing.size() == 1 && startingPlayers > 1) {
            Team winner = standing.get(0);
            end("Team " + winner.colored(), new ArrayList<>(winner.members));
        }
    }

    @Override
    protected void onLeaveRunning(Player player) {
        respawning.remove(player.getUniqueId());
        super.onLeaveRunning(player);
    }

    // --------------------------------------------------------------- blocks

    private static long key(Block b) {
        return ((long) b.getX() & 0x3FFFFFF) << 38 | ((long) b.getZ() & 0x3FFFFFF) << 12 | ((long) b.getY() & 0xFFF);
    }

    @Override
    public void onBlockPlace(BlockPlaceEvent event) {
        Block b = event.getBlock();
        if (b.getY() > BUILD_MAX_Y || Math.abs(b.getX()) > BUILD_RADIUS || Math.abs(b.getZ()) > BUILD_RADIUS) {
            event.setCancelled(true);
            Msg.actionBar(event.getPlayer(), "<red>You can't build here!");
            return;
        }
        for (Team team : teams) {
            if (team.spawn.getBlock().getLocation().distanceSquared(b.getLocation()) < 2.5
                    || team.generator.getBlock().getLocation().distanceSquared(b.getLocation()) < 2.5) {
                event.setCancelled(true);
                Msg.actionBar(event.getPlayer(), "<red>You can't build here!");
                return;
            }
        }
        if (b.getType() == Material.TNT) {
            Explosives.primeNextTick(plugin, b, event.getPlayer());
            return;
        }
        placed.add(key(b));
    }

    @Override
    public void onBlockBreak(BlockBreakEvent event) {
        Block b = event.getBlock();
        Player p = event.getPlayer();
        for (Team team : teams) {
            if (team.isBed(b)) {
                event.setDropItems(false);
                Team own = team(p);
                if (own == team) {
                    event.setCancelled(true);
                    Msg.actionBar(p, "<red>You can't break your own bed!");
                    return;
                }
                bedDestroyed(team, p);
                return;
            }
        }
        if (!placed.remove(key(b))) {
            event.setCancelled(true);
            Msg.actionBar(p, "<red>You can only break blocks placed by players.");
        }
    }

    private void bedDestroyed(Team team, Player breaker) {
        team.bedAlive = false;
        bedsBroken.merge(breaker.getUniqueId(), 1, Integer::sum);
        Team by = team(breaker);
        Msg.all(online(), "<bold>BED DESTRUCTION</bold> <dark_gray>»</dark_gray> " + team.colored() + " Bed <gray>was destroyed by "
                + (by == null ? "<white>" : by.color.mm) + breaker.getName() + "<gray>!");
        Msg.sound(online(), "entity.ender_dragon.growl", 1.3f);
        for (Player member : members(team)) {
            Msg.title(member, "<red><bold>BED DESTROYED!", "<gray>You will no longer respawn!", 5, 60, 10);
            Msg.sound(member, "entity.wither.death", 1f);
        }
    }

    @Override
    public void onExplode(EntityExplodeEvent event) {
        event.blockList().removeIf(b -> BLAST_PROOF.contains(b.getType()) || !placed.contains(key(b)));
        for (Block b : event.blockList()) {
            placed.remove(key(b));
        }
    }

    @Override
    protected void onDamage(EntityDamageEvent event, Player victim, Player attacker) {
        if (attacker != null && !attacker.equals(victim)) {
            Team a = team(attacker);
            if (a != null && a == team(victim)) {
                event.setCancelled(true);
                return;
            }
        }
        EntityDamageEvent.DamageCause cause = event.getCause();
        if (cause == EntityDamageEvent.DamageCause.ENTITY_EXPLOSION || cause == EntityDamageEvent.DamageCause.BLOCK_EXPLOSION) {
            event.setDamage(event.getDamage() * 0.4);
        }
    }

    // -------------------------------------------------------------- interact

    @Override
    public void onInteractEntity(PlayerInteractEntityEvent event) {
        Set<String> tags = event.getRightClicked().getScoreboardTags();
        if (tags.contains(SHOP_TAG)) {
            event.setCancelled(true);
            if (event.getHand() == EquipmentSlot.HAND) {
                shop.openShop(event.getPlayer(), 0);
            }
        } else if (tags.contains(UPGRADE_TAG)) {
            event.setCancelled(true);
            if (event.getHand() == EquipmentSlot.HAND) {
                shop.openUpgrades(event.getPlayer());
            }
        }
    }

    @Override
    public void onInteract(PlayerInteractEvent event) {
        explosives.handleFireball(event);
    }

    @Override
    public void onInventoryClick(InventoryClickEvent event) {
        if (event.getSlotType() == InventoryType.SlotType.ARMOR) {
            event.setCancelled(true);
        }
    }

    @Override
    protected boolean allowItemDrops() {
        return true;
    }

    @Override
    protected double voidLevel() {
        return Y - 30;
    }

    @Override
    protected Location spectatorSpawn() {
        return new Location(world, 0.5, Y + 25, 0.5, 0, 70);
    }

    // -------------------------------------------------------------- sidebar

    @Override
    protected List<String> sidebar(Player player) {
        List<String> lines = new ArrayList<>();
        lines.add("<dark_gray>#" + id);
        lines.add(" ");
        TimedEvent next = null;
        for (TimedEvent e : timeline) {
            if (e.at() > elapsed) {
                next = e;
                break;
            }
        }
        if (next != null) {
            lines.add("<white>" + next.name() + " in <green>" + Msg.time(next.at() - elapsed));
        }
        lines.add("  ");
        Team mine = team(player);
        for (Team team : teams) {
            int aliveCount = 0;
            for (UUID uuid : team.members) {
                if (alive.contains(uuid)) {
                    aliveCount++;
                }
            }
            String status;
            if (team.bedAlive && aliveCount > 0) {
                status = "<green>✔";
            } else if (aliveCount > 0) {
                status = "<yellow>" + aliveCount;
            } else {
                status = "<red>✘";
            }
            lines.add(team.letter() + " <white>" + team.name() + ": " + status + (team == mine ? " <gray>YOU" : ""));
        }
        lines.add("   ");
        lines.add("<white>Kills: <green>" + kills.getOrDefault(player.getUniqueId(), 0));
        lines.add("<white>Final kills: <green>" + finalKills.getOrDefault(player.getUniqueId(), 0));
        lines.add("<white>Beds broken: <green>" + bedsBroken.getOrDefault(player.getUniqueId(), 0));
        return lines;
    }

    @Override
    protected void cleanup() {
        respawning.clear();
    }
}
