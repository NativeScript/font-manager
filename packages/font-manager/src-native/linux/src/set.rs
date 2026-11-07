//! The process-wide `FontFaceSet` (`document.fonts`), its loading periods and listeners.

use crate::css::{self, Shorthand};
use crate::face::{Face, LOADED, LOADING};
use crate::fontconfig;
use std::collections::HashMap;
use std::ffi::{c_char, c_void, CString};
use std::sync::atomic::{AtomicI32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

pub const CHANGE_ADDED: i32 = 0;
pub const CHANGE_DELETED: i32 = 1;
pub const CHANGE_CLEARED: i32 = 2;
pub const CHANGE_LOADED: i32 = 3;
pub const CHANGE_ERROR: i32 = 4;

pub const EVENT_STATUS: i32 = 0;
pub const EVENT_LOADING: i32 = 1;
pub const EVENT_LOADING_DONE: i32 = 2;
pub const EVENT_LOADING_ERROR: i32 = 3;

pub const SET_LOADING: i32 = 0;
pub const SET_LOADED: i32 = 1;

pub type FaceList = Vec<Arc<Face>>;
pub type ChangedFn = unsafe extern "C" fn(reason: i32, face: *const Face, user_data: *mut c_void);
pub type EventFn =
    unsafe extern "C" fn(event: i32, status: i32, faces: *const FaceList, error: *const c_char, user_data: *mut c_void);

#[derive(Default)]
struct State {
    faces: FaceList,
    by_family: HashMap<String, FaceList>,
    loading: FaceList,
    loaded: FaceList,
    failed: FaceList,
    last_error: Option<String>,
}

/// A finished loading period, raised once the lock is released.
#[derive(Default)]
struct PeriodEnd {
    ended: bool,
    loaded: FaceList,
    failed: FaceList,
    error: Option<String>,
}

static STATE: Mutex<Option<State>> = Mutex::new(None);
static CHANGED: Mutex<Vec<(i32, ChangedFn, usize)>> = Mutex::new(Vec::new());
static EVENTS: Mutex<Vec<(i32, EventFn, usize)>> = Mutex::new(Vec::new());
static NEXT_LISTENER: AtomicI32 = AtomicI32::new(1);
static GENERATION: AtomicU64 = AtomicU64::new(1);

pub fn generation() -> u64 {
    GENERATION.load(Ordering::Acquire)
}

fn with<R>(f: impl FnOnce(&mut State) -> R) -> R {
    let mut guard = STATE.lock().unwrap();
    f(guard.get_or_insert_with(State::default))
}

fn contains(list: &FaceList, face: &Arc<Face>) -> bool {
    list.iter().any(|f| Arc::ptr_eq(f, face))
}

fn remove(list: &mut FaceList, face: &Arc<Face>) -> bool {
    let before = list.len();
    list.retain(|f| !Arc::ptr_eq(f, face));
    list.len() != before
}

pub fn add_changed_listener(f: ChangedFn, user_data: *mut c_void) -> i32 {
    let id = NEXT_LISTENER.fetch_add(1, Ordering::Relaxed);
    CHANGED.lock().unwrap().push((id, f, user_data as usize));
    id
}

pub fn remove_changed_listener(id: i32) -> bool {
    let mut l = CHANGED.lock().unwrap();
    let before = l.len();
    l.retain(|(i, ..)| *i != id);
    l.len() != before
}

pub fn add_event_listener(f: EventFn, user_data: *mut c_void) -> i32 {
    let id = NEXT_LISTENER.fetch_add(1, Ordering::Relaxed);
    EVENTS.lock().unwrap().push((id, f, user_data as usize));
    id
}

pub fn remove_event_listener(id: i32) -> bool {
    let mut l = EVENTS.lock().unwrap();
    let before = l.len();
    l.retain(|(i, ..)| *i != id);
    l.len() != before
}

fn notify_changed(reason: i32, face: Option<&Arc<Face>>) {
    GENERATION.fetch_add(1, Ordering::AcqRel);
    let listeners = CHANGED.lock().unwrap().clone();
    let ptr = face.map_or(std::ptr::null(), Arc::as_ptr);
    for (_, f, data) in listeners {
        unsafe { f(reason, ptr, data as *mut c_void) };
    }
}

fn raise(event: i32, status: i32, faces: &FaceList, error: Option<&str>) {
    let listeners = EVENTS.lock().unwrap().clone();
    if listeners.is_empty() {
        return;
    }
    let error = error.map(|e| CString::new(e.replace('\0', "")).unwrap());
    let error_ptr = error.as_ref().map_or(std::ptr::null(), |e| e.as_ptr());
    for (_, f, data) in listeners {
        unsafe { f(event, status, faces, error_ptr, data as *mut c_void) };
    }
}

fn raise_end(end: PeriodEnd) {
    if !end.ended {
        return;
    }
    let first: FaceList = end.loaded.first().cloned().into_iter().collect();
    raise(EVENT_STATUS, SET_LOADED, &first, None);
    raise(EVENT_LOADING_DONE, SET_LOADED, &end.loaded, None);
    if !end.failed.is_empty() {
        raise(EVENT_LOADING_ERROR, SET_LOADED, &end.failed, end.error.as_deref());
    }
}

fn settle_locked(s: &mut State, face: Option<&Arc<Face>>, error: Option<&str>) -> PeriodEnd {
    if let Some(face) = face {
        match error {
            None => s.loaded.push(face.clone()),
            Some(e) => {
                s.failed.push(face.clone());
                s.last_error = Some(e.to_string());
            }
        }
    }
    if !s.loading.is_empty() {
        return PeriodEnd::default();
    }
    PeriodEnd {
        ended: true,
        loaded: std::mem::take(&mut s.loaded),
        failed: std::mem::take(&mut s.failed),
        error: s.last_error.take(),
    }
}

pub fn add(face: &Arc<Face>) -> bool {
    let added = with(|s| {
        if contains(&s.faces, face) {
            return false;
        }
        s.faces.push(face.clone());
        s.by_family.entry(face.family_key.clone()).or_default().push(face.clone());
        true
    });
    if added {
        notify_changed(CHANGE_ADDED, Some(face));
        if face.status() == LOADING {
            face_loading(face);
        }
    }
    added
}

pub fn delete(face: &Arc<Face>) -> bool {
    let end = with(|s| {
        if !remove(&mut s.faces, face) {
            return None;
        }
        if let Some(list) = s.by_family.get_mut(&face.family_key) {
            remove(list, face);
            if list.is_empty() {
                s.by_family.remove(&face.family_key);
            }
        }
        Some(if remove(&mut s.loading, face) && s.loading.is_empty() {
            settle_locked(s, None, None)
        } else {
            PeriodEnd::default()
        })
    });
    let Some(end) = end else { return false };
    notify_changed(CHANGE_DELETED, Some(face));
    raise_end(end);
    true
}

pub fn clear() {
    let end = with(|s| {
        if s.faces.is_empty() {
            return None;
        }
        s.faces.clear();
        s.by_family.clear();
        Some(if s.loading.is_empty() {
            PeriodEnd::default()
        } else {
            s.loading.clear();
            settle_locked(s, None, None)
        })
    });
    if let Some(end) = end {
        notify_changed(CHANGE_CLEARED, None);
        raise_end(end);
    }
}

pub fn has(face: &Arc<Face>) -> bool {
    with(|s| contains(&s.faces, face))
}

pub fn size() -> usize {
    with(|s| s.faces.len())
}

pub fn faces() -> FaceList {
    with(|s| s.faces.clone())
}

pub fn status() -> i32 {
    with(|s| if s.loading.is_empty() { SET_LOADED } else { SET_LOADING })
}

/// A member face started loading: the first one opens a loading period.
pub fn face_loading(face: &Arc<Face>) {
    let started = with(|s| {
        if !contains(&s.faces, face) || face.status() != LOADING || contains(&s.loading, face) {
            return false;
        }
        let started = s.loading.is_empty() && s.loaded.is_empty() && s.failed.is_empty();
        s.loading.push(face.clone());
        started
    });
    if started {
        let faces = vec![face.clone()];
        raise(EVENT_STATUS, SET_LOADING, &faces, None);
        raise(EVENT_LOADING, SET_LOADING, &faces, None);
    }
}

/// A face finished loading; fonts changed for everyone, not only for members.
pub fn face_settled(face: &Arc<Face>, error: Option<&str>) {
    let end = with(|s| {
        if remove(&mut s.loading, face) {
            settle_locked(s, Some(face), error)
        } else {
            PeriodEnd::default()
        }
    });
    notify_changed(if error.is_none() { CHANGE_LOADED } else { CHANGE_ERROR }, Some(face));
    raise_end(end);
}

/// The member face of `family` closest to the requested weight and style.
fn best_locked(s: &State, family: &str, weight: i32, italic: bool, oblique: bool, text: &str, loaded: bool) -> Option<Arc<Face>> {
    s.by_family
        .get(&family.to_lowercase())?
        .iter()
        .filter(|f| !loaded || f.status() == LOADED)
        .filter_map(|f| {
            let d = f.descriptors.lock().unwrap();
            d.covers(text).then(|| (d.score(weight, italic, oblique), f))
        })
        .min_by_key(|(score, _)| *score)
        .map(|(_, f)| f.clone())
}

fn has_family_locked(s: &State, family: &str) -> bool {
    s.by_family.contains_key(&family.to_lowercase())
}

/// The best member face for each family of a `font` shorthand; `None` when it doesn't parse.
pub fn matching(font: &str, text: &str) -> Option<FaceList> {
    let f = css::parse_shorthand(font)?;
    Some(with(|s| {
        let mut out = FaceList::new();
        for family in &f.families {
            if let Some(face) = best_locked(s, family, f.weight, f.italic, f.oblique, text, false) {
                if !contains(&out, &face) {
                    out.push(face);
                }
            }
        }
        out
    }))
}

/// Whether text in `font` can render without loading anything.
pub fn check(font: &str, text: &str) -> bool {
    let Some(f) = css::parse_shorthand(font) else { return false };
    let Shorthand { weight, italic, oblique, .. } = f;
    for family in &f.families {
        if css::is_generic(family) {
            continue;
        }
        if let Some(face) = with(|s| best_locked(s, family, weight, italic, oblique, text, false)) {
            if face.status() != LOADED {
                return false;
            }
            continue;
        }
        if fontconfig::mapped_family(family, weight, italic || oblique).is_none() && !fontconfig::family_exists(family) {
            return false;
        }
    }
    true
}

pub enum Resolved {
    Face(Arc<Face>),
    /// The family has member faces, none loaded yet.
    Pending,
    None,
}

pub fn resolve_member(family: &str, weight: i32, italic: bool) -> Resolved {
    with(|s| match best_locked(s, family, weight, italic, italic, "", true) {
        Some(face) => Resolved::Face(face),
        None if has_family_locked(s, family) => Resolved::Pending,
        None => Resolved::None,
    })
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::fontconfig::tests::fixture;
    use std::sync::Mutex as StdMutex;

    /// The set is process-wide: tests touching it run one at a time.
    pub static SERIAL: StdMutex<()> = StdMutex::new(());

    static LOG: StdMutex<Vec<String>> = StdMutex::new(Vec::new());

    unsafe extern "C" fn on_event(event: i32, status: i32, faces: *const FaceList, error: *const c_char, _: *mut c_void) {
        let names: Vec<String> = (*faces).iter().map(|f| f.family.to_string_lossy().into_owned()).collect();
        let error = if error.is_null() { String::new() } else { std::ffi::CStr::from_ptr(error).to_string_lossy().into_owned() };
        LOG.lock().unwrap().push(format!("event {event} {status} {} {error}", names.join(",")));
    }

    unsafe extern "C" fn on_changed(reason: i32, face: *const Face, _: *mut c_void) {
        let name = if face.is_null() { "-".into() } else { (*face).family.to_string_lossy().into_owned() };
        LOG.lock().unwrap().push(format!("changed {reason} {name}"));
    }

    fn take_log() -> Vec<String> {
        std::mem::take(&mut *LOG.lock().unwrap())
    }

    fn path(name: &str) -> String {
        fixture(name).display().to_string()
    }

    #[test]
    fn membership_and_events() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        clear();
        let events = add_event_listener(on_event, std::ptr::null_mut());
        let changed = add_changed_listener(on_changed, std::ptr::null_mut());
        take_log();

        let regular = Face::new("Set Stix", Some(&path("stix_two_text_regular.ttf")));
        let bold = Face::new("Set Stix", Some(&path("stix_two_text_bold.ttf")));
        bold.descriptors.lock().unwrap().set(crate::descriptors::Which::Weight, "bold");
        assert!(add(&regular) && !add(&regular) && add(&bold));
        assert_eq!(size(), 2);
        assert!(has(&bold));
        assert!(!check("16px 'Set Stix'", ""), "unloaded");
        assert!(Arc::ptr_eq(&matching("bold 16px 'Set Stix'", "").unwrap()[0], &bold));
        assert!(Arc::ptr_eq(&matching("16px 'Set Stix', serif", "").unwrap()[0], &regular));
        assert!(matching("Set Stix", "").is_none());

        assert_eq!(regular.load(), LOADED);
        assert!(check("16px 'Set Stix'", "abc"));
        assert!(!check("bold 16px 'Set Stix'", ""), "bold face isn't loaded");
        assert_eq!(status(), SET_LOADED);

        let remote = Face::new("Set Remote", Some("https://example.invalid/a.ttf"));
        add(&remote);
        assert_eq!(remote.load(), LOADING);
        assert_eq!(status(), SET_LOADING);
        assert_eq!(bold.load(), LOADED);
        assert_eq!(status(), SET_LOADING);
        remote.fail("offline");
        assert_eq!(status(), SET_LOADED);

        let log = take_log();
        assert_eq!(
            log,
            [
                "changed 0 Set Stix",
                "changed 0 Set Stix",
                "event 0 0 Set Stix ",
                "event 1 0 Set Stix ",
                "changed 3 Set Stix",
                "event 0 1 Set Stix ",
                "event 2 1 Set Stix ",
                "changed 0 Set Remote",
                "event 0 0 Set Remote ",
                "event 1 0 Set Remote ",
                "changed 3 Set Stix",
                "changed 4 Set Remote",
                "event 0 1 Set Stix ",
                "event 2 1 Set Stix ",
                "event 3 1 Set Remote offline",
            ]
        );

        assert!(delete(&bold) && !delete(&bold));
        clear();
        assert_eq!(size(), 0);
        assert_eq!(take_log(), ["changed 1 Set Stix", "changed 2 -"]);
        assert!(remove_event_listener(events) && remove_changed_listener(changed) && !remove_changed_listener(changed));
    }

    #[test]
    fn deleting_the_last_loading_face_ends_the_period() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        clear();
        let face = Face::new("Pending Remote", Some("https://example.invalid/b.ttf"));
        add(&face);
        face.load();
        assert_eq!(status(), SET_LOADING);
        delete(&face);
        assert_eq!(status(), SET_LOADED);
        face.fail("gone");
    }

    #[test]
    fn check_system_and_generic() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        assert!(check("16px serif", ""));
        assert!(check("16px 'DejaVu Sans', monospace", "") == fontconfig::family_exists("DejaVu Sans"));
        assert!(!check("16px \"NonExistentFont12345\"", ""));
        assert!(!check("NonExistent", ""));
    }
}
