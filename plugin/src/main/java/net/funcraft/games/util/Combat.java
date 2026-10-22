package net.funcraft.games.util;

import org.bukkit.attribute.Attribute;
import org.bukkit.attribute.AttributeInstance;
import org.bukkit.entity.Player;

/** Switches a player between modern combat and old 1.8-style spam-click combat. */
public final class Combat {

    private static final double MODERN_ATTACK_SPEED = 4.0;
    private static final double LEGACY_ATTACK_SPEED = 1024.0;

    private Combat() {
    }

    /** No attack cooldown: every click is a full-strength hit, like before 1.9. */
    public static void legacy(Player player) {
        AttributeInstance speed = player.getAttribute(Attribute.ATTACK_SPEED);
        if (speed != null) {
            speed.setBaseValue(LEGACY_ATTACK_SPEED);
        }
    }

    public static void reset(Player player) {
        AttributeInstance speed = player.getAttribute(Attribute.ATTACK_SPEED);
        if (speed != null) {
            speed.setBaseValue(MODERN_ATTACK_SPEED);
        }
    }
}
