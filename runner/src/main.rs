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
mod processing;
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
        std::process::exit(70);
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

    let sketch_path: PathBuf = env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            eprintln!("usage: luamode-runner <sketch.lua>");
            std::process::exit(2);
        });

    // Not read_to_string: one stray byte (a Latin-1 comment, say) shouldn't
    // stop the sketch from running. Lua strings are bytes anyway.
    let sketch_src = fs::read(&sketch_path).unwrap_or_else(|e| {
        eprintln!("{}: {}", sketch_path.display(), e);
        std::process::exit(2);
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

    if let Err(e) = register_globals(&lua).and_then(|_| lua.load(PRELUDE).set_name("=luamode").exec()) {
        eprintln!("luamode-runner internal error: {}", e);
        std::process::exit(70);
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
        .mouse_released(|s| event(s, &["mouseReleased", "mouseClicked"]))
        .mouse_moved(|s| event(s, &["mouseMoved"]))
        .mouse_dragged(|s| event(s, &["mouseDragged"]))
        .mouse_wheel(|s, delta| {
            sync_frame_globals(&s.lua);
            call_with(s, "mouseWheel", delta as f64);
        })
        .key_pressed(|s| event(s, &["keyPressed"]))
        .key_released(|s| event(s, &["keyReleased"]))
        .key_typed(|s| event(s, &["keyTyped"]))
        .run();
}

// ── App callbacks ─────────────────────────────────────────────────────────

fn setup_fn(s: &mut RunnerState) {
    call_with(s, "setup", ());
}

fn draw_fn(s: &mut RunnerState) {
    sync_frame_globals(&s.lua);
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
    std::process::exit(1);
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
    g.set("size", lua.create_function(|lua, (w, h): (LuaValue, LuaValue)| {
        let dim = |v: &LuaValue| -> LuaResult<u32> {
            let n = num(v, "size()")?;
            if !n.is_finite() || n < 1.0 {
                return Err(LuaError::RuntimeError("size() needs a width and height of at least 1".into()));
            }
            Ok((n.round() as u32).min(8192))
        };
        let (w, h) = (dim(&w)?, dim(&h)?);
        processing::size(w, h);
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
    g.set("BASELINE", processing::BASELINE)?;
    g.set("CORNER",   processing::CORNER)?;
    g.set("CORNERS",  processing::CORNERS)?;
    g.set("RADIUS",   processing::RADIUS)?;
    g.set("OPEN",    0_i32)?;
    g.set("CLOSE",   1_i32)?;
    g.set("PIE",     0_i32)?;
    g.set("CHORD",   0_i32)?;
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
    g.set("ROUND",   0_i32)?;
    g.set("SQUARE",  1_i32)?;
    g.set("PROJECT", 2_i32)?;
    g.set("MITER",   3_i32)?;
    g.set("BEVEL",   4_i32)?;
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

    g.set("lerpColor", lua.create_function(|_, (r1,g1,b1, r2,g2,b2, t): (f32,f32,f32,f32,f32,f32,f32)| {
        let (r,g,b) = processing::lerp_color(r1,g1,b1, r2,g2,b2, t);
        // Return as table {r,g,b}
        Ok(LuaMultiValue::from_vec(vec![
            LuaValue::Number(r as f64),
            LuaValue::Number(g as f64),
            LuaValue::Number(b as f64),
        ]))
    })?)?;

    // ── Shapes ────────────────────────────────────────────────────────────
    g.set("rect", lua.create_function(|_, (x,y,w,h,r): (f32,f32,f32,f32,Option<f32>)| {
        match r {
            Some(r) if r > 0.0 => processing::rect_rounded(x,y,w,h,r),
            _                  => processing::rect(x,y,w,h),
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

    g.set("line", lua.create_function(|_, (x1,y1,x2,y2): (f32,f32,f32,f32)| {
        processing::line(x1,y1,x2,y2); Ok(())
    })?)?;

    g.set("point", lua.create_function(|_, (x,y): (f32,f32)| {
        processing::point(x,y); Ok(())
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

    g.set("vertex", lua.create_function(|_, (x,y): (f32,f32)| {
        processing::vertex(x,y); Ok(())
    })?)?;

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
    g.set("pushMatrix", lua.create_function(|_, ()| { processing::push_matrix(); Ok(()) })?)?;
    g.set("popMatrix",  lua.create_function(|_, ()| { processing::pop_matrix();  Ok(()) })?)?;
    g.set("pushStyle",  lua.create_function(|_, ()| { processing::push_style();  Ok(()) })?)?;
    g.set("popStyle",   lua.create_function(|_, ()| { processing::pop_style();   Ok(()) })?)?;

    g.set("translate", lua.create_function(|_, (x,y): (f32,f32)| {
        processing::translate(x,y); Ok(())
    })?)?;

    g.set("rotate", lua.create_function(|_, angle: f32| {
        processing::rotate(angle); Ok(())
    })?)?;

    g.set("scale", lua.create_function(|_, args: LuaMultiValue| {
        let vals: Vec<f32> = args.iter()
            .filter_map(|v| v.to_num())
            .collect();
        match vals.len() {
            0 => return Err(LuaError::RuntimeError("scale() expects one or two numbers".into())),
            1 => processing::scale_uniform(vals[0]),
            _ => processing::scale(vals[0], vals[1]),
        }
        Ok(())
    })?)?;

    g.set("resetMatrix", lua.create_function(|_, ()| {
        processing::reset_matrix(); Ok(())
    })?)?;

    // ── Text ──────────────────────────────────────────────────────────────
    // text(anything, x, y): numbers, booleans and nil are shown the way
    // print() would show them
    g.set("text", lua.create_function(|lua, (v, x, y): (LuaValue, f32, f32)| {
        let s = match &v {
            LuaValue::String(s) => s.to_string_lossy().into_owned(),
            other => lua.globals().get::<_, LuaFunction>("tostring")?.call::<_, String>(other.clone())?,
        };
        processing::text(&s, x, y); Ok(())
    })?)?;

    g.set("textSize", lua.create_function(|_, sz: f32| {
        processing::text_size(sz); Ok(())
    })?)?;

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
    g.set("cursor", lua.create_function(|_, ()| {
        processing::show_cursor(); Ok(())
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
            std::process::exit(0);
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

    g.set("tint", lua.create_function(|_, args: LuaMultiValue| {
        let c = unpack_color(args);
        processing::tint(c[0], c[1], c[2], c[3]); Ok(())
    })?)?;

    g.set("noTint", lua.create_function(|_, ()| { processing::no_tint(); Ok(()) })?)?;

    // get(x, y) returns the pixel's red, green and blue (0..255)
    g.set("get", lua.create_function(|_, (x, y): (f64, f64)| {
        let (r, g, b) = processing::get_pixel(x.floor() as i32, y.floor() as i32);
        Ok((r as i64, g as i64, b as i64))
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
    let vals: Vec<f32> = args.iter().filter_map(|v| v.to_num()).collect();
    processing::resolve_color(&vals)
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
