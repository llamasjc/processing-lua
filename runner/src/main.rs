/// luamode-runner
///
/// A thin Rust binary that:
///   1. Parses one CLI argument: the path to a combined .lua sketch file.
///   2. Registers every Processing function and constant as a Lua global.
///   3. Loads and executes the sketch file, which defines `setup` and `draw`.
///   4. Drives the event loop via `processing::App`, which internally uses
///      glfw::Runner — the same path all native Processing sketches use.
///
/// This is the architecturally clean path for LuaMode's IDE backend.
/// `processing_surface_create` (the C FFI) needs an existing native window
/// handle, so it cannot be called from LuaJIT directly.  Using the Rust App
/// builder side-steps that entirely: the runner is a first-class processing
/// sketch that happens to be driven by Lua.
///
/// Error output follows the standard Lua format:
///   <filename>:<line>: <message>
/// LuaBuild.java's LuaErrorMapper understands this format and maps line
/// numbers back to the correct sketch tab.

use mlua::prelude::*;
mod payload;
mod processing;
mod parity;
use processing::App;
use std::{
    env,
    fs,
    io::Write,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

const PRELUDE: &str = include_str!("prelude.lua");

// ── Shared state threaded through setup/draw ──────────────────────────────

struct RunnerState {
    lua:   Lua,
    /// Name the sketch chunk was loaded under; error locations start with it.
    chunk: String,
}

/// When the callback currently running was entered (ms since the epoch), or 0
/// between callbacks. The instruction hook uses it to notice a stuck loop.
static CALLBACK_STARTED: AtomicU64 = AtomicU64::new(0);
const STUCK_AFTER_MS: u64 = 10_000;

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

// ── Entry point ───────────────────────────────────────────────────────────

fn main() {
    // A bug in the runner or the engine should read as one, not as a wall of
    // Rust backtrace, and must never be mistaken for an error in the sketch.
    std::panic::set_hook(Box::new(|info| {
        let msg = info.payload().downcast_ref::<&str>().map(|s| s.to_string())
            .or_else(|| info.payload().downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "unknown error".into());
        let at = info.location().map(|l| format!(" ({}, line {})", l.file(), l.line())).unwrap_or_default();
        eprintln!("luamode-runner internal error: {}{}", msg, at);
        eprintln!("This is a bug in Lua Mode, not in your sketch.");
        processing::exit_with(70);
    }));

    // Started by the IDE: it keeps our stdin open and never writes to it.
    // End of input therefore means the IDE is gone (crashed or was killed),
    // and a sketch window nobody can stop any more should not stay behind.
    if env::var_os("LUAMODE_WATCH_STDIN").is_some() {
        let _ = std::thread::Builder::new().name("ide-watch".into()).spawn(|| {
            use std::io::Read;
            let mut buf = [0u8; 256];
            let mut stdin = std::io::stdin();
            loop {
                match stdin.read(&mut buf) {
                    Ok(0) => std::process::exit(0),
                    Ok(_) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                    Err(_) => return,   // no usable stdin: nothing to watch
                }
            }
        });
    }

    // Present pressed in the IDE: LUAMODE_PRESENT is "width,height,x,y" of the
    // screen the editor is on.
    if let Ok(v) = env::var("LUAMODE_PRESENT") {
        let n: Vec<i64> = v.split(',').filter_map(|p| p.trim().parse().ok()).collect();
        if n.len() == 4 && n[0] > 0 && n[1] > 0 {
            processing::present(n[0] as usize, n[1] as usize, n[2] as isize, n[3] as isize);
        }
    }

    // A one-file export: the sketch and its data are inside this program
    let embedded = if env::args().nth(1).is_none() { payload::read() } else { None };
    if let Some(p) = &embedded { payload::apply(p); }
    let embedded_src = embedded.as_ref().and_then(|p| p.get("sketch.lua").map(|s| s.to_vec()));

    // Windows exports start the runner itself (named after the sketch, with
    // its icon), with sketch.lua next to it instead of on the command line
    let next_to_exe = env::current_exe().ok()
        .and_then(|e| e.parent().map(|d| d.join("sketch.lua")))
        .filter(|p| p.is_file());
    let sketch_path: PathBuf = env::args()
        .nth(1)
        .map(PathBuf::from)
        .or(next_to_exe)
        .or_else(|| embedded_src.as_ref().map(|_| PathBuf::from("sketch.lua")))
        .unwrap_or_else(|| {
            eprintln!("usage: luamode-runner <sketch.lua>");
            processing::exit_with(2);
        });
    engine::apply_launch_file();

    // Not read_to_string: one stray byte (a Latin-1 comment, say) shouldn't
    // stop the sketch from running. Lua strings are bytes anyway.
    let sketch_src = embedded_src.map(Ok).unwrap_or_else(|| fs::read(&sketch_path)).unwrap_or_else(|e| {
        eprintln!("{}: {}", sketch_path.display(), e);
        processing::exit_with(2);
    });
    // a UTF-8 byte order mark is a syntax error to Lua
    let sketch_src = sketch_src.strip_prefix(b"\xEF\xBB\xBF").unwrap_or(&sketch_src);

    // Errors read "<file name>:<line>: message". Only the file name, not the
    // whole path: Lua cuts chunk names off at 60 characters, and temp paths on
    // macOS and Windows are longer than that.
    let chunk = sketch_path.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "sketch.lua".into());

    // unsafe_new only means "with the debug library" (the prelude needs it,
    // and debug.traceback is handy in sketches). This runs the user's own code.
    let lua = unsafe { Lua::unsafe_new() };

    // A runaway loop that keeps allocating gets a Lua error instead of
    // dragging the whole machine into swap. LUAMODE_MEMORY_MB overrides it.
    let limit_mb = env::var("LUAMODE_MEMORY_MB").ok()
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(2048);
    if limit_mb > 0 {
        let _ = lua.set_memory_limit(limit_mb.saturating_mul(1024 * 1024));
    }

    if let Err(e) = register_globals(&lua).and_then(|_| parity::register(&lua)).and_then(|_| lua.load(PRELUDE).set_name("=luamode").exec()) {
        eprintln!("luamode-runner internal error: {}", e);
        processing::exit_with(70);
    }

    // The window can't process events while Lua is running, so a sketch stuck
    // in a loop looks frozen. Say so once instead of leaving people guessing.
    lua.set_hook(mlua::HookTriggers::new().every_nth_instruction(1_000_000), |_, _| {
        let started = CALLBACK_STARTED.load(Ordering::Relaxed);
        if started != 0 && now_ms().saturating_sub(started) > STUCK_AFTER_MS {
            CALLBACK_STARTED.store(0, Ordering::Relaxed);   // once per callback
            eprintln!("The sketch has been busy for 10 seconds without finishing a frame. \
                       If it's stuck in a loop, press Stop.");
        }
        Ok(())
    });

    // Run the sketch file: this defines setup/draw/the event functions (and
    // runs any top-level code). The window opens afterwards.
    if let Err(e) = lua.load(sketch_src).set_name(format!("@{}", chunk)).exec() {
        fail(&e, &chunk);
    }

    let state = RunnerState { lua, chunk };

    App::new(state, setup_fn, draw_fn)
        .title("Lua sketch")
        .mouse_pressed(|s| event(s, &["mousePressed"]))
        .mouse_released(|s| event(s, &["mouseReleased"]))
        .mouse_clicked(|s| event(s, &["mouseClicked"]))
        .mouse_moved(|s| event(s, &["mouseMoved"]))
        .mouse_dragged(|s| event(s, &["mouseDragged"]))
        .mouse_wheel(|s, delta| {
            sync_frame_globals(&s.lua);
            call_with(s, "mouseWheel", delta as f64);
        })
        .key_pressed(|s| event(s, &["keyPressed"]))
        .key_released(|s| event(s, &["keyReleased"]))
        .key_typed(|s| event(s, &["keyTyped"]))
        .focus_gained(|s| event(s, &["focusGained"]))
        .focus_lost(|s| event(s, &["focusLost"]))
        .mouse_entered(|s| event(s, &["mouseEntered"]))
        .mouse_exited(|s| event(s, &["mouseExited"]))
        .window_moved(|s| event(s, &["windowMoved"]))
        .window_resized(|s| event(s, &["windowResized"]))
        .run();
}

// ── App callbacks ─────────────────────────────────────────────────────────

fn setup_fn(s: &mut RunnerState) {
    call_with(s, "setup", ());
}

fn draw_fn(s: &mut RunnerState) {
    sync_frame_globals(&s.lua);
    call_with(s, "__runThreads", ());
    call_with(s, "draw", ());
}

/// An input event from the engine: refresh the globals so mouseX, key, ...
/// describe this event, then call the sketch's handlers if it defined them.
fn event(s: &mut RunnerState, names: &[&str]) {
    sync_frame_globals(&s.lua);
    for name in names { call_with(s, name, ()); }
}

/// Calls a global function if the sketch defined one. `mousePressed` and
/// `keyPressed` can also be plain booleans (see sync_frame_globals), so
/// anything that isn't a function is simply not called.
fn call_with<'lua, A: IntoLuaMulti<'lua>>(s: &'lua RunnerState, name: &str, args: A) {
    let f = match s.lua.globals().raw_get::<_, LuaValue>(name) {
        Ok(LuaValue::Function(f)) => f,
        _ => return,
    };
    CALLBACK_STARTED.store(now_ms(), Ordering::Relaxed);
    let result = f.call::<_, ()>(args);
    CALLBACK_STARTED.store(0, Ordering::Relaxed);
    if let Err(e) = result { fail(&e, &s.chunk); }
}

// ── Errors ────────────────────────────────────────────────────────────────
//
// Like Processing, the first error stops the sketch. (Carrying on would print
// the same error sixty times a second.) What goes to stderr is one line,
//   <file>:<line>: message
// which the IDE maps back to the right tab and line, then exit status 1.

fn fail(e: &LuaError, chunk: &str) -> ! {
    let _ = std::io::stdout().flush();
    eprintln!("{}", describe(e, chunk));
    processing::exit_with(1);
}

fn describe(e: &LuaError, chunk: &str) -> String {
    // Unwrap to the innermost cause, keeping the first traceback seen: that
    // one is closest to where the sketch was when things went wrong.
    let mut cur = e;
    let mut traceback = String::new();
    loop {
        match cur {
            LuaError::CallbackError { traceback: tb, cause } => {
                if traceback.is_empty() { traceback = tb.clone(); }
                cur = cause;
            }
            LuaError::WithContext { cause, .. } => cur = cause,
            _ => break,
        }
    }

    let mut msg = match cur {
        LuaError::RuntimeError(m) | LuaError::MemoryError(m) => m.clone(),
        LuaError::SyntaxError { message, .. } => message.clone(),
        LuaError::BadArgument { pos, cause, .. } => {
            let what = match &**cause {
                // 2.5 or 1e30 where an integer constant belongs
                LuaError::FromLuaConversionError { from, to, .. }
                    if (*from == "number" || *from == "integer") && friendly_type(to) == "a whole number" =>
                    "expected a whole number".to_string(),
                LuaError::FromLuaConversionError { from, to, .. } =>
                    format!("expected {}, got {}", friendly_type(to), from),
                other => other.to_string(),
            };
            match called_function(&traceback) {
                Some(f) => format!("bad argument #{} to {}(): {}", pos, f, what),
                None    => format!("bad argument #{}: {}", pos, what),
            }
        }
        other => other.to_string(),
    };
    if let Some(i) = msg.find("\nstack traceback:") {
        if traceback.is_empty() { traceback = msg[i..].to_string(); }
        msg.truncate(i);
    }
    let msg = msg.trim();

    let prefix = format!("{}:", chunk);
    if msg.starts_with(&prefix) {
        return msg.to_string();
    }
    // No location on the message itself (it came from one of our functions,
    // or from error() with a non-string): take the sketch line from the traceback.
    match sketch_line(&traceback, &prefix) {
        Some(line) => format!("{}{}: {}", prefix, line, msg),
        None       => msg.to_string(),
    }
}

/// First "<chunk>:<digits>:" in a traceback.
fn sketch_line(traceback: &str, prefix: &str) -> Option<u32> {
    let mut rest = traceback;
    while let Some(i) = rest.find(prefix) {
        let after = &rest[i + prefix.len()..];
        let digits: String = after.chars().take_while(|c| c.is_ascii_digit()).collect();
        if !digits.is_empty() && after[digits.len()..].starts_with(':') {
            return digits.parse().ok();
        }
        rest = after;
    }
    None
}

/// The traceback of an error raised inside one of our functions starts with
/// "[C]: in function 'ellipse'".
fn called_function(traceback: &str) -> Option<String> {
    let line = traceback.lines().find(|l| l.trim_start().starts_with("[C]: in "))?;
    let start = line.find('\'')? + 1;
    let end = start + line[start..].find('\'')?;
    let name = &line[start..end];
    // Lua 5.4 may say "global 'ellipse'" style names with a prefix; keep the last word
    Some(name.rsplit(|c| c == '.' || c == ' ').next().unwrap_or(name).to_string())
}

fn friendly_type(rust: &str) -> &str {
    match rust {
        "f32" | "f64" => "a number",
        "i32" | "i64" | "u32" | "u64" | "usize" => "a whole number",
        "String" | "string" => "a string",
        "bool" => "true or false",
        other => other,
    }
}

/// Copies the engine's current input and frame state into Lua globals.
/// Called before draw() and before every event callback.
fn sync_frame_globals(lua: &Lua) {
    let g = lua.globals();
    // whole pixels, like Processing (and so print(mouseX) says 120, not 120.0)
    let _ = g.raw_set("mouseX",  processing::mouse_x().round() as i64);
    let _ = g.raw_set("mouseY",  processing::mouse_y().round() as i64);
    let _ = g.raw_set("pmouseX", processing::pmouse_x().round() as i64);
    let _ = g.raw_set("pmouseY", processing::pmouse_y().round() as i64);
    // windowRatio: the mouse and size in the sketch's own units
    let _ = g.raw_set("rmouseX", engine::rmouse_x().round() as i64);
    let _ = g.raw_set("rmouseY", engine::rmouse_y().round() as i64);
    let _ = g.raw_set("rwidth",  engine::rwidth().round() as i64);
    let _ = g.raw_set("rheight", engine::rheight().round() as i64);
    // mousePressed / keyPressed are also the names of the event callbacks.
    // Lua can't hold both, so the state lives in mouseIsPressed / keyIsPressed
    // (like p5.js), and the old names are only set when the sketch hasn't
    // defined a function with that name.
    let mp = processing::mouse_is_pressed();
    let kp = processing::key_is_pressed();
    let _ = g.raw_set("mouseIsPressed", mp);
    let _ = g.raw_set("keyIsPressed",   kp);
    if !matches!(g.raw_get::<_, LuaValue>("mousePressed"), Ok(LuaValue::Function(_))) {
        let _ = g.raw_set("mousePressed", mp);
    }
    if !matches!(g.raw_get::<_, LuaValue>("keyPressed"), Ok(LuaValue::Function(_))) {
        let _ = g.raw_set("keyPressed", kp);
    }
    let _ = g.raw_set("mouseButton", processing::mouse_button());
    let _ = g.raw_set("focused", processing::focused());
    // arrows, modifiers and the like have no character: key is CODED and the
    // sketch looks at keyCode
    if processing::key_is_coded() {
        let _ = g.raw_set("key", CODED);
    } else {
        let k = processing::key_char();
        let _ = g.raw_set("key", if k == '\0' { String::new() } else { k.to_string() });
    }
    let _ = g.raw_set("keyCode",    processing::key_code() as i64);
    let _ = g.raw_set("frameCount", processing::frame_count() as i64);
    let _ = g.raw_set("frameRate",  processing::frame_rate() as f64);
    let (w, h) = (processing::width() as i64, processing::height() as i64);
    if w > 0 && h > 0 {
        let _ = g.raw_set("width",  w);
        let _ = g.raw_set("height", h);
    }
}

const CODED: i64 = 0xFFFF;

/// A Lua number argument as f64, with a readable complaint otherwise.
fn num(v: &LuaValue, what: &str) -> LuaResult<f64> {
    match v {
        LuaValue::Number(n)  => Ok(*n),
        LuaValue::Integer(n) => Ok(*n as f64),
        LuaValue::String(s)  => s.to_str().ok().and_then(|t| t.trim().parse::<f64>().ok())
            .ok_or_else(|| LuaError::RuntimeError(format!("{} expects a number, got a string", what))),
        other => Err(LuaError::RuntimeError(format!("{} expects a number, got {}", what, other.type_name()))),
    }
}

// ── Global registration ───────────────────────────────────────────────────
//
// Every Processing function and constant is a Lua global, named as in the
// Processing reference. The math helpers live in prelude.lua.

fn register_globals(lua: &Lua) -> LuaResult<()> {
    let g = lua.globals();

    // ── size / dimensions ─────────────────────────────────────────────────
    // size(w, h) or size(w, h, P3D); the renderer is kept for is2D() / is3D()
    g.set("size", lua.create_function(|lua, (w, h, r): (LuaValue, LuaValue, LuaValue)| {
        let dim = |v: &LuaValue| -> LuaResult<u32> {
            let n = num(v, "size()")?;
            if !n.is_finite() || n < 1.0 {
                return Err(LuaError::RuntimeError("size() needs a width and height of at least 1".into()));
            }
            Ok((n.round() as u32).min(8192))
        };
        let (w, h) = (dim(&w)?, dim(&h)?);
        processing::size(w, h);
        lua.globals().raw_set("__renderer", r)?;
        lua.globals().raw_set("width",  w)?;
        lua.globals().raw_set("height", h)?;
        Ok(())
    })?)?;

    g.set("width",  100_i64)?;
    g.set("height", 100_i64)?;
    processing::size(100, 100);   // Processing's default when size() is never called
    // text(s, x, y) puts the baseline at y unless textAlign() says otherwise
    processing::text_align(processing::LEFT, processing::BASELINE);

    // ── Frame state (refreshed before draw() and every event) ─────────────
    g.set("frameCount",    0_i64)?;
    g.set("frameRate",     60_f64)?;
    g.set("mouseX",        0_i64)?;
    g.set("mouseY",        0_i64)?;
    g.set("pmouseX",       0_i64)?;
    g.set("pmouseY",       0_i64)?;
    g.set("mousePressed",   false)?;
    g.set("keyPressed",     false)?;
    g.set("mouseIsPressed", false)?;
    g.set("keyIsPressed",   false)?;
    g.set("mouseButton",   0_i64)?;
    g.set("key",           "")?;
    g.set("keyCode",       0_i64)?;

    // ── Constants ─────────────────────────────────────────────────────────
    use std::f32::consts::PI;
    g.set("PI",       PI)?;
    g.set("TWO_PI",   PI * 2.0)?;
    g.set("HALF_PI",  PI / 2.0)?;
    g.set("TAU",      PI * 2.0)?;
    g.set("QUARTER_PI", PI / 4.0)?;
    // LEFT / RIGHT / CENTER carry Processing's values because each does three
    // jobs: key code, mouse button and alignment.
    g.set("LEFT",     processing::LEFT)?;
    g.set("RIGHT",    processing::RIGHT)?;
    g.set("CENTER",   processing::CENTER)?;
    g.set("TOP",      processing::TOP)?;
    g.set("BOTTOM",   processing::BOTTOM)?;
    g.set("BASELINE", engine::BASELINE)?;
    g.set("CORNER",   processing::CORNER)?;
    g.set("CORNERS",  processing::CORNERS)?;
    g.set("RADIUS",   processing::RADIUS)?;
    // Processing's own numbers
    g.set("OPEN",    1_i32)?;
    g.set("CLOSE",   2_i32)?;
    g.set("CHORD",   2_i32)?;
    g.set("PIE",     3_i32)?;
    // Blend modes
    g.set("REPLACE",    0_i32)?;
    g.set("BLEND",      1_i32)?;
    g.set("ADD",        2_i32)?;
    g.set("SUBTRACT",   4_i32)?;
    g.set("LIGHTEST",   8_i32)?;
    g.set("DARKEST",    16_i32)?;
    g.set("DIFFERENCE", 32_i32)?;
    g.set("EXCLUSION",  64_i32)?;
    g.set("MULTIPLY",   128_i32)?;
    g.set("SCREEN",     256_i32)?;
    // Color modes
    g.set("RGB",     1_i32)?;
    g.set("HSB",     3_i32)?;
    // Shape kinds
    g.set("POINTS",       0_i32)?;
    g.set("LINES",        1_i32)?;
    g.set("TRIANGLES",    4_i32)?;
    g.set("TRIANGLE_STRIP", 5_i32)?;
    g.set("TRIANGLE_FAN", 6_i32)?;
    g.set("QUADS",        7_i32)?;
    g.set("QUAD_STRIP",   8_i32)?;
    g.set("POLYGON",      9_i32)?;
    // Stroke caps / joins
    g.set("SQUARE",  1_i32)?;
    g.set("ROUND",   2_i32)?;
    g.set("PROJECT", 4_i32)?;
    g.set("MITER",   8_i32)?;
    g.set("BEVEL",   32_i32)?;
    // Key codes
    g.set("BACKSPACE", 8_i32)?;
    g.set("TAB",       9_i32)?;
    g.set("ENTER",     10_i32)?;
    g.set("RETURN",    13_i32)?;
    g.set("ESC",       27_i32)?;
    g.set("DELETE",    127_i32)?;
    g.set("CODED",     CODED)?;
    g.set("UP",        38_i32)?;
    g.set("DOWN",      40_i32)?;
    g.set("SHIFT",     16_i32)?;
    g.set("CONTROL",   17_i32)?;
    g.set("ALT",       18_i32)?;
    g.set("NONE",    0_i32)?;

    // ── Background / color ────────────────────────────────────────────────
    g.set("background", lua.create_function(|_, args: LuaMultiValue| {
        let c = unpack_color(args);
        processing::background(c[0], c[1], c[2], c[3]);
        Ok(())
    })?)?;

    g.set("fill", lua.create_function(|_, args: LuaMultiValue| {
        let c = unpack_color(args);
        processing::fill(c[0], c[1], c[2], c[3]);
        Ok(())
    })?)?;

    g.set("noFill", lua.create_function(|_, ()| {
        processing::no_fill();
        Ok(())
    })?)?;

    g.set("stroke", lua.create_function(|_, args: LuaMultiValue| {
        let c = unpack_color(args);
        processing::stroke(c[0], c[1], c[2], c[3]);
        Ok(())
    })?)?;

    g.set("noStroke", lua.create_function(|_, ()| {
        processing::no_stroke();
        Ok(())
    })?)?;

    g.set("strokeWeight", lua.create_function(|_, w: f32| {
        processing::stroke_weight(w);
        Ok(())
    })?)?;

    g.set("strokeCap", lua.create_function(|_, cap: i32| {
        processing::stroke_cap(cap);
        Ok(())
    })?)?;

    g.set("strokeJoin", lua.create_function(|_, join: i32| {
        processing::stroke_join(join);
        Ok(())
    })?)?;

    // colorMode(mode), colorMode(mode, max), colorMode(mode, m1, m2, m3[, mA])
    g.set("colorMode", lua.create_function(|_, args: LuaMultiValue| {
        let v: Vec<f32> = args.iter().filter_map(|a| a.to_num()).collect();
        let mode = v.first().copied().unwrap_or(1.0) as i32;
        processing::color_mode(mode, &v[1.min(v.len())..]);
        Ok(())
    })?)?;

    // lerpColor(c1, c2, t) with colors from color(), or
    // lerpColor(r1, g1, b1, r2, g2, b2, t) which returns r, g, b
    g.set("lerpColor", lua.create_function(|_, args: LuaMultiValue| {
        let v: Vec<LuaValue> = args.into_iter().collect();
        if v.len() == 3 {
            let (a, b) = (color_arg(&v[0]), color_arg(&v[1]));
            let t = (num(&v[2], "lerpColor()")? as f32).clamp(0.0, 1.0);
            let mix = [0, 1, 2, 3].map(|i| a[i] + (b[i] - a[i]) * t);
            return Ok(LuaMultiValue::from_vec(vec![LuaValue::Integer(pack_color(mix))]));
        }
        if v.len() < 7 {
            return Err(LuaError::RuntimeError(
                "lerpColor() expects (color, color, amount) or (r1, g1, b1, r2, g2, b2, amount)".into()));
        }
        let n: Vec<f32> = v.iter().map(|x| x.to_num().unwrap_or(0.0)).collect();
        let (r, g, b) = processing::lerp_color(n[0], n[1], n[2], n[3], n[4], n[5], n[6]);
        Ok(LuaMultiValue::from_vec(vec![
            LuaValue::Number(r as f64), LuaValue::Number(g as f64), LuaValue::Number(b as f64),
        ]))
    })?)?;

    // color(...) packs a color into one value that fill(), stroke(),
    // background(), tint(), set() and lerpColor() all accept.
    g.set("color", lua.create_function(|_, args: LuaMultiValue| {
        Ok(pack_color(unpack_color(args)))
    })?)?;
    // red(c), green(c), blue(c), alpha(c): 0..255
    for (name, i) in [("red", 0usize), ("green", 1), ("blue", 2), ("alpha", 3)] {
        g.set(name, lua.create_function(move |_, c: LuaValue| Ok(color_arg(&c)[i] as f64))?)?;
    }
    // hue(c), saturation(c), brightness(c): in the range colorMode() set
    for (name, i) in [("hue", 0usize), ("saturation", 1), ("brightness", 2)] {
        g.set(name, lua.create_function(move |_, c: LuaValue| {
            let c = color_arg(&c);
            let hsb = processing::rgb_to_hsb(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0);
            let max = if processing::is_hsb() { processing::color_max(i) } else { 255.0 };
            Ok(([hsb.0, hsb.1, hsb.2][i] * max) as f64)
        })?)?;
    }

    // filter(GRAY), filter(INVERT), filter(BLUR, 4), filter(THRESHOLD, 0.5),
    // filter(POSTERIZE, 4), filter(ERODE), filter(DILATE)
    g.set("filter", lua.create_function(|_, (kind, param): (i32, Option<f32>)| {
        processing::filter(kind, param.unwrap_or(f32::NAN)); Ok(())
    })?)?;
    // shaders: prelude.lua wraps the handle into an object with :set()
    g.set("__loadShader", lua.create_function(|_, (path, vert): (LuaString, Option<LuaString>)| {
        let s = match vert {
            Some(v) => engine::load_shader_vf(&path.to_string_lossy(), &v.to_string_lossy()),
            None => engine::load_shader(&path.to_string_lossy()),
        };
        Ok(SHADERS.with(|v| { let mut v = v.borrow_mut(); v.push(s); v.len() as i64 }))
    })?)?;
    g.set("__shaderFromSource", lua.create_function(|_, (src, vert): (LuaString, Option<LuaString>)| {
        let s = match vert {
            Some(v) => engine::shader_from_source_vf(&src.to_string_lossy(), &v.to_string_lossy()),
            None => engine::shader_from_source(&src.to_string_lossy()),
        };
        Ok(SHADERS.with(|v| { let mut v = v.borrow_mut(); v.push(s); v.len() as i64 }))
    })?)?;
    g.set("__shaderOk", lua.create_function(|_, h: i64| {
        Ok(SHADERS.with(|v| v.borrow().get((h - 1) as usize).map(|s| s.is_ok()).unwrap_or(false)))
    })?)?;
    g.set("__shaderSet", lua.create_function(|_, (h, name, args): (i64, LuaString, LuaMultiValue)| {
        let mut vals = Vec::new();
        for a in args.iter() {
            match a {
                LuaValue::Boolean(b) => vals.push(if *b { 1.0 } else { 0.0 }),
                LuaValue::Table(t) => for x in t.clone().sequence_values::<f64>().flatten() { vals.push(x as f32) },
                other => if let Some(n) = other.to_num() { vals.push(n) },
            }
        }
        if let Some(s) = SHADERS.with(|v| v.borrow().get((h - 1) as usize).copied()) {
            s.set(&name.to_string_lossy(), vals);
        }
        Ok(())
    })?)?;
    g.set("__shapeShader", lua.create_function(|_, h: Option<i64>| {
        match h.and_then(|h| SHADERS.with(|v| v.borrow().get((h - 1) as usize).copied())) {
            Some(s) => engine::shader(s),
            None => engine::reset_shader(),
        }
        Ok(())
    })?)?;
    g.set("__filterShader", lua.create_function(|_, h: i64| {
        if let Some(s) = SHADERS.with(|v| v.borrow().get((h - 1) as usize).copied()) { engine::filter(s); }
        Ok(())
    })?)?;
    for (name, v) in [("BLUR", 11), ("GRAY", 12), ("INVERT", 13), ("OPAQUE", 14),
                      ("POSTERIZE", 15), ("THRESHOLD", 16), ("ERODE", 17), ("DILATE", 18)] {
        g.set(name, v as i64)?;
    }
    // fullScreen() in setup(): the sketch covers the screen and width/height
    // become the screen's size
    g.set("fullScreen", lua.create_function(|lua, ()| {
        processing::full_screen();
        let (w, h) = processing::target_size();
        lua.globals().raw_set("width",  w as i64)?;
        lua.globals().raw_set("height", h as i64)?;
        Ok(())
    })?)?;
    let (dw, dh) = processing::display_size();
    g.set("displayWidth",  dw as i64)?;
    g.set("displayHeight", dh as i64)?;
    g.set("focused", true)?;

    g.set("blendMode", lua.create_function(|_, mode: i32| { processing::blend_mode(mode); Ok(()) })?)?;

    // ── Shapes ────────────────────────────────────────────────────────────
    // rect(x, y, w, h), rect(x, y, w, h, r), rect(x, y, w, h, tl, tr, br, bl)
    g.set("rect", lua.create_function(|_, (x,y,w,h,r,tr,br,bl): (f32,f32,f32,f32,Option<f32>,Option<f32>,Option<f32>,Option<f32>)| {
        match (r, tr, br, bl) {
            (Some(tl), Some(tr), Some(br), Some(bl)) => processing::rect_radii(x,y,w,h,tl,tr,br,bl),
            (Some(r), ..) if r > 0.0 => processing::rect_rounded(x,y,w,h,r),
            _                        => processing::rect(x,y,w,h),
        }
        Ok(())
    })?)?;

    g.set("square", lua.create_function(|_, (x,y,s): (f32,f32,f32)| {
        processing::rect(x,y,s,s); Ok(())
    })?)?;

    g.set("rectMode", lua.create_function(|_, m: i32| { processing::rect_mode(m); Ok(()) })?)?;
    g.set("ellipseMode", lua.create_function(|_, m: i32| { processing::ellipse_mode(m); Ok(()) })?)?;

    g.set("ellipse", lua.create_function(|_, (x,y,w,h): (f32,f32,f32,f32)| {
        processing::ellipse(x,y,w,h); Ok(())
    })?)?;

    g.set("circle", lua.create_function(|_, (x,y,d): (f32,f32,f32)| {
        processing::circle(x,y,d); Ok(())
    })?)?;

    // line(x1, y1, x2, y2), or line(x1, y1, z1, x2, y2, z2) in 3D
    g.set("line", lua.create_function(|_, (a, b, c, d, e, f): (f32, f32, f32, f32, Option<f32>, Option<f32>)| {
        match (e, f) {
            (Some(e), Some(f)) => processing::line3(a, b, c, d, e, f),
            _ => processing::line(a, b, c, d),
        }
        Ok(())
    })?)?;

    g.set("point", lua.create_function(|_, (x, y, z): (f32, f32, Option<f32>)| {
        match z { Some(z) => processing::point3(x, y, z), None => processing::point(x, y) }
        Ok(())
    })?)?;

    g.set("triangle", lua.create_function(|_, (x1,y1,x2,y2,x3,y3): (f32,f32,f32,f32,f32,f32)| {
        processing::triangle(x1,y1,x2,y2,x3,y3); Ok(())
    })?)?;

    g.set("quad", lua.create_function(|_, (x1,y1,x2,y2,x3,y3,x4,y4): (f32,f32,f32,f32,f32,f32,f32,f32)| {
        processing::quad(x1,y1,x2,y2,x3,y3,x4,y4); Ok(())
    })?)?;

    g.set("arc", lua.create_function(|_, (x,y,w,h,start,stop,mode): (f32,f32,f32,f32,f32,f32,Option<i32>)| {
        processing::arc(x,y,w,h,start,stop, mode.unwrap_or(0)); Ok(())
    })?)?;

    g.set("bezier", lua.create_function(|_, (x1,y1,cx1,cy1,cx2,cy2,x2,y2): (f32,f32,f32,f32,f32,f32,f32,f32)| {
        processing::bezier(x1,y1,cx1,cy1,cx2,cy2,x2,y2); Ok(())
    })?)?;

    g.set("curve", lua.create_function(|_, (cx1,cy1,x1,y1,x2,y2,cx2,cy2): (f32,f32,f32,f32,f32,f32,f32,f32)| {
        processing::curve(cx1,cy1,x1,y1,x2,y2,cx2,cy2); Ok(())
    })?)?;

    // ── Vertex / shape builders ───────────────────────────────────────────
    g.set("beginShape", lua.create_function(|_, kind: Option<i32>| {
        processing::begin_shape(kind.unwrap_or(9)); Ok(())
    })?)?;

    g.set("endShape", lua.create_function(|_, mode: Option<i32>| {
        processing::end_shape(mode.unwrap_or(0)); Ok(())
    })?)?;


    g.set("beginContour", lua.create_function(|_, ()| { engine::begin_contour(); Ok(()) })?)?;
    g.set("endContour", lua.create_function(|_, ()| { engine::end_contour(); Ok(()) })?)?;
    g.set("bezierVertex", lua.create_function(|_, (cx1,cy1,cx2,cy2,x,y): (f32,f32,f32,f32,f32,f32)| {
        processing::bezier_vertex(cx1,cy1,cx2,cy2,x,y); Ok(())
    })?)?;

    g.set("quadraticVertex", lua.create_function(|_, (cx,cy,x,y): (f32,f32,f32,f32)| {
        processing::quadratic_vertex(cx,cy,x,y); Ok(())
    })?)?;

    g.set("curveVertex", lua.create_function(|_, (x,y): (f32,f32)| {
        processing::curve_vertex(x,y); Ok(())
    })?)?;

    // ── Transform ─────────────────────────────────────────────────────────
    // push() / pop() save and restore both the transform and the style, as in p5.js
    g.set("push", lua.create_function(|_, ()| { processing::push_matrix(); processing::push_style(); Ok(()) })?)?;
    g.set("pop",  lua.create_function(|_, ()| { processing::pop_style(); processing::pop_matrix(); Ok(()) })?)?;
    // clip(x, y, w, h) / noClip(): only a rectangle can be drawn on
    g.set("clip", lua.create_function(|_, (x, y, w, h): (f32, f32, f32, f32)| { engine::clip(x, y, w, h); Ok(()) })?)?;
    g.set("noClip", lua.create_function(|_, ()| { engine::no_clip(); Ok(()) })?)?;
    g.set("hint", lua.create_function(|_, which: i32| { engine::hint(which); Ok(()) })?)?;
    for (n, v) in [("DISABLE_DEPTH_TEST", engine::DISABLE_DEPTH_TEST), ("ENABLE_DEPTH_TEST", engine::ENABLE_DEPTH_TEST),
                   ("ENABLE_DEPTH_SORT", engine::ENABLE_DEPTH_SORT), ("DISABLE_DEPTH_SORT", engine::DISABLE_DEPTH_SORT),
                   ("DISABLE_DEPTH_MASK", engine::DISABLE_DEPTH_MASK), ("ENABLE_DEPTH_MASK", engine::ENABLE_DEPTH_MASK),
                   ("DISABLE_OPTIMIZED_STROKE", engine::DISABLE_OPTIMIZED_STROKE), ("ENABLE_OPTIMIZED_STROKE", engine::ENABLE_OPTIMIZED_STROKE),
                   ("ENABLE_STROKE_PERSPECTIVE", engine::ENABLE_STROKE_PERSPECTIVE), ("DISABLE_STROKE_PERSPECTIVE", engine::DISABLE_STROKE_PERSPECTIVE),
                   ("DISABLE_TEXTURE_MIPMAPS", engine::DISABLE_TEXTURE_MIPMAPS), ("ENABLE_TEXTURE_MIPMAPS", engine::ENABLE_TEXTURE_MIPMAPS),
                   ("ENABLE_STROKE_PURE", engine::ENABLE_STROKE_PURE), ("DISABLE_STROKE_PURE", engine::DISABLE_STROKE_PURE),
                   ("ENABLE_ASYNC_SAVEFRAME", engine::ENABLE_ASYNC_SAVEFRAME), ("DISABLE_ASYNC_SAVEFRAME", engine::DISABLE_ASYNC_SAVEFRAME),
                   ("DISABLE_OPENGL_ERRORS", engine::DISABLE_OPENGL_ERRORS), ("ENABLE_OPENGL_ERRORS", engine::ENABLE_OPENGL_ERRORS)] {
        g.set(n, v)?;
    }
    g.set("link", lua.create_function(|_, url: String| { engine::link(&url); Ok(()) })?)?;
    g.set("launch", lua.create_function(|_, args: LuaMultiValue| {
        let mut v: Vec<String> = Vec::new();
        for a in args.iter() {
            match a {
                LuaValue::Table(t) => for s in t.clone().sequence_values::<String>() { v.push(s?); },
                other => v.push(other.to_string()?),
            }
        }
        let refs: Vec<&str> = v.iter().map(|s| s.as_str()).collect();
        Ok(engine::launch(&refs))
    })?)?;
    g.set("windowRatio", lua.create_function(|lua, (w, h): (f32, f32)| {
        engine::window_ratio(w, h);
        let g = lua.globals();
        g.raw_set("rwidth", engine::rwidth().round() as i64)?;
        g.raw_set("rheight", engine::rheight().round() as i64)?;
        Ok(())
    })?)?;
    // beginRecord(PDF or SVG, "file") or beginRecord("file.svg") ... endRecord()
    g.set("PDF", engine::PDF)?;
    g.set("SVG", engine::SVG)?;
    g.set("beginRecord", lua.create_function(|_, (a, b): (String, Option<String>)| {
        match b { Some(path) => engine::begin_record(&a, &path), None => engine::begin_record("", &a) }
        Ok(())
    })?)?;
    g.set("endRecord", lua.create_function(|_, ()| Ok(engine::end_record()))?)?;
    g.set("beginRaw", lua.create_function(|_, (a, b): (String, Option<String>)| {
        match b { Some(path) => engine::begin_raw(&a, &path), None => engine::begin_raw("", &a) }
        Ok(())
    })?)?;
    g.set("endRaw", lua.create_function(|_, ()| Ok(engine::end_raw()))?)?;
    // attrib("name", x [, y, z, w]): a value of your own for the next vertices
    g.set("attrib", lua.create_function(|_, (name, vals): (String, LuaMultiValue)| {
        let mut v = Vec::new();
        for a in vals.iter() {
            match a { LuaValue::Integer(i) => v.push(*i as f32), LuaValue::Number(x) => v.push(*x as f32), _ => {} }
        }
        engine::attrib(&name, v);
        Ok(())
    })?)?;
    g.set("attribPosition", lua.create_function(|_, (name, x, y, z): (String, f32, f32, Option<f32>)| { engine::attrib(&name, vec![x, y, z.unwrap_or(0.0)]); Ok(()) })?)?;
    g.set("attribNormal", lua.create_function(|_, (name, x, y, z): (String, f32, f32, f32)| { engine::attrib(&name, vec![x, y, z]); Ok(()) })?)?;
    g.set("saveStream", lua.create_function(|_, (target, source): (String, String)| Ok(engine::save_stream(&target, &source)))?)?;
    g.set("pushMatrix", lua.create_function(|_, ()| { processing::push_matrix(); Ok(()) })?)?;
    g.set("popMatrix",  lua.create_function(|_, ()| { processing::pop_matrix();  Ok(()) })?)?;
    g.set("pushStyle",  lua.create_function(|_, ()| { processing::push_style();  Ok(()) })?)?;
    g.set("popStyle",   lua.create_function(|_, ()| { processing::pop_style();   Ok(()) })?)?;

    g.set("translate", lua.create_function(|_, (x, y, z): (f32, f32, Option<f32>)| {
        processing::translate3(x, y, z.unwrap_or(0.0)); Ok(())
    })?)?;


    g.set("scale", lua.create_function(|_, args: LuaMultiValue| {
        let vals: Vec<f32> = args.iter()
            .filter_map(|v| v.to_num())
            .collect();
        match vals.len() {
            0 => return Err(LuaError::RuntimeError("scale() expects one or two numbers".into())),
            1 => processing::scale_uniform(vals[0]),
            2 => processing::scale(vals[0], vals[1]),
            _ => processing::scale3(vals[0], vals[1], vals[2]),
        }
        Ok(())
    })?)?;

    // ── 3D ───────────────────────────────────────────────────────────────
    // box, sphere, a camera, a depth buffer and lights. translate, rotate,
    // scale, pushMatrix and popMatrix move 3D shapes too.
    g.set("P2D", 2_i64)?;
    g.set("P3D", 3_i64)?;
    g.set("rotateX", lua.create_function(|_, a: f32| { let _ = processing::three("rotateX", &[a]); Ok(()) })?)?;
    g.set("rotateY", lua.create_function(|_, a: f32| { let _ = processing::three("rotateY", &[a]); Ok(()) })?)?;
    g.set("rotateZ", lua.create_function(|_, a: f32| { processing::rotate(a); Ok(()) })?)?;
    g.set("IMAGE", 0_i64)?;
    g.set("NORMAL", 1_i64)?;
    g.set("CLAMP", 0_i64)?;
    g.set("REPEAT", 1_i64)?;
    for name in ["box", "sphere", "sphereDetail", "camera", "perspective", "ortho", "lights", "noLights",
                 "ambientLight", "directionalLight", "pointLight", "screenX", "screenY", "screenZ",
                 "beginCamera", "endCamera", "printCamera", "printProjection", "frustum",
                 "modelX", "modelY", "modelZ", "normal", "textureMode", "textureWrap", "texture", "noTexture",
                 "vertex", "rotate", "applyMatrix",
                 "spotLight", "lightFalloff", "lightSpecular", "ambient", "specular", "emissive", "shininess",
                 "bezierDetail", "curveDetail", "curveTightness", "shapeMode", "pixelDensity", "displayDensity",
                 "pixelWidth", "pixelHeight", "windowMove", "windowResize", "textMode", "printMatrix", "copy", "blend"] {
        g.set(name, lua.create_function(move |_, args: LuaMultiValue| {
            let mut v = Vec::with_capacity(args.len());
            for a in args.iter() {
                if a.is_nil() { break; }     // a replayed createShape step pads with nils
                match a.to_num() {
                    Some(n) => v.push(n),
                    None => return Err(LuaError::RuntimeError(format!("{name}() expects numbers"))),
                }
            }
            match processing::three(name, &v) {
                Ok(r) => Ok(r.map(|x| x as f64)),
                Err(e) => Err(LuaError::RuntimeError(format!("{name}(): {e}"))),
            }
        })?)?;
    }
    // line and point take a z too in 3D: line(x1, y1, z1, x2, y2, z2)
    g.set("shearX", lua.create_function(|_, a: f32| { processing::shear_x(a); Ok(()) })?)?;
    g.set("shearY", lua.create_function(|_, a: f32| { processing::shear_y(a); Ok(()) })?)?;

    g.set("resetMatrix", lua.create_function(|_, ()| {
        processing::reset_matrix(); Ok(())
    })?)?;

    // ── Text ──────────────────────────────────────────────────────────────
    // text(anything, x, y): numbers, booleans and nil are shown the way
    // print() would show them
    // text(s, x, y, w, h): wrapped inside the box, lines that don't fit left out
    g.set("text", lua.create_function(|lua, (v, x, y, w, h): (LuaValue, f32, f32, Option<f32>, Option<f32>)| {
        let s = match &v {
            LuaValue::String(s) => s.to_string_lossy().into_owned(),
            other => lua.globals().get::<_, LuaFunction>("tostring")?.call::<_, String>(other.clone())?,
        };
        match (w, h) {
            (Some(w), Some(h)) => processing::text_box(&s, x, y, w, h),
            _ => processing::text(&s, x, y),
        }
        Ok(())
    })?)?;

    g.set("textSize", lua.create_function(|_, sz: f32| {
        processing::text_size(sz); Ok(())
    })?)?;

    // createFont("DejaVu Sans", 32) or createFont("MyFont.ttf", 32): a .ttf /
    // .otf file (also looked for in data/), or the name of an installed font.
    // Returns 0 when it can't be loaded; text then stays in the built-in font.
    g.set("createFont", lua.create_function(|_, (name, size): (LuaString, Option<f32>)| {
        Ok(processing::create_font(&name.to_string_lossy(), size.unwrap_or(0.0)) as i64)
    })?)?;
    g.set("loadFont", lua.create_function(|_, name: LuaString| {
        Ok(processing::create_font(&name.to_string_lossy(), 0.0) as i64)
    })?)?;
    // textFont(font) or textFont(font, size); textFont(0) is the built-in font
    g.set("textFont", lua.create_function(|_, (font, size): (Option<i64>, Option<f32>)| {
        processing::text_font(font.unwrap_or(0).max(0) as u64, size.unwrap_or(0.0)); Ok(())
    })?)?;
    g.set("textLeading", lua.create_function(|_, px: f32| { processing::text_leading(px); Ok(()) })?)?;

    g.set("textAlign", lua.create_function(|_, (h, v): (i32, Option<i32>)| {
        processing::text_align(h, v.unwrap_or(processing::BASELINE)); Ok(())
    })?)?;

    g.set("textWidth", lua.create_function(|_, s: LuaString| {
        Ok(processing::text_width(&s.to_string_lossy()))
    })?)?;

    g.set("textAscent", lua.create_function(|_, ()| {
        Ok(processing::text_ascent())
    })?)?;

    g.set("textDescent", lua.create_function(|_, ()| {
        Ok(processing::text_descent())
    })?)?;

    // ── Math ──────────────────────────────────────────────────────────────
    // map, lerp, constrain, sin, floor, ... are defined in prelude.lua.

    // noise / random
    g.set("noise", lua.create_function(|_, args: LuaMultiValue| {
        let vals: Vec<f32> = args.iter().filter_map(|v| v.to_num()).collect();
        let at = |i: usize| vals.get(i).copied().unwrap_or(0.0);
        Ok(processing::noise3(at(0), at(1), at(2)) as f64)
    })?)?;

    g.set("noiseSeed", lua.create_function(|_, seed: LuaValue| {
        processing::noise_seed(num(&seed, "noiseSeed()")? as i64 as u64); Ok(())
    })?)?;

    g.set("noiseDetail", lua.create_function(|_, (oct, fall): (i32, Option<f32>)| {
        processing::noise_detail(oct, fall.unwrap_or(0.5)); Ok(())
    })?)?;

    g.set("random", lua.create_function(|_, args: LuaMultiValue| {
        let vals: Vec<f32> = args.iter().filter_map(|v| v.to_num()).collect();
        Ok(match vals.len() {
            0 => processing::random1(),
            1 => processing::random1() * vals[0],
            _ => vals[0] + processing::random1() * (vals[1] - vals[0]),
        })
    })?)?;

    g.set("randomSeed", lua.create_function(|_, seed: LuaValue| {
        processing::random_seed(num(&seed, "randomSeed()")? as i64 as u64); Ok(())
    })?)?;

    g.set("randomGaussian", lua.create_function(|_, ()| {
        Ok(processing::random_gaussian())
    })?)?;

    // ── Time / loop control ───────────────────────────────────────────────
    g.set("millis", lua.create_function(|_, ()| {
        Ok(processing::millis())
    })?)?;

    g.set("loop",   lua.create_function(|_, ()| { processing::set_loop(true);  Ok(()) })?)?;
    g.set("noLoop", lua.create_function(|_, ()| { processing::set_loop(false); Ok(()) })?)?;

    g.set("redraw", lua.create_function(|_, ()| {
        processing::redraw(); Ok(())
    })?)?;

    g.set("delay", lua.create_function(|_, ms: LuaValue| {
        let ms = num(&ms, "delay()")?;
        if ms.is_finite() && ms > 0.0 {
            std::thread::sleep(std::time::Duration::from_millis(ms.min(60_000.0) as u64));
        }
        Ok(())
    })?)?;

    // frameRate(n) sets the target; the frameRate global reads the current
    // rate. prelude.lua wires the two together through this function, which
    // returns the rate the engine settled on. setFrameRate(n) does the same.
    let set_rate = lua.create_function(|_, fps: f32| Ok(processing::set_frame_rate(fps) as f64))?;
    g.set("__luamode_set_frame_rate", set_rate)?;
    g.set("setFrameRate", lua.create_function(|lua, fps: f32| {
        lua.globals().raw_set("frameRate", processing::set_frame_rate(fps) as f64)
    })?)?;

    g.set("windowTitle", lua.create_function(|_, t: LuaString| {
        processing::window_title(&t.to_string_lossy()); Ok(())
    })?)?;
    // windowResizable(true) in setup() lets the window be resized. The default
    // is a fixed-size window, which tiling window managers show floating.
    g.set("windowResizable", lua.create_function(|_, on: Option<bool>| {
        processing::window_resizable(on.unwrap_or(true)); Ok(())
    })?)?;
    g.set("smooth",   lua.create_function(|_, ()| { processing::smooth(true);  Ok(()) })?)?;
    g.set("noSmooth", lua.create_function(|_, ()| { processing::smooth(false); Ok(()) })?)?;

    // cursor / noCursor
    // cursor(), cursor(HAND / CROSS / MOVE / TEXT / WAIT / ARROW), or a
    // picture: cursor(img) points with its middle, cursor(img, x, y) with
    // that pixel. Image numbers start at 65536, so they never look like a kind.
    g.set("cursor", lua.create_function(|_, args: LuaMultiValue| {
        let n = |v: Option<&LuaValue>| match v { Some(LuaValue::Integer(i)) => Some(*i as f64), Some(LuaValue::Number(f)) => Some(*f), _ => None };
        let first = n(args.get(0));
        match first {
            Some(k) if k >= 65536.0 && args.len() >= 3 => engine::cursor_image_at(k as u64, n(args.get(1)).unwrap_or(0.0) as f32, n(args.get(2)).unwrap_or(0.0) as f32),
            Some(k) if k >= 65536.0 => engine::cursor_image(k as u64),
            Some(k) if args.len() == 1 => engine::cursor_kind(k as u32),
            _ => processing::show_cursor(),
        }
        Ok(())
    })?)?;

    g.set("noCursor", lua.create_function(|_, ()| {
        processing::hide_cursor(); Ok(())
    })?)?;

    // exit() — close the sketch window cleanly
    g.set("exit", lua.create_function(|_, ()| {
        processing::exit(); Ok(())
    })?)?;

    // print: Lua's own goes through C stdio, which is fully buffered when
    // stdout is a pipe (as it is under the IDE), so output would show up in
    // chunks or only at exit. Same formatting as Lua's print (tostring on each
    // argument, tab-separated), but written and flushed a line at a time.
    // println is an alias (see prelude.lua).
    g.set("print", lua.create_function(|lua, args: LuaMultiValue| {
        let tostring: LuaFunction = lua.globals().get("tostring")?;
        let mut line: Vec<u8> = Vec::new();
        for (i, v) in args.into_iter().enumerate() {
            if i > 0 { line.push(b'\t'); }
            // bytes, not String: a Lua string doesn't have to be valid UTF-8
            line.extend_from_slice(tostring.call::<_, LuaString>(v)?.as_bytes());
        }
        line.push(b'\n');
        let mut out = std::io::stdout().lock();
        if out.write_all(&line).and_then(|_| out.flush()).is_err() {
            // Nobody is reading any more: the IDE that started us is gone.
            processing::exit_with(0);
        }
        Ok(())
    })?)?;

    // ── Image ─────────────────────────────────────────────────────────────
    // Images are opaque handles (u64 IDs returned by processing::load_image).
    // We store them as Lua integers.
    g.set("loadImage", lua.create_function(|_, path: LuaString| {
        Ok(processing::load_image(&path.to_string_lossy()) as i64)
    })?)?;

    g.set("image", lua.create_function(|_, (id, x, y, w, h): (i64, f32, f32, Option<f32>, Option<f32>)| {
        match (w, h) {
            (Some(w), Some(h)) => processing::image_sized(id as u64, x, y, w, h),
            _                  => processing::image(id as u64, x, y),
        }
        Ok(())
    })?)?;

    // Movie and Capture: prelude.lua wraps these handles into objects
    g.set("__movieNew", lua.create_function(|_, path: LuaString| {
        let m = engine::Movie::new(&path.to_string_lossy());
        let (img, w, h) = (m.image(), m.width(), m.height());
        Ok((video_add(Video::M(m)), img as i64, w as f64, h as f64))
    })?)?;
    g.set("__captureNew", lua.create_function(|_, (w, h, name, fps): (f32, f32, Option<LuaString>, Option<f32>)| {
        let name = name.map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let c = match fps { Some(f) => engine::Capture::with_fps(w, h, &name, f), None => engine::Capture::with_device(w, h, &name) };
        let img = c.image();
        Ok((video_add(Video::C(c)), img as i64))
    })?)?;
    g.set("__captureList", lua.create_function(|_, ()| Ok(engine::capture_list()))?)?;
    g.set("__video", lua.create_function(|_, (h, op, arg): (i64, LuaString, Option<f32>)| {
        let op = op.to_string_lossy();
        VIDEOS.with(|v| {
            let mut v = v.borrow_mut();
            let Some(Some(item)) = v.get_mut(h as usize) else { return Ok(LuaValue::Nil) };
            let x = arg.unwrap_or(0.0);
            Ok(match item {
                Video::M(m) => match op.as_ref() {
                    "play" => { m.play(); LuaValue::Nil }
                    "loop" => { m.loop_(); LuaValue::Nil }
                    "noLoop" => { m.no_loop(); LuaValue::Nil }
                    "pause" => { m.pause(); LuaValue::Nil }
                    "stop" => { m.stop(); LuaValue::Nil }
                    "jump" => { m.jump(x); LuaValue::Nil }
                    "speed" => { m.speed(x); LuaValue::Nil }
                    "time" => LuaValue::Number(m.time() as f64),
                    "duration" => LuaValue::Number(m.duration() as f64),
                    "frameRate" => LuaValue::Number(m.frame_rate() as f64),
                    "isPlaying" => LuaValue::Boolean(m.is_playing()),
                    "available" => LuaValue::Boolean(m.available()),
                    "read" => { m.read(); LuaValue::Nil }
                    _ => LuaValue::Nil,
                },
                Video::C(c) => match op.as_ref() {
                    "start" => { c.start(); LuaValue::Nil }
                    "stop" => { c.stop(); LuaValue::Nil }
                    "available" => LuaValue::Boolean(c.available()),
                    "read" => { c.read(); LuaValue::Nil }
                    _ => LuaValue::Nil,
                },
            })
        })
    })?)?;

    // curvePoint / curveTangent, with the engine's curveTightness
    g.set("__curve", lua.create_function(|_, (a, b, c, d, t, tangent): (f32, f32, f32, f32, f32, i32)| {
        Ok(if tangent == 1 { engine::curve_tangent(a, b, c, d, t) } else { engine::curve_point(a, b, c, d, t) } as f64)
    })?)?;
    // match / matchAll with regular expressions, like Processing (Lua's own
    // string.match takes Lua patterns)
    g.set("match", lua.create_function(|lua, (text, pat): (LuaString, LuaString)| {
        match engine::match_re(&text.to_string_lossy(), &pat.to_string_lossy()) {
            Some(v) => Ok(LuaValue::Table(lua.create_sequence_from(v)?)),
            None => Ok(LuaValue::Nil),
        }
    })?)?;
    g.set("matchAll", lua.create_function(|lua, (text, pat): (LuaString, LuaString)| {
        let all = engine::match_all(&text.to_string_lossy(), &pat.to_string_lossy());
        if all.is_empty() { return Ok(LuaValue::Nil); }
        let t = lua.create_table()?;
        for (i, m) in all.into_iter().enumerate() { t.set(i + 1, lua.create_sequence_from(m)?)?; }
        Ok(LuaValue::Table(t))
    })?)?;
    // file dialogs: wait for the choice, then call back like Processing
    for (name, kind) in [("__selectInput", 0), ("__selectOutput", 1), ("__selectFolder", 2)] {
        g.set(name, lua.create_function(move |_, prompt: Option<LuaString>| {
            let p = prompt.map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
            Ok(match kind { 0 => engine::select_input(&p), 1 => engine::select_output(&p), _ => engine::select_folder(&p) })
        })?)?;
    }
    // XML: parsed in Rust, handed to Lua as nested tables (prelude.lua wraps them)
    fn xml_to_lua<'l>(lua: &'l Lua, x: &engine::Xml) -> LuaResult<LuaTable<'l>> {
        let t = lua.create_table()?;
        t.set("name", x.get_name())?;
        let attrs = lua.create_table()?;
        let order = lua.create_table()?;
        for (i, k) in x.list_attributes().into_iter().enumerate() { attrs.set(k.as_str(), x.get_string(&k))?; order.set(i + 1, k)?; }
        t.set("attrs", attrs)?;
        t.set("order", order)?;
        t.set("content", x.get_content())?;
        let kids = lua.create_table()?;
        for (i, c) in x.get_children("").into_iter().enumerate() { kids.set(i + 1, xml_to_lua(lua, &c)?)?; }
        t.set("children", kids)?;
        Ok(t)
    }
    g.set("__parseXML", lua.create_function(|lua, text: LuaString| {
        match engine::parse_xml(&text.to_string_lossy()) {
            Ok(x) => Ok((LuaValue::Table(xml_to_lua(lua, &x)?), LuaValue::Nil)),
            Err(e) => Ok((LuaValue::Nil, LuaValue::String(lua.create_string(&e)?))),
        }
    })?)?;

    // loadShape: prelude.lua wraps these into an object with width, height,
    // disableStyle() and enableStyle()
    g.set("__loadShape", lua.create_function(|_, path: LuaString| {
        let id = processing::load_shape(&path.to_string_lossy());
        let (w, h) = processing::shape_size(id);
        Ok((id as i64, w as f64, h as f64))
    })?)?;
    g.set("__shape", lua.create_function(|_, (id, x, y, w, h): (i64, Option<f32>, Option<f32>, Option<f32>, Option<f32>)| {
        let (x, y) = (x.unwrap_or(0.0), y.unwrap_or(0.0));
        match (w, h) {
            (Some(w), Some(h)) => processing::shape_sized(id as u64, x, y, w, h),
            _                  => processing::shape(id as u64, x, y),
        }
        Ok(())
    })?)?;
    g.set("__shapeStyle", lua.create_function(|_, (id, on): (i64, bool)| {
        processing::shape_own_style(id as u64, on); Ok(())
    })?)?;
    // getChild(name or index), getChildCount(), getVertex(i): parts of a loaded SVG
    g.set("__shapeChild", lua.create_function(|_, (id, key): (i64, LuaValue)| {
        use engine::LoadedShapeExt;
        let id = id as u64;
        let child = match key {
            LuaValue::String(s) => { let k = s.to_string_lossy().to_string(); id.get_child(k.as_str()) }
            LuaValue::Integer(i) => id.get_child(i.max(0) as usize),
            LuaValue::Number(n) => id.get_child(n.max(0.0) as usize),
            _ => 0,
        };
        let (w, h) = processing::shape_size(child);
        Ok((child as i64, w as f64, h as f64))
    })?)?;
    g.set("__shapeChildCount", lua.create_function(|_, id: i64| {
        use engine::LoadedShapeExt;
        Ok((id as u64).get_child_count() as i64)
    })?)?;
    g.set("__shapePoints", lua.create_function(|lua, id: i64| {
        let t = lua.create_table()?;
        use engine::LoadedShapeExt;
        let id = id as u64;
        for i in 0..id.get_vertex_count() {
            let v = id.get_vertex(i);
            let p = lua.create_table()?;
            p.set("x", v.x)?; p.set("y", v.y)?;
            t.set(i + 1, p)?;
        }
        Ok(t)
    })?)?;
    // PFont.list(): installed fonts by name
    g.set("__fontList", lua.create_function(|lua, ()| {
        let t = lua.create_table()?;
        for (i, n) in engine::PFont::list().into_iter().enumerate() { t.set(i + 1, n)?; }
        Ok(t)
    })?)?;

    // createGraphics: the Lua side (prelude.lua) wraps these into an object
    // with beginDraw / endDraw and hands image() the right one.
    g.set("__createGraphics", lua.create_function(|_, (w, h): (LuaValue, LuaValue)| {
        let dim = |v: &LuaValue| -> LuaResult<u32> {
            let n = num(v, "createGraphics()")?;
            if !n.is_finite() || n < 1.0 {
                return Err(LuaError::RuntimeError("createGraphics() needs a width and height of at least 1".into()));
            }
            Ok((n.round() as u32).min(8192))
        };
        let (w, h) = (dim(&w)?, dim(&h)?);
        Ok((processing::create_graphics(w, h) as i64, w as i64, h as i64))
    })?)?;
    g.set("__beginGraphics", lua.create_function(|lua, id: i64| {
        if processing::begin_graphics(id as u64) {
            // width and height describe what is being drawn on
            let (w, h) = processing::target_size();
            let g = lua.globals();
            g.raw_set("width",  w as i64)?;
            g.raw_set("height", h as i64)?;
            Ok(true)
        } else { Ok(false) }
    })?)?;
    g.set("__endGraphics", lua.create_function(|lua, ()| {
        processing::end_graphics();
        let (w, h) = processing::target_size();
        let g = lua.globals();
        g.raw_set("width",  w as i64)?;
        g.raw_set("height", h as i64)?;
        Ok(())
    })?)?;
    g.set("__imageGraphics", lua.create_function(|_, (id, x, y, w, h): (i64, f32, f32, Option<f32>, Option<f32>)| {
        match (w, h) {
            (Some(w), Some(h)) => processing::graphics_image_sized(id as u64, x, y, w, h),
            _                  => processing::graphics_image(id as u64, x, y),
        }
        Ok(())
    })?)?;
    g.set("clear", lua.create_function(|_, ()| { processing::clear(); Ok(()) })?)?;

    g.set("imageMode", lua.create_function(|_, m: i32| { processing::image_mode(m); Ok(()) })?)?;
    g.set("imageWidth", lua.create_function(|_, id: i64| Ok(processing::image_size(id as u64).0 as i64))?)?;
    g.set("imageHeight", lua.create_function(|_, id: i64| Ok(processing::image_size(id as u64).1 as i64))?)?;

    g.set("tint", lua.create_function(|_, args: LuaMultiValue| {
        let c = unpack_color(args);
        processing::tint(c[0], c[1], c[2], c[3]); Ok(())
    })?)?;

    g.set("noTint", lua.create_function(|_, ()| { processing::no_tint(); Ok(()) })?)?;

    // get(x, y) returns the pixel's red, green and blue (0..255)
    g.set("get", lua.create_function(|_, (x, y, w, h): (f64, f64, Option<f64>, Option<f64>)| {
        // get(x, y, w, h): a piece of the canvas as a new image
        if let (Some(w), Some(h)) = (w, h) {
            let id = processing::get_region(x.floor() as i32, y.floor() as i32, w.max(0.0) as u32, h.max(0.0) as u32);
            return Ok(LuaMultiValue::from_vec(vec![LuaValue::Integer(id as i64)]));
        }
        let (r, g, b) = processing::get_pixel(x.floor() as i32, y.floor() as i32);
        Ok(LuaMultiValue::from_vec(vec![LuaValue::Integer(r as i64), LuaValue::Integer(g as i64), LuaValue::Integer(b as i64)]))
    })?)?;

    // Image editing. Images are the numbers loadImage() and createImage() return.
    g.set("createImage", lua.create_function(|_, (w, h): (f64, f64)| {
        Ok(processing::create_image(w.max(0.0) as u32, h.max(0.0) as u32) as i64)
    })?)?;
    // imageGet(img, x, y) -> color; imageGet(img, x, y, w, h) -> a new image
    g.set("imageGet", lua.create_function(|_, (id, x, y, w, h): (i64, f64, f64, Option<f64>, Option<f64>)| {
        let (x, y) = (x.floor() as i32, y.floor() as i32);
        if let (Some(w), Some(h)) = (w, h) {
            return Ok(processing::image_crop(id as u64, x, y, w.max(0.0) as u32, h.max(0.0) as u32) as i64);
        }
        Ok(pack_color(processing::image_get(id as u64, x, y)))
    })?)?;
    g.set("imageSet", lua.create_function(|_, (id, x, y, c): (i64, f64, f64, LuaValue)| {
        processing::image_set(id as u64, x.floor() as i32, y.floor() as i32, color_arg(&c));
        Ok(())
    })?)?;
    // imagePixels(img) -> a list of colors, row by row, from 1;
    // imageSetPixels(img, list) writes them back.
    g.set("imagePixels", lua.create_function(|lua, id: i64| {
        let px = processing::image_pixels(id as u64);
        let t = lua.create_table_with_capacity(px.len(), 0)?;
        for (i, c) in px.iter().enumerate() { t.raw_set(i as i64 + 1, pack_color(*c))?; }
        Ok(t)
    })?)?;
    g.set("imageSetPixels", lua.create_function(|_, (id, t): (i64, LuaTable)| {
        let mut px = Vec::with_capacity(t.raw_len());
        // Whole numbers here are always colors, so transparent pixels survive the round trip.
        for v in t.sequence_values::<LuaValue>() {
            let v = v?;
            px.push(match v { LuaValue::Integer(n) => unpack_packed(n), other => color_arg(&other) });
        }
        processing::image_set_pixels(id as u64, &px);
        Ok(())
    })?)?;
    g.set("imageCopy", lua.create_function(|_, id: i64| Ok(processing::image_copy(id as u64) as i64))?)?;
    g.set("imageResize", lua.create_function(|_, (id, w, h): (i64, f64, Option<f64>)| {
        processing::image_resize(id as u64, w.max(0.0) as u32, h.unwrap_or(0.0).max(0.0) as u32);
        Ok(())
    })?)?;
    g.set("imageMask", lua.create_function(|_, (id, m): (i64, i64)| Ok(processing::image_mask(id as u64, m as u64)))?)?;
    g.set("saveImage", lua.create_function(|_, (id, path): (i64, LuaString)| {
        Ok(processing::save_image(id as u64, &path.to_string_lossy()))
    })?)?;

    // loadPixels() fills the global `pixels` with one color() value per
    // pixel; the pixel at (x, y) is pixels[y * width + x], counting from 0 as
    // in Processing. Change entries, then updatePixels() to show them.
    g.set("loadPixels", lua.create_function(|lua, ()| {
        let px = processing::load_pixels();
        let t = match lua.globals().raw_get::<_, LuaValue>("pixels")? {
            LuaValue::Table(t) if t.raw_len() + 1 == px.len() => t,   // reuse: same size as last time
            _ => lua.create_table_with_capacity(px.len(), 1)?,
        };
        for (i, p) in px.iter().enumerate() { t.raw_set(i as i64, *p as i64)?; }
        lua.globals().raw_set("pixels", t)
    })?)?;
    g.set("updatePixels", lua.create_function(|lua, ()| {
        let t = match lua.globals().raw_get::<_, LuaValue>("pixels")? {
            LuaValue::Table(t) => t,
            _ => return Err(LuaError::RuntimeError("updatePixels() needs loadPixels() first".into())),
        };
        let mut px = processing::load_pixels();
        for (i, p) in px.iter_mut().enumerate() {
            match t.raw_get::<_, LuaValue>(i as i64)? {
                LuaValue::Integer(n) => *p = if is_packed(n) { n as u32 } else { gray_pixel(n as f32) },
                LuaValue::Number(n)  => *p = gray_pixel(n as f32),
                _ => {}   // nil or anything else: that pixel stays as it is
            }
        }
        processing::update_pixels(&px);
        Ok(())
    })?)?;

    // set(x, y, color) or set(x, y, r, g, b): one pixel, ignores transforms
    g.set("set", lua.create_function(|_, args: LuaMultiValue| {
        let mut it = args.into_iter();
        let (x, y) = (it.next(), it.next());
        let (Some(x), Some(y)) = (x, y) else {
            return Err(LuaError::RuntimeError("set() expects x, y and a color".into()));
        };
        let (x, y) = (num(&x, "set()")?, num(&y, "set()")?);
        let c = unpack_color(it.collect());
        if x.is_finite() && y.is_finite() {
            processing::set_pixel(x.floor() as i32, y.floor() as i32, c[0], c[1], c[2]);
        }
        Ok(())
    })?)?;

    g.set("saveFrame", lua.create_function(|_, name: Option<String>| {
        processing::save_frame(&name.unwrap_or_else(|| "screen-####.png".into())); Ok(())
    })?)?;

    Ok(())
}

// ── Color unpacking ───────────────────────────────────────────────────────
//
// Processing color calls accept multiple arities:
//   background(v)           → grey
//   background(v, a)        → grey + alpha
//   background(r, g, b)     → rgb
//   background(r, g, b, a)  → rgba
//
// The values are interpreted in the current colorMode (RGB or HSB, with
// per-channel ranges) and come back as RGBA in 0..255.

fn unpack_color(args: LuaMultiValue) -> [f32; 4] {
    // fill(c) and fill(c, alpha) with c made by color()
    if args.len() == 1 || args.len() == 2 {
        if let Some(LuaValue::Integer(n)) = args.iter().next() {
            if is_packed(*n) {
                let mut c = unpack_packed(*n);
                if let Some(a) = args.iter().nth(1).and_then(|v| v.to_num()) {
                    c[3] = (a / processing::color_max(3)).clamp(0.0, 1.0) * 255.0;
                }
                return c;
            }
        }
    }
    let vals: Vec<f32> = args.iter().filter_map(|v| v.to_num()).collect();
    processing::resolve_color(&vals)
}

// A color from color() is one integer, 0xAARRGGBB, like Processing's. Small
// integers stay what they always were: fill(255) is white, not blue. (Same
// rule as Processing: a color with alpha 0 can't be told from a gray.)
/// pixels[i] = 128 means gray, as with fill(128).
fn gray_pixel(v: f32) -> u32 {
    let c = processing::resolve_color(&[v]);
    pack_color(c) as u32
}
fn is_packed(n: i64) -> bool { n > 0x00FF_FFFF || n < 0 }
fn unpack_packed(n: i64) -> [f32; 4] {
    let n = n as u32;
    [((n >> 16) & 0xFF) as f32, ((n >> 8) & 0xFF) as f32, (n & 0xFF) as f32, ((n >> 24) & 0xFF) as f32]
}
fn pack_color(c: [f32; 4]) -> i64 {
    let ch = |v: f32| (v.round().clamp(0.0, 255.0)) as i64;
    let n = (ch(c[3]) << 24) | (ch(c[0]) << 16) | (ch(c[1]) << 8) | ch(c[2]);
    // Fully transparent colors would look like small plain numbers (grays);
    // bit 32 marks them as colors. unpack_packed drops it again.
    if ch(c[3]) == 0 { n | (1 << 32) } else { n }
}
/// One value as a color: a packed color, or a gray in the current colorMode.
fn color_arg(v: &LuaValue) -> [f32; 4] {
    match v {
        LuaValue::Integer(n) if is_packed(*n) => unpack_packed(*n),
        other => processing::resolve_color(&[other.to_num().unwrap_or(0.0)]),
    }
}

// ── LuaValue helper ───────────────────────────────────────────────────────

/// Lua 5.4 numbers are either Integer or Number. mlua 0.9 has its own
/// `as_f32` that only accepts Number, so this is deliberately named `to_num`.
trait AsF32 {
    fn to_num(&self) -> Option<f32>;
}

impl AsF32 for LuaValue<'_> {
    fn to_num(&self) -> Option<f32> {
        match self {
            LuaValue::Number(n)  => Some(*n as f32),
            LuaValue::Integer(n) => Some(*n as f32),
            _                    => None,
        }
    }
}

// ── Movie and Capture handles ────────────────────────────────────────────
enum Video { M(engine::Movie), C(engine::Capture) }
thread_local! { static VIDEOS: std::cell::RefCell<Vec<Option<Video>>> = const { std::cell::RefCell::new(Vec::new()) }; }
fn video_add(v: Video) -> i64 {
    VIDEOS.with(|all| { let mut all = all.borrow_mut(); all.push(Some(v)); all.len() as i64 - 1 })
}

thread_local! { static SHADERS: std::cell::RefCell<Vec<engine::PShader>> = const { std::cell::RefCell::new(Vec::new()) }; }
