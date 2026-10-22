package net.funcraft.games.util;

import net.kyori.adventure.audience.Audience;
import net.kyori.adventure.key.Key;
import net.kyori.adventure.sound.Sound;
import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.TextDecoration;
import net.kyori.adventure.text.minimessage.MiniMessage;
import net.kyori.adventure.title.Title;
import org.bukkit.entity.Player;

import java.time.Duration;
import java.util.Collection;

/** Small helpers around Adventure / MiniMessage so the rest of the code stays short. */
public final class Msg {

    public static final String PREFIX = "<gradient:#ffb300:#ff5e00><bold>FunCraft</bold></gradient> <dark_gray>»</dark_gray> ";
    private static final MiniMessage MM = MiniMessage.miniMessage();

    private Msg() {
    }

    /** Parses MiniMessage text. Italic is disabled so item names/lore look clean. */
    public static Component mm(String text) {
        return MM.deserialize(text).decorationIfAbsent(TextDecoration.ITALIC, TextDecoration.State.FALSE);
    }

    public static String escape(String raw) {
        return MM.escapeTags(raw);
    }

    public static void send(Audience to, String text) {
        to.sendMessage(mm(PREFIX + text));
    }

    public static void raw(Audience to, String text) {
        to.sendMessage(mm(text));
    }

    public static void all(Collection<? extends Player> players, String text) {
        Component c = mm(PREFIX + text);
        for (Player p : players) {
            p.sendMessage(c);
        }
    }

    public static void title(Player p, String title, String subtitle, int fadeIn, int stay, int fadeOut) {
        p.showTitle(Title.title(mm(title), mm(subtitle), Title.Times.times(
                Duration.ofMillis(fadeIn * 50L), Duration.ofMillis(stay * 50L), Duration.ofMillis(fadeOut * 50L))));
    }

    public static void title(Collection<? extends Player> players, String title, String subtitle) {
        for (Player p : players) {
            title(p, title, subtitle, 5, 40, 10);
        }
    }

    public static void actionBar(Player p, String text) {
        p.sendActionBar(mm(text));
    }

    /** Plays a vanilla sound by its key, e.g. "entity.experience_orb.pickup". */
    public static void sound(Player p, String key, float pitch) {
        p.playSound(Sound.sound(Key.key(key), Sound.Source.MASTER, 1f, pitch));
    }

    public static void sound(Collection<? extends Player> players, String key, float pitch) {
        for (Player p : players) {
            sound(p, key, pitch);
        }
    }

    public static String time(int seconds) {
        if (seconds < 0) {
            seconds = 0;
        }
        return String.format("%d:%02d", seconds / 60, seconds % 60);
    }
}
