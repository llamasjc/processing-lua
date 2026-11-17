package processing.mode.lua;

import processing.app.Base;
import processing.app.SketchCode;
import processing.app.syntax.SyntaxDocument;
import processing.app.syntax.JEditTextArea;
import processing.app.syntax.PdeTextArea;
import processing.app.syntax.PdeTextAreaDefaults;
import processing.app.ui.Editor;
import processing.app.ui.EditorState;
import processing.app.ui.EditorToolbar;

import javax.swing.*;
import java.awt.event.ActionEvent;
import java.awt.event.KeyEvent;
import java.io.File;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

public class LuaEditor extends Editor {

    private final LuaMode         luaMode;
    private volatile LuaRunner    runner;

    // One token marker per tab. Each tab has its own document, and a marker
    // holds the colors for exactly one text, so sharing one between tabs
    // would paint tab A with tab B's colors.
    private final Map<SyntaxDocument, TsLuaTokenMarker> markers = new IdentityHashMap<>();
    private boolean ready;   // false while Editor's constructor is still running

    public LuaEditor(Base base, String path, EditorState state, LuaMode mode)
            throws Exception {
        super(base, path, state, mode);
        this.luaMode = mode;
        ready = true;
        attachTokenMarker();
    }

    // ── Text area ─────────────────────────────────────────────────────────
    //
    // Editor's default is a bare JEditTextArea: no gutter (so no line numbers)
    // and a PdeInputHandler that expects a PdeTextArea, which is why Enter
    // misbehaved. Same setup as Java mode, with Lua-aware typing on top.
    // Called from Editor's constructor, before our own fields are set.

    @Override
    protected JEditTextArea createTextArea() {
        return new PdeTextArea(new PdeTextAreaDefaults(getMode()), new LuaInputHandler(this), this);
    }

    // ── Token markers ─────────────────────────────────────────────────────

    /**
     * Editor calls this whenever another tab is shown (and while a sketch is
     * loading). The tab's document may be brand new, so this is the place to
     * give it a marker.
     */
    @Override
    public void setCode(SketchCode code) {
        super.setCode(code);
        if (ready) {
            try {
                attachTokenMarker();
            } catch (Throwable t) {
                System.err.println("[LuaMode] couldn't set up highlighting for this tab: " + t);
            }
        }
    }

    /** Makes sure the document now in the text area has a Lua token marker. */
    private void attachTokenMarker() {
        SyntaxDocument doc = getTextArea().getDocument();
        if (doc == null) return;
        if (markers.containsKey(doc)) return;
        // a query that doesn't load would mean no colors at all: keep the default
        // keyword colors, and only when the native parser is there to begin with
        if (!LuaNative.isLoaded() || !TsLuaTokenMarker.available()) return;

        TsLuaTokenMarker marker = new TsLuaTokenMarker();
        marker.setLintConsumer(problems -> SwingUtilities.invokeLater(() -> {
            // only the tab on screen gets to use the status line
            if (getTextArea().getDocument() == doc) showLintProblems(problems);
        }));
        // highlights are rebuilt off the EDT; repaint once they're ready
        marker.setRepaintHook(() -> SwingUtilities.invokeLater(() -> {
            if (getTextArea().getDocument() == doc) getTextArea().getPainter().repaint();
        }));
        doc.setTokenMarker(marker);
        doc.addDocumentListener(new javax.swing.event.DocumentListener() {
            public void insertUpdate(javax.swing.event.DocumentEvent e)  { edited(); }
            public void removeUpdate(javax.swing.event.DocumentEvent e)  { edited(); }
            public void changedUpdate(javax.swing.event.DocumentEvent e) { edited(); }
            private void edited() {
                runErrorShowing = false;   // the code changed; the old run's error is history
                marker.invalidate(doc);
            }
        });
        markers.put(doc, marker);
        marker.invalidate(doc);
        forgetClosedTabs();
    }

    /** Drops the markers of tabs that no longer exist (deleted, or the sketch was reloaded). */
    private void forgetClosedTabs() {
        if (markers.size() <= sketch.getCodeCount()) return;
        Set<SyntaxDocument> open = Collections.newSetFromMap(new IdentityHashMap<>());
        for (SketchCode c : sketch.getCode()) {
            Object d = c.getDocument();
            if (d instanceof SyntaxDocument) open.add((SyntaxDocument) d);
        }
        markers.entrySet().removeIf(e -> {
            if (open.contains(e.getKey())) return false;
            e.getValue().dispose();
            return true;
        });
    }

    private void showLintProblems(List<LuaProblem> problems) {
        if (runner != null) return;
        // The error of the run that just failed stays until the code is
        // edited. It names the real problem; the linter can only say
        // "Syntax error".
        if (runErrorShowing) return;
        if (problems.isEmpty()) { statusEmpty(); return; }
        LuaProblem first = problems.stream()
            .filter(LuaProblem::isError).findFirst().orElse(problems.get(0));
        String msg = (first.isError() ? "" : "Warning: ") +
            "Line " + (first.getLineNumber() + 1) + ": " + first.getMessage();
        if (first.isError()) statusError(msg); else statusNotice(msg);
    }

    private boolean runErrorShowing;

    void invalidateHighlights() {
        SyntaxDocument doc = getTextArea().getDocument();
        if (doc != null) {
            TsLuaTokenMarker m = markers.get(doc);
            if (m != null) m.invalidate(doc);
        }
    }

    // ── Abstract Editor methods ───────────────────────────────────────────

    @Override public String getCommentPrefix() { return "--"; }

    @Override
    public void internalCloseRunner() {
        stopCurrentRunner();
    }

    /** The Run button goes back to normal. Stopping the sketch is internalCloseRunner's job. */
    @Override
    public void deactivateRun() {
        try { getToolbar().deactivateRun(); } catch (Throwable ignored) {}
    }

    // Real menus: Editor adds the standard items (Import Library etc.) through
    // the protected buildXMenu(JMenuItem[]) overloads. An empty JMenu here is
    // what caused the removeImportMenu NPE.
    @Override
    public JMenu buildFileMenu() {
        // like Processing's: Ctrl+Shift+E
        JMenuItem app = new JMenuItem("Export Application...");
        app.setAccelerator(KeyStroke.getKeyStroke(KeyEvent.VK_E,
            java.awt.Toolkit.getDefaultToolkit().getMenuShortcutKeyMaskEx()
            | java.awt.event.InputEvent.SHIFT_DOWN_MASK));
        app.addActionListener(this::handleExportApplication);
        JMenuItem pdez = new JMenuItem("Export as PDEZ...");
        pdez.addActionListener(this::handleExportPdez);
        JMenuItem roblox = new JMenuItem("Export for Roblox...");
        roblox.addActionListener(this::handleRobloxExport);
        JMenuItem love2d = new JMenuItem("Export for LOVE2D...");
        love2d.addActionListener(this::handleLove2dExport);
        try {
            return buildFileMenu(new JMenuItem[] { app, pdez, roblox, love2d });
        } catch (Throwable t) {
            System.err.println("[LuaMode] File menu fallback: " + t);
            JMenu file = new JMenu("File");
            file.add(app);
            file.add(pdez);
            file.add(roblox);
            file.add(love2d);
            return file;
        }
    }

    @Override
    public JMenu buildSketchMenu() {
        JMenuItem run = new JMenuItem("Run");
        run.setAccelerator(KeyStroke.getKeyStroke(KeyEvent.VK_R,
            java.awt.Toolkit.getDefaultToolkit().getMenuShortcutKeyMaskEx()));
        run.addActionListener(e -> getToolbar().handleRun(0));
        // fills the screen this window is on, sketch in the middle; Esc closes it
        JMenuItem present = new JMenuItem("Present");
        present.setAccelerator(KeyStroke.getKeyStroke(KeyEvent.VK_R,
            java.awt.Toolkit.getDefaultToolkit().getMenuShortcutKeyMaskEx()
            | java.awt.event.InputEvent.SHIFT_DOWN_MASK));
        present.addActionListener(e -> getToolbar().handleRun(1));
        JMenuItem stop = new JMenuItem("Stop");
        stop.addActionListener(e -> handleStop());
        try {
            // sets Editor's private sketchMenu field, which windowActivated needs
            return buildSketchMenu(new JMenuItem[] { run, present, stop });
        } catch (Throwable t) {
            System.err.println("[LuaMode] Sketch menu fallback: " + t);
            JMenu sketchMenu = new JMenu("Sketch");
            sketchMenu.add(run);
            sketchMenu.add(present);
            sketchMenu.add(stop);
            return sketchMenu;
        }
    }

    @Override
    public JMenu buildHelpMenu() {
        JMenu help = new JMenu("Help");
        JMenuItem site = new JMenuItem("Lua Mode on GitHub");
        site.addActionListener(e -> openUrl("https://github.com/llamasjc/LuaMode"));
        help.add(site);
        JMenuItem ref = new JMenuItem("Lua 5.4 Reference Manual");
        ref.addActionListener(e -> openUrl("https://www.lua.org/manual/5.4/"));
        help.add(ref);
        return help;
    }
    @Override public void handleImportLibrary(String lib) {}
    @Override public processing.app.Formatter createFormatter() { return null; }

    // ── Run / Stop ────────────────────────────────────────────────────────

    /** Called by the toolbar's handleRun(int mode). mode 0=Run, 1=Present. */
    void startRunner(boolean present) {
        try {
            // Copy each tab's live editor text into the sketch (and clear the
            // console if that preference is on). Without this, Run used what was
            // last saved to disk, so an unsaved sketch ran as an empty file.
            prepareRun();
            RunLog.log("Run pressed (present=" + present + ") sketch=" + sketch.getName()
                + " folder=" + sketch.getFolder());
            stopCurrentRunner();
            statusEmpty();
            runErrorShowing = false;
            LuaRunner[] ref = {null};
            LuaRunner thisRunner = new LuaRunner(sketch, luaMode.getFolder(), this,
                problems -> SwingUtilities.invokeLater(() -> showRunProblems(problems)),
                () -> onRunnerFinished(ref[0]));
            ref[0] = thisRunner;
            java.awt.Rectangle screen = screenBounds();
            thisRunner.setDisplay(screen);
            if (present) thisRunner.setPresent(screen);
            runner  = thisRunner;
            try { getToolbar().activateRun(); } catch (Throwable ignored) {}
            thisRunner.launch();
        } catch (Throwable t) {
            // whatever went wrong, the Run button must keep working
            RunLog.log("startRunner failed", t);
            runner = null;
            deactivateRun();
            statusError("Could not start the sketch: " + t);
        }
    }

    /** The screen this editor window is on (present mode covers that one). */
    private java.awt.Rectangle screenBounds() {
        try {
            java.awt.GraphicsConfiguration gc = getGraphicsConfiguration();
            if (gc != null) return gc.getBounds();
        } catch (Throwable ignored) {}
        try {
            java.awt.Dimension d = java.awt.Toolkit.getDefaultToolkit().getScreenSize();
            return new java.awt.Rectangle(0, 0, d.width, d.height);
        } catch (Throwable t) {
            return null;   // no screen info: runs in a normal window
        }
    }

    private void onRunnerFinished(LuaRunner finished) {
        // runs on the runner thread
        SwingUtilities.invokeLater(() -> {
            if (runner == finished) {
                runner = null;
                deactivateRun();
            }
        });
    }

    /** A run ended with an error: go to the tab and line, and say what happened. */
    private void showRunProblems(List<LuaProblem> problems) {
        if (problems.isEmpty()) return;
        LuaProblem p = problems.stream().filter(LuaProblem::hasLocation).findFirst().orElse(problems.get(0));
        try {
            if (p.hasLocation() && p.getTabIndex() < sketch.getCodeCount()) {
                if (sketch.getCurrentCodeIndex() != p.getTabIndex()) sketch.setCurrentCode(p.getTabIndex());
                JEditTextArea ta = getTextArea();
                int line = Math.min(p.getLineNumber(), ta.getLineCount() - 1);
                if (line >= 0) {
                    int start = ta.getLineStartOffset(line);
                    int stop  = Math.max(start, ta.getLineStopOffset(line) - 1);
                    ta.select(start, stop);
                }
            }
        } catch (Throwable t) {
            RunLog.log("couldn't highlight the error line", t);
        }
        runErrorShowing = true;
        statusError(LuaRunner.formatProblem(p));
    }

    public void handleStop() {
        boolean wasRunning = runner != null;
        stopCurrentRunner();
        deactivateRun();
        if (wasRunning) statusNotice("Stopped."); else statusEmpty();
    }

    private void stopCurrentRunner() {
        LuaRunner r = runner;
        runner = null;
        if (r != null) r.halt();
    }

    // ── Toolbar ───────────────────────────────────────────────────────────

    @Override
    public EditorToolbar createToolbar() {
        return new EditorToolbar(this) {
            @Override public void handleRun(int mode) { LuaEditor.this.startRunner(mode == 1); }
            @Override public void handleStop() { LuaEditor.this.handleStop(); }
            // the renderer menu, left of the mode selector
            @Override public void addModeButtons(javax.swing.Box box, javax.swing.JLabel label) {
                box.add(Renderer.menu());
                addGap(box);
            }
        };
    }

    // ── Export menu ───────────────────────────────────────────────────────


    private void handleExportApplication(ActionEvent e) {
        if (sketch.isUntitled() || sketch.isReadOnly()) {
            statusError("Save the sketch first: the export goes inside its folder.");
            return;
        }
        if (sketch.isModified()) {
            try { sketch.save(); } catch (Exception ex) { statusError("Couldn't save: " + ex.getMessage()); return; }
        }
        statusNotice("Exporting...");
        try {
            File dest = new LuaBuild(sketch, luaMode.getFolder()).exportApplication();
            statusNotice("Exported to " + sketch.getName() + "/" + dest.getName() + "/");
            AppExport.show(dest);
        } catch (Exception ex) {
            statusError("Export failed: " + ex.getMessage());
            ex.printStackTrace();
        }
    }

    private void handleExportPdez(ActionEvent e) {
        if (sketch.isUntitled() || sketch.isReadOnly()) {
            statusError("Save the sketch first.");
            return;
        }
        if (sketch.isModified()) {
            try { sketch.save(); } catch (Exception ex) { statusError("Couldn't save: " + ex.getMessage()); return; }
        }
        try {
            File pdez = AppExport.pdez(sketch.getFolder());
            statusNotice("Exported " + pdez.getName());
            AppExport.show(pdez.getParentFile());
        } catch (Exception ex) {
            statusError("Export failed: " + ex.getMessage());
            ex.printStackTrace();
        }
    }

    private void handleRobloxExport(ActionEvent e) {
        JFileChooser fc = new JFileChooser(sketch.getFolder());
        fc.setSelectedFile(new File(sketch.getFolder(), sketch.getName() + "_roblox.lua"));
        fc.setDialogTitle("Export for Roblox (save as LocalScript)");
        if (fc.showSaveDialog(null) != JFileChooser.APPROVE_OPTION) return;
        File dest = fc.getSelectedFile();
        try {
            LuaExporter.exportRoblox(sketch, dest);
            statusNotice("Exported to " + dest.getName());
        } catch (Exception ex) {
            statusError("Export failed: " + ex.getMessage());
            ex.printStackTrace();
        }
    }

    private void handleLove2dExport(ActionEvent e) {
        JFileChooser fc = new JFileChooser(sketch.getFolder().getParentFile());
        fc.setFileSelectionMode(JFileChooser.DIRECTORIES_ONLY);
        fc.setSelectedFile(new File(sketch.getFolder().getParentFile(),
                                    sketch.getName() + "-love2d"));
        fc.setDialogTitle("Export for LOVE2D (choose output folder)");
        if (fc.showSaveDialog(null) != JFileChooser.APPROVE_OPTION) return;
        File dest = fc.getSelectedFile();
        try {
            LuaExporter.exportLove2d(sketch, dest, luaMode.getFolder());
            statusNotice("Exported to " + dest.getName() + "/");
        } catch (Exception ex) {
            statusError("Export failed: " + ex.getMessage());
            ex.printStackTrace();
        }
    }

    // ── Cleanup ───────────────────────────────────────────────────────────

    @Override
    public void dispose() {
        stopCurrentRunner();
        for (TsLuaTokenMarker m : markers.values()) m.dispose();
        markers.clear();
        super.dispose();
    }

    private static void openUrl(String url) {
        new Thread(() -> {
            try {
                if (System.getProperty("os.name", "").toLowerCase().contains("linux")) {
                    new ProcessBuilder("xdg-open", url).start();
                } else {
                    java.awt.Desktop.getDesktop().browse(new java.net.URI(url));
                }
            } catch (Exception ex) {
                System.err.println("[LuaMode] couldn't open " + url + ": " + ex);
            }
        }, "luamode-open-url").start();
    }
}
