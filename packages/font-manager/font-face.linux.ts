import { alias, fontsChanged, localFile, readText, registerFile, writeFontFile } from './fontconfig.linux';

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

type Status = 'unloaded' | 'loading' | 'loaded' | 'error';

const FORMATS = /^(woff2?|truetype|opentype|collection)$/i;

/** The first `url()` in a `src` list whose format fontconfig (FreeType) can read. */
function pickSource(src: string, base?: string): string | null {
  for (const part of src.split(/,(?![^(]*\))/)) {
    const url = /url\(\s*(['"]?)(.*?)\1\s*\)/i.exec(part)?.[2];
    if (!url) continue;
    const format = /format\(\s*(['"]?)(.*?)\1\s*\)/i.exec(part)?.[2];
    if (format && !FORMATS.test(format) && !/^(woff2|woff|truetype|opentype)-variations$/i.test(format)) continue;
    return base && !/^([a-z]+:|\/|~\/)/i.test(url) ? new URL(url, base).toString() : url;
  }
  return null;
}

function cssWeight(value: string | undefined): number | undefined {
  if (!value || value === 'normal') return value ? 400 : undefined;
  if (value === 'bold') return 700;
  const n = parseInt(value, 10);
  return Number.isFinite(n) ? n : undefined;
}

export class FontFace {
  readonly family: string;
  private _status: Status = 'unloaded';
  private _source?: string | TypedArray | ArrayBuffer;
  private _loading?: Promise<void>;
  /** Families fontconfig found in the font file. */
  private _families: string[] = [];

  ascentOverride = 'normal';
  descentOverride = 'normal';
  display = 'auto';
  featureSettings = 'normal';
  lineGapOverride = 'normal';
  stretch = 'normal';
  style = 'normal';
  unicodeRange = 'U+0-10FFFF';
  variationSettings = 'normal';
  weight = 'normal';
  kerning = 'auto';
  variantLigatures = 'normal';

  constructor(family: string, source?: string | TypedArray | ArrayBuffer, descriptors?: FontDescriptor) {
    this.family = String(family ?? '')
      .trim()
      .replace(/^(['"])(.*)\1$/, '$2');
    this._source = source;
    if (descriptors) {
      for (const key of Object.keys(descriptors)) {
        const value = (descriptors as any)[key];
        if (value !== undefined) (this as any)[key] = String(value);
      }
    }
  }

  get status(): Status {
    return this._status;
  }

  load(): Promise<void> {
    if (this._status === 'loaded') return Promise.resolve();
    if (this._loading) return this._loading;
    this._status = 'loading';
    const set = (global as any).__fontManagerSet;
    set?._loading(this);
    this._loading = this._load().then(
      () => {
        this._status = 'loaded';
        this._loading = undefined;
        fontsChanged();
        set?._loaded(this);
      },
      (error) => {
        this._status = 'error';
        this._loading = undefined;
        set?._failed(this, error);
        throw error;
      },
    );
    return this._loading;
  }

  private async _load(): Promise<void> {
    const source = this._source;
    let file: string;
    if (source == null) {
      // a family the system already has
      return;
    } else if (typeof source === 'string') {
      const url = pickSource(source) ?? source.trim();
      file = await localFile(this.family, url);
    } else {
      file = writeFontFile(this.family, source as ArrayBuffer | ArrayBufferView);
    }
    const families = registerFile(file);
    if (!families) throw new Error(`Failed to load font ${this.family}: unsupported or missing file ${file}`);
    this._families = families;
    const italic = this.style === 'normal' ? undefined : true;
    const weight = this.weight === 'normal' ? undefined : cssWeight(this.weight);
    // the CSS family name resolves to the family inside the file
    const actual = families[0];
    if (actual) {
      alias(this.family, actual);
      if (weight != null || italic != null) alias(this.family, actual, weight, italic);
    }
  }

  /** The families inside the loaded font file. */
  get fontFamilies(): string[] {
    return this._families.slice();
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

  /** Applies the declarations of an `@font-face` rule (or a bare declaration list). */
  updateDescriptor(css: string) {
    for (const [name, value] of declarations(css)) {
      const key = DESCRIPTORS[name];
      if (key) (this as any)[key] = value;
    }
  }
}

const DESCRIPTORS: Record<string, string> = {
  'font-style': 'style',
  'font-weight': 'weight',
  'font-stretch': 'stretch',
  'font-display': 'display',
  'font-feature-settings': 'featureSettings',
  'font-variation-settings': 'variationSettings',
  'unicode-range': 'unicodeRange',
  'ascent-override': 'ascentOverride',
  'descent-override': 'descentOverride',
  'line-gap-override': 'lineGapOverride',
  'font-kerning': 'kerning',
  'font-variant-ligatures': 'variantLigatures',
};

function declarations(css: string): Array<[string, string]> {
  const body = /\{([\s\S]*)\}/.exec(css)?.[1] ?? css;
  return body
    .split(/;(?![^(]*\))/)
    .map((d) => d.trim())
    .filter(Boolean)
    .map((d) => {
      const colon = d.indexOf(':');
      return [d.slice(0, colon).trim().toLowerCase(), d.slice(colon + 1).trim()] as [string, string];
    })
    .filter(([name]) => !!name);
}

/** The `@font-face` rules of a stylesheet as faces (sources resolved against its URL). */
async function facesFromCSS(url: string): Promise<FontFace[]> {
  const css = await readText(url);
  const base = /^https?:\/\//i.test(url) ? url : undefined;
  const faces: FontFace[] = [];
  for (const match of css.matchAll(/@font-face\s*\{([^}]*)\}/gi)) {
    const decls = new Map(declarations(match[1]));
    const family = decls.get('font-family');
    if (!family) continue;
    const src = decls.get('src');
    const face = new FontFace(family, src ? (pickSource(src, base) ?? undefined) : undefined);
    face.updateDescriptor(match[1]);
    faces.push(face);
  }
  return faces;
}

export function loadFontsFromCSS(url: string): Promise<FontFace[]> {
  return facesFromCSS(url);
}

/** Loads every face of a stylesheet and adds them to the document's set. */
export async function importFontsFromCSS(url: string): Promise<FontFace[]> {
  const faces = await facesFromCSS(url);
  const set = (global as any).__fontManagerSet;
  for (const face of faces) set?.add(face);
  await Promise.all(faces.map((face) => face.load()));
  return faces;
}
