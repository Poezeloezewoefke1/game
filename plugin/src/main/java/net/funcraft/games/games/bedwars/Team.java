package net.funcraft.games.games.bedwars;

import net.kyori.adventure.text.format.NamedTextColor;
import org.bukkit.Color;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.block.Block;

import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;

/** A BedWars team and its island. */
public final class Team {

    public enum Color4 {
        RED("Red", "<red>", NamedTextColor.RED, Material.RED_WOOL, Material.RED_BED, Material.RED_STAINED_GLASS, Material.RED_CONCRETE, Color.RED),
        BLUE("Blue", "<blue>", NamedTextColor.BLUE, Material.BLUE_WOOL, Material.BLUE_BED, Material.BLUE_STAINED_GLASS, Material.BLUE_CONCRETE, Color.BLUE),
        GREEN("Green", "<green>", NamedTextColor.GREEN, Material.LIME_WOOL, Material.LIME_BED, Material.LIME_STAINED_GLASS, Material.LIME_CONCRETE, Color.LIME),
        YELLOW("Yellow", "<yellow>", NamedTextColor.YELLOW, Material.YELLOW_WOOL, Material.YELLOW_BED, Material.YELLOW_STAINED_GLASS, Material.YELLOW_CONCRETE, Color.YELLOW);

        final String name;
        final String mm;
        final NamedTextColor text;
        final Material wool;
        final Material bed;
        final Material glass;
        final Material concrete;
        final Color leather;

        Color4(String name, String mm, NamedTextColor text, Material wool, Material bed, Material glass, Material concrete, Color leather) {
            this.name = name;
            this.mm = mm;
            this.text = text;
            this.wool = wool;
            this.bed = bed;
            this.glass = glass;
            this.concrete = concrete;
            this.leather = leather;
        }
    }

    final Color4 color;
    final Set<UUID> members = new LinkedHashSet<>();
    Location spawn;
    Location islandCenter;
    Location generator;
    Block bedFoot;
    Block bedHead;
    boolean bedAlive = true;

    // team upgrades
    boolean sharpness;
    int protection;
    int haste;
    int forge;
    boolean healPool;
    /** One-shot trap armed in the base. */
    boolean trap;

    double ironProgress;
    double goldProgress;

    Team(Color4 color) {
        this.color = color;
    }

    public String name() {
        return color.name;
    }

    /** Coloured team name in MiniMessage. */
    public String colored() {
        return color.mm + color.name;
    }

    public String letter() {
        return color.mm + "<bold>" + color.name.charAt(0) + "</bold>";
    }

    boolean isBed(Block b) {
        return b.equals(bedFoot) || b.equals(bedHead);
    }
}
