//! libfontmanager.so: the web font loading API (FontFace, FontFaceSet) over fontconfig, with the
//! C ABI declared in include/font_manager.h.

#![allow(clippy::missing_safety_doc)]

mod css;
mod descriptors;
mod face;
mod files;
mod fontconfig;
mod resolver;
mod set;

use descriptors::{Descriptors, Which};
use face::{Face, SharedDescriptors};
use set::FaceList;
use std::borrow::Cow;
use std::ffi::{c_char, c_void, CStr, CString};
use std::mem::ManuallyDrop;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

type DescriptorsCell = Mutex<Descriptors>;

unsafe fn text<'a>(p: *const c_char) -> Cow<'a, str> {
    if p.is_null() {
        Cow::Borrowed("")
    } else {
        CStr::from_ptr(p).to_string_lossy()
    }
}

unsafe fn bytes<'a>(data: *const c_void, length: usize) -> &'a [u8] {
    if data.is_null() || length == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(data as *const u8, length)
    }
}

fn owned(s: String) -> *mut c_char {
    CString::new(s.replace('\0', "")).unwrap().into_raw()
}

/// The `Arc` behind a handle, without taking a reference.
unsafe fn face(p: *const Face) -> Option<ManuallyDrop<Arc<Face>>> {
    (!p.is_null()).then(|| ManuallyDrop::new(Arc::from_raw(p)))
}

unsafe fn descriptors(p: *const DescriptorsCell) -> Option<ManuallyDrop<SharedDescriptors>> {
    (!p.is_null()).then(|| ManuallyDrop::new(Arc::from_raw(p)))
}

fn face_handle(face: Arc<Face>) -> *mut Face {
    Arc::into_raw(face) as *mut Face
}

fn list_handle(list: FaceList) -> *mut FaceList {
    Box::into_raw(Box::new(list))
}

fn dir(p: *const c_char) -> Option<PathBuf> {
    let s = unsafe { text(p) };
    (!s.is_empty()).then(|| PathBuf::from(s.into_owned()))
}

#[no_mangle]
pub extern "C" fn fm_set_app_dir(path: *const c_char) {
    files::set_app_dir(dir(path));
}

#[no_mangle]
pub extern "C" fn fm_set_cache_dir(path: *const c_char) {
    files::set_cache_dir(dir(path));
}

#[no_mangle]
pub unsafe extern "C" fn fm_string_free(string: *mut c_char) {
    if !string.is_null() {
        drop(CString::from_raw(string));
    }
}

#[no_mangle]
pub unsafe extern "C" fn fm_descriptors_new(family: *const c_char) -> *mut DescriptorsCell {
    Arc::into_raw(Arc::new(Mutex::new(Descriptors::new(&text(family))))) as *mut _
}

#[no_mangle]
pub unsafe extern "C" fn fm_descriptors_ref(d: *mut DescriptorsCell) -> *mut DescriptorsCell {
    if !d.is_null() {
        Arc::increment_strong_count(d as *const DescriptorsCell);
    }
    d
}

#[no_mangle]
pub unsafe extern "C" fn fm_descriptors_unref(d: *mut DescriptorsCell) {
    if !d.is_null() {
        Arc::decrement_strong_count(d as *const DescriptorsCell);
    }
}

#[no_mangle]
pub unsafe extern "C" fn fm_descriptors_get(d: *const DescriptorsCell, which: i32) -> *mut c_char {
    match (descriptors(d), Which::from_i32(which)) {
        (Some(d), Some(which)) => owned(d.lock().unwrap().get(which)),
        _ => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn fm_descriptors_set(d: *mut DescriptorsCell, which: i32, value: *const c_char) -> bool {
    match (descriptors(d), Which::from_i32(which)) {
        (Some(d), Some(which)) => d.lock().unwrap().set(which, &text(value)),
        _ => false,
    }
}

#[no_mangle]
pub unsafe extern "C" fn fm_descriptors_update(d: *mut DescriptorsCell, css: *const c_char) {
    if let Some(d) = descriptors(d) {
        d.lock().unwrap().update(&text(css));
    }
}

#[no_mangle]
pub unsafe extern "C" fn fm_descriptors_weight(d: *const DescriptorsCell) -> i32 {
    descriptors(d).map_or(400, |d| d.lock().unwrap().weight.0)
}

#[no_mangle]
pub unsafe extern "C" fn fm_descriptors_italic(d: *const DescriptorsCell) -> bool {
    descriptors(d).is_some_and(|d| d.lock().unwrap().italic())
}

#[no_mangle]
pub unsafe extern "C" fn fm_descriptors_display(d: *const DescriptorsCell) -> i32 {
    descriptors(d).map_or(0, |d| d.lock().unwrap().display as i32)
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_new(family: *const c_char, source: *const c_char) -> *mut Face {
    let source = (!source.is_null()).then(|| text(source));
    face_handle(Face::new(&text(family), source.as_deref()))
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_new_data(family: *const c_char, data: *const c_void, length: usize) -> *mut Face {
    face_handle(Face::new_data(&text(family), bytes(data, length)))
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_ref(f: *mut Face) -> *mut Face {
    if !f.is_null() {
        Arc::increment_strong_count(f as *const Face);
    }
    f
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_unref(f: *mut Face) {
    if !f.is_null() {
        Arc::decrement_strong_count(f as *const Face);
    }
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_id(f: *const Face) -> u32 {
    face(f).map_or(0, |f| f.id)
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_family(f: *const Face) -> *const c_char {
    face(f).map_or(std::ptr::null(), |f| f.family.as_ptr())
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_url(f: *const Face) -> *const c_char {
    face(f).and_then(|f| f.url.as_ref().map(|u| u.as_ptr())).unwrap_or(std::ptr::null())
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_is_remote(f: *const Face) -> bool {
    face(f).is_some_and(|f| f.is_remote())
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_descriptors(f: *const Face) -> *mut DescriptorsCell {
    face(f).map_or(std::ptr::null_mut(), |f| Arc::into_raw(f.descriptors.clone()) as *mut _)
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_status(f: *const Face) -> i32 {
    face(f).map_or(face::ERROR, |f| f.status())
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_error(f: *const Face) -> *mut c_char {
    face(f).and_then(|f| f.error()).map_or(std::ptr::null_mut(), owned)
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_actual_family(f: *const Face) -> *const c_char {
    face(f).and_then(|f| f.actual_family().map(|s| s.as_ptr())).unwrap_or(std::ptr::null())
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_path(f: *const Face) -> *const c_char {
    face(f).and_then(|f| f.path().map(|s| s.as_ptr())).unwrap_or(std::ptr::null())
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_load(f: *mut Face) -> i32 {
    face(f).map_or(face::ERROR, |f| f.load())
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_load_data(f: *mut Face, data: *const c_void, length: usize) -> i32 {
    face(f).map_or(face::ERROR, |f| f.load_data(bytes(data, length)))
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_fail(f: *mut Face, error: *const c_char) -> i32 {
    face(f).map_or(face::ERROR, |f| f.fail(&text(error)))
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_list_size(list: *const FaceList) -> usize {
    list.as_ref().map_or(0, Vec::len)
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_list_get(list: *const FaceList, index: usize) -> *mut Face {
    list.as_ref()
        .and_then(|l| l.get(index))
        .map_or(std::ptr::null_mut(), |f| Arc::as_ptr(f) as *mut Face)
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_list_free(list: *mut FaceList) {
    if !list.is_null() {
        drop(Box::from_raw(list));
    }
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_set_add(f: *mut Face) -> bool {
    face(f).is_some_and(|f| set::add(&f))
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_set_delete(f: *mut Face) -> bool {
    face(f).is_some_and(|f| set::delete(&f))
}

#[no_mangle]
pub extern "C" fn fm_face_set_clear() {
    set::clear();
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_set_has(f: *const Face) -> bool {
    face(f).is_some_and(|f| set::has(&f))
}

#[no_mangle]
pub extern "C" fn fm_face_set_size() -> usize {
    set::size()
}

#[no_mangle]
pub extern "C" fn fm_face_set_status() -> i32 {
    set::status()
}

#[no_mangle]
pub extern "C" fn fm_face_set_faces() -> *mut FaceList {
    list_handle(set::faces())
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_set_check(font: *const c_char, text_: *const c_char) -> bool {
    set::check(&text(font), &text(text_))
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_set_match(font: *const c_char, text_: *const c_char) -> *mut FaceList {
    set::matching(&text(font), &text(text_)).map_or(std::ptr::null_mut(), list_handle)
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_set_load(font: *const c_char, text_: *const c_char) -> *mut FaceList {
    match set::matching(&text(font), &text(text_)) {
        Some(faces) => {
            for f in &faces {
                f.load();
            }
            list_handle(faces)
        }
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_set_add_changed_listener(callback: Option<set::ChangedFn>, user_data: *mut c_void) -> i32 {
    callback.map_or(0, |cb| set::add_changed_listener(cb, user_data))
}

#[no_mangle]
pub extern "C" fn fm_face_set_remove_changed_listener(id: i32) -> bool {
    set::remove_changed_listener(id)
}

#[no_mangle]
pub unsafe extern "C" fn fm_face_set_add_event_listener(callback: Option<set::EventFn>, user_data: *mut c_void) -> i32 {
    callback.map_or(0, |cb| set::add_event_listener(cb, user_data))
}

#[no_mangle]
pub extern "C" fn fm_face_set_remove_event_listener(id: i32) -> bool {
    set::remove_event_listener(id)
}

fn stylesheet_faces(css_text: &str, base: &str) -> FaceList {
    let base = (!base.is_empty()).then_some(base);
    css::font_face_blocks(css_text)
        .iter()
        .filter_map(|block| {
            let decls = css::declarations(block);
            let family = decls.iter().find(|(n, _)| n == "font-family")?.1.as_str();
            let family = css::unquote(family);
            if family.is_empty() {
                return None;
            }
            let face = match decls.iter().find(|(n, _)| n == "src") {
                Some((_, src)) => Face::from_url(family, css::pick_source(src, base), src),
                None => Face::new(family, None),
            };
            {
                let mut d = face.descriptors.lock().unwrap();
                for (name, value) in &decls {
                    if let Some(which) = Which::from_css(name) {
                        d.set(which, value);
                    }
                }
            }
            Some(face)
        })
        .collect()
}

#[no_mangle]
pub unsafe extern "C" fn fm_parse_stylesheet(css_text: *const c_char, base_url: *const c_char) -> *mut FaceList {
    list_handle(stylesheet_faces(&text(css_text), &text(base_url)))
}

#[no_mangle]
pub unsafe extern "C" fn fm_load_stylesheet(url: *const c_char) -> *mut FaceList {
    match files::read_text(&text(url)) {
        Ok((css_text, base)) => list_handle(stylesheet_faces(&css_text, &base)),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn fm_resolve_family(families: *const c_char, weight: i32, italic: bool) -> *const c_char {
    resolver::resolve(&text(families), weight, italic).as_ptr()
}

#[no_mangle]
pub unsafe extern "C" fn fm_family_exists(family: *const c_char) -> bool {
    fontconfig::family_exists(&text(family))
}

#[no_mangle]
pub unsafe extern "C" fn fm_is_generic_family(family: *const c_char) -> bool {
    css::is_generic(&text(family))
}

#[no_mangle]
pub extern "C" fn fm_generation() -> u64 {
    fontconfig::generation().wrapping_add(set::generation())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fontconfig::tests::fixture;
    use crate::set::tests::SERIAL;

    #[test]
    fn stylesheet() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let dir = fixture("");
        let css = r#"
            @font-face { font-family: "Sheet Stix"; src: url(stix_two_text_regular.ttf) format("truetype"); }
            @font-face { font-family: 'Sheet Stix'; src: local(x), url(stix_two_text_bold.ttf); font-weight: 700; font-display: swap }
            @font-face { font-family: Sheet Eot; src: url(a.eot) format("embedded-opentype"); }
            @font-face { src: url(nofamily.ttf) }
        "#;
        let faces = stylesheet_faces(css, &dir.join("fonts.css").display().to_string());
        assert_eq!(faces.len(), 3);
        assert_eq!(faces[1].descriptors.lock().unwrap().weight, (700, 700));
        assert_eq!(faces[1].descriptors.lock().unwrap().get(Which::Display), "swap");
        assert!(faces[0].url.as_ref().unwrap().to_str().unwrap().ends_with("Fixtures/stix_two_text_regular.ttf"));
        assert_eq!(faces[0].load(), face::LOADED);
        assert_eq!(faces[1].load(), face::LOADED);
        assert_eq!(faces[2].load(), face::ERROR);
    }

    #[test]
    fn handles() {
        unsafe {
            let f = fm_face_new(c"Handle".as_ptr(), std::ptr::null());
            assert_eq!(CStr::from_ptr(fm_face_family(f)).to_str().unwrap(), "Handle");
            assert!(fm_face_url(f).is_null());
            let d = fm_face_descriptors(f);
            assert!(fm_descriptors_set(d, Which::Weight as i32, c"bold".as_ptr()));
            let w = fm_descriptors_get(d, Which::Weight as i32);
            assert_eq!(CStr::from_ptr(w).to_str().unwrap(), "bold");
            fm_string_free(w);
            fm_face_unref(fm_face_ref(f));
            fm_face_unref(f);
            assert_eq!(fm_descriptors_weight(d), 700, "descriptors outlive the face");
            fm_descriptors_unref(d);
            assert!(fm_face_set_match(c"nonsense".as_ptr(), std::ptr::null()).is_null());
        }
    }
}
