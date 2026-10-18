//! Adapter between the Lua bindings in main.rs and RustMode's engine.
//!
//! The Lua side uses Processing's own constant values where one name serves
//! several jobs (LEFT is a key code, a mouse button and a text alignment), and
//! a few calls have different arities than the engine's Rust-facing API.
//! Everything is translated here so the bindings stay readable and the engine
//! stays Processing-shaped for RustMode.

use std::sync::atomic::{AtomicI32, AtomicU32, Ordering};

// Constants as the Lua globals define them (Processing's values).
pub const LEFT: i32 = 37;
pub const RIGHT: i32 = 39;
pub const CENTER: i32 = 3;
pub const TOP: i32 = 101;
pub const BOTTOM: i32 = 102;
pub const BASELINE: i32 = 0;
pub const CORNER: i32 = 0;
pub const CORNERS: i32 = 1;
pub const RADIUS: i32 = 2;

pub use engine::App;

// ── Input ─────────────────────────────────────────────────────────────────

pub fn mouse_x() -> f32  { engine::mouse_x() }
pub fn mouse_y() -> f32  { engine::mouse_y() }
pub fn pmouse_x() -> f32 { engine::pmouse_x() }
pub fn pmouse_y() -> f32 { engine::pmouse_y() }
pub fn mouse_is_pressed() -> bool { engine::mouse_pressed_global() }
pub fn key_is_pressed() -> bool   { engine::key_pressed_global() }
pub fn key_char() -> char         { engine::key() }

/// The button that was pressed last: LEFT 37, RIGHT 39, CENTER 3 (0 before
/// the first press). It stays set in mouseReleased() and mouseClicked(), so
/// those can tell which button it was.
pub fn mouse_button() -> i32 { engine::mouse_button() as i32 }

/// Keys with no character of their own (arrows, modifiers). Processing sets
/// `key` to CODED for these and the sketch reads `keyCode` instead.
pub fn key_is_coded() -> bool {
    let k = engine::key_code();
    [engine::UP, engine::DOWN, engine::LEFT, engine::RIGHT, engine::SHIFT, engine::CONTROL,
     engine::HOME, engine::END, engine::PAGE_UP, engine::PAGE_DOWN].contains(&k)
        || (engine::F1..=engine::F12).contains(&k)
}

/// Translate the engine's key codes (minifb) to the Processing / Java codes
/// the Lua constants use (UP 38, DOWN 40, ENTER 10, ...). Printable keys
/// report their character code, like Processing.
pub fn key_code() -> u32 {
    let k = engine::key_code();
    match k {
        k if k == engine::UP        => 38,
        k if k == engine::DOWN      => 40,
        k if k == engine::LEFT      => 37,
        k if k == engine::RIGHT     => 39,
        k if k == engine::ENTER     => 10,
        k if k == engine::BACKSPACE => 8,
        k if k == engine::DELETE    => 127,
        k if k == engine::ESCAPE    => 27,
        k if k == engine::TAB       => 9,
        k if k == engine::SHIFT     => 16,
        k if k == engine::CONTROL   => 17,
        0 => 0,
        // letters report the uppercase code, like Java's key codes ('a' is 65)
        _ => engine::key().to_ascii_uppercase() as u32,
    }
}

// ── Environment ───────────────────────────────────────────────────────────

pub fn size(w: u32, h: u32)  { engine::size(w, h) }
pub fn window_title(t: &str) { engine::window_title(t) }
pub fn window_resizable(on: bool) { engine::window_resizable(on) }
pub fn present(w: usize, h: usize, x: isize, y: isize) { engine::present(w, h, x, y) }
pub fn smooth(on: bool)      { if on { engine::smooth() } else { engine::no_smooth() } }
pub fn width() -> f32        { engine::width() }
pub fn height() -> f32       { engine::height() }
pub fn frame_count() -> u64  { engine::frame_count() }
pub fn frame_rate() -> f32   { engine::current_frame_rate() }
/// Sets the target and returns what the engine made of it (clamped).
pub fn set_frame_rate(fps: f32) -> f32 { engine::frame_rate(fps); engine::current_frame_rate() }
pub fn millis() -> u64       { engine::millis() }
pub fn set_loop(on: bool)    { if on { engine::r#loop() } else { engine::no_loop() } }
pub fn redraw()              { engine::redraw() }
pub fn exit()                { engine::exit() }
pub fn exit_with(code: i32) -> ! { engine::exit_with(code) }
pub fn show_cursor()         { engine::cursor() }
pub fn hide_cursor()         { engine::no_cursor() }

// ── Color ─────────────────────────────────────────────────────────────────
//
// main.rs's unpack_color() calls resolve_color() on the raw arguments, so
// background/fill/stroke/tint below already receive RGBA in 0..255.

const RGB: u32 = 1;
const HSB: u32 = 3;
static COLOR_MODE: AtomicU32 = AtomicU32::new(RGB);
// per-channel maxima as f32 bits: [c1, c2, c3, alpha], default 255 each
static COLOR_MAX: [AtomicU32; 4] = [
    AtomicU32::new(0x437f0000), AtomicU32::new(0x437f0000),
    AtomicU32::new(0x437f0000), AtomicU32::new(0x437f0000),
];

/// Processing semantics: colorMode(m) keeps the ranges, colorMode(m, max)
/// sets all four, colorMode(m, a, b, c) sets the three color channels and
/// keeps alpha, colorMode(m, a, b, c, d) sets all four.
pub fn color_mode(mode: i32, maxes: &[f32]) {
    COLOR_MODE.store(if mode == HSB as i32 { HSB } else { RGB }, Ordering::Relaxed);
    let set = |i: usize, v: f32| COLOR_MAX[i].store(if v > 0.0 { v } else { 255.0 }.to_bits(), Ordering::Relaxed);
    match maxes.len() {
        0 => {}
        1 | 2 => for i in 0..4 { set(i, maxes[0]) },
        3 => for i in 0..3 { set(i, maxes[i]) },
        _ => for i in 0..4 { set(i, maxes[i]) },
    }
}

/// Turn the raw numbers from background()/fill()/stroke()/tint() into RGBA
/// 0..255, honouring colorMode:
///   (v) gray (brightness in HSB) · (v, a) gray + alpha
///   (c1, c2, c3) · (c1, c2, c3, a)
pub fn resolve_color(v: &[f32]) -> [f32; 4] {
    let m = |i: usize| f32::from_bits(COLOR_MAX[i].load(Ordering::Relaxed));
    let unit = |x: f32, i: usize| (x / m(i)).clamp(0.0, 1.0);
    let hsb = COLOR_MODE.load(Ordering::Relaxed) == HSB;
    let (rgb, alpha) = match v.len() {
        0 => ((0.0, 0.0, 0.0), 1.0),
        1 | 2 => {
            // a lone value is gray: in HSB that's brightness, in RGB all three
            let g = unit(v[0], if hsb { 2 } else { 0 });
            ((g, g, g), if v.len() == 2 { unit(v[1], 3) } else { 1.0 })
        }
        n => {
            let (a, b, c) = (unit(v[0], 0), unit(v[1], 1), unit(v[2], 2));
            (if hsb { hsb_to_rgb(a, b, c) } else { (a, b, c) },
             if n >= 4 { unit(v[3], 3) } else { 1.0 })
        }
    };
    [rgb.0 * 255.0, rgb.1 * 255.0, rgb.2 * 255.0, alpha * 255.0]
}

/// (hue, saturation, brightness), each 0..1, of an r, g, b in 0..1.
pub fn rgb_to_hsb(r: f32, g: f32, b: f32) -> (f32, f32, f32) {
    let (max, min) = (r.max(g).max(b), r.min(g).min(b));
    let d = max - min;
    let s = if max > 0.0 { d / max } else { 0.0 };
    let h = if d <= 0.0 { 0.0 }
        else if max == r { ((g - b) / d).rem_euclid(6.0) }
        else if max == g { (b - r) / d + 2.0 }
        else { (r - g) / d + 4.0 };
    (h / 6.0, s, max)
}
/// Channel maximum set by colorMode(): 0, 1, 2 for the three channels, 3 for alpha.
pub fn color_max(i: usize) -> f32 { f32::from_bits(COLOR_MAX[i.min(3)].load(Ordering::Relaxed)) }
pub fn is_hsb() -> bool { COLOR_MODE.load(Ordering::Relaxed) == HSB }

fn hsb_to_rgb(h: f32, s: f32, v: f32) -> (f32, f32, f32) {
    let h = (h.fract() + 1.0).fract() * 6.0;
    let i = h.floor();
    let f = h - i;
    let (p, q, t) = (v * (1.0 - s), v * (1.0 - s * f), v * (1.0 - s * (1.0 - f)));
    match i as i32 {
        0 => (v, t, p), 1 => (q, v, p), 2 => (p, v, t),
        3 => (p, q, v), 4 => (t, p, v), _ => (v, p, q),
    }
}

pub fn background(r: f32, g: f32, b: f32, a: f32) { engine::background_rgba(r, g, b, a) }
pub fn fill(r: f32, g: f32, b: f32, a: f32) { engine::fill_rgba(r, g, b, a) }
pub fn stroke(r: f32, g: f32, b: f32, a: f32) { engine::stroke_rgba(r, g, b, a) }
pub fn tint(r: f32, g: f32, b: f32, a: f32) { engine::tint_rgba(r, g, b, a) }
pub fn no_fill()   { engine::no_fill() }
pub fn no_stroke() { engine::no_stroke() }
pub fn no_tint()   { engine::no_tint() }
pub fn stroke_weight(w: f32) { engine::stroke_weight(w) }
pub fn stroke_cap(cap: i32)   { engine::stroke_cap(cap.max(0) as u32) }
pub fn stroke_join(join: i32) { engine::stroke_join(join.max(0) as u32) }
pub fn blend_mode(mode: i32)  { engine::blend_mode(mode.max(0) as u32) }
pub fn image_mode(mode: i32)  { engine::image_mode(mode.max(0) as u32) }
pub fn image_size(id: u64) -> (f32, f32) { (engine::image_width(id), engine::image_height(id)) }
pub fn set_pixel(x: i32, y: i32, r: f32, g: f32, b: f32) { engine::set_pixel(x, y, r, g, b) }
pub fn filter(kind: i32, param: f32) { engine::filter_param(kind.max(0) as u32, param) }
pub fn full_screen() { engine::full_screen() }
pub fn display_size() -> (f32, f32) { (engine::display_width(), engine::display_height()) }
pub fn focused() -> bool { engine::focused() }
pub fn rect_radii(a: f32, b: f32, c: f32, d: f32, tl: f32, tr: f32, br: f32, bl: f32) {
    let (x, y, w, h) = to_corner(RECT_MODE.load(Ordering::Relaxed), a, b, c, d);
    engine::rect_radii(x, y, w, h, tl, tr, br, bl)
}
pub fn load_shape(path: &str) -> u64 { engine::load_shape(path) }
pub fn shape_size(id: u64) -> (f32, f32) { (engine::shape_width(id), engine::shape_height(id)) }
pub fn shape(id: u64, x: f32, y: f32) { engine::shape(id, x, y) }
pub fn shape_sized(id: u64, x: f32, y: f32, w: f32, h: f32) { engine::shape_sized(id, x, y, w, h) }
pub fn shape_own_style(id: u64, on: bool) { if on { engine::shape_enable_style(id) } else { engine::shape_disable_style(id) } }
pub fn create_graphics(w: u32, h: u32) -> u64 { engine::create_graphics(w, h) }
pub fn begin_graphics(id: u64) -> bool { engine::begin_graphics(id) }
pub fn end_graphics() { engine::end_graphics() }
pub fn graphics_image(id: u64, x: f32, y: f32) { engine::graphics_image(id, x, y) }
pub fn graphics_image_sized(id: u64, x: f32, y: f32, w: f32, h: f32) { engine::graphics_image_sized(id, x, y, w, h) }
pub fn clear() { engine::clear() }
pub fn target_size() -> (u32, u32) { engine::target_size() }
pub fn load_pixels() -> Vec<u32> { engine::load_pixels() }
pub fn update_pixels(px: &[u32]) { engine::update_pixels(px) }
pub fn shear_x(a: f32) { engine::shear_x(a) }
pub fn shear_y(a: f32) { engine::shear_y(a) }

pub fn lerp_color(r1: f32, g1: f32, b1: f32, r2: f32, g2: f32, b2: f32, t: f32) -> (f32, f32, f32) {
    let t = t.clamp(0.0, 1.0);
    (r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t)
}

// ── Shapes ────────────────────────────────────────────────────────────────

// rectMode / ellipseMode: the engine draws rects from the corner and ellipses
// from the center, so the four numbers are converted here.
static RECT_MODE: AtomicI32 = AtomicI32::new(CORNER);
static ELLIPSE_MODE: AtomicI32 = AtomicI32::new(CENTER);
pub fn rect_mode(m: i32)    { RECT_MODE.store(m, Ordering::Relaxed) }
pub fn ellipse_mode(m: i32) { ELLIPSE_MODE.store(m, Ordering::Relaxed) }

/// (a, b, c, d) in the given mode to corner x, y, width, height.
fn to_corner(mode: i32, a: f32, b: f32, c: f32, d: f32) -> (f32, f32, f32, f32) {
    match mode {
        CORNERS => (a.min(c), b.min(d), (c - a).abs(), (d - b).abs()),
        CENTER  => (a - c / 2.0, b - d / 2.0, c, d),
        RADIUS  => (a - c, b - d, c * 2.0, d * 2.0),
        _       => (a, b, c, d),
    }
}

pub fn rect(a: f32, b: f32, c: f32, d: f32) {
    let (x, y, w, h) = to_corner(RECT_MODE.load(Ordering::Relaxed), a, b, c, d);
    engine::rect(x, y, w, h)
}
pub fn rect_rounded(a: f32, b: f32, c: f32, d: f32, r: f32) {
    let (x, y, w, h) = to_corner(RECT_MODE.load(Ordering::Relaxed), a, b, c, d);
    engine::rect_rounded(x, y, w, h, r)
}
pub fn ellipse(a: f32, b: f32, c: f32, d: f32) {
    let (x, y, w, h) = to_corner(ELLIPSE_MODE.load(Ordering::Relaxed), a, b, c, d);
    engine::ellipse(x + w / 2.0, y + h / 2.0, w, h)
}
pub fn circle(x: f32, y: f32, d: f32) { ellipse(x, y, d, d) }
pub fn line(x1: f32, y1: f32, x2: f32, y2: f32) { engine::line(x1, y1, x2, y2) }
pub fn point(x: f32, y: f32)                   { engine::point(x, y) }
pub fn triangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) {
    engine::triangle(x1, y1, x2, y2, x3, y3)
}
pub fn quad(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, x4: f32, y4: f32) {
    engine::quad(x1, y1, x2, y2, x3, y3, x4, y4)
}
/// mode: 0 for none given, else OPEN (1), CHORD (2) or PIE (3). Follows ellipseMode().
pub fn arc(a: f32, b: f32, c: f32, d: f32, start: f32, stop: f32, mode: i32) {
    let (x, y, w, h) = to_corner(ELLIPSE_MODE.load(Ordering::Relaxed), a, b, c, d);
    engine::arc_mode(x + w / 2.0, y + h / 2.0, w, h, start, stop, mode.clamp(0, 3) as u32)
}
pub fn bezier(x1: f32, y1: f32, cx1: f32, cy1: f32, cx2: f32, cy2: f32, x2: f32, y2: f32) {
    engine::bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)
}
pub fn curve(cx1: f32, cy1: f32, x1: f32, y1: f32, x2: f32, y2: f32, cx2: f32, cy2: f32) {
    engine::curve(cx1, cy1, x1, y1, x2, y2, cx2, cy2)
}

pub fn quadratic_vertex(cx: f32, cy: f32, x: f32, y: f32) { engine::quadratic_vertex(cx, cy, x, y) }

/// Lua kinds: POINTS 0, LINES 1, TRIANGLES 4, TRIANGLE_STRIP 5,
/// TRIANGLE_FAN 6, QUADS 7, QUAD_STRIP 8, anything else polygon.
pub fn begin_shape(kind: i32) {
    let k = match kind {
        0 => engine::POINTS, 1 => engine::LINES, 4 => engine::TRIANGLES,
        5 => engine::TRIANGLE_STRIP, 6 => engine::TRIANGLE_FAN,
        7 => engine::QUADS, 8 => engine::QUAD_STRIP, _ => engine::POLYGON,
    };
    engine::begin_shape_kind(k)
}
/// CLOSE is 2, as in Processing.
pub fn end_shape(mode: i32) { engine::end_shape_mode(if mode == 2 { engine::CLOSE } else { 0 }) }
pub fn bezier_vertex(cx1: f32, cy1: f32, cx2: f32, cy2: f32, x: f32, y: f32) {
    engine::bezier_vertex(cx1, cy1, cx2, cy2, x, y)
}
pub fn curve_vertex(x: f32, y: f32) { engine::curve_vertex(x, y) }

// ── Transform / style ─────────────────────────────────────────────────────

pub fn push_matrix()  { engine::push_matrix() }
pub fn pop_matrix()   { engine::pop_matrix() }
pub fn push_style()   { engine::push_style() }
pub fn pop_style()    { engine::pop_style() }
#[allow(dead_code)]
pub fn translate(x: f32, y: f32) { engine::translate(x, y) }
pub fn translate3(x: f32, y: f32, z: f32) { engine::translate_3d(x, y, z) }
pub fn scale3(x: f32, y: f32, z: f32) { engine::scale_3d(x, y, z) }
/// The 3D calls, by their Lua name. Some(value) for screenX / screenY.
pub fn three(name: &str, a: &[f32]) -> Result<Option<f32>, String> {
    let need = |n: usize| if a.len() >= n { Ok(()) } else { Err(format!("expects {n} numbers")) };
    match (name, a.len()) {
        ("rotateX", _) => { need(1)?; engine::rotate_x(a[0]) }
        ("rotateY", _) => { need(1)?; engine::rotate_y(a[0]) }
        ("box", 1) | ("box", 2) => engine::box_cube(a[0]),
        ("box", _) => { need(1)?; engine::box_3d(a[0], a[1], a[2]) }
        ("sphere", _) => { need(1)?; engine::sphere(a[0]) }
        ("sphereDetail", 1) => engine::sphere_detail(a[0]),
        ("sphereDetail", _) => { need(1)?; engine::sphere_detail_uv(a[0], a[1]) }
        ("camera", 0) => engine::camera(),
        ("camera", _) => { need(9)?; engine::camera_look(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8]) }
        ("perspective", 0) => engine::perspective_default(),
        ("perspective", _) => { need(4)?; engine::perspective(a[0], a[1], a[2], a[3]) }
        ("lights", _) => engine::lights(),
        ("noLights", _) => engine::no_lights(),
        ("ambientLight", 1) => engine::ambient_light(a[0], a[0], a[0]),
        ("ambientLight", _) => { need(3)?; engine::ambient_light(a[0], a[1], a[2]) }
        ("directionalLight", _) => { need(6)?; engine::directional_light(a[0], a[1], a[2], a[3], a[4], a[5]) }
        ("pointLight", _) => { need(6)?; engine::point_light(a[0], a[1], a[2], a[3], a[4], a[5]) }
        ("beginCamera", _) => engine::begin_camera(),
        ("endCamera", _) => engine::end_camera(),
        ("printCamera", _) => engine::print_camera(),
        ("printProjection", _) => engine::print_projection(),
        ("frustum", _) => { need(6)?; engine::frustum(a[0], a[1], a[2], a[3], a[4], a[5]) }
        ("ortho", 0) => engine::ortho(),
        ("ortho", 4) | ("ortho", 5) => engine::ortho_rect(a[0], a[1], a[2], a[3]),
        ("ortho", _) => { need(6)?; engine::ortho_planes(a[0], a[1], a[2], a[3], a[4], a[5]) }
        ("modelX", _) => { need(3)?; return Ok(Some(engine::model_x(a[0], a[1], a[2]))) }
        ("modelY", _) => { need(3)?; return Ok(Some(engine::model_y(a[0], a[1], a[2]))) }
        ("modelZ", _) => { need(3)?; return Ok(Some(engine::model_z(a[0], a[1], a[2]))) }
        ("screenZ", _) => { need(3)?; return Ok(Some(engine::screen_z(a[0], a[1], a[2]))) }
        ("normal", _) => {}
        ("textureMode", _) => { need(1)?; engine::texture_mode(a[0] as u8) }
        ("textureWrap", _) => { need(1)?; engine::texture_wrap(a[0] as u8) }
        ("texture", _) => { need(1)?; engine::texture(a[0] as u64) }
        ("noTexture", _) => engine::no_texture(),
        ("vertex", 2) => engine::vertex(a[0], a[1]),
        ("vertex", 3) => engine::vertex_3d(a[0], a[1], a[2]),
        ("vertex", 4) => engine::vertex_uv(a[0], a[1], a[2], a[3]),
        ("vertex", _) => { need(5)?; engine::vertex_3d_uv(a[0], a[1], a[2], a[3], a[4]) }
        ("rotate", 1) => engine::rotate(a[0]),
        ("rotate", _) => { need(4)?; engine::rotate_axis(a[0], a[1], a[2], a[3]) }
        ("applyMatrix", 6) => engine::apply_matrix(a[0], a[1], a[2], a[3], a[4], a[5]),
        ("applyMatrix", _) => { need(16)?; engine::apply_matrix_3d(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7],
                                                                    a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15]) }
        ("spotLight", _) => { need(11)?; engine::spot_light(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10]) }
        ("lightFalloff", _) => { need(3)?; engine::light_falloff(a[0], a[1], a[2]) }
        ("lightSpecular", 1) => engine::light_specular(a[0], a[0], a[0]),
        ("lightSpecular", _) => { need(3)?; engine::light_specular(a[0], a[1], a[2]) }
        ("ambient", 1) => engine::ambient(a[0], a[0], a[0]),
        ("ambient", _) => { need(3)?; engine::ambient(a[0], a[1], a[2]) }
        ("specular", 1) => engine::specular(a[0], a[0], a[0]),
        ("specular", _) => { need(3)?; engine::specular(a[0], a[1], a[2]) }
        ("emissive", 1) => engine::emissive(a[0], a[0], a[0]),
        ("emissive", _) => { need(3)?; engine::emissive(a[0], a[1], a[2]) }
        ("shininess", _) => { need(1)?; engine::shininess(a[0]) }
        ("bezierDetail", _) => { need(1)?; engine::bezier_detail(a[0]) }
        ("curveDetail", _) => { need(1)?; engine::curve_detail(a[0]) }
        ("curveTightness", _) => { need(1)?; engine::curve_tightness(a[0]) }
        ("shapeMode", _) => { need(1)?; engine::shape_mode(a[0] as u32) }
        ("pixelDensity", _) => { need(1)?; engine::pixel_density(a[0]) }
        ("displayDensity", _) => return Ok(Some(engine::display_density())),
        ("pixelWidth", _) => return Ok(Some(engine::pixel_width())),
        ("pixelHeight", _) => return Ok(Some(engine::pixel_height())),
        ("windowMove", _) => { need(2)?; engine::window_move(a[0], a[1]) }
        ("windowResize", _) => { need(2)?; engine::window_resize(a[0], a[1]) }
        ("textMode", _) => {}
        ("printMatrix", _) => engine::print_matrix(),
        ("copy", _) => { need(8)?; engine::copy(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]) }
        ("blend", _) => { need(9)?; engine::blend(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8] as u32) }
        ("screenX", _) => { need(2)?; return Ok(Some(engine::screen_x(a[0], a[1], a.get(2).copied().unwrap_or(0.0)))) }
        ("screenY", _) => { need(2)?; return Ok(Some(engine::screen_y(a[0], a[1], a.get(2).copied().unwrap_or(0.0)))) }
        _ => {}
    }
    Ok(None)
}
pub fn line3(x1: f32, y1: f32, z1: f32, x2: f32, y2: f32, z2: f32) { engine::line_3d(x1, y1, z1, x2, y2, z2) }
pub fn point3(x: f32, y: f32, z: f32) { engine::point_3d(x, y, z) }
pub fn rotate(a: f32)            { engine::rotate(a) }
pub fn scale(x: f32, y: f32)     { engine::scale_xy(x, y) }
pub fn scale_uniform(s: f32)     { engine::scale(s) }
pub fn reset_matrix()            { engine::reset_matrix() }

// ── Text ──────────────────────────────────────────────────────────────────

pub fn text(s: &str, x: f32, y: f32) { engine::text(s, x, y) }
pub fn text_box(s: &str, x: f32, y: f32, w: f32, h: f32) { engine::text_box(s, x, y, w, h) }
pub fn text_size(sz: f32)            { engine::text_size(sz) }
pub fn create_font(name: &str, size: f32) -> u64 { engine::create_font(name, size) }
pub fn text_font(font: u64, size: f32) { engine::text_font_size(font, size) }
pub fn text_leading(px: f32) { engine::text_leading(px) }
pub fn text_width(s: &str) -> f32    { engine::text_width(s) }
pub fn text_ascent() -> f32          { engine::text_ascent() }
pub fn text_descent() -> f32         { engine::text_descent() }

/// Anything unrecognised falls back to Processing's defaults: LEFT, BASELINE.
pub fn text_align(h: i32, v: i32) {
    let hh = match h { RIGHT => engine::ALIGN_RIGHT, CENTER => engine::ALIGN_CENTER, _ => engine::ALIGN_LEFT };
    let vv = match v { CENTER => engine::ALIGN_CENTER, TOP => engine::ALIGN_TOP, BOTTOM => engine::ALIGN_BOTTOM, _ => engine::ALIGN_BASELINE };
    engine::text_align(hh, vv)
}

// ── Math ──────────────────────────────────────────────────────────────────

pub fn noise3(x: f32, y: f32, z: f32) -> f32 { engine::noise3(x, y, z) }
pub fn noise_seed(seed: u64)               { engine::noise_seed(seed) }
pub fn noise_detail(oct: i32, fall: f32)   { engine::noise_detail(oct.max(0) as u32, fall) }
pub fn random1() -> f32                    { engine::random(1.0) }
pub fn random_seed(seed: u64)              { engine::random_seed(seed) }
pub fn random_gaussian() -> f32            { engine::random_gaussian() }

// ── Images ────────────────────────────────────────────────────────────────

pub fn load_image(path: &str) -> u64 { engine::load_image(path) }
pub fn image(id: u64, x: f32, y: f32) { engine::image(id, x, y) }
pub fn image_sized(id: u64, x: f32, y: f32, w: f32, h: f32) { engine::image_sized(id, x, y, w, h) }

pub fn save_frame(name: &str) { engine::save_frame(name) }
pub fn get_pixel(x: i32, y: i32) -> (u8, u8, u8) { engine::get_pixel(x, y) }

// ── Image editing (colors as [r, g, b, a] in 0..255) ─────────────────────

fn to_engine(c: [f32; 4]) -> engine::Color {
    engine::Color::from_rgba(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0, c[3] / 255.0)
}
fn from_engine(c: engine::Color) -> [f32; 4] { [c.r * 255.0, c.g * 255.0, c.b * 255.0, c.a * 255.0] }
pub fn create_image(w: u32, h: u32) -> u64 { engine::create_image(w, h) }
pub fn image_get(id: u64, x: i32, y: i32) -> [f32; 4] { from_engine(engine::image_get(id, x, y)) }
pub fn image_set(id: u64, x: i32, y: i32, c: [f32; 4]) { engine::image_set(id, x, y, to_engine(c)) }
pub fn image_pixels(id: u64) -> Vec<[f32; 4]> { engine::image_pixels(id).into_iter().map(from_engine).collect() }
pub fn image_set_pixels(id: u64, px: &[[f32; 4]]) {
    let v: Vec<engine::Color> = px.iter().map(|c| to_engine(*c)).collect();
    engine::image_set_pixels(id, &v)
}
pub fn image_crop(id: u64, x: i32, y: i32, w: u32, h: u32) -> u64 { engine::image_crop(id, x, y, w, h) }
pub fn image_copy(id: u64) -> u64 { engine::image_copy(id) }
pub fn image_resize(id: u64, w: u32, h: u32) { engine::image_resize(id, w, h) }
pub fn image_mask(id: u64, mask: u64) -> bool { engine::image_mask(id, mask) }
pub fn save_image(id: u64, path: &str) -> bool { engine::save_image(id, path) }
pub fn get_region(x: i32, y: i32, w: u32, h: u32) -> u64 { engine::get_region(x, y, w, h) }
