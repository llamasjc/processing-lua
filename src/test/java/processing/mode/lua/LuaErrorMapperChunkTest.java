package processing.mode.lua;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Mapping what luamode-runner prints (errors named after the temp file the
 * combined sketch was loaded from) back to tabs and lines.
 */
class LuaErrorMapperChunkTest {

    private static final String CHUNK  = "processing_lua_123.lua";
    private static final int    HEADER = 3;
    // tab 0 starts at combined line 3, tab 1 at 13, tab 2 at 20 (0-based)
    private static final int[]    TABS  = {3, 13, 20};
    private static final String[] NAMES = {"sketch.lua", "ball.lua", "util.lua"};

    @Test
    void errorInFirstTab() {
        List<LuaProblem> ps = LuaErrorMapper.map(CHUNK + ":8: attempt to call a nil value (global 'elipse')\n",
                                                 CHUNK, HEADER, TABS);
        assertEquals(1, ps.size());
        assertEquals(0, ps.get(0).getTabIndex());
        assertEquals(4, ps.get(0).getLineNumber());       // line 8 -> index 7 -> minus 3 header lines
        assertEquals("attempt to call a nil value (global 'elipse')", ps.get(0).getMessage());
        assertTrue(ps.get(0).hasLocation());
    }

    @Test
    void errorInLaterTab() {
        List<LuaProblem> ps = LuaErrorMapper.map(CHUNK + ":22: boom", CHUNK, HEADER, TABS);
        assertEquals(1, ps.size());
        assertEquals(2, ps.get(0).getTabIndex());
        assertEquals(1, ps.get(0).getLineNumber());
    }

    @Test
    void warningsBeforeTheErrorAreNotErrors() {
        String out =
            "loadImage(\"cat.png\"): No such file or directory (os error 2) (only PNG is supported)\n" +
            "saveFrame(\"a/b.png\"): No such file or directory (os error 2)\n" +
            CHUNK + ":14: bad argument #3 to ellipse(): expected a number, got nil\n";
        List<LuaProblem> ps = LuaErrorMapper.map(out, CHUNK, HEADER, TABS);
        assertEquals(1, ps.size(), "only the line naming the sketch is an error: " + ps);
        assertEquals(1, ps.get(0).getTabIndex());
        assertEquals(0, ps.get(0).getLineNumber());
    }

    @Test
    void otherFilesAndTimesAreNotSketchLines() {
        // the old "anything:digits:" rule read all three of these as sketch lines
        String out =
            "started at 12:30:05\n" +
            "thread 'main' panicked at src/lib.rs:123:45:\n" +
            "helper.lua:7: from a file the sketch loaded itself\n";
        List<LuaProblem> ps = LuaErrorMapper.map(out, CHUNK, HEADER, TABS);
        assertEquals(1, ps.size());
        assertFalse(ps.get(0).hasLocation(), "no sketch line was named, so nothing to highlight");
        assertEquals("helper.lua:7: from a file the sketch loaded itself", ps.get(0).getMessage());
    }

    @Test
    void runnerInternalErrorHasNoLocation() {
        String out = "luamode-runner internal error: index out of bounds (src/main.rs, line 640)\n" +
                     "This is a bug in Lua Mode, not in your sketch.\n";
        List<LuaProblem> ps = LuaErrorMapper.map(out, CHUNK, HEADER, TABS);
        assertEquals(1, ps.size());
        assertFalse(ps.get(0).hasLocation());
    }

    @Test
    void emptyOutputGivesNothing() {
        assertTrue(LuaErrorMapper.map("", CHUNK, HEADER, TABS).isEmpty());
        assertTrue(LuaErrorMapper.map("\n  \n", CHUNK, HEADER, TABS).isEmpty());
    }

    @Test
    void lineInsideTheHeaderOrAbsurdlyLarge() {
        List<LuaProblem> header = LuaErrorMapper.map(CHUNK + ":1: odd", CHUNK, HEADER, TABS);
        assertEquals(1, header.size());
        assertFalse(header.get(0).hasLocation());

        List<LuaProblem> huge = LuaErrorMapper.map(CHUNK + ":99999999999999999999: odd", CHUNK, HEADER, TABS);
        assertEquals(1, huge.size());
        assertFalse(huge.get(0).hasLocation());
    }

    @Test
    void chunkNameWithRegexCharacters() {
        String chunk = "processing_lua_(1)+[x].lua";
        List<LuaProblem> ps = LuaErrorMapper.map(chunk + ":4: msg", chunk, HEADER, new int[]{3});
        assertEquals(1, ps.size());
        assertEquals(0, ps.get(0).getLineNumber());
    }

    @Test
    void tracebackIsIgnored() {
        String out = CHUNK + ":5: first\nstack traceback:\n\t" + CHUNK + ":9: in function 'draw'\n";
        assertEquals(1, LuaErrorMapper.map(out, CHUNK, HEADER, TABS).size());
    }

    // ── What the console shows ────────────────────────────────────────────────

    @Test
    void rewriteUsesTabNameAndTabLine() {
        assertEquals("sketch.lua:5: attempt to call a nil value",
            LuaErrorMapper.rewrite(CHUNK + ":8: attempt to call a nil value", CHUNK, HEADER, TABS, NAMES));
        assertEquals("ball.lua:1: boom",
            LuaErrorMapper.rewrite(CHUNK + ":14: boom", CHUNK, HEADER, TABS, NAMES));
        assertEquals("util.lua:2: boom",
            LuaErrorMapper.rewrite(CHUNK + ":22: boom", CHUNK, HEADER, TABS, NAMES));
    }

    @Test
    void rewriteLeavesEverythingElseAlone() {
        for (String line : new String[]{"", "hello", "frame 60", "12:30:05", "other.lua:3: x", "$1 \\ weird"}) {
            assertEquals(line, LuaErrorMapper.rewrite(line, CHUNK, HEADER, TABS, NAMES));
        }
        assertEquals(null, LuaErrorMapper.rewrite(null, CHUNK, HEADER, TABS, NAMES));
    }

    @Test
    void rewriteSurvivesMissingNames() {
        assertEquals("sketch:5: x", LuaErrorMapper.rewrite(CHUNK + ":8: x", CHUNK, HEADER, TABS, null));
        // fewer names than tabs: the tab without one is just called "sketch"
        assertEquals("sketch:2: x", LuaErrorMapper.rewrite(CHUNK + ":22: x", CHUNK, HEADER, TABS, new String[]{"a.lua"}));
    }

    @Test
    void formatProblemWithAndWithoutLine() {
        assertEquals("Line 5: boom",
            LuaRunner.formatProblem(new LuaProblem(0, 4, "boom", LuaProblem.Severity.ERROR)));
        assertEquals("The sketch stopped unexpectedly (exit status 139).",
            LuaRunner.formatProblem(new LuaProblem(-1, -1,
                "The sketch stopped unexpectedly (exit status 139).", LuaProblem.Severity.ERROR)));
    }

    // ── line numbers inside the message ──────────────────────────────────

    @Test
    void closingLineInsideSyntaxErrorIsTranslated() {
        // 3 header lines; the "(" is on line 2 of the sketch = line 5 combined
        List<LuaProblem> p = LuaErrorMapper.map(
            "t.lua:6: ')' expected (to close '(' at line 5) near 'end'", "t.lua", 3, new int[]{3});
        assertEquals(1, p.size());
        assertEquals(2, p.get(0).getLineNumber());
        assertEquals("')' expected (to close '(' at line 2) near 'end'", p.get(0).getMessage());
    }

    @Test
    void consoleLineGetsBothNumbersTranslated() {
        String out = LuaErrorMapper.rewrite(
            "t.lua:6: ')' expected (to close '(' at line 5) near 'end'",
            "t.lua", 3, new int[]{3}, new String[]{"sketch.lua"});
        assertEquals("sketch.lua:3: ')' expected (to close '(' at line 2) near 'end'", out);
    }

    @Test
    void closingLineInAnotherTabNamesThatTab() {
        // tab a.lua: combined lines 3..12, tab b.lua from 13. Opened in a (line 4), fails in b.
        String out = LuaErrorMapper.rewrite(
            "t.lua:15: 'end' expected (to close 'function' at line 7) near <eof>",
            "t.lua", 3, new int[]{3, 13}, new String[]{"a.lua", "b.lua"});
        assertEquals("b.lua:2: 'end' expected (to close 'function' at line 4 of a.lua) near <eof>", out);
    }

    @Test
    void messageThatOnlyMentionsLinesIsLeftAlone() {
        assertEquals("look at line 5 please",
            LuaErrorMapper.innerLines("look at line 5 please", 0, 3, new int[]{3}, null));
    }
}
