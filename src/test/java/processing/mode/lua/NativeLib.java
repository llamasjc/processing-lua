package processing.mode.lua;

import java.io.File;

/**
 * Loads the native tree-sitter library for tests that parse real Lua.
 *
 * In the IDE, LuaMode unpacks and loads it. Tests don't have a Mode, so they
 * load lib/&lt;platform&gt;/&lt;library&gt; (the output of native/build.sh) directly.
 * Returns false when it hasn't been built, and the caller skips; with
 * LUAMODE_REQUIRE_NATIVE=1 that is a failure instead, so CI can't quietly
 * stop running these tests.
 */
final class NativeLib {

    private static Boolean loaded;

    private NativeLib() {}

    static synchronized boolean load() {
        if (loaded != null) return loaded;
        String name = System.mapLibraryName("java-tree-sitter");
        String dir  = System.getProperty("luamode.native.dir",
                                         "lib/" + LuaNative.platform());
        File lib = new File(dir, name);
        String problem = null;
        if (!lib.isFile()) {
            problem = "not built: " + lib.getAbsolutePath();
        } else {
            try {
                System.load(lib.getAbsolutePath());
                LuaNative.markLoaded();
            } catch (Throwable t) {
                problem = "could not load " + lib + ": " + t;
            }
        }
        if (problem != null && "1".equals(System.getenv("LUAMODE_REQUIRE_NATIVE"))) {
            throw new IllegalStateException("LUAMODE_REQUIRE_NATIVE=1 but the native library is " + problem);
        }
        loaded = (problem == null);
        return loaded;
    }
}
