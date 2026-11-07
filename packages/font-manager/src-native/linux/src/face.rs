//! A web `FontFace`: a family, a source and descriptors, loaded into fontconfig.

use crate::descriptors::Descriptors;
use crate::files::{self, Source};
use crate::{css, fontconfig, set};
use std::ffi::CString;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicI32, AtomicU32, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

pub const UNLOADED: i32 = 0;
pub const LOADING: i32 = 1;
pub const LOADED: i32 = 2;
pub const ERROR: i32 = 3;

pub type SharedDescriptors = Arc<Mutex<Descriptors>>;

enum FaceSource {
    /// A family the system already has.
    None,
    Url(String),
    /// Bytes given at creation, already in the cache.
    Data(Result<PathBuf, String>),
    Invalid(String),
}

#[derive(Default)]
struct LoadState {
    error: Option<String>,
    /// Loading a remote source; its bytes come through `load_data`.
    awaiting_data: bool,
}

pub struct Face {
    pub id: u32,
    pub family: CString,
    pub family_key: String,
    pub descriptors: SharedDescriptors,
    pub url: Option<CString>,
    source: FaceSource,
    status: AtomicI32,
    state: Mutex<LoadState>,
    actual: OnceLock<CString>,
    path: OnceLock<CString>,
}

static NEXT_ID: AtomicU32 = AtomicU32::new(1);

fn c_string(s: &str) -> CString {
    CString::new(s.replace('\0', "")).unwrap()
}

impl Face {
    fn with_source(family: &str, source: FaceSource, url: Option<&str>) -> Arc<Self> {
        let descriptors = Descriptors::new(family);
        Arc::new(Face {
            id: NEXT_ID.fetch_add(1, Ordering::Relaxed),
            family: c_string(&descriptors.family),
            family_key: descriptors.family.to_lowercase(),
            descriptors: Arc::new(Mutex::new(descriptors)),
            url: url.map(c_string),
            source,
            status: AtomicI32::new(UNLOADED),
            state: Mutex::default(),
            actual: OnceLock::new(),
            path: OnceLock::new(),
        })
    }

    /// `source`: a CSS `src` list, `url(...)`, a URL or a path; `None` for a system family.
    pub fn new(family: &str, source: Option<&str>) -> Arc<Self> {
        match source.map(str::trim).filter(|s| !s.is_empty()) {
            None => Self::with_source(family, FaceSource::None, None),
            Some(src) => Self::from_url(family, css::source_url(src), src),
        }
    }

    /// A face for the URL picked from `src`; `None` when none of it is usable.
    pub fn from_url(family: &str, url: Option<String>, src: &str) -> Arc<Self> {
        match url {
            Some(url) => Self::with_source(family, FaceSource::Url(url.clone()), Some(&url)),
            None => Self::with_source(family, FaceSource::Invalid(format!("No supported font source in {src}")), None),
        }
    }

    pub fn new_data(family: &str, bytes: &[u8]) -> Arc<Self> {
        Self::with_source(family, FaceSource::Data(files::persist(bytes)), None)
    }

    pub fn status(&self) -> i32 {
        self.status.load(Ordering::Acquire)
    }

    pub fn error(&self) -> Option<String> {
        self.state.lock().unwrap().error.clone()
    }

    pub fn actual_family(&self) -> Option<&CString> {
        self.actual.get()
    }

    pub fn path(&self) -> Option<&CString> {
        self.path.get()
    }

    pub fn is_remote(&self) -> bool {
        matches!(&self.source, FaceSource::Url(u) if files::is_remote(u))
    }

    /// Marks the face loading; false when it already is, or is loaded.
    fn begin(self: &Arc<Self>) -> bool {
        {
            let mut st = self.state.lock().unwrap();
            let status = self.status();
            if status == LOADED || status == LOADING {
                return false;
            }
            st.error = None;
            self.status.store(LOADING, Ordering::Release);
        }
        set::face_loading(self);
        true
    }

    /// Loads a local, `data:` or byte source synchronously. A remote source stays loading until
    /// its bytes arrive through `load_data` (or `fail`).
    pub fn load(self: &Arc<Self>) -> i32 {
        if !self.begin() {
            return self.status();
        }
        let result = match &self.source {
            FaceSource::None => Ok(()),
            FaceSource::Invalid(e) => Err(e.clone()),
            FaceSource::Data(Ok(path)) => self.register(path),
            FaceSource::Data(Err(e)) => Err(e.clone()),
            FaceSource::Url(url) => match files::classify(url) {
                Ok(Source::Remote(_)) => {
                    self.state.lock().unwrap().awaiting_data = true;
                    return LOADING;
                }
                Ok(Source::File(path)) => self.register(&path),
                Ok(Source::Data(bytes)) => files::persist(&bytes).and_then(|p| self.register(&p)),
                Err(e) => Err(e),
            },
        };
        self.settle(result)
    }

    /// Loads the face from font bytes (a remote source's download, or new data).
    pub fn load_data(self: &Arc<Self>, bytes: &[u8]) -> i32 {
        let provider = std::mem::take(&mut self.state.lock().unwrap().awaiting_data);
        if !provider && !self.begin() {
            return self.status();
        }
        let result = files::persist(bytes).and_then(|p| self.register(&p));
        self.settle(result)
    }

    /// Fails a load waiting for its bytes.
    pub fn fail(self: &Arc<Self>, error: &str) -> i32 {
        if !std::mem::take(&mut self.state.lock().unwrap().awaiting_data) {
            return self.status();
        }
        self.settle(Err(if error.is_empty() { "Failed to load font".into() } else { error.into() }))
    }

    fn register(&self, path: &Path) -> Result<(), String> {
        let (weight, italic) = {
            let d = self.descriptors.lock().unwrap();
            (d.weight, d.italic())
        };
        let actual = fontconfig::register(path, &self.family.to_string_lossy(), weight, italic)?;
        let _ = self.actual.set(c_string(&actual));
        let _ = self.path.set(CString::new(path.as_os_str().as_bytes()).unwrap_or_default());
        Ok(())
    }

    fn settle(self: &Arc<Self>, result: Result<(), String>) -> i32 {
        let status = if result.is_ok() { LOADED } else { ERROR };
        let error = result.err();
        {
            let mut st = self.state.lock().unwrap();
            st.error = error.clone();
            self.status.store(status, Ordering::Release);
        }
        set::face_settled(self, error.as_deref());
        status
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fontconfig::tests::fixture;
    use crate::set::tests::SERIAL;

    #[test]
    fn lifecycle_from_path() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let face = Face::new("Stix Path", Some(&format!("url('{}') format('truetype')", fixture("stix_two_text_regular.ttf").display())));
        assert_eq!(face.status(), UNLOADED);
        assert_eq!(face.load(), LOADED);
        assert_eq!(face.load(), LOADED);
        assert!(face.actual_family().unwrap().to_str().unwrap().starts_with("STIX Two Text"));
        assert!(face.error().is_none());
    }

    #[test]
    fn errors_and_retry() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let face = Face::new("Missing", Some("/nonexistent/font.ttf"));
        assert_eq!(face.load(), ERROR);
        assert!(face.error().unwrap().contains("not found"));
        assert_eq!(face.load(), ERROR, "retries");
        assert_eq!(Face::new("Eot", Some("url(a.eot) format('embedded-opentype')")).load(), ERROR);
        assert_eq!(Face::new("serif", None).load(), LOADED);
    }

    #[test]
    fn data_and_remote() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        crate::files::tests::use_test_cache();
        let bytes = std::fs::read(fixture("stix_two_text_italic.ttf")).unwrap();
        let face = Face::new_data("Stix Data", &bytes);
        assert_eq!(face.load(), LOADED);

        let remote = Face::new("Stix Remote", Some("https://example.invalid/stix.ttf"));
        assert!(remote.is_remote());
        assert_eq!(remote.load(), LOADING);
        assert_eq!(remote.load(), LOADING);
        assert_eq!(remote.load_data(&bytes), LOADED);

        let failing = Face::new("Stix Fail", Some("https://example.invalid/x.ttf"));
        assert_eq!(failing.fail("not loading"), UNLOADED);
        assert_eq!(failing.load(), LOADING);
        assert_eq!(failing.fail("HTTP 404"), ERROR);
        assert_eq!(failing.error().as_deref(), Some("HTTP 404"));

        assert_eq!(Face::new_data("Garbage", b"not a font").load(), ERROR);
    }
}
