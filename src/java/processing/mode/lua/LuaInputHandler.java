package processing.mode.lua;

import processing.app.ui.Editor;
import processing.app.syntax.JEditTextArea;
import processing.app.syntax.PdeInputHandler;

import java.awt.event.KeyEvent;

/**
 * Keyboard shortcuts specific to Lua Mode.
 *
 * Currently handles:
 *   • Auto-pairing of parentheses, brackets, braces, and quotes.
 *   • Over-typing: when the cursor is immediately before an auto-inserted
 *     closing character, typing that character skips over it rather than
 *     inserting a duplicate.
 *   • Smart indent after "then", "do", "function …", "repeat".
 *   • Auto-close of blocks on "end" detection is left to the editor's
 *     default indent logic.
 */
public class LuaInputHandler extends PdeInputHandler {

    private final Editor editor;

    public LuaInputHandler(Editor editor) {
        super(editor);
        this.editor = editor;
    }

    // ── PdeInputHandler hooks ─────────────────────────────────────────────

    @Override
    public boolean handleTyped(KeyEvent e) {
        try {
            if (handleKey(e)) return true;
        } catch (Throwable t) {
            // a typing helper must never eat the keystroke or break the editor
            report(t);
        }
        return super.handleTyped(e);
    }

    /**
     * Enter in Lua code:
     *   after a block opener (then, do, function(...), repeat, else, {) the
     *   next line is indented one level;
     *   on a line that closes a block (end, else, elseif, until, }) the line
     *   itself is first pulled back to where its block started.
     * Everything else is left to the editor's own Enter handling.
     */
    @Override
    public boolean handlePressed(KeyEvent e) {
        try {
            if (e.getKeyCode() == KeyEvent.VK_ENTER && e.getModifiersEx() == 0 && luaEnter()) {
                e.consume();
                return true;
            }
        } catch (Throwable t) {
            report(t);
        }
        return super.handlePressed(e);
    }

    private static boolean reported;
    private static void report(Throwable t) {
        if (reported) return;
        reported = true;
        System.err.println("[LuaMode] typing helper failed, falling back to plain editing: " + t);
    }

    /** Returns true when it handled the Enter key. */
    private boolean luaEnter() {
        JEditTextArea ta = editor.getTextArea();
        if (!ta.isEditable() || ta.getSelectionStart() != ta.getSelectionStop()) return false;

        int caret     = ta.getCaretPosition();
        int line      = ta.getCaretLine();
        int lineStart = ta.getLineStartOffset(line);
        String lineText = ta.getLineText(line);
        if (lineText == null) return false;
        int col = Math.max(0, Math.min(caret - lineStart, lineText.length()));
        String before = lineText.substring(0, col);
        String after  = lineText.substring(col);

        boolean opens  = opensBlock(before);
        boolean closes = after.isBlank() && closesBlock(lineText);
        if (!opens && !closes) return false;

        String indent = leadingWhitespace(lineText);
        editor.startCompoundEdit();
        try {
            if (closes) {
                String target = dedentTarget(previousCodeLine(ta, line), indentUnit());
                // only ever pull a line back, and only when it is clearly too deep
                if (target != null && target.length() < indent.length()) {
                    ta.select(lineStart, lineStart + indent.length());
                    ta.setSelectedText(target);
                    indent = target;
                    ta.setCaretPosition(lineStart + indent.length() + (col - leadingWhitespace(before).length()));
                }
            }
            ta.setSelectedText("\n" + indent + (opens ? indentUnit() : ""));
        } finally {
            editor.stopCompoundEdit();
        }
        return true;
    }

    /** The nearest line above `line` that has code on it, or null. */
    private static String previousCodeLine(JEditTextArea ta, int line) {
        for (int i = line - 1; i >= 0 && i >= line - 200; i--) {
            String t = ta.getLineText(i);
            if (t != null && !t.replaceAll("--.*$", "").isBlank()) return t;
        }
        return null;
    }

    /** True when the line starts with a word that ends (or continues) a block. */
    static boolean closesBlock(String line) {
        String code = line.replaceAll("--.*$", "").strip();
        return code.matches("(end|else|until|elseif)\\b.*") || code.startsWith("}");
    }

    /**
     * Indentation a closing line should have, judged from the code line above
     * it: level with that line if it opened the block (an empty block),
     * otherwise one unit back from it. Null when there is no line above.
     */
    static String dedentTarget(String previousCodeLine, String unit) {
        if (previousCodeLine == null) return null;
        String prev = leadingWhitespace(previousCodeLine);
        if (opensBlock(previousCodeLine)) return prev;
        if (prev.endsWith(unit)) return prev.substring(0, prev.length() - unit.length());
        if (prev.endsWith("\t")) return prev.substring(0, prev.length() - 1);
        return prev.length() >= unit.length() ? prev.substring(0, prev.length() - unit.length()) : "";
    }

    private static String indentUnit() {
        int n = 2;
        try { n = processing.app.Preferences.getInteger("editor.tabs.size"); } catch (Exception ignored) {}
        return " ".repeat(Math.max(1, n));
    }

    /** True when the code before the caret ends with something that opens a Lua block. */
    static boolean opensBlock(String lineBeforeCaret) {
        String code = lineBeforeCaret.replaceAll("--.*$", "").stripTrailing();
        if (code.isEmpty()) return false;
        return code.matches(".*\\b(then|do|else|repeat)")
            || code.matches(".*\\bfunction\\b[^()]*\\([^()]*\\)")
            || code.endsWith("{");
    }

    static String leadingWhitespace(String s) {
        int i = 0;
        while (i < s.length() && (s.charAt(i) == ' ' || s.charAt(i) == '\t')) i++;
        return s.substring(0, i);
    }

    /**
     * Called from LuaEditor's keyTyped handler.
     * Returns {@code true} if the event was consumed.
     */
    public boolean handleKey(KeyEvent e) {
        char c = e.getKeyChar();
        switch (c) {
            case ')' -> { return handleClose(')', e); }
            case ']' -> { return handleClose(']', e); }
            case '}' -> { return handleClose('}', e); }
            case '(' -> { insertPair("(", ")"); e.consume(); return true; }
            case '[' -> { insertPair("[", "]"); e.consume(); return true; }
            case '{' -> { insertPair("{", "}"); e.consume(); return true; }
            case '"' -> { handleQuote('"'); e.consume(); return true; }
            case '\'' -> { insertSingleQuote(); e.consume(); return true; }
            default  -> { return false; }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    /**
     * Handle a closing bracket/paren/brace.
     * If the character immediately after the caret is already that closing
     * character (and there is no selection), skip over it (over-type).
     * Otherwise insert it literally so the user can still type closing chars
     * in contexts where auto-pair didn't fire.
     */
    private boolean handleClose(char close, KeyEvent e) {
        JEditTextArea ta = editor.getTextArea();
        if (ta.getSelectionStart() == ta.getSelectionStop()) {
            int pos  = ta.getCaretPosition();
            String text = ta.getText();
            if (shouldOverType(text, pos, close)) {
                ta.setCaretPosition(pos + 1);
                e.consume();
                return true;
            }
        }
        return false;   // let the editor insert the character normally
    }

    private void insertPair(String open, String close) {
        JEditTextArea ta = editor.getTextArea();
        String sel = ta.getSelectedText();
        if (sel != null && !sel.isEmpty()) {
            ta.setSelectedText(open + sel + close);
        } else {
            ta.setSelectedText(open + close);
            ta.setCaretPosition(ta.getCaretPosition() - 1);
        }
    }

    /**
     * Handle a double-quote keystroke.
     * Over-types if the next char is already {@code "}, otherwise inserts pair.
     */
    private void handleQuote(char q) {
        JEditTextArea ta = editor.getTextArea();
        if (ta.getSelectionStart() == ta.getSelectionStop()) {
            int pos = ta.getCaretPosition();
            String text = ta.getText();
            if (shouldOverType(text, pos, q)) {
                ta.setCaretPosition(pos + 1);
                return;
            }
        }
        insertPair(String.valueOf(q), String.valueOf(q));
    }

    private void insertSingleQuote() {
        JEditTextArea ta = editor.getTextArea();
        int pos = ta.getCaretPosition();
        String text = ta.getText();
        // Over-type if next char is already a closing single-quote
        if (ta.getSelectionStart() == ta.getSelectionStop()
                && shouldOverType(text, pos, '\'')) {
            ta.setCaretPosition(pos + 1);
            return;
        }
        // Don't double-quote inside a word (e.g., "it's")
        if (shouldSuppressSingleQuote(text, pos)) {
            ta.setSelectedText("'");
        } else {
            insertPair("'", "'");
        }
    }

    // ── Pure decision helpers (package-private for testing) ───────────────

    /**
     * Returns {@code true} when the character at {@code pos} in {@code text}
     * equals {@code ch} — the condition for over-typing (skipping) rather than
     * inserting a new character.
     */
    static boolean shouldOverType(String text, int pos, char ch) {
        return pos < text.length() && text.charAt(pos) == ch;
    }

    /**
     * Returns {@code true} when a single-quote keystroke should be suppressed
     * (insert one literal {@code '} rather than a pair) because the cursor is
     * immediately after a letter or digit — the contraction case ("it's").
     */
    static boolean shouldSuppressSingleQuote(String text, int pos) {
        return pos > 0 && Character.isLetterOrDigit(text.charAt(pos - 1));
    }
}
