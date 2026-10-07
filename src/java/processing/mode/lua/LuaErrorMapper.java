package processing.mode.lua;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Maps Lua interpreter error output back to sketch tabs.
 *
 * Lua errors look like:
 *   input:12: attempt to index a nil value (global 'foo')
 *   [string "..."]:5: ...
 *   /tmp/processing_lua_12345.lua:8: ...
 *
 * This class is pure static — no state, no I/O.
 */
public final class LuaErrorMapper {

    // Matches:  <path>:<line>: <message>
    //
    // The path is matched lazily so the FIRST :<digits>: wins; a message like
    // "error at 12:30:00" must not be read as line 30. Windows paths still work:
    // in C:\tmp\foo.lua:12: the drive colon isn't followed by digits, so the
    // lazy match moves past it to :12:.
    private static final Pattern LUA_ERROR =
        Pattern.compile("^(.+?):(\\d+):\\s*(.+)$");

    private LuaErrorMapper() {}

    // ── Runner output ─────────────────────────────────────────────────────
    //
    // luamode-runner loads the combined sketch under the temp file's name and
    // reports errors as "<that name>:<line>: message". Matching on that exact
    // name (instead of "anything followed by :digits:") means a warning that
    // happens to contain a time, a path or a Rust source location is never
    // mistaken for a line in the sketch.

    private static Pattern located(String chunkName) {
        return Pattern.compile("(?:^|[\\s\\[\"'/\\\\])" + Pattern.quote(chunkName) + ":(\\d+):\\s*");
    }

    /**
     * Problems from the stderr of a runner that exited with an error.
     *
     * @param chunkName name the combined source was loaded under (the temp file's name)
     */
    public static List<LuaProblem> map(String output, String chunkName,
                                       int headerLines, int[] tabStartLines) {
        List<LuaProblem> problems = new ArrayList<>();
        Pattern loc = located(chunkName);
        String lastPlain = null;

        for (String raw : output.lines().toList()) {
            String line = raw.strip();
            if (line.isEmpty()) continue;
            if (line.equals("stack traceback:")) break;
            Matcher m = loc.matcher(line);
            if (!m.find()) { lastPlain = line; continue; }

            int userLine;
            try {
                userLine = Integer.parseInt(m.group(1)) - 1 - headerLines;
            } catch (NumberFormatException tooBig) {
                lastPlain = line;
                continue;
            }
            String message = innerLines(line.substring(m.end()).strip(),
                userLine < 0 ? -1 : tabIndex(userLine, tabStartLines, headerLines),
                headerLines, tabStartLines, null);
            if (message.isEmpty()) message = "error";
            if (userLine < 0) {
                problems.add(new LuaProblem(-1, -1, message, LuaProblem.Severity.ERROR));
            } else {
                problems.add(new LuaProblem(
                    tabIndex(userLine, tabStartLines, headerLines),
                    lineInTab(userLine, tabStartLines, headerLines),
                    message, LuaProblem.Severity.ERROR));
            }
        }

        if (problems.isEmpty() && lastPlain != null) {
            // Nothing that points at a line (a runner problem, say). Still an
            // error, just not one we can highlight.
            problems.add(new LuaProblem(-1, -1, lastPlain, LuaProblem.Severity.ERROR));
        }
        return problems;
    }

    /**
     * One line of runner output with every "<chunk>:<line>:" turned into
     * "<tab file>:<line in that tab>:", so the console shows the numbers the
     * person sees in the editor instead of positions in a temp file.
     */
    public static String rewrite(String line, String chunkName, int headerLines,
                                 int[] tabStartLines, String[] tabNames) {
        if (line == null || chunkName == null || line.indexOf(chunkName) < 0) return line;
        Matcher m = Pattern.compile(Pattern.quote(chunkName) + ":(\\d+):").matcher(line);
        StringBuilder sb = new StringBuilder();
        while (m.find()) {
            String repl = m.group();
            try {
                int userLine = Integer.parseInt(m.group(1)) - 1 - headerLines;
                if (userLine >= 0) {
                    int tab = tabIndex(userLine, tabStartLines, headerLines);
                    int ln  = lineInTab(userLine, tabStartLines, headerLines);
                    String name = (tabNames != null && tab < tabNames.length && tabNames[tab] != null)
                        ? tabNames[tab] : "sketch";
                    repl = name + ":" + (ln + 1) + ":";
                }
            } catch (NumberFormatException ignored) {}
            m.appendReplacement(sb, Matcher.quoteReplacement(repl));
        }
        m.appendTail(sb);
        return innerLines(sb.toString(), firstTab(line, chunkName, headerLines, tabStartLines),
            headerLines, tabStartLines, tabNames);
    }

    // Lua's syntax errors carry a second line number inside the message:
    //   ')' expected (to close '(' at line 5) near 'end'
    // That one counts lines of the combined file too, so it needs the same
    // translation, or it points a few lines below the real spot.
    private static final Pattern INNER_LINE = Pattern.compile("\\bat line (\\d+)\\)");

    /** Tab of the first "<chunk>:<line>:" in a line of runner output, or -1. */
    private static int firstTab(String line, String chunkName, int headerLines, int[] tabStartLines) {
        Matcher m = Pattern.compile(Pattern.quote(chunkName) + ":(\\d+):").matcher(line);
        if (!m.find()) return -1;
        try {
            int userLine = Integer.parseInt(m.group(1)) - 1 - headerLines;
            return userLine < 0 ? -1 : tabIndex(userLine, tabStartLines, headerLines);
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    /**
     * @param errorTab tab the error itself is in; a line in another tab gets
     *                 that tab's name added (when names are known)
     */
    static String innerLines(String message, int errorTab, int headerLines,
                             int[] tabStartLines, String[] tabNames) {
        if (message.indexOf("at line ") < 0) return message;
        Matcher m = INNER_LINE.matcher(message);
        StringBuilder sb = new StringBuilder();
        while (m.find()) {
            String repl = m.group();
            try {
                int userLine = Integer.parseInt(m.group(1)) - 1 - headerLines;
                if (userLine >= 0) {
                    int tab = tabIndex(userLine, tabStartLines, headerLines);
                    int ln  = lineInTab(userLine, tabStartLines, headerLines) + 1;
                    boolean elsewhere = errorTab >= 0 && tab != errorTab
                        && tabNames != null && tab < tabNames.length && tabNames[tab] != null;
                    repl = "at line " + ln + (elsewhere ? " of " + tabNames[tab] : "") + ")";
                }
            } catch (NumberFormatException ignored) {}
            m.appendReplacement(sb, Matcher.quoteReplacement(repl));
        }
        m.appendTail(sb);
        return sb.toString();
    }

    /**
     * Parse interpreter output into a list of {@link LuaProblem}s,
     * mapping combined-source line numbers back to sketch tabs.
     *
     * @param output        raw stderr / stdout from the Lua interpreter
     * @param headerLines   number of generated header lines prepended before user code
     * @param tabStartLines first combined-source line of each tab (0-based, length = tab count)
     */
    public static List<LuaProblem> map(String output, int headerLines, int[] tabStartLines) {
        List<LuaProblem> problems = new ArrayList<>();

        for (String raw : output.lines().toList()) {
            // Everything after "stack traceback:" repeats locations of the error
            // already reported; reporting them again would duplicate it.
            if (raw.trim().equals("stack traceback:")) break;
            Matcher m = LUA_ERROR.matcher(raw.trim());
            if (!m.matches()) continue;

            int    combinedLine = Integer.parseInt(m.group(2)) - 1; // convert to 0-based
            String message      = m.group(3).trim();

            int userLine = combinedLine - headerLines;
            if (userLine < 0) {
                // Error in the generated header — surface at tab 0, line 0
                problems.add(new LuaProblem(0, 0,
                    "Internal error in generated header: " + message,
                    LuaProblem.Severity.ERROR));
                continue;
            }

            problems.add(new LuaProblem(
                tabIndex(userLine, tabStartLines, headerLines),
                lineInTab(userLine, tabStartLines, headerLines),
                message,
                LuaProblem.Severity.ERROR
            ));
        }

        if (problems.isEmpty() && !output.isBlank()) {
            // Unstructured error — no line info, surface at top of sketch
            problems.add(new LuaProblem(0, 0, output.trim(), LuaProblem.Severity.ERROR));
        }

        return problems;
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private static int tabIndex(int userLine, int[] tabStartLines, int headerLines) {
        for (int t = tabStartLines.length - 1; t >= 0; t--) {
            if (userLine >= tabStartLines[t] - headerLines) return t;
        }
        return 0;
    }

    private static int lineInTab(int userLine, int[] tabStartLines, int headerLines) {
        if (tabStartLines.length == 0) return userLine;   // no tab info: whole sketch is one tab
        int tab = tabIndex(userLine, tabStartLines, headerLines);
        return userLine - (tabStartLines[tab] - headerLines);
    }
}
