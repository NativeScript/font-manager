//! Registration with fontconfig, the process-wide registry Pango resolves families from.

use std::collections::{HashMap, HashSet};
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

#[repr(C)]
struct FcFontSet {
    nfont: c_int,
    sfont: c_int,
    fonts: *mut *mut c_void,
}

const FC_RESULT_MATCH: c_int = 0;
const FC_SET_APPLICATION: c_int = 1;

extern "C" {
    fn FcConfigGetCurrent() -> *mut c_void;
    fn FcConfigAppFontAddFile(config: *mut c_void, file: *const c_char) -> c_int;
    fn FcConfigGetFonts(config: *mut c_void, set: c_int) -> *mut FcFontSet;
    fn FcConfigParseAndLoadFromMemory(config: *mut c_void, buffer: *const c_char, complain: c_int) -> c_int;
    fn FcFreeTypeQuery(file: *const c_char, id: c_int, blanks: *mut c_void, count: *mut c_int) -> *mut c_void;
    fn FcPatternCreate() -> *mut c_void;
    fn FcPatternDestroy(p: *mut c_void);
    fn FcPatternGetString(p: *const c_void, object: *const c_char, n: c_int, s: *mut *const c_char) -> c_int;
    fn FcObjectSetCreate() -> *mut c_void;
    fn FcObjectSetAdd(os: *mut c_void, object: *const c_char) -> c_int;
    fn FcObjectSetDestroy(os: *mut c_void);
    fn FcFontList(config: *mut c_void, p: *mut c_void, os: *mut c_void) -> *mut FcFontSet;
    fn FcFontSetDestroy(s: *mut FcFontSet);
    fn FcWeightFromOpenType(weight: c_int) -> c_int;
}

const FAMILY: &CStr = c"family";

/// Bumped whenever fonts or family mappings change.
static GENERATION: AtomicU64 = AtomicU64::new(1);

pub fn generation() -> u64 {
    GENERATION.load(Ordering::Acquire)
}

struct Mapping {
    actual: String,
    weight: (i32, i32),
    italic: bool,
}

#[derive(Default)]
struct Registry {
    /// Families inside each registered file.
    files: HashMap<PathBuf, Vec<String>>,
    /// Loaded faces per lowercased CSS family.
    mappings: HashMap<String, Vec<Mapping>>,
    rules: HashSet<String>,
    /// Lowercased families fontconfig knows, built on first use.
    families: Option<HashSet<String>>,
    /// Application font count `families` was built with, to notice fonts others add.
    app_fonts: c_int,
}

fn registry() -> &'static Mutex<Registry> {
    static R: OnceLock<Mutex<Registry>> = OnceLock::new();
    R.get_or_init(Default::default)
}

unsafe fn pattern_families(p: *const c_void, out: &mut Vec<String>) {
    let mut i = 0;
    let mut s: *const c_char = std::ptr::null();
    while FcPatternGetString(p, FAMILY.as_ptr(), i, &mut s) == FC_RESULT_MATCH && !s.is_null() {
        out.push(CStr::from_ptr(s).to_string_lossy().into_owned());
        i += 1;
    }
}

pub fn app_font_count() -> c_int {
    unsafe {
        let set = FcConfigGetFonts(std::ptr::null_mut(), FC_SET_APPLICATION);
        if set.is_null() {
            0
        } else {
            (*set).nfont
        }
    }
}

fn all_families() -> HashSet<String> {
    let mut families = HashSet::new();
    unsafe {
        let pattern = FcPatternCreate();
        let os = FcObjectSetCreate();
        FcObjectSetAdd(os, FAMILY.as_ptr());
        let set = FcFontList(std::ptr::null_mut(), pattern, os);
        FcObjectSetDestroy(os);
        FcPatternDestroy(pattern);
        if !set.is_null() {
            let mut names = Vec::new();
            for i in 0..(*set).nfont as usize {
                pattern_families(*(*set).fonts.add(i), &mut names);
            }
            FcFontSetDestroy(set);
            families.extend(names.into_iter().map(|n| n.to_lowercase()));
        }
    }
    families
}

/// Whether fontconfig has a family by exactly this name (no substitution).
pub fn family_exists(family: &str) -> bool {
    let key = family.trim().to_lowercase();
    let mut r = registry().lock().unwrap();
    let count = app_font_count();
    if r.families.is_none() || count != r.app_fonts {
        r.families = Some(all_families());
        r.app_fonts = count;
    }
    r.families.as_ref().unwrap().contains(&key)
}

/// The family of the best loaded face registered for a CSS family.
pub fn mapped_family(css_family: &str, weight: i32, italic: bool) -> Option<String> {
    let r = registry().lock().unwrap();
    let list = r.mappings.get(&css_family.to_lowercase())?;
    list.iter()
        .min_by_key(|m| {
            let (lo, hi) = m.weight;
            let diff = (lo as i64 - weight as i64).max(weight as i64 - hi as i64).max(0);
            diff + if m.italic == italic { 0 } else { 1000 }
        })
        .map(|m| m.actual.clone())
}

fn escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

fn family_test(css: &str) -> String {
    format!(r#"<test name="family" qual="any" ignore-blanks="true"><string>{}</string></test>"#, escape(css))
}

/// Rule giving `css` the faces of `actual` (after the CSS name, so earlier families in a list still win).
fn alias_rule(css: &str, actual: &str) -> String {
    format!(
        r#"<match target="pattern">{}<edit name="family" mode="append" binding="strong"><string>{}</string></edit></match>"#,
        family_test(css),
        escape(actual)
    )
}

/// Rule sending requests for one weight / slant of `css` to `actual`, ahead of the plain aliases.
fn face_rule(css: &str, m: &Mapping) -> String {
    let (lo, hi) = m.weight;
    let weight = unsafe {
        if lo == hi {
            format!(r#"<test name="weight" compare="eq"><int>{}</int></test>"#, FcWeightFromOpenType(lo))
        } else {
            format!(
                r#"<test name="weight" compare="more_eq"><int>{}</int></test><test name="weight" compare="less_eq"><int>{}</int></test>"#,
                FcWeightFromOpenType(lo),
                FcWeightFromOpenType(hi)
            )
        }
    };
    format!(
        r#"<match target="pattern">{}{}<test name="slant" compare="{}"><int>0</int></test><edit name="family" mode="prepend" binding="strong"><string>{}</string></edit></match>"#,
        family_test(css),
        weight,
        if m.italic { "not_eq" } else { "eq" },
        escape(&m.actual)
    )
}

fn load_rules(rules: &[String]) {
    if rules.is_empty() {
        return;
    }
    let xml = format!(
        r#"<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig>{}</fontconfig>"#,
        rules.concat()
    );
    let xml = CString::new(xml).unwrap_or_default();
    unsafe { FcConfigParseAndLoadFromMemory(FcConfigGetCurrent(), xml.as_ptr(), 1) };
}

/// Registers a font file for a CSS family; returns the family inside the file.
pub fn register(path: &Path, css_family: &str, weight: (i32, i32), italic: bool) -> Result<String, String> {
    let mut r = registry().lock().unwrap();
    let mut changed = false;
    let families = match r.files.get(path) {
        Some(f) => f.clone(),
        None => {
            let c_path = CString::new(path.as_os_str().as_bytes()).map_err(|_| "Invalid font path".to_string())?;
            let mut families = Vec::new();
            unsafe {
                let mut count = 0;
                let pattern = FcFreeTypeQuery(c_path.as_ptr(), 0, std::ptr::null_mut(), &mut count);
                if pattern.is_null() {
                    return Err(if path.exists() {
                        format!("Unsupported font file {}", path.display())
                    } else {
                        format!("Font file not found: {}", path.display())
                    });
                }
                pattern_families(pattern, &mut families);
                FcPatternDestroy(pattern);
                if FcConfigAppFontAddFile(std::ptr::null_mut(), c_path.as_ptr()) == 0 {
                    return Err(format!("fontconfig refused {}", path.display()));
                }
            }
            if let Some(known) = r.families.as_mut() {
                known.extend(families.iter().map(|f| f.to_lowercase()));
            }
            r.app_fonts = app_font_count();
            r.files.insert(path.to_path_buf(), families.clone());
            changed = true;
            families
        }
    };
    let actual = families.first().cloned().unwrap_or_else(|| css_family.to_string());

    let key = css_family.to_lowercase();
    let mapping = Mapping { actual: actual.clone(), weight, italic };
    let list = r.mappings.entry(key.clone()).or_default();
    if !list.iter().any(|m| m.actual == mapping.actual && m.weight == mapping.weight && m.italic == mapping.italic) {
        list.push(mapping);
    }
    let mut rules = Vec::new();
    if key != actual.to_lowercase() {
        rules.push(alias_rule(css_family, &actual));
    }
    // several files behind one CSS family: weight / slant pick the file's family
    let list = &r.mappings[&key];
    let distinct = list.iter().any(|m| !m.actual.eq_ignore_ascii_case(&list[0].actual));
    if distinct {
        rules.extend(list.iter().map(|m| face_rule(css_family, m)));
    }
    rules.retain(|rule| !r.rules.contains(rule));
    if !rules.is_empty() {
        load_rules(&rules);
        r.rules.extend(rules);
        changed = true;
    }
    drop(r);
    if changed {
        GENERATION.fetch_add(1, Ordering::AcqRel);
        refresh_pango();
    }
    Ok(actual)
}

static REFRESH_PENDING: AtomicBool = AtomicBool::new(false);

type FontMapDefault = unsafe extern "C" fn() -> *mut c_void;
type ConfigChanged = unsafe extern "C" fn(*mut c_void);
type SourceFunc = unsafe extern "C" fn(*mut c_void) -> c_int;
type InvokeFull = unsafe extern "C" fn(*mut c_void, c_int, SourceFunc, *mut c_void, *mut c_void);

const G_PRIORITY_HIGH: c_int = -100;

unsafe fn symbol(name: &CStr) -> *mut c_void {
    libc::dlsym(libc::RTLD_DEFAULT, name.as_ptr())
}

unsafe extern "C" fn refresh_font_map(_: *mut c_void) -> c_int {
    REFRESH_PENDING.store(false, Ordering::Release);
    let default = symbol(c"pango_cairo_font_map_get_default");
    let changed = symbol(c"pango_fc_font_map_config_changed");
    if !default.is_null() && !changed.is_null() {
        let default: FontMapDefault = std::mem::transmute(default);
        let changed: ConfigChanged = std::mem::transmute(changed);
        let map = default();
        if !map.is_null() {
            changed(map);
        }
    }
    0
}

/// Pango (when loaded) re-reads fontconfig, on the thread running the default main context:
/// its default font map is per thread.
fn refresh_pango() {
    unsafe {
        if symbol(c"pango_fc_font_map_config_changed").is_null() || REFRESH_PENDING.swap(true, Ordering::AcqRel) {
            return;
        }
        let invoke = symbol(c"g_main_context_invoke_full");
        if invoke.is_null() {
            refresh_font_map(std::ptr::null_mut());
        } else {
            let invoke: InvokeFull = std::mem::transmute(invoke);
            invoke(std::ptr::null_mut(), G_PRIORITY_HIGH, refresh_font_map, std::ptr::null_mut(), std::ptr::null_mut());
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub fn fixture(name: &str) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../ios/FontManager/Tests/FontManagerTests/Fixtures").join(name)
    }

    #[test]
    fn registers_and_maps() {
        let path = fixture("stix_two_text_bold.ttf");
        let actual = register(&path, "FcTestAlias", (700, 700), false).unwrap();
        assert!(actual.to_lowercase().starts_with("stix two text"), "{actual}");
        assert!(family_exists(&actual));
        assert_eq!(mapped_family("fctestalias", 700, false).as_deref(), Some(actual.as_str()));
        assert!(!family_exists("NoSuchFamily12345"));
        let before = generation();
        register(&path, "FcTestAlias", (700, 700), false).unwrap();
        assert_eq!(generation(), before, "re-registering changes nothing");
        assert!(register(Path::new("/nonexistent.ttf"), "x", (400, 400), false).unwrap_err().contains("not found"));
    }

    extern "C" {
        fn FcNameParse(name: *const c_char) -> *mut c_void;
        fn FcPatternAddInteger(p: *mut c_void, object: *const c_char, i: c_int) -> c_int;
        fn FcConfigSubstitute(config: *mut c_void, p: *mut c_void, kind: c_int) -> c_int;
        fn FcDefaultSubstitute(p: *mut c_void);
        fn FcFontMatch(config: *mut c_void, p: *mut c_void, result: *mut c_int) -> *mut c_void;
    }

    /// What fontconfig gives Pango for a family + weight + slant: the matched file name.
    pub fn matched_file(family: &str, weight: i32, italic: bool) -> String {
        unsafe {
            let name = CString::new(family.replace('-', "\\-")).unwrap();
            let p = FcNameParse(name.as_ptr());
            FcPatternAddInteger(p, c"weight".as_ptr(), FcWeightFromOpenType(weight));
            FcPatternAddInteger(p, c"slant".as_ptr(), if italic { 100 } else { 0 });
            FcConfigSubstitute(std::ptr::null_mut(), p, 0);
            FcDefaultSubstitute(p);
            let mut result = 0;
            let m = FcFontMatch(std::ptr::null_mut(), p, &mut result);
            FcPatternDestroy(p);
            let mut file: *const c_char = std::ptr::null();
            FcPatternGetString(m, c"file".as_ptr(), 0, &mut file);
            let file = Path::new(&*CStr::from_ptr(file).to_string_lossy()).file_name().unwrap().to_string_lossy().into_owned();
            FcPatternDestroy(m);
            file
        }
    }

    fn android_font(name: &str) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../android/fontmanager/src/main/res/font").join(name)
    }

    #[test]
    fn css_names_reach_the_files() {
        register(&fixture("stix_two_text_italic.ttf"), "Alias Only", (400, 400), true).unwrap();
        assert_eq!(matched_file("Alias Only", 400, true), "stix_two_text_italic.ttf");
        assert_eq!(matched_file("alias only", 400, true), "stix_two_text_italic.ttf");

        // one CSS family over files of two font families: weight / slant pick the file
        register(&android_font("stix_two_math_regular.ttf"), "Mixed Faces", (400, 400), false).unwrap();
        register(&android_font("stix_two_text_bold_italic.ttf"), "Mixed Faces", (700, 700), true).unwrap();
        assert_eq!(matched_file("Mixed Faces", 400, false), "stix_two_math_regular.ttf");
        assert_eq!(matched_file("Mixed Faces", 700, true), "stix_two_text_bold_italic.ttf");
    }

    #[test]
    fn rule_xml() {
        let m = Mapping { actual: "A&B".into(), weight: (700, 700), italic: true };
        let rule = face_rule("Foo <x>", &m);
        assert!(rule.contains("Foo &lt;x&gt;") && rule.contains("A&amp;B") && rule.contains("not_eq"));
        assert!(alias_rule("Foo", "Bar").contains(r#"mode="append""#));
    }
}
