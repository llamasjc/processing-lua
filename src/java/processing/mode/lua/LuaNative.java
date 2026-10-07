package processing.mode.lua;

/**
 * Whether the tree-sitter native library is loaded, and which platform
 * folder it lives in. Kept apart from LuaMode on purpose: LuaMode extends
 * Processing's Mode, and the highlighter and the tests must not need the
 * whole IDE on the classpath just to ask these two questions.
 */
final class LuaNative {

    private static volatile boolean loaded;

    private LuaNative() {}

    static boolean isLoaded()  { return loaded; }
    static void    markLoaded() { loaded = true; }

    static String platform() {
        String os   = System.getProperty("os.name", "").toLowerCase();
        String arch = System.getProperty("os.arch", "").toLowerCase();
        String a    = arch.contains("aarch64") || arch.contains("arm64") ? "aarch64" : "x86_64";
        if (os.contains("linux"))   return "linux-"   + a;
        if (os.contains("mac"))     return "macos-"   + a;
        if (os.contains("windows")) return "windows-" + a;
        return "linux-x86_64";
    }
}
