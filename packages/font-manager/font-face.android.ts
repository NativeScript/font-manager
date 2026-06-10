import { knownFolders, Utils } from '@nativescript/core';
type TypedArray = Int8Array | Uint8Array | Uint8ClampedArray | Int16Array | Uint16Array | Int32Array | Uint32Array | Float32Array | Float64Array;

const url_ex = /url\(([^)]+?)\.(woff2?|ttf|otf|eot)\)/;
declare const kotlin: any;
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

export function loadFontsFromCSS(url: string) {
  return new Promise<any[]>((resolve, reject) => {
    const cb = new kotlin.jvm.functions.Function2({
      invoke(fonts: java.util.List<org.nativescript.fontmanager.FontFace>, error: string) {
        const count = fonts.size();
        const ret = new Array(count);
        if (error) {
          reject(error);
        } else {
          for (let i = 0; i < count; i++) {
            ret[i] = FontFace.fromNative(fonts.get(i));
          }
          resolve(ret);
        }
      },
    });
    org.nativescript.fontmanager.FontFace.importFromRemote(Utils.android.getApplicationContext(), url, false, cb);
  });
}

export function importFontsFromCSS(url: string) {
  return new Promise<FontFace[]>((resolve, reject) => {
    const cb = new kotlin.jvm.functions.Function2({
      invoke(fonts: java.util.List<org.nativescript.fontmanager.FontFace>, error: string) {
        const count = fonts.size();
        const ret = new Array(count);
        if (error) {
          reject(error);
        } else {
          for (let i = 0; i < count; i++) {
            const font = fonts.get(i) as org.nativescript.fontmanager.FontFace;
            ret[i] = FontFace.fromNative(font);
          }
          resolve(ret);
        }
      },
    });
    org.nativescript.fontmanager.FontFace.importFromRemote(Utils.android.getApplicationContext(), url, true, cb);
  });
}

const ctor_ = Symbol('[[ctor]]');
export class FontFace {
  native_: org.nativescript.fontmanager.FontFace;
  private extension?: string;
  constructor(family: string, source?: string | TypedArray | ArrayBuffer, descriptors?: FontDescriptor, ctor?: symbol, native?: org.nativescript.fontmanager.FontFace) {
    if (ctor === ctor_ && native instanceof org.nativescript.fontmanager.FontFace) {
      this.native_ = native;
      return;
    }

    if (source) {
      if (ArrayBuffer.isView(source) || source instanceof ArrayBuffer) {
        this.native_ = new org.nativescript.fontmanager.FontFace(family, source as never);
      } else if (typeof source === 'string') {
        const matches = source.match(url_ex) ?? [];
        this.extension = matches[2];
        let path = matches[1];
        if (path && path.startsWith('~/')) {
          path = path.replace('~', knownFolders.currentApp().path);
        }
        const url = `${path}${this.extension ? '.' + this.extension : ''}`;
        this.native_ = new org.nativescript.fontmanager.FontFace(family, url ?? source ?? null);
      }
    } else {
      this.native_ = new org.nativescript.fontmanager.FontFace(family);
    }

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
      this.native_.updateDescriptor(parts.join(' '));
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
      const cb = new kotlin.jvm.functions.Function1({
        invoke(error) {
          if (error) {
            reject(error);
          } else {
            resolve();
          }
        },
      });
      this.native_.load(Utils.android.getApplicationContext(), cb);
    });
  }

  get ascentOverride() {
    return this.native_.getAscentOverride();
  }

  set ascentOverride(value: string) {
    this.native_.setFontAscentOverride(value);
  }

  get descentOverride() {
    return this.native_.getDescentOverride();
  }

  set descentOverride(value: string) {
    this.native_.setFontDescentOverride(value);
  }

  get lineGapOverride() {
    return this.native_.getLineGapOverride();
  }

  set lineGapOverride(value: string) {
    this.native_.setFontLineGapOverride(value);
  }

  get stretch() {
    return this.native_.getStretch();
  }

  set stretch(value: string) {
    this.native_.setFontStretch(value);
  }

  get unicodeRange() {
    return this.native_.getUnicodeRange();
  }

  set unicodeRange(value: string) {
    this.native_.setFontUnicodeRange(value);
  }

  get featureSettings() {
    return this.native_.getFeatureSettings();
  }

  set featureSettings(value: string) {
    this.native_.setFontFeatureSettings(value);
  }

  get variationSettings() {
    return this.native_.getVariationSettings();
  }

  set variationSettings(value: string) {
    this.native_.setFontVariationSettings(value);
  }

  get display() {
    switch (this.native_.getDisplay()) {
      case org.nativescript.fontmanager.FontDisplay.Auto:
        return 'auto';
      case org.nativescript.fontmanager.FontDisplay.Block:
        return 'block';
      case org.nativescript.fontmanager.FontDisplay.Fallback:
        return 'fallback';
      case org.nativescript.fontmanager.FontDisplay.Optional:
        return 'optional';
      case org.nativescript.fontmanager.FontDisplay.Swap:
        return 'swap';
    }
  }

  set display(value: string) {
    this.native_.setFontDisplay(value);
  }

  get family() {
    return this.native_.getFontFamily();
  }

  get status() {
    switch (this.native_.getStatus()) {
      case org.nativescript.fontmanager.FontFaceStatus.Loaded:
        return 'loaded';
      case org.nativescript.fontmanager.FontFaceStatus.Loading:
        return 'loading';
      case org.nativescript.fontmanager.FontFaceStatus.Unloaded:
        return 'unloaded';
    }
  }

  get style() {
    return this.native_.getStyle().toString();
  }

  set style(value: string) {
    this.native_.setFontStyle(value);
  }

  get weight() {
    switch (this.native_.getWeight()) {
      case org.nativescript.fontmanager.FontWeight.Thin:
        return 'thin';
      case org.nativescript.fontmanager.FontWeight.ExtraLight:
        return 'extra-light';
      case org.nativescript.fontmanager.FontWeight.Light:
        return 'light';
      case org.nativescript.fontmanager.FontWeight.Normal:
        return 'normal';
      case org.nativescript.fontmanager.FontWeight.Medium:
        return 'medium';
      case org.nativescript.fontmanager.FontWeight.SemiBold:
        return 'semi-bold';
      case org.nativescript.fontmanager.FontWeight.Bold:
        return 'bold';
      case org.nativescript.fontmanager.FontWeight.ExtraBold:
        return 'extra-bold';
      case org.nativescript.fontmanager.FontWeight.Black:
        return 'black';
    }
  }

  set weight(value: string) {
    this.native_.setFontWeight(value);
  }

  get kerning() {
    return this.native_.getKerning();
  }

  set kerning(value: string) {
    this.native_.setFontKerning(value);
  }

  get variantLigatures() {
    return this.native_.getVariantLigatures();
  }

  set variantLigatures(value: string) {
    this.native_.setFontVariantLigatures(value);
  }

  updateDescriptor(css: string) {
    this.native_.updateDescriptor(css);
  }

  static fromNative(native: any): FontFace | null {
    if (native instanceof org.nativescript.fontmanager.FontFace) {
      const font = new FontFace('', undefined, undefined, ctor_, native);
      font.native_ = native;
      return font;
    }
    return null;
  }
}
