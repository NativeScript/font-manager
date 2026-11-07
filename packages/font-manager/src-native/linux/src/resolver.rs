//! CSS `font-family` list + weight + style -> the family Pango should be given.

use crate::set::{self, Resolved};
use crate::{css, fontconfig};
use std::collections::{HashMap, HashSet};
use std::ffi::{CStr, CString};
use std::sync::Mutex;

pub const FALLBACK: &str = "sans-serif";

/// Resolved names live for the process (a handful of families), so callers needn't free them.
fn intern(name: &str) -> &'static CStr {
    static POOL: Mutex<Option<HashSet<&'static CStr>>> = Mutex::new(None);
    let c = CString::new(name.replace('\0', "")).unwrap();
    let mut pool = POOL.lock().unwrap();
    let pool = pool.get_or_insert_with(HashSet::new);
    if let Some(existing) = pool.get(c.as_c_str()) {
        return existing;
    }
    let leaked: &'static CStr = Box::leak(c.into_boxed_c_str());
    pool.insert(leaked);
    leaked
}

pub fn resolve_uncached(families: &str, weight: i32, italic: bool) -> String {
    for family in css::parse_family_list(families) {
        match set::resolve_member(&family, weight, italic) {
            Resolved::Face(face) => {
                return match face.actual_family() {
                    Some(actual) => actual.to_string_lossy().into_owned(),
                    None => css::fontconfig_generic(&family).map_or(family, str::to_string),
                };
            }
            // CSS falls back while the family's faces load
            Resolved::Pending => continue,
            Resolved::None => {}
        }
        if let Some(generic) = css::fontconfig_generic(&family) {
            return generic.to_string();
        }
        if let Some(actual) = fontconfig::mapped_family(&family, weight, italic) {
            return actual;
        }
        if fontconfig::family_exists(&family) {
            return family;
        }
    }
    FALLBACK.to_string()
}

type Key = (i32, bool);

struct Cache {
    stamp: (u64, u64, i32),
    entries: HashMap<String, Vec<(Key, &'static CStr)>>,
}

static CACHE: Mutex<Option<Cache>> = Mutex::new(None);

/// Cached by input until fonts or the set change.
pub fn resolve(families: &str, weight: i32, italic: bool) -> &'static CStr {
    let stamp = (fontconfig::generation(), set::generation(), fontconfig::app_font_count());
    {
        let mut cache = CACHE.lock().unwrap();
        let cache = cache.get_or_insert_with(|| Cache { stamp, entries: HashMap::new() });
        if cache.stamp != stamp {
            cache.stamp = stamp;
            cache.entries.clear();
        }
        if let Some(hit) = cache.entries.get(families).and_then(|v| v.iter().find(|(k, _)| *k == (weight, italic))) {
            return hit.1;
        }
    }
    let resolved = intern(&resolve_uncached(families, weight, italic));
    let mut cache = CACHE.lock().unwrap();
    if let Some(cache) = cache.as_mut().filter(|c| c.stamp == stamp) {
        // keyed by caller strings: bound it
        if cache.entries.len() >= 4096 {
            cache.entries.clear();
        }
        cache.entries.entry(families.to_string()).or_default().push(((weight, italic), resolved));
    }
    resolved
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::descriptors::Which;
    use crate::face::Face;
    use crate::fontconfig::tests::fixture;
    use crate::set::tests::SERIAL;

    fn r(families: &str, weight: i32, italic: bool) -> &'static str {
        resolve(families, weight, italic).to_str().unwrap()
    }

    #[test]
    fn generics_and_fallback() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        assert_eq!(r("system-ui", 400, false), "sans-serif");
        assert_eq!(r("'NoSuchFamily', ui-monospace", 400, false), "monospace");
        assert_eq!(r("NoSuchFamily", 400, false), FALLBACK);
        assert_eq!(r("", 400, false), FALLBACK);
        if fontconfig::family_exists("DejaVu Sans") {
            assert_eq!(r("'dejavu sans', serif", 400, false), "dejavu sans");
        }
        assert!(std::ptr::eq(resolve("serif", 400, false), resolve("serif", 400, false)));
    }

    #[test]
    fn member_faces_by_weight_and_style() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        set::clear();
        let face = |file: &str, weight: &str, style: &str| {
            let f = Face::new("Resolver Stix", Some(&fixture(file).display().to_string()));
            let mut d = f.descriptors.lock().unwrap();
            d.set(Which::Weight, weight);
            d.set(Which::Style, style);
            drop(d);
            set::add(&f);
            f
        };
        let regular = face("stix_two_text_regular.ttf", "400", "normal");
        let bold = face("stix_two_text_bold.ttf", "700", "normal");
        assert_eq!(r("'Resolver Stix', monospace", 400, false), "monospace", "nothing loaded yet");
        regular.load();
        let regular_family = regular.actual_family().unwrap().to_str().unwrap().to_string();
        assert_eq!(r("'Resolver Stix', monospace", 700, false), regular_family, "only the regular is loaded");
        bold.load();
        assert_eq!(r("'Resolver Stix', monospace", 700, false), bold.actual_family().unwrap().to_str().unwrap());
        assert_eq!(r("'Resolver Stix'", 300, false), regular_family);
        set::clear();
        // still registered with fontconfig under the CSS name
        assert_eq!(r("'Resolver Stix'", 400, false), regular_family);
    }
}
