package net.funcraft.games.util;

import io.papermc.paper.scoreboard.numbers.NumberFormat;
import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;
import org.bukkit.scoreboard.Criteria;
import org.bukkit.scoreboard.DisplaySlot;
import org.bukkit.scoreboard.Objective;
import org.bukkit.scoreboard.Scoreboard;
import org.bukkit.scoreboard.Team;

import java.util.List;

/**
 * Per-player sidebar. Each line is a scoreboard team whose prefix holds the text, so lines
 * can change every second without flicker. The same scoreboard also carries name-tag colour
 * teams for team based games.
 */
public final class Sidebar {

    private static final int MAX_LINES = 15;
    private static final String[] ENTRIES = new String[MAX_LINES];

    static {
        String codes = "0123456789abcdef";
        for (int i = 0; i < MAX_LINES; i++) {
            ENTRIES[i] = "§" + codes.charAt(i) + "§r";
        }
    }

    private final Scoreboard board;
    private final Objective objective;
    private int shown;

    public Sidebar(Player player) {
        this.board = Bukkit.getScoreboardManager().getNewScoreboard();
        this.objective = board.registerNewObjective("fc_side", Criteria.DUMMY, Component.text("FunCraft"));
        objective.setDisplaySlot(DisplaySlot.SIDEBAR);
        objective.numberFormat(NumberFormat.blank());
        player.setScoreboard(board);
    }

    public Scoreboard board() {
        return board;
    }

    public void update(String title, List<String> lines) {
        objective.displayName(Msg.mm(title));
        int count = Math.min(MAX_LINES, lines.size());
        for (int i = 0; i < count; i++) {
            String entry = ENTRIES[i];
            Team team = board.getTeam("fc_line_" + i);
            if (team == null) {
                team = board.registerNewTeam("fc_line_" + i);
                team.addEntry(entry);
            }
            team.prefix(Msg.mm(lines.get(i)));
            objective.getScore(entry).setScore(count - i);
        }
        for (int i = count; i < shown; i++) {
            board.resetScores(ENTRIES[i]);
        }
        shown = count;
    }

    /** Colours a player's name tag / tab name for whoever owns this sidebar. */
    public void nameColor(String teamId, NamedTextColor color, String prefix, String playerName) {
        Team team = board.getTeam("fc_tag_" + teamId);
        if (team == null) {
            team = board.registerNewTeam("fc_tag_" + teamId);
            team.color(color);
            team.prefix(Msg.mm(prefix));
            team.setAllowFriendlyFire(true);
            team.setCanSeeFriendlyInvisibles(true);
        }
        if (!team.hasEntry(playerName)) {
            team.addEntry(playerName);
        }
    }

    public void clearNameColors() {
        for (Team team : board.getTeams()) {
            if (team.getName().startsWith("fc_tag_")) {
                team.unregister();
            }
        }
    }
}
