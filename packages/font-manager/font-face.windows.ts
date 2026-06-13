import { knownFolders } from '@nativescript/core';

export type TypedArray = Int8Array | Uint8Array | Uint8ClampedArray | Int16Array | Uint16Array | Int32Array | Uint32Array | Float32Array | Float64Array;

const url_ex = /url\(([^)]+?)\.(woff2?|ttf|otf|eot)\)/;

type stretchName = 'ultra-condensed' | 'extra-condensed' | 'condensed' | 'semi-condensed' | 'normal' | 'semi-expanded' | 'expanded' | 'extra-expanded' | 'ultra-expanded';
type strechPercent = '50%' | '62.5%' | '75%' | '87.5%' | '100%' | '112.5%' | '125%' | '150%' | '200%' | '300%' | '400%';
type stretch = stretchName | strechPercent;
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

// IVectorView<FontFace> -> FontFace[]. Tolerates either the WinRT (.Size/.GetAt) or an array-like
// (.length/index) projection, depending on how the runtime surfaces collections.
function viewToFaces(view: any): FontFace[] {
  const out: FontFace[] = [];
  if (!view) return out;
  const count = typeof view.Size === 'number' ? view.Size : typeof view.size === 'number' ? view.size : view.length ?? 0;
  for (let i = 0; i < count; i++) {
    const native = typeof view.GetAt === 'function' ? view.GetAt(i) : view[i];
    const face = FontFace.fromNative(native);
    if (face) out.push(face);
  }
  return out;
}

function toBuffer(source: TypedArray | ArrayBuffer): any {
  // The runtime marshals a Uint8Array to Windows.Storage.Streams.IBuffer (as in @nativescript/core
  // image-source.windows.ts, which passes `bytes as never`).
  return (source instanceof ArrayBuffer ? new Uint8Array(source) : source) as never;
}

export function loadFontsFromCSS(url: string) {
  return new Promise<FontFace[]>((resolve, reject) => {
    NSWinRT.toPromise(NativeScript.FontManager.FontFace.ImportFromRemoteAsync(url, false)).then(
      (fonts) => resolve(viewToFaces(fonts)),
      (error) => reject(error),
    );
  });
}

export function importFontsFromCSS(url: string) {
  return new Promise<FontFace[]>((resolve, reject) => {
    NSWinRT.toPromise(NativeScript.FontManager.FontFace.ImportFromRemoteAsync(url, true)).then(
      (fonts) => resolve(viewToFaces(fonts)),
      (error) => reject(error),
    );
  });
}

const ctor_ = Symbol('[[ctor]]');
export class FontFace {
  native_: NativeScript.FontManager.FontFace;
  private extension?: string;
  constructor(family: string, source?: string | TypedArray | ArrayBuffer, descriptors?: FontDescriptor, ctor?: symbol, native?: NativeScript.FontManager.FontFace) {
    if (ctor === ctor_ && native) {
      this.native_ = native;
      return;
    }

    let descriptor: NativeScript.FontManager.FontDescriptors | null = null;

    if (descriptors) {
      const parts = [`@font-face { font-family: '${family}';`];
      if (descriptors.style !== undefined) parts.push(`font-style: ${descriptors.style};`);
      if (descriptors.weight !== undefined) parts.push(`font-weight: ${descriptors.weight};`);
      if (descriptors.stretch !== undefined) parts.push(`font-stretch: ${descriptors.stretch};`);
      if (descriptors.display !== undefined) parts.push(`font-display: ${descriptors.display};`);
      if (descriptors.featureSettings !== undefined) parts.push(`font-feature-settings: ${descriptors.featureSettings};`);
      if (descriptors.variationSettings !== undefined) parts.push(`font-variation-settings: ${descriptors.variationSettings};`);
      if (descriptors.unicodeRange !== undefined) parts.push(`unicode-range: ${descriptors.unicodeRange};`);
      if (descriptors.ascentOverride !== undefined) parts.push(`ascent-override: ${descriptors.ascentOverride};`);
      if (descriptors.descentOverride !== undefined) parts.push(`descent-override: ${descriptors.descentOverride};`);
      if (descriptors.lineGapOverride !== undefined) parts.push(`line-gap-override: ${descriptors.lineGapOverride};`);
      if (descriptors.kerning !== undefined) parts.push(`font-kerning: ${descriptors.kerning};`);
      if (descriptors.variantLigatures !== undefined) parts.push(`font-variant-ligatures: ${descriptors.variantLigatures};`);
      parts.push('}');
      descriptor = new NativeScript.FontManager.FontDescriptors(family);
      descriptor.Update(parts.join(' '));
    }

    if (source) {
      if (ArrayBuffer.isView(source) || source instanceof ArrayBuffer) {
        const data = toBuffer(source as TypedArray | ArrayBuffer);
        this.native_ = descriptor ? NativeScript.FontManager.FontFace.FromDescriptorData(descriptor, data) : NativeScript.FontManager.FontFace.FromFamilyData(family, data);
      } else if (typeof source === 'string') {
        const matches = source.match(url_ex) ?? [];
        this.extension = matches[2];
        let path = matches[1];
        if (path && path.startsWith('~/')) {
          path = path.replace('~', knownFolders.currentApp().path);
        }
        const url = `${path}${this.extension ? '.' + this.extension : ''}`;
        const resolved = url || source;
        this.native_ = descriptor ? NativeScript.FontManager.FontFace.FromDescriptorSource(descriptor, resolved) : NativeScript.FontManager.FontFace.FromFamilySource(family, resolved);
      }
    } else {
      this.native_ = descriptor ? NativeScript.FontManager.FontFace.FromDescriptor(descriptor) : NativeScript.FontManager.FontFace.FromFamily(family);
    }
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

  load() {
    return new Promise<void>((resolve, reject) => {
      if (this.status === 'loaded') {
        resolve();
        return;
      }
      NSWinRT.toPromise<string>(this.native_.LoadAsync()).then(
        (error) => {
          if (error) {
            reject(error);
          } else {
            resolve();
          }
        },
        (error) => reject(error),
      );
    });
  }

  /** A XAML-usable FontFamily URI (`...#Family`) for the loaded font; empty until loaded. */
  get fontUri() {
    return this.native_.FontUri;
  }

  get ascentOverride() {
    return this.native_.AscentOverride;
  }

  set ascentOverride(value: string) {
    this.native_.SetFontAscentOverride(value);
  }

  get descentOverride() {
    return this.native_.DescentOverride;
  }

  set descentOverride(value: string) {
    this.native_.SetFontDescentOverride(value);
  }

  get lineGapOverride() {
    return this.native_.LineGapOverride;
  }

  set lineGapOverride(value: string) {
    this.native_.SetFontLineGapOverride(value);
  }

  get stretch() {
    return this.native_.Stretch;
  }

  set stretch(value: string) {
    this.native_.SetFontStretch(value);
  }

  get unicodeRange() {
    return this.native_.UnicodeRange;
  }

  set unicodeRange(value: string) {
    this.native_.SetFontUnicodeRange(value);
  }

  get featureSettings() {
    return this.native_.FeatureSettings;
  }

  set featureSettings(value: string) {
    this.native_.SetFontFeatureSettings(value);
  }

  get variationSettings() {
    return this.native_.VariationSettings;
  }

  set variationSettings(value: string) {
    this.native_.SetFontVariationSettings(value);
  }

  get display() {
    switch (this.native_.Display) {
      case NativeScript.FontManager.FontDisplay.Auto:
        return 'auto';
      case NativeScript.FontManager.FontDisplay.Block:
        return 'block';
      case NativeScript.FontManager.FontDisplay.Fallback:
        return 'fallback';
      case NativeScript.FontManager.FontDisplay.Optional:
        return 'optional';
      case NativeScript.FontManager.FontDisplay.Swap:
        return 'swap';
    }
  }

  set display(value: string) {
    this.native_.SetFontDisplay(value);
  }

  get family() {
    return this.native_.Family;
  }

  get status() {
    switch (this.native_.Status) {
      case NativeScript.FontManager.FontFaceStatus.Loaded:
        return 'loaded';
      case NativeScript.FontManager.FontFaceStatus.Loading:
        return 'loading';
      case NativeScript.FontManager.FontFaceStatus.Error:
        return 'error';
      case NativeScript.FontManager.FontFaceStatus.Unloaded:
        return 'unloaded';
    }
  }

  get style() {
    return this.native_.Style;
  }

  set style(value: string) {
    const obliqueMatch = /^oblique\s*(.*)$/.exec(value);
    if (obliqueMatch) {
      this.native_.SetFontStyle('oblique', obliqueMatch[1] || '0deg');
    } else {
      this.native_.SetFontStyle(value, '');
    }
  }

  get weight() {
    switch (this.native_.Weight) {
      case NativeScript.FontManager.FontWeight.Thin:
        return 'thin';
      case NativeScript.FontManager.FontWeight.ExtraLight:
        return 'extra-light';
      case NativeScript.FontManager.FontWeight.Light:
        return 'light';
      case NativeScript.FontManager.FontWeight.Normal:
        return 'normal';
      case NativeScript.FontManager.FontWeight.Medium:
        return 'medium';
      case NativeScript.FontManager.FontWeight.SemiBold:
        return 'semi-bold';
      case NativeScript.FontManager.FontWeight.Bold:
        return 'bold';
      case NativeScript.FontManager.FontWeight.ExtraBold:
        return 'extra-bold';
      case NativeScript.FontManager.FontWeight.Black:
        return 'black';
    }
  }

  set weight(value: string) {
    this.native_.SetFontWeight(value);
  }

  get kerning() {
    return this.native_.Kerning;
  }

  set kerning(value: string) {
    this.native_.SetFontKerning(value);
  }

  get variantLigatures() {
    return this.native_.VariantLigatures;
  }

  set variantLigatures(value: string) {
    this.native_.SetFontVariantLigatures(value);
  }

  updateDescriptor(css: string) {
    this.native_.UpdateDescriptor(css);
  }

  static fromNative(native: any): FontFace | null {
    if (native) {
      return new FontFace('', undefined, undefined, ctor_, native);
    }
    return null;
  }
}
