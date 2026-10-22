package net.funcraft.games;

import net.funcraft.games.util.Msg;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/** Groups of friends that queue together (and share a BedWars team). */
public final class Parties {

    public static final int MAX_SIZE = 8;
    private static final long INVITE_MS = 60_000;

    /** A party; the first member is the leader. */
    public static final class Party {
        private final Set<UUID> members = new LinkedHashSet<>();

        public UUID leader() {
            return members.iterator().next();
        }

        public Set<UUID> members() {
            return members;
        }

        public List<Player> online() {
            List<Player> list = new ArrayList<>();
            for (UUID id : members) {
                Player p = Bukkit.getPlayer(id);
                if (p != null) {
                    list.add(p);
                }
            }
            return list;
        }
    }

    private final Map<UUID, Party> byMember = new HashMap<>();
    /** invited player -> (party leader, time) */
    private final Map<UUID, Map<UUID, Long>> invites = new HashMap<>();

    public Party of(Player player) {
        return byMember.get(player.getUniqueId());
    }

    public Party of(UUID player) {
        return byMember.get(player);
    }

    public boolean isLeader(Player player) {
        Party party = of(player);
        return party != null && party.leader().equals(player.getUniqueId());
    }

    public void invite(Player leader, Player target) {
        if (leader.equals(target)) {
            Msg.send(leader, "<red>You can't invite yourself.");
            return;
        }
        Party party = of(leader);
        if (party != null && !party.leader().equals(leader.getUniqueId())) {
            Msg.send(leader, "<red>Only the party leader can invite people.");
            return;
        }
        if (party != null && party.members().size() >= MAX_SIZE) {
            Msg.send(leader, "<red>Your party is full (" + MAX_SIZE + " players).");
            return;
        }
        if (of(target) != null && of(target) == party) {
            Msg.send(leader, "<gray>" + target.getName() + " is already in your party.");
            return;
        }
        invites.computeIfAbsent(target.getUniqueId(), k -> new HashMap<>()).put(leader.getUniqueId(), System.currentTimeMillis());
        Msg.send(leader, "<green>Party invite sent to <yellow>" + target.getName() + "<green>.");
        Msg.send(target, "<yellow>" + leader.getName() + " <aqua>invited you to their party! "
                + "<click:run_command:'/party accept " + leader.getName() + "'><green><bold>[JOIN]</bold></green></click>");
        Msg.sound(target, "entity.player.levelup", 1.8f);
    }

    public void accept(Player player, Player leader) {
        Map<UUID, Long> mine = invites.get(player.getUniqueId());
        Long time = mine == null ? null : mine.remove(leader.getUniqueId());
        if (time == null || System.currentTimeMillis() - time > INVITE_MS) {
            Msg.send(player, "<red>You have no (recent) party invite from " + leader.getName() + ".");
            return;
        }
        Party party = of(leader);
        if (party == null) {
            party = new Party();
            party.members().add(leader.getUniqueId());
            byMember.put(leader.getUniqueId(), party);
        }
        if (party.members().size() >= MAX_SIZE) {
            Msg.send(player, "<red>That party is full.");
            return;
        }
        leave(player, false);
        party.members().add(player.getUniqueId());
        byMember.put(player.getUniqueId(), party);
        broadcast(party, "<yellow>" + player.getName() + " <green>joined the party!");
    }

    public void leave(Player player, boolean announce) {
        Party party = of(player);
        if (party == null) {
            if (announce) {
                Msg.send(player, "<gray>You are not in a party.");
            }
            return;
        }
        boolean wasLeader = party.leader().equals(player.getUniqueId());
        party.members().remove(player.getUniqueId());
        byMember.remove(player.getUniqueId());
        if (announce) {
            Msg.send(player, "<gray>You left the party.");
        }
        if (party.members().size() <= 1) {
            for (UUID id : party.members()) {
                byMember.remove(id);
                Player p = Bukkit.getPlayer(id);
                if (p != null) {
                    Msg.send(p, "<gray>Your party was disbanded.");
                }
            }
            party.members().clear();
            return;
        }
        broadcast(party, "<yellow>" + player.getName() + " <gray>left the party.");
        if (wasLeader) {
            Player next = Bukkit.getPlayer(party.leader());
            broadcast(party, "<yellow>" + (next == null ? "?" : next.getName()) + " <gray>is the new party leader.");
        }
    }

    public void kick(Player leader, Player target) {
        Party party = of(leader);
        if (party == null || !party.leader().equals(leader.getUniqueId())) {
            Msg.send(leader, "<red>Only the party leader can kick.");
            return;
        }
        if (of(target) != party || target.equals(leader)) {
            Msg.send(leader, "<red>" + target.getName() + " is not in your party.");
            return;
        }
        leave(target, false);
        Msg.send(target, "<red>You were removed from the party.");
    }

    public void list(Player player) {
        Party party = of(player);
        if (party == null) {
            Msg.send(player, "<gray>You are not in a party. Invite someone with <yellow>/party invite <player>");
            return;
        }
        List<String> names = new ArrayList<>();
        for (UUID id : party.members()) {
            Player p = Bukkit.getPlayer(id);
            String name = p == null ? Bukkit.getOfflinePlayer(id).getName() : p.getName();
            names.add((id.equals(party.leader()) ? "<gold>★ " : "<white>") + name + (p == null ? " <dark_gray>(offline)" : ""));
        }
        Msg.send(player, "<aqua>Party (" + party.members().size() + "/" + MAX_SIZE + "): " + String.join("<gray>, ", names));
    }

    public void chat(Player player, String message) {
        Party party = of(player);
        if (party == null) {
            Msg.send(player, "<gray>You are not in a party.");
            return;
        }
        for (Player p : party.online()) {
            Msg.raw(p, "<aqua>[Party] <white>" + player.getName() + "<dark_gray>: <white>" + Msg.escape(message));
        }
    }

    public void broadcast(Party party, String text) {
        for (Player p : party.online()) {
            Msg.send(p, text);
        }
    }

    public void quit(Player player) {
        invites.remove(player.getUniqueId());
        for (Map<UUID, Long> map : invites.values()) {
            map.remove(player.getUniqueId());
        }
        leave(player, false);
    }
}
