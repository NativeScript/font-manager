import { knownFolders, Utils } from '@nativescript/core';
import { fontSourcePath } from './font-source';
type TypedArray = Int8Array | Uint8Array | Uint8ClampedArray | Int16Array | Uint16Array | Int32Array | Uint32Array | Float32Array | Float64Array;

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

/**
 * Reading `org.nativescript.fontmanager.X.Y` crosses the bridge every time, so a
 * getter that switched over 9 enum constants cost 9 crossings per property read.
 * These resolve once, on first use — not at module load, since the runtime may not
 * have the classes bound yet.
 */
let bridge: {
  FontFace: typeof org.nativescript.fontmanager.FontFace;
  display: Record<'auto' | 'block' | 'fallback' | 'optional' | 'swap', org.nativescript.fontmanager.FontDisplay>;
  status: Record<'loaded' | 'loading' | 'unloaded' | 'error', org.nativescript.fontmanager.FontFaceStatus>;
  weight: Record<'thin' | 'extraLight' | 'light' | 'normal' | 'medium' | 'semiBold' | 'bold' | 'extraBold' | 'black', org.nativescript.fontmanager.FontWeight>;
};

function natives() {
  if (!bridge) {
    const ns = org.nativescript.fontmanager;
    const D = ns.FontDisplay;
    const S = ns.FontFaceStatus;
    const W = ns.FontWeight;
    bridge = {
      FontFace: ns.FontFace,
      display: { auto: D.Auto, block: D.Block, fallback: D.Fallback, optional: D.Optional, swap: D.Swap },
      status: { loaded: S.Loaded, loading: S.Loading, unloaded: S.Unloaded, error: S.Error },
      weight: {
        thin: W.Thin,
        extraLight: W.ExtraLight,
        light: W.Light,
        normal: W.Normal,
        medium: W.Medium,
        semiBold: W.SemiBold,
        bold: W.Bold,
        extraBold: W.ExtraBold,
        black: W.Black,
      },
    };
  }
  return bridge;
}

/**
 * One JS wrapper per native face. Besides the allocation, this fixes identity:
 * iterating the set twice used to hand back different objects for the same face,
 * so `===` never matched.
 */
const wrappers = new WeakMap<object, FontFace>();

const ctor_ = Symbol('[[ctor]]');
export class FontFace {
  native_: org.nativescript.fontmanager.FontFace;
  constructor(family: string, source?: string | TypedArray | ArrayBuffer, descriptors?: FontDescriptor, ctor?: symbol, native?: org.nativescript.fontmanager.FontFace) {
    if (ctor === ctor_ && native instanceof natives().FontFace) {
      this.native_ = native;
      return;
    }

    if (source) {
      if (ArrayBuffer.isView(source) || source instanceof ArrayBuffer) {
        this.native_ = new org.nativescript.fontmanager.FontFace(family, source as never);
      } else if (typeof source === 'string') {
        this.native_ = new org.nativescript.fontmanager.FontFace(family, fontSourcePath(source, knownFolders.currentApp().path));
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

    // Registered here too, so a face handed back through fromNative (events,
    // iteration) resolves to this same wrapper.
    if (this.native_) {
      wrappers.set(this.native_, this);
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
    const d = natives().display;
    switch (this.native_.getDisplay()) {
      case d.auto:
        return 'auto';
      case d.block:
        return 'block';
      case d.fallback:
        return 'fallback';
      case d.optional:
        return 'optional';
      case d.swap:
        return 'swap';
    }
  }

  set display(value: string) {
    this.native_.setFontDisplay(value);
  }

  get family() {
    // Set once at construction on the native side, so it is worth not re-marshaling.
    return (this.family_ ??= this.native_.getFontFamily());
  }
  private family_?: string;

  get status() {
    const s = natives().status;
    switch (this.native_.getStatus()) {
      case s.loaded:
        return 'loaded';
      case s.loading:
        return 'loading';
      case s.unloaded:
        return 'unloaded';
      case s.error:
        return 'error';
    }
  }

  get style() {
    return this.native_.getStyle().toString();
  }

  set style(value: string) {
    this.native_.setFontStyle(value);
  }

  get weight() {
    const w = natives().weight;
    switch (this.native_.getWeight()) {
      case w.thin:
        return 'thin';
      case w.extraLight:
        return 'extra-light';
      case w.light:
        return 'light';
      case w.normal:
        return 'normal';
      case w.medium:
        return 'medium';
      case w.semiBold:
        return 'semi-bold';
      case w.bold:
        return 'bold';
      case w.extraBold:
        return 'extra-bold';
      case w.black:
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
    if (!(native instanceof natives().FontFace)) {
      return null;
    }
    const existing = wrappers.get(native);
    if (existing) {
      return existing;
    }
    const font = new FontFace('', undefined, undefined, ctor_, native);
    wrappers.set(native, font);
    return font;
  }
}
