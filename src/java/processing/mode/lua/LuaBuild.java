package processing.mode.lua;

import processing.app.Sketch;
import processing.app.SketchCode;

import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

/**
 * Orchestrates a single build+run of a Lua sketch inside the Processing IDE.
 *
 * Responsibilities (only):
 *   1. Assemble the combined source (header + sketch tabs).
 *   2. Write it to a temp file.
 *   3. Locate luamode-runner.
 *   4. Exec luamode-runner and collect output.
 *   5. Delegate error mapping to {@link LuaErrorMapper}.
 *
 * Why luamode-runner instead of raw LuaJIT?
 *   libprocessing's C FFI ({@code processing_surface_create}) requires an
 *   existing native window handle — it cannot create windows on its own.
 *   Window creation goes through glfw::Runner internally in Rust.  The runner
 *   binary uses that same App builder path, so it is a first-class Processing
 *   sketch that happens to be driven by Lua.  No LuaJIT FFI gymnastics needed.
 *
 * Error output from luamode-runner follows the standard Lua format:
 *   {@code <filename>:<line>: <message>}
 * {@link LuaErrorMapper} maps those line numbers back to the correct sketch tab.
 */
public final class LuaBuild {

    // ── Fields ────────────────────────────────────────────────────────────

    private final Sketch sketch;
    private final File   modeFolder;

    // Set by buildSource(), read by run() and LuaErrorMapper
    private int      headerLines;
    private int[]    tabStartLines;
    private String[] tabNames;

    private volatile Process proc;

    // Present mode: the screen to cover, or null for a normal window.
    private volatile java.awt.Rectangle presentOn;

    /** Run the sketch in present mode on this screen (null: a normal window). */
    public void setPresent(java.awt.Rectangle screen) { presentOn = screen; }

    // The screen the editor is on: fullScreen(), displayWidth and displayHeight need it.
    private volatile java.awt.Rectangle display;

    public void setDisplay(java.awt.Rectangle screen) { display = screen; }

    // ── Construction ──────────────────────────────────────────────────────

    public LuaBuild(Sketch sketch, File modeFolder) {
        this.sketch     = sketch;
        this.modeFolder = modeFolder;
    }

    // ── Public API ────────────────────────────────────────────────────────

    /**
     * Build and run the sketch via luamode-runner. Blocks until the runner exits.
     *
     * @return list of problems; empty on clean exit
     */
    public List<LuaProblem> run() throws IOException, InterruptedException {
        RunLog.log("build: assembling " + sketch.getCodeCount() + " tab(s)");
        String source = buildSource();

        String runner = resolveRunner();
        RunLog.log("build: runner = " + runner);
        if (runner == null && Renderer.libprocessing()) {
            return List.of(new LuaProblem(-1, -1,
                "The libprocessing runner isn't built yet. Run LuaMode/runner/build-libprocessing.sh "
                + "(it uses ~/sketchbook/libprocessing when it's there), or pick Software in the toolbar.",
                LuaProblem.Severity.ERROR));
        }
        if (runner == null) {
            return List.of(new LuaProblem(-1, -1,
                "The sketch runner (luamode-runner) is missing for " + LuaMode.detectPlatform()
                + ". Reinstall Lua Mode, or build it with `cargo build --release` in LuaMode/runner.",
                LuaProblem.Severity.ERROR));
        }

        Path tmp = writeTempFile(source);
        RunLog.log("build: wrote " + tmp);
        try {
            return runProcess(runner, tmp);
        } finally {
            try { Files.deleteIfExists(tmp); } catch (IOException ignored) {}
        }
    }

    /** Stops the sketch if it is running. Safe to call from any thread, any number of times. */
    public void kill() {
        Process p = proc;
        if (p != null) stop(p);
    }

    // Sketch processes that are still alive. Emptied by a shutdown hook, so
    // quitting the IDE never leaves sketch windows behind.
    private static final Set<Process> LIVE = ConcurrentHashMap.newKeySet();
    static {
        try {
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                for (Process p : LIVE) p.destroyForcibly();
            }, "luamode-stop-sketches"));
        } catch (Throwable ignored) {}   // already shutting down
    }

    private static void stop(Process p) {
        p.destroy();
        try {
            if (!p.waitFor(1, TimeUnit.SECONDS)) p.destroyForcibly();
        } catch (InterruptedException e) {
            p.destroyForcibly();
            Thread.currentThread().interrupt();
        }
    }

    private List<LuaProblem> runProcess(String runner, Path tmp) throws IOException, InterruptedException {
        String chunk = tmp.getFileName().toString();

        ProcessBuilder pb = new ProcessBuilder(runner, tmp.toAbsolutePath().toString());
        // relative paths (loadImage, saveFrame) resolve in the sketch folder;
        // an untitled sketch whose temp folder is gone still has to run
        File dir = sketch.getFolder();
        pb.directory(dir != null && dir.isDirectory() ? dir : tmp.getParent().toFile());

        // The sketch's stdin stays open and unused on purpose. The runner
        // watches it: if the IDE dies without a chance to clean up (a crash,
        // kill -9), the pipe closes and the sketch window closes with it
        // instead of staying behind as an orphan.
        pb.environment().put("LUAMODE_WATCH_STDIN", "1");
        if (Renderer.libprocessing()) pb.environment().put("PROCESSING_RENDERER", "libprocessing");
        else pb.environment().remove("PROCESSING_RENDERER");
        java.awt.Rectangle disp = display;
        if (disp != null && disp.width > 0 && disp.height > 0) {
            pb.environment().put("PROCESSING_DISPLAY",
                disp.width + "," + disp.height + "," + disp.x + "," + disp.y);
        } else {
            pb.environment().remove("PROCESSING_DISPLAY");
        }
        java.awt.Rectangle scr = presentOn;
        if (scr != null && scr.width > 0 && scr.height > 0) {
            pb.environment().put("LUAMODE_PRESENT",
                scr.width + "," + scr.height + "," + scr.x + "," + scr.y);
        } else {
            pb.environment().remove("LUAMODE_PRESENT");
        }

        RunLog.log("build: starting " + runner + " in " + pb.directory());
        Process p = pb.start();
        proc = p;
        LIVE.add(p);

        // Processing's console shows whatever goes to System.out / System.err,
        // so forward the runner's output there line by line as it arrives:
        // print() lands in the console like it does in Java mode. stderr is
        // also kept for mapping errors back to tab/line. Separate threads so
        // a full pipe on one stream can't block the other.
        final int[] starts = tabStartLines;
        final int   header = headerLines;
        final String[] names = tabNames;
        Thread drainOut = pump(p.getInputStream(), System.out, null, "lua-stdout", null);
        StringBuilder stderrBuf = new StringBuilder();
        Thread drainErr = pump(p.getErrorStream(), System.err, stderrBuf, "lua-stderr",
            line -> LuaErrorMapper.rewrite(line, chunk, header, starts, names));

        int exit;
        try {
            exit = p.waitFor();
        } catch (InterruptedException ie) {
            // Stop pressed: close the sketch window
            stop(p);
            Thread.currentThread().interrupt();
            throw ie;
        } finally {
            if (!p.isAlive()) LIVE.remove(p);
        }

        drainOut.join(1000);
        drainErr.join(1000);
        LIVE.remove(p);
        proc = null;

        RunLog.log("build: runner exited with " + exit);
        if (exit == 0) return List.of();
        // we stopped it ourselves (Stop, a new Run, closing the editor)
        if (Thread.currentThread().isInterrupted()) return List.of();

        String err;
        synchronized (stderrBuf) { err = stderrBuf.toString(); }
        List<LuaProblem> problems = LuaErrorMapper.map(err, chunk, headerLines, tabStartLines);
        if (problems.isEmpty()) {
            problems = List.of(new LuaProblem(-1, -1,
                "The sketch stopped unexpectedly (exit status " + exit + ").",
                LuaProblem.Severity.ERROR));
        }
        return problems;
    }

    // At most this much stderr is kept for error mapping. A sketch that
    // floods stderr still shows everything in the console, it just doesn't
    // get to grow this buffer without limit.
    private static final int MAX_KEPT = 256 * 1024;

    private static Thread pump(java.io.InputStream in, java.io.PrintStream out,
                               StringBuilder keep, String name,
                               java.util.function.UnaryOperator<String> shown) {
        Thread t = new Thread(() -> {
            try (java.io.BufferedReader r = new java.io.BufferedReader(
                    new java.io.InputStreamReader(in, StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) {
                    if (keep != null) synchronized (keep) {
                        if (keep.length() > MAX_KEPT) keep.delete(0, keep.length() - MAX_KEPT / 2);
                        keep.append(line).append('\n');
                    }
                    String display = line;
                    if (shown != null) {
                        try { display = shown.apply(line); } catch (RuntimeException e) { display = line; }
                    }
                    out.println(display);
                }
            } catch (IOException ignored) {
            } catch (Throwable t2) {
                RunLog.log("output pump " + name + " failed", t2);
            }
        }, name);
        t.setDaemon(true);
        t.start();
        return t;
    }

    // ── Source assembly ───────────────────────────────────────────────────

    /**
     * Assembles the combined Lua source: generated header + all sketch tabs.
     *
     * The generated header calls {@code setup()} and {@code draw()} once
     * registered — the runner binary registers all Processing globals before
     * loading this file, so the header only needs to be a thin shim that
     * calls P.inject(_ENV) equivalently (the runner already did that).
     *
     * For luamode-runner the header is minimal: the runner pre-registers all
     * Processing globals, so the "header" just needs to document itself and
     * not accidentally shadow anything.
     */
    private String buildSource() {
        String header = ideHeader();
        headerLines   = countLines(header);

        SketchCode[] codes = sketch.getCode();
        tabStartLines      = new int[codes.length];
        tabNames           = new String[codes.length];

        StringBuilder sb = new StringBuilder(header);

        // Track the running line count so we don't re-scan the whole buffer
        // for each tab (avoids O(n²) for many-tab sketches).
        int runningLines = headerLines;

        for (int i = 0; i < codes.length; i++) {
            tabStartLines[i] = runningLines;
            tabNames[i]      = codes[i].getFileName();
            String prog = codes[i].getProgram();
            if (prog == null) prog = "";
            // one tab must not be able to swallow the next: "\r\n" and lone
            // "\r" line ends would throw the line numbers off
            prog = prog.replace("\r\n", "\n").replace('\r', '\n');
            sb.append(prog);
            if (!prog.endsWith("\n")) sb.append('\n');
            runningLines += countLines(prog) + (prog.endsWith("\n") ? 0 : 1);
        }

        return sb.toString();
    }

    /**
     * Minimal generated header for luamode-runner.
     *
     * The runner binary pre-registers all Processing globals before loading
     * the sketch, so no require() calls are needed.  This header just marks
     * the generated boundary for LuaErrorMapper and provides the size()
     * override that stores width/height in Lua globals.
     */
    private static String ideHeader() {
        return
            "-- [LuaMode generated, do not edit]\n" +
            "-- All Processing globals are pre-registered by luamode-runner.\n" +
            "-- [end generated header]\n";
    }

    // ── Runner location ───────────────────────────────────────────────────

    /**
     * Looks for luamode-runner in priority order:
     *   1. {@code <modeFolder>/runner/target/release/luamode-runner}, a local
     *      {@code cargo build --release}, so a fresh dev build is always used.
     *   2. The binary unpacked from the JAR by {@link LuaMode} at startup
     *      (the normal installed path; works for end users out of the box).
     *   3. {@code <modeFolder>/mode/runner/<platform>/luamode-runner}
     *      (the dist ZIP layout).
     *
     * Returns the absolute path string, or null if not found anywhere.
     */
    private String resolveRunner() {
        String exe = System.getProperty("os.name", "").toLowerCase().contains("win")
                     ? "luamode-runner.exe" : "luamode-runner";

        // libprocessing picked in the toolbar: only its own build will do
        if (Renderer.libprocessing()) {
            File lp = new File(modeFolder, "runner/target-libprocessing/release/" + exe);
            if (!lp.exists()) lp = new File(modeFolder, "mode/runner/" + LuaMode.detectPlatform() + "-libprocessing/" + exe);
            return lp.exists() && lp.canExecute() ? lp.getAbsolutePath() : null;
        }

        // 1. Dev build: a fresh `cargo build --release` in runner/ always wins,
        //    so working on the runner never runs a stale bundled copy
        File devBuild = new File(modeFolder, "runner/target/release/" + exe);
        if (devBuild.exists() && devBuild.canExecute()) {
            return devBuild.getAbsolutePath();
        }

        // 2. Unpacked from the jar by LuaMode on startup
        File extracted = LuaMode.getRunnerExecutable();
        if (extracted != null && extracted.exists() && extracted.canExecute()) {
            return extracted.getAbsolutePath();
        }

        // 3. Installed in mode/runner/<platform>/ (dist ZIP layout)
        String platform = LuaMode.detectPlatform();
        File installed = new File(modeFolder, "mode/runner/" + platform + "/" + exe);
        if (installed.exists() && installed.canExecute()) {
            return installed.getAbsolutePath();
        }

        return null;
    }

    // ── Utilities ─────────────────────────────────────────────────────────

    private static Path writeTempFile(String source) throws IOException {
        Path tmp = Files.createTempFile("processing_lua_", ".lua");
        tmp.toFile().deleteOnExit();
        Files.writeString(tmp, source, StandardCharsets.UTF_8);
        return tmp;
    }

    /** Package-private hook for tests. */
    static int testCountLines(String s) { return countLines(s); }

    private static int countLines(String s) {
        if (s == null || s.isEmpty()) return 0;
        int n = 0;
        for (int i = 0; i < s.length(); i++) {
            if (s.charAt(i) == '\n') n++;
        }
        return n;
    }
}
