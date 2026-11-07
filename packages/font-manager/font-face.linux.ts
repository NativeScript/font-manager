import { Application, knownFolders } from '@nativescript/core';

export type TypedArray = Int8Array | Uint8Array | Uint8ClampedArray | Int16Array | Uint16Array | Int32Array | Uint32Array | Float32Array | Float64Array;

export type stretchName = 'ultra-condensed' | 'extra-condensed' | 'condensed' | 'semi-condensed' | 'normal' | 'semi-expanded' | 'expanded' | 'extra-expanded' | 'ultra-expanded';
export type stretchPercent = '50%' | '62.5%' | '75%' | '87.5%' | '100%' | '112.5%' | '125%' | '150%' | '200%' | '300%' | '400%';
export type stretch = stretchName | stretchPercent;

interface FontDescriptor {
  ascentOverride?: 'normal' | `${number}%`;
  descentOverride?: 'normal' | `${number}%`;
  display?: 'auto' | 'block' | 'swap' | 'fallback' | 'optional';
  featureSettings?: string;
  lineGapOverride?: 'normal' | `${number}%`;
  stretch?: stretch | `${stretch} ${stretch}`;
  style?: 'normal' | 'italic' | 'oblique' | `oblique ${number}deg`;
  unicodeRange?: string;
  variationSettings?: 'normal' | `${string} ${number}`;
  weight?: 'normal' | 'bold' | 'bolder' | 'lighter' | `${number}` | '100' | '200' | '300' | '400' | '500' | '600' | '700' | '800' | '900';
  kerning?: 'auto' | 'normal' | 'none';
  variantLigatures?: string;
}

// fm_face_status_t
const LOADING = 1;
const LOADED = 2;
const ERROR = 3;
const STATUS = ['unloaded', 'loading', 'loaded', 'error'] as const;

// fm_descriptor_t
const enum Descriptor {
  Style = 1,
  Weight = 2,
  Stretch = 3,
  UnicodeRange = 4,
  FeatureSettings = 5,
  VariationSettings = 6,
  Display = 7,
  AscentOverride = 8,
  DescentOverride = 9,
  LineGapOverride = 10,
  Kerning = 11,
  VariantLigatures = 12,
}

// fm_change_t
const CHANGE_LOADED = 3;
const CHANGE_ERROR = 4;

const WEIGHTS: Record<string, string> = { '100': 'thin', '200': 'extra-light', '300': 'light', '500': 'medium', '600': 'semi-bold', '800': 'extra-bold', '900': 'black' };

fm_set_app_dir(knownFolders.currentApp().path);
fm_set_cache_dir(`${knownFolders.temp().path}/fonts`);

/** Owned C string -> JS string. */
function take(pointer: any): string | null {
  if (!pointer) return null;
  const value = interop.stringFromCString(pointer);
  fm_string_free(pointer);
  return value;
}

/** One wrapper per native face, so set events hand back the faces JS created. */
const wrappers = new Map<number, WeakRef<FontFace>>();
const released = new FinalizationRegistry<{ id: number; native: interop.Pointer; descriptors: interop.Pointer }>(({ id, native, descriptors }) => {
  if (!wrappers.get(id)?.deref()) wrappers.delete(id);
  fm_descriptors_unref(descriptors);
  fm_face_unref(native);
});

/** Loads finishing on another thread. */
const settling = new Map<number, Array<() => void>>();

function onChanged(reason: number, face: interop.Pointer) {
  if (reason !== CHANGE_LOADED && reason !== CHANGE_ERROR) return;
  // Pango has re-read fontconfig: views lay text out again (Mason listens)
  if (reason === CHANGE_LOADED && fm_face_path(face)) Application.notify({ eventName: 'fontsChanged', object: Application } as any);
  const id = fm_face_id(face);
  const waiters = settling.get(id);
  if (waiters) {
    settling.delete(id);
    waiters.forEach((resolve) => resolve());
  }
}
fm_face_set_add_changed_listener(onChanged as any, null);

/** The faces of a native list, which is freed. */
export function facesFromList(list: interop.Pointer | null): FontFace[] {
  if (!list) return [];
  const faces: FontFace[] = [];
  const count = fm_face_list_size(list);
  for (let i = 0; i < count; i++) {
    const face = FontFace.fromNative(fm_face_list_get(list, i) as interop.Pointer);
    if (face) faces.push(face);
  }
  fm_face_list_free(list);
  return faces;
}

const ctor_ = Symbol('[[ctor]]');

export class FontFace {
  readonly native_: interop.Pointer;
  private readonly _descriptors: interop.Pointer;
  private _loading?: Promise<void>;

  constructor(family: string, source?: string | TypedArray | ArrayBuffer, descriptors?: FontDescriptor, ctor?: symbol, native?: interop.Pointer) {
    if (ctor === ctor_ && native) {
      this.native_ = native;
    } else if (source instanceof ArrayBuffer || ArrayBuffer.isView(source)) {
      // zero-copy: the runtime passes the buffer's memory
      this.native_ = fm_face_new_data(String(family ?? ''), source, source.byteLength) as interop.Pointer;
    } else {
      this.native_ = fm_face_new(String(family ?? ''), typeof source === 'string' ? source : null) as interop.Pointer;
    }
    this._descriptors = fm_face_descriptors(this.native_) as interop.Pointer;
    const id = fm_face_id(this.native_);
    wrappers.set(id, new WeakRef(this));
    released.register(this, { id, native: this.native_, descriptors: this._descriptors });
    if (descriptors) {
      for (const key of Object.keys(descriptors)) {
        const value = (descriptors as any)[key];
        if (value !== undefined && key in this) (this as any)[key] = String(value);
      }
    }
  }

  static fromNative(native: interop.Pointer | null): FontFace | null {
    if (!native) return null;
    const existing = wrappers.get(fm_face_id(native))?.deref();
    return existing ?? new FontFace('', undefined, undefined, ctor_, fm_face_ref(native) as interop.Pointer);
  }

  get family(): string {
    return fm_face_family(this.native_) ?? '';
  }

  get status(): (typeof STATUS)[number] {
    return STATUS[fm_face_status(this.native_)] ?? 'error';
  }

  /** The family inside the loaded font file. */
  get fontFamilies(): string[] {
    const actual = fm_face_actual_family(this.native_);
    return actual ? [actual] : [];
  }

  load(): Promise<void> {
    if (fm_face_status(this.native_) === LOADED) return Promise.resolve();
    return (this._loading ??= this._load().finally(() => (this._loading = undefined)));
  }

  private async _load(): Promise<void> {
    const face = this.native_;
    const before = fm_face_status(face);
    let status = fm_face_load(face);
    if (status === LOADING) {
      if (before !== LOADING && fm_face_is_remote(face)) {
        status = await this._fetch(fm_face_url(face));
      } else {
        // another thread is loading it
        await new Promise<void>((resolve) => {
          const id = fm_face_id(face);
          settling.set(id, [...(settling.get(id) ?? []), resolve]);
        });
        status = fm_face_status(face);
      }
    }
    if (status === ERROR) {
      throw new Error(take(fm_face_error(face)) ?? `Failed to load font ${this.family}`);
    }
  }

  private async _fetch(url: string): Promise<number> {
    try {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`Failed to fetch ${url}: ${response.status}`);
      const data = await response.arrayBuffer();
      return fm_face_load_data(this.native_, data, data.byteLength);
    } catch (error) {
      return fm_face_fail(this.native_, error?.message ?? String(error));
    }
  }

  private _get(which: Descriptor): string {
    return take(fm_descriptors_get(this._descriptors, which)) ?? '';
  }

  private _set(which: Descriptor, value: string) {
    fm_descriptors_set(this._descriptors, which, String(value));
  }

  get ascentOverride() {
    return this._get(Descriptor.AscentOverride);
  }

  set ascentOverride(value: string) {
    this._set(Descriptor.AscentOverride, value);
  }

  get descentOverride() {
    return this._get(Descriptor.DescentOverride);
  }

  set descentOverride(value: string) {
    this._set(Descriptor.DescentOverride, value);
  }

  get lineGapOverride() {
    return this._get(Descriptor.LineGapOverride);
  }

  set lineGapOverride(value: string) {
    this._set(Descriptor.LineGapOverride, value);
  }

  get display() {
    return this._get(Descriptor.Display);
  }

  set display(value: string) {
    this._set(Descriptor.Display, value);
  }

  get featureSettings() {
    return this._get(Descriptor.FeatureSettings);
  }

  set featureSettings(value: string) {
    this._set(Descriptor.FeatureSettings, value);
  }

  get variationSettings() {
    return this._get(Descriptor.VariationSettings);
  }

  set variationSettings(value: string) {
    this._set(Descriptor.VariationSettings, value);
  }

  get stretch() {
    return this._get(Descriptor.Stretch);
  }

  set stretch(value: string) {
    this._set(Descriptor.Stretch, value);
  }

  get style() {
    return this._get(Descriptor.Style);
  }

  set style(value: string) {
    this._set(Descriptor.Style, value);
  }

  get unicodeRange() {
    return this._get(Descriptor.UnicodeRange);
  }

  set unicodeRange(value: string) {
    this._set(Descriptor.UnicodeRange, value);
  }

  /** Named like iOS and Windows: 'thin' ... 'black'. */
  get weight() {
    const value = this._get(Descriptor.Weight);
    return WEIGHTS[value] ?? value;
  }

  set weight(value: string) {
    this._set(Descriptor.Weight, value);
  }

  get kerning() {
    return this._get(Descriptor.Kerning);
  }

  set kerning(value: string) {
    this._set(Descriptor.Kerning, value);
  }

  get variantLigatures() {
    return this._get(Descriptor.VariantLigatures);
  }

  set variantLigatures(value: string) {
    this._set(Descriptor.VariantLigatures, value);
  }

  /** Applies the declarations of an `@font-face` rule (or a bare declaration list). */
  updateDescriptor(css: string) {
    fm_descriptors_update(this._descriptors, css);
  }

  toJSON() {
    return {
      ascentOverride: this.ascentOverride,
      descentOverride: this.descentOverride,
      display: this.display,
      family: this.family,
      status: this.status,
      style: this.style,
      weight: this.weight,
    };
  }
}

/** The `@font-face` rules of a stylesheet as faces, sources resolved against its URL. */
async function facesFromCSS(url: string): Promise<FontFace[]> {
  if (/^https?:\/\//i.test(url)) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Failed to fetch ${url}: ${response.status}`);
    return facesFromList(fm_parse_stylesheet(await response.text(), url) as interop.Pointer);
  }
  const list = fm_load_stylesheet(url) as interop.Pointer;
  if (!list) throw new Error(`Couldn't read ${url}`);
  return facesFromList(list);
}

export function loadFontsFromCSS(url: string): Promise<FontFace[]> {
  return facesFromCSS(url);
}

/** Adds a stylesheet's faces to the document's set and loads them; failures show in each face's status. */
export async function importFontsFromCSS(url: string): Promise<FontFace[]> {
  const faces = await facesFromCSS(url);
  for (const face of faces) fm_face_set_add(face.native_);
  await Promise.allSettled(faces.map((face) => face.load()));
  return faces;
}
