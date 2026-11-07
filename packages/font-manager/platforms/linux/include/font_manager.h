/* C ABI of libfontmanager.so (src-native/linux): the web FontFace / FontFaceSet API over fontconfig.

   Strings are UTF-8. Returned char* are freed with fm_string_free; returned const char* are borrowed
   (lifetime noted per function). Faces and descriptors are reference counted: *_new and *_ref return
   a reference the caller releases with *_unref. Face lists are freed with fm_face_list_free; the
   faces fm_face_list_get returns are borrowed from the list.

   Every function may be called from any thread. Callbacks run on the thread whose call caused them,
   with no library lock held, so they may call back in. When Pango is loaded, its font map is
   refreshed on the thread owning the default GMainContext: inline (before the load's callbacks) when
   that is the calling thread or the context is free, else queued there at high priority. */
#ifndef FONT_MANAGER_H
#define FONT_MANAGER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct fm_descriptors fm_descriptors_t;
typedef struct fm_face fm_face_t;
typedef struct fm_face_list fm_face_list_t;

typedef enum fm_face_status_t {
    FM_FACE_UNLOADED = 0,
    FM_FACE_LOADING = 1,
    FM_FACE_LOADED = 2,
    FM_FACE_ERROR = 3
} fm_face_status_t;

typedef enum fm_set_status_t {
    FM_SET_LOADING = 0,
    FM_SET_LOADED = 1
} fm_set_status_t;

typedef enum fm_display_t {
    FM_DISPLAY_AUTO = 0,
    FM_DISPLAY_BLOCK = 1,
    FM_DISPLAY_FALLBACK = 2,
    FM_DISPLAY_OPTIONAL = 3,
    FM_DISPLAY_SWAP = 4
} fm_display_t;

typedef enum fm_descriptor_t {
    FM_DESCRIPTOR_FAMILY = 0,
    FM_DESCRIPTOR_STYLE = 1,
    FM_DESCRIPTOR_WEIGHT = 2,
    FM_DESCRIPTOR_STRETCH = 3,
    FM_DESCRIPTOR_UNICODE_RANGE = 4,
    FM_DESCRIPTOR_FEATURE_SETTINGS = 5,
    FM_DESCRIPTOR_VARIATION_SETTINGS = 6,
    FM_DESCRIPTOR_DISPLAY = 7,
    FM_DESCRIPTOR_ASCENT_OVERRIDE = 8,
    FM_DESCRIPTOR_DESCENT_OVERRIDE = 9,
    FM_DESCRIPTOR_LINE_GAP_OVERRIDE = 10,
    FM_DESCRIPTOR_KERNING = 11,
    FM_DESCRIPTOR_VARIANT_LIGATURES = 12,
    FM_DESCRIPTOR_VARIANT = 13
} fm_descriptor_t;

/* Reasons passed to fm_changed_fn. LOADED / ERROR are raised for every face, not only set members:
   registration with fontconfig is process-wide. */
typedef enum fm_change_t {
    FM_CHANGE_ADDED = 0,
    FM_CHANGE_DELETED = 1,
    FM_CHANGE_CLEARED = 2,
    FM_CHANGE_LOADED = 3,
    FM_CHANGE_ERROR = 4
} fm_change_t;

/* FontFaceSet events: STATUS and LOADING open a loading period, STATUS, LOADING_DONE and (when a face
   failed) LOADING_ERROR close it. */
typedef enum fm_event_t {
    FM_EVENT_STATUS = 0,
    FM_EVENT_LOADING = 1,
    FM_EVENT_LOADING_DONE = 2,
    FM_EVENT_LOADING_ERROR = 3
} fm_event_t;

/* face is NULL for FM_CHANGE_CLEARED; borrowed for the call. */
typedef void (*fm_changed_fn)(int32_t reason, fm_face_t *face, void *user_data);
/* faces and error (NULL unless LOADING_ERROR) are borrowed for the call. */
typedef void (*fm_event_fn)(int32_t event, int32_t status, const fm_face_list_t *faces, const char *error, void *user_data);

/* Base of "~/" and relative font paths (the app folder). */
void fm_set_app_dir(const char *path);
/* Where font bytes are written for fontconfig; defaults to $XDG_CACHE_HOME/nativescript-fonts. */
void fm_set_cache_dir(const char *path);
void fm_string_free(char *string);

fm_descriptors_t *fm_descriptors_new(const char *family);
fm_descriptors_t *fm_descriptors_ref(fm_descriptors_t *descriptors);
void fm_descriptors_unref(fm_descriptors_t *descriptors);
/* CSS text of a descriptor (fm_descriptor), e.g. "bold", "oblique 10deg", "swap". */
char *fm_descriptors_get(const fm_descriptors_t *descriptors, int32_t which);
/* Parses a descriptor's CSS text; false (and no change) when invalid. The family can't be set. */
bool fm_descriptors_set(fm_descriptors_t *descriptors, int32_t which, const char *value);
/* Applies the declarations of an "@font-face { ... }" rule or a bare declaration list. */
void fm_descriptors_update(fm_descriptors_t *descriptors, const char *css);
/* Lower bound of a weight range. */
int32_t fm_descriptors_weight(const fm_descriptors_t *descriptors);
bool fm_descriptors_italic(const fm_descriptors_t *descriptors);
int32_t fm_descriptors_display(const fm_descriptors_t *descriptors);

/* source: a CSS src list ("url(a.woff2) format('woff2'), url(a.ttf)"), a URL (file://, data:,
   http(s)) or a path; NULL for a family the system has. */
fm_face_t *fm_face_new(const char *family, const char *source);
/* Writes the bytes to the cache right away (they aren't kept). */
fm_face_t *fm_face_new_data(const char *family, const void *data, size_t length);
fm_face_t *fm_face_ref(fm_face_t *face);
void fm_face_unref(fm_face_t *face);
/* Unique per face for the process; never 0. */
uint32_t fm_face_id(const fm_face_t *face);
/* Borrowed for the face's lifetime. */
const char *fm_face_family(const fm_face_t *face);
/* The URL picked from the source, or NULL; borrowed for the face's lifetime. */
const char *fm_face_url(const fm_face_t *face);
/* Whether the source is http(s): its bytes come through fm_face_load_data. */
bool fm_face_is_remote(const fm_face_t *face);
/* The face's descriptors (shared: changes apply to the face). */
fm_descriptors_t *fm_face_descriptors(const fm_face_t *face);
int32_t fm_face_status(const fm_face_t *face);
/* The last load error, or NULL. */
char *fm_face_error(const fm_face_t *face);
/* The family inside the loaded file, or NULL; borrowed for the face's lifetime. */
const char *fm_face_actual_family(const fm_face_t *face);
/* The registered font file, or NULL; borrowed for the face's lifetime. */
const char *fm_face_path(const fm_face_t *face);
/* Loads a file, data: or byte source synchronously and returns the new status. A remote face, or one
   another thread is loading, returns FM_FACE_LOADING: the remote one waits for fm_face_load_data
   or fm_face_fail. Loading an errored face retries. */
int32_t fm_face_load(fm_face_t *face);
/* Loads the face from font bytes (a remote source's download). */
int32_t fm_face_load_data(fm_face_t *face, const void *data, size_t length);
/* Fails a remote load waiting for its bytes. */
int32_t fm_face_fail(fm_face_t *face, const char *error);

size_t fm_face_list_size(const fm_face_list_t *list);
fm_face_t *fm_face_list_get(const fm_face_list_t *list, size_t index);
void fm_face_list_free(fm_face_list_t *list);

/* The process-wide FontFaceSet (document.fonts). */
bool fm_face_set_add(fm_face_t *face);
bool fm_face_set_delete(fm_face_t *face);
void fm_face_set_clear(void);
bool fm_face_set_has(const fm_face_t *face);
size_t fm_face_set_size(void);
int32_t fm_face_set_status(void);
fm_face_list_t *fm_face_set_faces(void);
/* Whether text in a CSS font shorthand renders without loading: each family is generic, has a loaded
   best-matching member face, or is known to fontconfig. */
bool fm_face_set_check(const char *font, const char *text);
/* The best member face (weight / style / unicode-range) per family of a font shorthand; NULL when
   the shorthand doesn't parse. */
fm_face_list_t *fm_face_set_match(const char *font, const char *text);
/* fm_face_set_match, loading each face (remote ones stay loading). */
fm_face_list_t *fm_face_set_load(const char *font, const char *text);
/* Returns a listener id (> 0). */
int32_t fm_face_set_add_changed_listener(fm_changed_fn callback, void *user_data);
bool fm_face_set_remove_changed_listener(int32_t id);
int32_t fm_face_set_add_event_listener(fm_event_fn callback, void *user_data);
bool fm_face_set_remove_event_listener(int32_t id);

/* Faces of a stylesheet's @font-face rules (not added or loaded); relative URLs resolve against
   base_url. */
fm_face_list_t *fm_parse_stylesheet(const char *css, const char *base_url);
/* fm_parse_stylesheet for a file path, file://, ~/ or data: URL; NULL when it can't be read. */
fm_face_list_t *fm_load_stylesheet(const char *url);

/* The family Pango should be given for a CSS font-family list: a loaded member face's file family,
   a generic family's fontconfig name, a family fontconfig has, or "sans-serif". Interned: valid for
   the process, not freed. */
const char *fm_resolve_family(const char *families, int32_t weight, bool italic);
/* Whether fontconfig has a family by this name (no substitution). */
bool fm_family_exists(const char *family);
bool fm_is_generic_family(const char *family);
/* Changes whenever fonts, mappings or the set change. */
uint64_t fm_generation(void);

#endif
