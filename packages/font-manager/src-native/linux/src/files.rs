//! Font sources on disk: app paths, file URLs, `data:` URIs and the cache bytes are written to.

use std::hash::Hasher;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::RwLock;

static APP_DIR: RwLock<Option<PathBuf>> = RwLock::new(None);
static CACHE_DIR: RwLock<Option<PathBuf>> = RwLock::new(None);

pub fn set_app_dir(dir: Option<PathBuf>) {
    *APP_DIR.write().unwrap() = dir;
}

pub fn set_cache_dir(dir: Option<PathBuf>) {
    *CACHE_DIR.write().unwrap() = dir;
}

fn cache_dir() -> PathBuf {
    if let Some(dir) = CACHE_DIR.read().unwrap().clone() {
        return dir;
    }
    // XDG says relative values are ignored; they would land in the CWD
    let absolute = |p: PathBuf| p.is_absolute().then_some(p);
    std::env::var_os("XDG_CACHE_HOME")
        .and_then(|p| absolute(PathBuf::from(p)))
        .or_else(|| std::env::var_os("HOME").and_then(|h| absolute(PathBuf::from(h).join(".cache"))))
        .map(|base| base.join("nativescript-fonts"))
        .unwrap_or_else(|| std::env::temp_dir().join(format!("nativescript-fonts-{}", unsafe { libc::geteuid() })))
}

/// Creates `dir` 0700, or makes it so: a real directory of this user, that nobody else can plant
/// or swap files in.
fn private_dir(dir: &Path) -> Result<(), String> {
    use std::os::unix::fs::{DirBuilderExt, MetadataExt};
    let fail = |e: String| format!("Couldn't use cache directory {}: {e}", dir.display());
    if let Some(parent) = dir.parent() {
        std::fs::create_dir_all(parent).map_err(|e| fail(e.to_string()))?;
    }
    match std::fs::DirBuilder::new().mode(0o700).create(dir) {
        Err(e) if e.kind() != std::io::ErrorKind::AlreadyExists => return Err(fail(e.to_string())),
        _ => {}
    }
    let meta = std::fs::symlink_metadata(dir).map_err(|e| fail(e.to_string()))?;
    if !meta.is_dir() || meta.uid() != unsafe { libc::geteuid() } {
        return Err(fail("not a directory of this user".into()));
    }
    // older versions created it with the umask's mode
    if meta.mode() & 0o077 != 0 {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700)).map_err(|e| fail(e.to_string()))?;
    }
    Ok(())
}

pub enum Source {
    File(PathBuf),
    Remote(String),
    Data(Vec<u8>),
}

fn percent_decode(s: &str) -> Vec<u8> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            let hex = |c: u8| (c as char).to_digit(16);
            if let (Some(h), Some(l)) = (hex(b[i + 1]), hex(b[i + 2])) {
                out.push((h * 16 + l) as u8);
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    out
}

fn base64_decode(s: &str) -> Option<Vec<u8>> {
    fn value(c: u8) -> Option<u32> {
        Some(match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' | b'-' => 62,
            b'/' | b'_' => 63,
            _ => return None,
        } as u32)
    }
    let mut out = Vec::with_capacity(s.len() * 3 / 4);
    let (mut acc, mut bits) = (0u32, 0u32);
    for c in s.bytes() {
        if c == b'=' {
            break;
        }
        if c.is_ascii_whitespace() {
            continue;
        }
        acc = (acc << 6) | value(c)?;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
            acc &= (1 << bits) - 1;
        }
    }
    Some(out)
}

/// Payload of a `data:` URI.
pub fn decode_data_uri(uri: &str) -> Option<Vec<u8>> {
    let rest = uri.get(5..).filter(|_| uri[..5].eq_ignore_ascii_case("data:"))?;
    let comma = rest.find(',')?;
    let (meta, payload) = (&rest[..comma], &rest[comma + 1..]);
    if meta.to_ascii_lowercase().ends_with(";base64") {
        base64_decode(&String::from_utf8_lossy(&percent_decode(payload)))
    } else {
        Some(percent_decode(payload))
    }
}

pub fn is_remote(url: &str) -> bool {
    let lower = url.get(..8).unwrap_or(url).to_ascii_lowercase();
    lower.starts_with("http://") || lower.starts_with("https://")
}

/// Where a face source lives: `~/` and relative paths are under the app directory.
pub fn classify(url: &str) -> Result<Source, String> {
    if is_remote(url) {
        return Ok(Source::Remote(url.to_string()));
    }
    let lower = url.get(..8).unwrap_or(url).to_ascii_lowercase();
    if lower.starts_with("data:") {
        return decode_data_uri(url).map(Source::Data).ok_or_else(|| "Invalid data: URI".to_string());
    }
    if lower.starts_with("file://") {
        let path = &url[7..];
        let path = path.strip_prefix("localhost").unwrap_or(path);
        return Ok(Source::File(PathBuf::from(std::ffi::OsString::from(
            String::from_utf8_lossy(&percent_decode(path)).into_owned(),
        ))));
    }
    if let Some(colon) = url.find(':') {
        if colon > 1 && url[..colon].bytes().all(|c| c.is_ascii_alphanumeric()) && !url.starts_with('/') {
            return Err(format!("Unsupported font URL {url}"));
        }
    }
    let app = APP_DIR.read().unwrap();
    if let Some(rest) = url.strip_prefix("~/") {
        return match app.as_ref() {
            Some(dir) => Ok(Source::File(dir.join(rest))),
            None => Err(format!("{url}: no app directory set (fm_set_app_dir)")),
        };
    }
    let path = Path::new(url);
    match app.as_ref() {
        Some(dir) if path.is_relative() => Ok(Source::File(dir.join(url.trim_start_matches("./")))),
        // not against the CWD
        None if path.is_relative() => Err(format!("{url}: relative path with no app directory set (fm_set_app_dir)")),
        _ => Ok(Source::File(path.to_path_buf())),
    }
}

fn extension(bytes: &[u8]) -> &'static str {
    match bytes.get(..4) {
        Some(b"wOF2") => "woff2",
        Some(b"wOFF") => "woff",
        Some(b"OTTO") => "otf",
        Some(b"ttcf") => "ttc",
        _ => "ttf",
    }
}

/// Writes font bytes to the cache, named by content so equal bytes share a file.
pub fn persist(bytes: &[u8]) -> Result<PathBuf, String> {
    use std::os::unix::fs::OpenOptionsExt;
    if bytes.is_empty() {
        return Err("Empty font data".into());
    }
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    hasher.write(bytes);
    let name = format!("font_{:016x}_{:x}.{}", hasher.finish(), bytes.len(), extension(bytes));
    let dir = cache_dir();
    private_dir(&dir)?;
    let target = dir.join(&name);
    // the hash isn't collision resistant: reuse only a file with these exact bytes
    if std::fs::read(&target).is_ok_and(|existing| existing == bytes) {
        return Ok(target);
    }
    // temp file + rename, so a partial write never sits under the final name
    static COUNTER: AtomicU32 = AtomicU32::new(0);
    let temp = dir.join(format!("{name}.{}_{}.part", std::process::id(), COUNTER.fetch_add(1, Ordering::Relaxed)));
    let written = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temp)
        .and_then(|mut f| f.write_all(bytes));
    if let Err(e) = written.and_then(|_| std::fs::rename(&temp, &target)) {
        let _ = std::fs::remove_file(&temp);
        if !target.exists() {
            return Err(format!("Couldn't write {}: {e}", target.display()));
        }
    }
    Ok(target)
}

/// Reads a stylesheet from a path, `file://`, `~/` or `data:` URL; returns the text and the base
/// for its relative URLs.
pub fn read_text(url: &str) -> Result<(String, String), String> {
    match classify(url)? {
        Source::Data(bytes) => Ok((String::from_utf8_lossy(&bytes).into_owned(), String::new())),
        Source::File(path) => {
            let text = std::fs::read(&path).map_err(|e| format!("Couldn't read {}: {e}", path.display()))?;
            Ok((String::from_utf8_lossy(&text).into_owned(), path.to_string_lossy().into_owned()))
        }
        Source::Remote(url) => Err(format!("{url} is remote: fetch it and use fm_parse_stylesheet")),
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    #[test]
    fn data_uris() {
        assert_eq!(decode_data_uri("data:font/ttf;base64,AAEC/w==").unwrap(), [0, 1, 2, 255]);
        assert_eq!(decode_data_uri("DATA:text/css,a%20b").unwrap(), b"a b");
        assert_eq!(decode_data_uri("data:;base64,SGVs bG8").unwrap(), b"Hello");
        assert!(decode_data_uri("data:font/ttf;base64,@@").is_none());
        assert!(decode_data_uri("http://x").is_none());
    }

    #[test]
    fn classifies() {
        assert!(matches!(classify("https://x.test/a.ttf"), Ok(Source::Remote(_))));
        assert!(matches!(classify("file:///tmp/a%20b.ttf"), Ok(Source::File(p)) if p == Path::new("/tmp/a b.ttf")));
        assert!(matches!(classify("/abs/a.ttf"), Ok(Source::File(p)) if p == Path::new("/abs/a.ttf")));
        assert!(classify("ftp://x/a.ttf").is_err());
        if APP_DIR.read().unwrap().is_none() {
            assert!(classify("fonts/a.ttf").is_err(), "relative to the CWD");
        }
    }

    pub fn use_test_cache() {
        static ONCE: std::sync::Once = std::sync::Once::new();
        ONCE.call_once(|| set_cache_dir(Some(std::env::temp_dir().join(format!("fm-test-{}", std::process::id())))));
    }

    #[test]
    fn persists_by_content() {
        use_test_cache();
        let a = persist(b"OTTO-some-bytes").unwrap();
        let b = persist(b"OTTO-some-bytes").unwrap();
        assert_eq!(a, b);
        assert_eq!(a.extension().unwrap(), "otf");
        assert_ne!(persist(b"other").unwrap(), a);
        assert!(persist(b"").is_err());
    }

    #[test]
    fn cache_is_private() {
        use std::os::unix::fs::PermissionsExt;
        use_test_cache();
        let path = persist(b"OTTO-private").unwrap();
        let mode = |p: &Path| std::fs::metadata(p).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode(&path), 0o600);
        assert_eq!(mode(path.parent().unwrap()), 0o700);
        // a file swapped in under the name isn't trusted
        std::fs::write(&path, b"OTTO-planted").unwrap();
        assert_eq!(persist(b"OTTO-private").unwrap(), path);
        assert_eq!(std::fs::read(&path).unwrap(), b"OTTO-private");

        let root = std::env::temp_dir().join(format!("fm-private-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("real")).unwrap();
        std::fs::set_permissions(root.join("real"), std::fs::Permissions::from_mode(0o777)).unwrap();
        std::os::unix::fs::symlink(root.join("real"), root.join("link")).unwrap();
        assert!(private_dir(&root.join("link")).is_err());
        private_dir(&root.join("real")).unwrap();
        assert_eq!(mode(&root.join("real")), 0o700);
        let _ = std::fs::remove_dir_all(&root);
    }
}
