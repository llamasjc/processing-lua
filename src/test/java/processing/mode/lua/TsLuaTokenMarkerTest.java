package processing.mode.lua;

import ch.usi.si.seart.treesitter.Language;
import ch.usi.si.seart.treesitter.Node;
import ch.usi.si.seart.treesitter.Parser;
import ch.usi.si.seart.treesitter.Tree;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import processing.app.syntax.SyntaxDocument;
import processing.app.syntax.Token;

import javax.swing.text.Element;
import javax.swing.text.Segment;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

/**
 * The highlighter end to end: real parser, real query, a real document.
 * Skipped when the native library hasn't been built (see {@link NativeLib}).
 */
class TsLuaTokenMarkerTest {

    private static boolean nativeAvailable;

    @BeforeAll
    static void loadNative() {
        nativeAvailable = NativeLib.load();
    }

    private void assumeNative() {
        org.junit.jupiter.api.Assumptions.assumeTrue(nativeAvailable,
            "native tree-sitter library not built, skipping highlighter test");
    }

    /** Highlights `src` and returns one token id per character. */
    private static byte[] highlight(String src) throws Exception {
        SyntaxDocument doc = new SyntaxDocument();
        doc.insertString(0, src, null);
        TsLuaTokenMarker marker = new TsLuaTokenMarker();
        CountDownLatch done = new CountDownLatch(1);
        marker.setRepaintHook(done::countDown);
        doc.setTokenMarker(marker);
        marker.invalidate(doc);
        assertTrue(done.await(10, TimeUnit.SECONDS), "highlighting never finished");

        byte[] ids = new byte[src.length()];
        Element root = doc.getDefaultRootElement();
        for (int line = 0; line < root.getElementCount(); line++) {
            Element el = root.getElement(line);
            int start = el.getStartOffset();
            int len   = Math.min(el.getEndOffset(), src.length() + 1) - start - 1;
            if (len < 0) len = 0;
            Segment seg = new Segment();
            doc.getText(start, len, seg);
            int pos = start;
            for (Token t = doc.getTokenMarker().markTokens(seg, line); t != null && t.id != Token.END; t = t.next) {
                for (int i = 0; i < t.length && pos < ids.length; i++) ids[pos++] = t.id;
            }
        }
        marker.dispose();
        return ids;
    }

    private static void assertToken(String src, byte[] ids, String word, byte expected) {
        int at = src.indexOf(word);
        assertTrue(at >= 0, "test bug: '" + word + "' not in source");
        for (int i = at; i < at + word.length(); i++) {
            assertEquals(expected, ids[i], "'" + word + "' at offset " + i);
        }
    }

    private static final String SKETCH =
        "-- a comment with function and \"quotes\"\n" +
        "local name = \"hello\"\n" +
        "function setup()\n" +
        "  size(640, 480)\n" +
        "  if name ~= nil then helper(3.5) end\n" +
        "end\n";

    @Test
    void colorsEachKindOfToken() throws Exception {
        assumeNative();
        byte[] ids = highlight(SKETCH);
        assertToken(SKETCH, ids, "-- a comment with function and \"quotes\"", Token.COMMENT1);
        assertToken(SKETCH, ids, "local",     Token.KEYWORD1);
        assertToken(SKETCH, ids, "\"hello\"", Token.LITERAL1);
        assertToken(SKETCH, ids, "size",      Token.KEYWORD2);   // Processing builtin
        assertToken(SKETCH, ids, "640",       Token.LITERAL2);
        assertToken(SKETCH, ids, "then",      Token.KEYWORD1);
        assertToken(SKETCH, ids, "helper",    Token.KEYWORD3);   // a call to the sketch's own function
        assertToken(SKETCH, ids, "3.5",       Token.LITERAL2);
    }

    /**
     * The last patterns in highlights.scm (builtin variables, constants,
     * calls) used to be cut off without any error: the file had non-ASCII
     * characters in its comments, see TsLuaTokenMarker.toAscii.
     */
    @Test
    void lastPatternsOfTheQueryAreAlive() throws Exception {
        assumeNative();
        String src = "x = width + mouseX * PI\nframeRate(30)\nmine(1)\nobj.field(2)\nobj:method(3)\n";
        byte[] ids = highlight(src);
        assertToken(src, ids, "width",     Token.KEYWORD2);
        assertToken(src, ids, "mouseX",    Token.KEYWORD2);
        assertToken(src, ids, "PI",        Token.KEYWORD2);
        assertToken(src, ids, "frameRate", Token.KEYWORD2);
        assertToken(src, ids, "mine",      Token.KEYWORD3);
        assertToken(src, ids, "field",     Token.KEYWORD3);
        assertToken(src, ids, "method",    Token.KEYWORD3);
        assertEquals(Token.NULL, ids[0], "a plain variable stays plain");
    }

    @Test
    void queryFileIsAscii() throws Exception {
        try (java.io.InputStream in = TsLuaTokenMarker.class.getResourceAsStream("/queries/highlights.scm")) {
            assertNotNull(in, "highlights.scm is on the classpath");
            String scm = new String(in.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
            for (int i = 0; i < scm.length(); i++) {
                assertTrue(scm.charAt(i) < 128, "non-ASCII character at offset " + i + " of highlights.scm");
            }
            assertEquals(scm, TsLuaTokenMarker.toAscii(scm));
            assertEquals("a?b", TsLuaTokenMarker.toAscii("a\u2014b"));
        }
    }

    /**
     * The Lua grammar's scanner used to start from uninitialised memory, so a
     * brand new parser would now and then read clean code as one long string
     * and report syntax errors. native/build.sh patches that; this keeps it fixed.
     */
    @Test
    void freshParsersParseCleanCodeCleanly() {
        assumeNative();
        String[] leftovers = { "local s = \"never closed", "--[[ never closed", "local t = [==[ open", "x = 'q" };
        for (int round = 0; round < 60; round++) {
            try (Parser p = Parser.getFor(Language.LUA)) {
                // what one parse leaves behind must not leak into the next
                if (round % 2 == 1) {
                    try (Tree junk = p.parse(leftovers[round % leftovers.length])) { assertNotNull(junk); }
                }
                try (Tree t = p.parse(SKETCH)) {
                    assertFalse(t.getRootNode().hasError(), "round " + round + ": clean code parsed with errors");
                }
            }
        }
    }

    @Test
    void oddInputsNeverThrow() throws Exception {
        assumeNative();
        String[] inputs = {
            "", "\n", "\n\n\n\n", "x", "\"", "--[[", "]]", "end", "function", "\t\t\t",
            "local café = '中文 😀'\nprint(café)\n",   // offsets are UTF-16 units
            "a\r\nb\r\nc", "\0", "x = 1 -- no newline at the end",
        };
        for (String in : inputs) {
            byte[] ids = highlight(in);
            assertEquals(in.length(), ids.length);
        }
    }

    @Test
    void nonAsciiTextKeepsColorsAligned() throws Exception {
        assumeNative();
        String src = "local s = '中文 😀' -- é\nfunction setup() end\n";
        byte[] ids = highlight(src);
        assertToken(src, ids, "function", Token.KEYWORD1);
        assertToken(src, ids, "end",      Token.KEYWORD1);
    }

    @Test
    void rapidEditsAndDisposeAreSafe() throws Exception {
        assumeNative();
        SyntaxDocument doc = new SyntaxDocument();
        TsLuaTokenMarker marker = new TsLuaTokenMarker();
        doc.setTokenMarker(marker);
        for (int i = 0; i < 300; i++) {
            doc.insertString(doc.getLength(), "local v" + i + " = " + i + "\n", null);
            marker.invalidate(doc);
            if (i % 50 == 0) Thread.sleep(200);     // let some rebuilds actually run
        }
        marker.dispose();
        marker.dispose();                            // twice is fine
        marker.invalidate(doc);                      // and so is using it afterwards
        Segment seg = new Segment();
        doc.getText(0, 5, seg);
        assertNotNull(doc.getTokenMarker().markTokens(seg, 0));

        // a marker that was disposed must not have taken the shared query with it
        assertToken(SKETCH, highlight(SKETCH), "local", Token.KEYWORD1);
    }

    @Test
    void largeFileIsHighlightedInReasonableTime() throws Exception {
        assumeNative();
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 20000; i++) sb.append("local v").append(i).append(" = fill(").append(i).append(") -- c\n");
        long t0 = System.nanoTime();
        byte[] ids = highlight(sb.toString());
        long ms = (System.nanoTime() - t0) / 1_000_000;
        assertEquals(sb.length(), ids.length);
        assertTrue(ms < 20_000, "20000 lines took " + ms + " ms");
    }
}
