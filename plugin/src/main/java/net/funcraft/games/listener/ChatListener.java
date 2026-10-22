package net.funcraft.games.listener;

import io.papermc.paper.event.player.AsyncChatEvent;
import net.funcraft.games.util.Msg;
import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Chat as "[12✫] Name: message", with the BedWars team colour on the name. The prefix is
 * computed on the main thread (see Sidebars) because chat events run asynchronously.
 */
public final class ChatListener implements Listener {

    private final Map<UUID, String> prefixes = new ConcurrentHashMap<>();

    /** MiniMessage for everything before the colon, e.g. "<gray>[3✫] <red>Steve". */
    public void setPrefix(Player player, String miniMessage) {
        prefixes.put(player.getUniqueId(), miniMessage);
    }

    public void remove(Player player) {
        prefixes.remove(player.getUniqueId());
    }

    @EventHandler(priority = EventPriority.HIGH, ignoreCancelled = true)
    public void onChat(AsyncChatEvent event) {
        String prefix = prefixes.getOrDefault(event.getPlayer().getUniqueId(), "<white>" + event.getPlayer().getName());
        Component head = Msg.mm(prefix + "<dark_gray>: ");
        event.renderer((source, displayName, message, viewer) ->
                Component.empty().append(head).append(message.colorIfAbsent(NamedTextColor.WHITE)));
    }
}
