//! One-file exports: the sketch rides inside the runner. Export Application
//! appends the files (sketch.lua, launch.txt, data/...) to a copy of the
//! runner, then a 16-byte trailer: the payload's length (u64, little end)
//! and "LUASKTCH". The runner reads them from its own file at start.

use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

const MAGIC: &[u8; 8] = b"LUASKTCH";

pub struct Payload {
    pub files: Vec<(String, Vec<u8>)>,
}

impl Payload {
    pub fn get(&self, name: &str) -> Option<&[u8]> {
        self.files.iter().find(|(n, _)| n == name).map(|(_, d)| d.as_slice())
    }
}

/// The files appended to this program, if it is a one-file export. In a
/// macOS .app they're in Contents/Resources/sketch.payload instead (a signed
/// program can't have anything after it).
pub fn read() -> Option<Payload> {
    let exe = std::env::current_exe().ok()?;
    if let Some(p) = exe.parent().map(|d| d.join("../Resources/sketch.payload")) {
        if let Ok(buf) = fs::read(&p) { return parse(&buf); }
    }
    let mut f = fs::File::open(&exe).ok()?;
    let size = f.metadata().ok()?.len();
    if size < 16 { return None; }
    f.seek(SeekFrom::End(-16)).ok()?;
    let mut tail = [0u8; 16];
    f.read_exact(&mut tail).ok()?;
    if &tail[8..] != MAGIC { return None; }
    let len = u64::from_le_bytes(tail[..8].try_into().ok()?);
    if len > size - 16 { return None; }
    f.seek(SeekFrom::Start(size - 16 - len)).ok()?;
    let mut buf = vec![0u8; len as usize];
    f.read_exact(&mut buf).ok()?;
    parse(&buf)
}

fn parse(buf: &[u8]) -> Option<Payload> {
    // entries: name length (u32), name, data length (u64), data
    let mut files = Vec::new();
    let mut i = 0usize;
    while i < buf.len() {
        let nl = u32::from_le_bytes(buf.get(i..i + 4)?.try_into().ok()?) as usize;
        i += 4;
        let name = String::from_utf8(buf.get(i..i + nl)?.to_vec()).ok()?;
        i += nl;
        let dl = u64::from_le_bytes(buf.get(i..i + 8)?.try_into().ok()?) as usize;
        i += 8;
        files.push((name, buf.get(i..i + dl)?.to_vec()));
        i += dl;
    }
    Some(Payload { files })
}

/// Settings a launcher would set (launch.txt), the data/ files unpacked to a
/// folder of their own (PROCESSING_DATA_DIR), and the program's folder as the
/// working folder, so saved files land next to it.
pub fn apply(p: &Payload) {
    if let Some(t) = p.get("launch.txt") {
        for line in String::from_utf8_lossy(t).lines() {
            if let Some((k, v)) = line.split_once('=') {
                let k = k.trim();
                if !k.is_empty() && !k.starts_with('#') && std::env::var_os(k).is_none() {
                    std::env::set_var(k, v.trim());
                }
            }
        }
    }
    // saved files go next to what was double-clicked: the AppImage, the
    // .app, or the program itself
    let here = if let Some(img) = std::env::var_os("APPIMAGE") {
        Path::new(&img).parent().map(Path::to_path_buf)
    } else {
        std::env::current_exe().ok().and_then(|exe| {
            let dir = exe.parent()?.to_path_buf();
            if dir.ends_with("Contents/MacOS") { dir.parent()?.parent()?.parent().map(Path::to_path_buf) } else { Some(dir) }
        })
    };
    if let Some(d) = here { let _ = std::env::set_current_dir(d); }
    let data: Vec<&(String, Vec<u8>)> = p.files.iter().filter(|(n, _)| n.starts_with("data/")).collect();
    if data.is_empty() { return; }
    // a folder per export, named after what is in it, so it's unpacked once
    let mut h: u64 = 0xcbf29ce484222325;
    for (n, d) in &data {
        for b in n.bytes().chain(d.iter().copied()) { h = (h ^ b as u64).wrapping_mul(0x100000001b3); }
    }
    let root = std::env::temp_dir().join(format!("processing-sketch-{h:016x}"));
    let ready = root.join(".ready");
    if !ready.is_file() {
        for (n, d) in &data {
            let rel = Path::new(n.as_str());
            if rel.components().any(|c| matches!(c, std::path::Component::ParentDir | std::path::Component::RootDir | std::path::Component::Prefix(_))) { continue; }
            let out: PathBuf = root.join(rel);
            if let Some(parent) = out.parent() { let _ = fs::create_dir_all(parent); }
            let _ = fs::write(&out, d);
        }
        let _ = fs::write(&ready, b"");
    }
    std::env::set_var("PROCESSING_DATA_DIR", root.join("data"));
}
