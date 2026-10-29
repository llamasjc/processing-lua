//! Bindings that bring Lua sketches closer to Processing's Java API: PImage
//! and PFont methods on handles, getMatrix/setMatrix, sketch paths and a regex
//! replace for Table. prelude.lua turns most of these into methods.

use mlua::prelude::*;
use engine::{PFontExt, PImageExt};

use super::{gray_pixel, is_packed, pack_color};

/// Fonts are handed to Lua as FONT_BASE + the engine's id, so a font and an
/// image never share a number (both counters start at 1).
pub const FONT_BASE: i64 = 1 << 40;

fn font_id(h: i64) -> u64 { if h > FONT_BASE { (h - FONT_BASE) as u64 } else { h.max(0) as u64 } }

/// 0xAARRGGBB from the engine to the packed form color() makes.
fn packed(p: u32) -> i64 {
    let n = p as i64;
    if (p >> 24) == 0 { n | (1 << 32) } else { n }
}

pub fn register(lua: &Lua) -> LuaResult<()> {
    let g = lua.globals();
    g.set("__FONT_BASE", FONT_BASE)?;

    // ── images ────────────────────────────────────────────────────────────
    g.set("__imgSize", lua.create_function(|_, id: i64| {
        let id = id.max(0) as u64;
        Ok((id.width() as i64, id.height() as i64))
    })?)?;
    // pixels counted from 0, like the canvas `pixels`
    g.set("__imgLoadPixels", lua.create_function(|lua, (id, t): (i64, Option<LuaTable>)| {
        let px = (id.max(0) as u64).load_pixels();
        let t = match t { Some(t) if t.raw_len() + 1 == px.len() => t, _ => lua.create_table_with_capacity(px.len(), 1)? };
        for (i, p) in px.iter().enumerate() { t.raw_set(i as i64, packed(*p))?; }
        Ok(t)
    })?)?;
    g.set("__imgUpdatePixels", lua.create_function(|_, (id, t): (i64, LuaTable)| {
        let id = id.max(0) as u64;
        let mut px = id.load_pixels();
        for (i, p) in px.iter_mut().enumerate() {
            match t.raw_get::<_, LuaValue>(i as i64)? {
                LuaValue::Integer(n) => *p = if is_packed(n) { n as u32 } else { gray_pixel(n as f32) },
                LuaValue::Number(n) => *p = gray_pixel(n as f32),
                _ => {}
            }
        }
        id.update_pixels(&px);
        Ok(())
    })?)?;
    g.set("__imgFilter", lua.create_function(|_, (id, kind, param): (i64, i64, Option<f32>)| {
        (id.max(0) as u64).filter(kind.max(0) as u32, param.unwrap_or(f32::NAN));
        Ok(())
    })?)?;
    // blend(src, sx, sy, sw, sh, dx, dy, dw, dh, mode) into id
    g.set("__imgBlend", lua.create_function(|_, (id, src, a, mode): (i64, i64, Vec<f32>, i64)| {
        if a.len() < 8 { return Err(LuaError::RuntimeError("blend() expects 8 numbers for the two regions".into())); }
        (id.max(0) as u64).blend(src.max(0) as u64, a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], mode.max(0) as u32);
        Ok(())
    })?)?;
    g.set("__imgSave", lua.create_function(|_, (id, path): (i64, LuaString)| {
        Ok((id.max(0) as u64).save(&path.to_string_lossy()))
    })?)?;
    // a color read from an image, packed like color()
    g.set("__imgGet", lua.create_function(|_, (id, x, y): (i64, f64, f64)| {
        let c = (id.max(0) as u64).get(x as f32, y as f32);
        Ok(pack_color([c.r * 255.0, c.g * 255.0, c.b * 255.0, c.a * 255.0]))
    })?)?;

    // ── fonts ─────────────────────────────────────────────────────────────
    g.set("__fontInfo", lua.create_function(|_, h: i64| {
        let id = font_id(h);
        Ok((id.get_size() as f64, id.get_name(), id.ascent() as f64, id.descent() as f64))
    })?)?;
    g.set("__fontCharWidth", lua.create_function(|_, (h, s): (i64, LuaString)| {
        let s = s.to_string_lossy();
        Ok(s.chars().next().map(|c| font_id(h).char_width(c)).unwrap_or(0.0) as f64)
    })?)?;

    g.set("__fontGlyphCount", lua.create_function(|_, h: i64| Ok(font_id(h).get_glyph_count() as i64))?)?;

    // a character's outline: contours of {code, numbers...} (see Font.getShape)
    g.set("__fontOutline", lua.create_function(|lua, (h, s): (i64, LuaString)| {
        let s = s.to_string_lossy();
        let Some(c) = s.chars().next() else { return Ok(lua.create_table()?) };
        let out = lua.create_table()?;
        for (i, contour) in font_id(h).get_outline(c).iter().enumerate() {
            let t = lua.create_table()?;
            for (j, (op, v)) in contour.iter().enumerate() {
                let seg = lua.create_table()?;
                seg.set(1, *op as i64)?;
                let n = match op { 0 => 2, 2 => 4, _ => 6 };
                for (k, x) in v.iter().take(n).enumerate() { seg.set(k + 2, *x as f64)?; }
                t.set(j + 1, seg)?;
            }
            out.set(i + 1, t)?;
        }
        Ok(out)
    })?)?;

    // ── matrices ──────────────────────────────────────────────────────────
    // the current transform, sixteen values row by row
    g.set("__getMatrix", lua.create_function(|_, ()| Ok(engine::get_matrix().get_array().to_vec()))?)?;
    g.set("__setMatrix", lua.create_function(|_, (a, apply): (Vec<f32>, Option<bool>)| {
        let mut m = engine::PMatrix3D::new();
        match a.len() {
            6 => m.set_array(&[a[0], a[1], 0.0, a[2], a[3], a[4], 0.0, a[5], 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]),
            16 => { let mut b = [0.0; 16]; b.copy_from_slice(&a); m.set_array(&b) }
            _ => return Err(LuaError::RuntimeError("expects a matrix, or 6 or 16 numbers".into())),
        }
        if apply.unwrap_or(false) { engine::apply_pmatrix(&m) } else { engine::set_matrix(&m) }
        Ok(())
    })?)?;

    // ── files ─────────────────────────────────────────────────────────────
    g.set("sketchPath", lua.create_function(|_, name: Option<String>| {
        Ok(match name { Some(n) => engine::sketch_path_of(&n), None => engine::sketch_path() })
    })?)?;
    g.set("sketchFile", lua.create_function(|_, name: String| Ok(engine::sketch_path_of(&name)))?)?;
    g.set("dataPath", lua.create_function(|_, name: String| Ok(engine::data_path(&name)))?)?;
    g.set("dataFile", lua.create_function(|_, name: String| Ok(engine::data_path(&name)))?)?;
    g.set("savePath", lua.create_function(|_, name: String| Ok(engine::save_path(&name)))?)?;
    g.set("saveFile", lua.create_function(|_, name: String| Ok(engine::save_path(&name)))?)?;
    g.set("listPaths", lua.create_function(|_, dir: Option<String>| Ok(engine::list_paths(&dir.unwrap_or_default())))?)?;
    g.set("listFiles", lua.create_function(|_, dir: Option<String>| Ok(engine::list_files(&dir.unwrap_or_default())))?)?;

    // Java-style regex replace (Table:replaceAll); $1 refers to a group
    g.set("__regexReplace", lua.create_function(|_, (text, pat, rep): (String, String, String)| {
        match regex::Regex::new(&pat) {
            Ok(re) => {
                // Java reads "$1nna" as group 1 then "nna"; the regex crate
                // would look for a group named "1nna", so the digits get braces
                let mut r = String::with_capacity(rep.len());
                let mut it = rep.chars().peekable();
                while let Some(c) = it.next() {
                    if c == '$' && it.peek().is_some_and(|d| d.is_ascii_digit()) {
                        r.push_str("${");
                        while let Some(d) = it.peek().copied().filter(|d| d.is_ascii_digit()) { r.push(d); it.next(); }
                        r.push('}');
                    } else { r.push(c); }
                }
                Ok(re.replace_all(&text, r.as_str()).into_owned())
            }
            Err(e) => Err(LuaError::RuntimeError(format!("bad regular expression: {e}"))),
        }
    })?)?;
    g.set("__regexFind", lua.create_function(|_, (text, pat): (String, String)| {
        match regex::Regex::new(&pat) {
            Ok(re) => Ok(re.is_match(&text)),
            Err(e) => Err(LuaError::RuntimeError(format!("bad regular expression: {e}"))),
        }
    })?)?;
    Ok(())
}
