package processing.mode.lua;

import processing.app.RunnerListener;
import processing.app.Sketch;

import java.io.File;
import java.util.List;
import java.util.function.Consumer;

/**
 * Drives {@link LuaBuild} on a background thread and reports results
 * back to the Processing editor via {@link RunnerListener}.
 *
 * This class owns the thread lifecycle only — no build logic lives here.
 *
 * <p>The {@code onComplete} callback is invoked on the runner thread when
 * the run ends — whether normally, on error, or via {@link #halt()}.
 * {@link LuaEditor} uses this to clear its {@code runner} reference so that
 * lint feedback resumes after a sketch exits naturally.</p>
 */
public final class LuaRunner {

    private final Sketch         sketch;
    private final File           modeFolder;
    private final RunnerListener listener;
    private final Consumer<List<LuaProblem>> onProblems;
    private final Runnable       onComplete;
    private volatile Thread      thread;
    private volatile LuaBuild    build;
    private volatile boolean     halted;
    private volatile java.awt.Rectangle presentOn;

    /** Present mode on this screen. Call before {@link #launch()}. */
    public void setPresent(java.awt.Rectangle screen) { presentOn = screen; }

    /**
     * @param onProblems called (on the runner thread) with the errors of a run
     *                   that failed; never called for a run that was stopped
     * @param onComplete called once when the runner thread finishes (any outcome).
     *                   May be {@code null} if no callback is needed.
     */
    public LuaRunner(Sketch sketch, File modeFolder, RunnerListener listener,
                     Consumer<List<LuaProblem>> onProblems, Runnable onComplete) {
        this.sketch     = sketch;
        this.modeFolder = modeFolder;
        this.listener   = listener;
        this.onProblems = onProblems;
        this.onComplete = onComplete != null ? onComplete : () -> {};
    }

    // ── Control ───────────────────────────────────────────────────────────

    public void launch() {
        Thread t = new Thread(this::doRun, "lua-runner");
        t.setDaemon(true);
        thread = t;
        t.start();
    }

    /** Stops the sketch. Safe to call more than once and from any thread. */
    public void halt() {
        halted = true;
        // Kill the process directly as well as interrupting: the interrupt
        // alone only works while the thread is parked in waitFor().
        LuaBuild b = build;
        if (b != null) b.kill();
        Thread t = thread;
        if (t != null) t.interrupt();
    }

    // ── Worker ────────────────────────────────────────────────────────────

    private void doRun() {
        RunLog.log("runner thread started");
        try {
            LuaBuild b = new LuaBuild(sketch, modeFolder);
            b.setPresent(presentOn);
            build = b;
            if (halted) return;
            List<LuaProblem> problems = b.run();

            if (halted || Thread.currentThread().isInterrupted()) return;

            if (problems.isEmpty()) {
                listener.statusNotice("Done.");
            } else if (onProblems != null) {
                onProblems.accept(problems);
            } else {
                listener.statusError(formatProblem(problems.get(0)));
            }

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (Throwable e) {
            if (halted) return;
            RunLog.log("run failed", e);
            String why = e.getMessage() != null ? e.getMessage() : e.toString();
            listener.statusError("Could not run the sketch: " + why);
            System.err.println("[LuaMode] could not run the sketch: " + e);
        } finally {
            // Always notify the editor that this runner has finished, so it can
            // clear its reference and re-enable lint feedback.
            try { onComplete.run(); } catch (Throwable t) { RunLog.log("onComplete failed", t); }
        }
    }

    static String formatProblem(LuaProblem p) {
        return p.hasLocation()
            ? String.format("Line %d: %s", p.getLineNumber() + 1, p.getMessage())
            : p.getMessage();
    }
}
