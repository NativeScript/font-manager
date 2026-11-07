import { Observable } from '@nativescript/core';
import { FontFace, facesFromList } from './font-face.linux';

// fm_event_t, fm_set_status_t
const EVENT_STATUS = 0;
const EVENT_LOADING = 1;
const EVENT_LOADING_DONE = 2;
const EVENT_LOADING_ERROR = 3;
const SET_LOADING = 0;

const instances = new Set<WeakRef<FontFaceSet>>();

let ready: Promise<void> = Promise.resolve();
let resolveReady: (() => void) | undefined;

/** The faces of a borrowed native list. */
function eventFaces(list: interop.Pointer | null): FontFace[] {
  const faces: FontFace[] = [];
  const count = list ? fm_face_list_size(list) : 0;
  for (let i = 0; i < count; i++) {
    const face = FontFace.fromNative(fm_face_list_get(list, i) as interop.Pointer);
    if (face) faces.push(face);
  }
  return faces;
}

function onEvent(event: number, status: number, list: interop.Pointer | null, error: string | null) {
  if (event === EVENT_STATUS) {
    if (status === SET_LOADING) {
      ready = new Promise((resolve) => (resolveReady = resolve));
    } else {
      resolveReady?.();
      resolveReady = undefined;
    }
  }
  const data =
    event === EVENT_STATUS
      ? { eventName: 'status', status: status === SET_LOADING ? 'loading' : 'loaded' }
      : {
          eventName: event === EVENT_LOADING ? 'loading' : event === EVENT_LOADING_DONE ? 'loadingdone' : 'loadingerror',
          fontfaces: eventFaces(list),
          ...(event === EVENT_LOADING_ERROR ? { error } : {}),
        };
  for (const ref of instances) {
    const set = ref.deref();
    if (set) set.notify({ ...data, object: set } as any);
    else instances.delete(ref);
  }
}
fm_face_set_add_event_listener(onEvent as any, null);

export class FontFaceSet extends Observable {
  constructor() {
    super();
    instances.add(new WeakRef(this));
  }

  static get instance(): FontFaceSet {
    if (!FontFaceSet._instance) {
      FontFaceSet._instance = new FontFaceSet();
    }
    return FontFaceSet._instance;
  }
  private static _instance: FontFaceSet;

  get ready(): Promise<void> {
    return ready;
  }

  get size(): number {
    return fm_face_set_size();
  }

  get status(): 'loading' | 'loaded' {
    return fm_face_set_status() === SET_LOADING ? 'loading' : 'loaded';
  }

  add(font: FontFace) {
    fm_face_set_add(font.native_);
    return this;
  }

  has(font: FontFace): boolean {
    return fm_face_set_has(font.native_);
  }

  entries(): IterableIterator<[FontFace, FontFace]> {
    return facesFromList(fm_face_set_faces() as interop.Pointer)
      .map((f) => [f, f] as [FontFace, FontFace])
      [Symbol.iterator]();
  }

  keys(): IterableIterator<FontFace> {
    return this.values();
  }

  values(): IterableIterator<FontFace> {
    return facesFromList(fm_face_set_faces() as interop.Pointer)[Symbol.iterator]();
  }

  [Symbol.iterator]() {
    return this.values();
  }

  forEach(callback: (value: FontFace, key: FontFace, parent: FontFaceSet) => void, thisArg?: any) {
    for (const font of this.values()) callback.call(thisArg, font, font, this);
  }

  /** Whether text in a CSS `font` renders without loading anything. */
  check(font: string, text?: string): boolean {
    return fm_face_set_check(font, text ?? '');
  }

  clear() {
    fm_face_set_clear();
  }

  delete(font: FontFace) {
    return fm_face_set_delete(font.native_);
  }

  /** Loads the best face of the set for each family of a CSS `font`. */
  load(font: string, text?: string): Promise<FontFace[]> {
    const list = fm_face_set_match(font, text ?? '') as interop.Pointer;
    if (!list) return Promise.reject(new Error(`Failed to parse font ${font}`));
    const faces = facesFromList(list);
    return Promise.all(faces.map((face) => face.load())).then(() => faces);
  }
}

// Exists from the start, so faces loaded on their own still report to it.
void FontFaceSet.instance;
