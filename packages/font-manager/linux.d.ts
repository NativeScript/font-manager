declare const __LINUX__: boolean;

declare module interop {
  function stringFromCString(pointer: any): string;
}

declare const enum fm_change_t {
  ADDED = 0,

  DELETED = 1,

  CLEARED = 2,

  LOADED = 3,

  ERROR = 4,
}

declare const enum fm_descriptor_t {
  FAMILY = 0,

  STYLE = 1,

  WEIGHT = 2,

  STRETCH = 3,

  UNICODE_RANGE = 4,

  FEATURE_SETTINGS = 5,

  VARIATION_SETTINGS = 6,

  DISPLAY = 7,

  ASCENT_OVERRIDE = 8,

  DESCENT_OVERRIDE = 9,

  LINE_GAP_OVERRIDE = 10,

  KERNING = 11,

  VARIANT_LIGATURES = 12,

  VARIANT = 13,
}

declare function fm_descriptors_display(descriptors: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): number;

declare function fm_descriptors_get(descriptors: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, which: number): interop.Pointer | interop.Reference<any> | null;

declare function fm_descriptors_italic(descriptors: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): boolean;

declare function fm_descriptors_new(family: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;

declare function fm_descriptors_ref(descriptors: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;

declare function fm_descriptors_set(descriptors: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, which: number, value: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): boolean;

declare function fm_descriptors_unref(descriptors: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): void;

declare function fm_descriptors_update(descriptors: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, css: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): void;

declare function fm_descriptors_weight(descriptors: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): number;

declare const enum fm_display_t {
  AUTO = 0,

  BLOCK = 1,

  FALLBACK = 2,

  OPTIONAL = 3,

  SWAP = 4,
}

declare const enum fm_event_t {
  STATUS = 0,

  LOADING = 1,

  LOADING_DONE = 2,

  LOADING_ERROR = 3,
}

declare function fm_face_actual_family(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): string | null;

declare function fm_face_descriptors(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;

declare function fm_face_error(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;

declare function fm_face_fail(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, error: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): number;

declare function fm_face_family(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): string | null;

declare function fm_face_id(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): number;

declare function fm_face_is_remote(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): boolean;

declare function fm_face_list_free(list: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): void;

declare function fm_face_list_get(list: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, index: number): interop.Pointer | interop.Reference<any> | null;

declare function fm_face_list_size(list: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): number;

declare function fm_face_load(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): number;

declare function fm_face_load_data(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, data: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, length: number): number;

declare function fm_face_new(family: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, source: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;

declare function fm_face_new_data(family: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, data: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, length: number): interop.Pointer | interop.Reference<any> | null;

declare function fm_face_path(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): string | null;

declare function fm_face_ref(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;

declare function fm_face_set_add(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): boolean;

declare function fm_face_set_add_changed_listener(callback: interop.FunctionReference<(p1: number, p2: interop.Pointer | interop.Reference<any> | null, p3: interop.Pointer | interop.Reference<any> | null) => void>, user_data: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): number;

declare function fm_face_set_add_event_listener(callback: interop.FunctionReference<(p1: number, p2: number, p3: interop.Pointer | interop.Reference<any> | null, p4: string | null, p5: interop.Pointer | interop.Reference<any> | null) => void>, user_data: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): number;

declare function fm_face_set_check(font: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, text: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): boolean;

declare function fm_face_set_clear(): void;

declare function fm_face_set_delete(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): boolean;

declare function fm_face_set_faces(): interop.Pointer | interop.Reference<any> | null;

declare function fm_face_set_has(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): boolean;

declare function fm_face_set_load(font: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, text: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;

declare function fm_face_set_match(font: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, text: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;

declare function fm_face_set_remove_changed_listener(id: number): boolean;

declare function fm_face_set_remove_event_listener(id: number): boolean;

declare function fm_face_set_size(): number;

declare function fm_face_set_status(): number;

declare function fm_face_status(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): number;

declare const enum fm_face_status_t {
  UNLOADED = 0,

  LOADING = 1,

  LOADED = 2,

  ERROR = 3,
}

declare function fm_face_unref(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): void;

declare function fm_face_url(face: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): string | null;

declare function fm_family_exists(family: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): boolean;

declare function fm_generation(): number;

declare function fm_is_generic_family(family: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): boolean;

declare function fm_load_stylesheet(url: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;

declare function fm_parse_stylesheet(css: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, base_url: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;

declare function fm_resolve_family(families: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, weight: number, italic: boolean): string | null;

declare function fm_set_app_dir(path: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): void;

declare function fm_set_cache_dir(path: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): void;

declare const enum fm_set_status_t {
  LOADING = 0,

  LOADED = 1,
}

declare function fm_string_free(string: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): void;
