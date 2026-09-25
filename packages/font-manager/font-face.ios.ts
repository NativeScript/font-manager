import { knownFolders } from '@nativescript/core';
import { fontSourcePath } from './font-source';

export type TypedArray = Int8Array | Uint8Array | Uint8ClampedArray | Int16Array | Uint16Array | Int32Array | Uint32Array | Float32Array | Float64Array;

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
    NSCFontFace.importFromRemoteLoadCompletion(url, false, (fonts, error) => {
      const count = fonts.count;
      const ret = new Array(count);
      if (error) {
        reject(error);
      } else {
        for (let i = 0; i < count; i++) {
          ret[i] = FontFace.fromNative(fonts.objectAtIndex(i));
        }
        resolve(ret);
      }
    });
  });
}

export function importFontsFromCSS(url: string) {
  return new Promise<FontFace[]>((resolve, reject) => {
    NSCFontFace.importFromRemoteLoadCompletion(url, true, (fonts, error) => {
      const count = fonts.count;
      const ret = new Array(count);
      if (error) {
        reject(error);
      } else {
        for (let i = 0; i < count; i++) {
          ret[i] = FontFace.fromNative(fonts.objectAtIndex(i));
        }
        resolve(ret);
      }
    });
  });
}

const wrappers = new WeakMap<object, FontFace>();

const ctor_ = Symbol('[[ctor]]');
export class FontFace {
  native_: NSCFontFace;
  constructor(family: string, source?: string | TypedArray | ArrayBuffer, descriptors?: FontDescriptor, ctor?: symbol, native?: NSCFontFace) {
    if (ctor === ctor_ && native instanceof NSCFontFace) {
      this.native_ = native;
      return;
    }
    let descriptor: NSCFontDescriptors | null = null;

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
      const descriptorValue = parts.join(' ');
      descriptor = NSCFontDescriptors.alloc().initWithFamily(family);
      descriptor.update(descriptorValue);
    }

    if (source) {
      if (ArrayBuffer.isView(source) || source instanceof ArrayBuffer) {
        if (descriptor) {
          this.native_ = NSCFontFace.alloc().initWithFontDescriptorData(descriptor, NSData.dataWithData(source as never));
        } else {
          this.native_ = NSCFontFace.alloc().initWithFamilyData(family, NSData.dataWithData(source as never));
        }
      } else if (typeof source === 'string') {
        const url = fontSourcePath(source, knownFolders.currentApp().path);
        if (descriptor) {
          this.native_ = NSCFontFace.alloc().initWithFontDescriptorSource(descriptor, url);
        } else {
          this.native_ = NSCFontFace.alloc().initWithFamilySource(family, url);
        }
      }
    } else {
      if (descriptor) {
        this.native_ = NSCFontFace.alloc().initWithFontDescriptor(descriptor);
      } else {
        this.native_ = NSCFontFace.alloc().initWithFamily(family);
      }
    }

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
      this.native_.load((error) => {
        if (error) {
          reject(error);
        } else {
          resolve();
        }
      });
    });
  }

  get ascentOverride() {
    return this.native_.fontDescriptors.ascentOverride;
  }

  set ascentOverride(value: string) {
    this.native_.fontDescriptors.ascentOverride = value;
  }

  get descentOverride() {
    return this.native_.fontDescriptors.descentOverride;
  }

  set descentOverride(value: string) {
    this.native_.fontDescriptors.descentOverride = value;
  }

  get lineGapOverride() {
    return this.native_.fontDescriptors.lineGapOverride;
  }

  set lineGapOverride(value: string) {
    this.native_.fontDescriptors.lineGapOverride = value;
  }

  get stretch() {
    return this.native_.fontDescriptors.stretch;
  }

  set stretch(value: string) {
    this.native_.fontDescriptors.stretch = value;
  }

  get unicodeRange() {
    return this.native_.fontDescriptors.unicodeRange;
  }

  set unicodeRange(value: string) {
    this.native_.fontDescriptors.unicodeRange = value;
  }

  get featureSettings() {
    return this.native_.fontDescriptors.featureSettings;
  }

  set featureSettings(value: string) {
    this.native_.fontDescriptors.featureSettings = value;
  }

  get variationSettings() {
    return this.native_.fontDescriptors.variationSettings;
  }

  set variationSettings(value: string) {
    this.native_.fontDescriptors.variationSettings = value;
  }

  get display() {
    switch (this.native_.fontDescriptors.display) {
      case NSCFontDisplay.Auto:
        return 'auto';
      case NSCFontDisplay.Block:
        return 'block';
      case NSCFontDisplay.Fallback:
        return 'fallback';
      case NSCFontDisplay.Optional:
        return 'optional';
      case NSCFontDisplay.Swap:
        return 'swap';
    }
  }

  set display(value: string) {
    this.native_.setFontDisplay(value);
  }

  get family() {
    return this.native_.family;
  }

  get status() {
    switch (this.native_.status) {
      case NSCFontFaceStatus.Loaded:
        return 'loaded';
      case NSCFontFaceStatus.Loading:
        return 'loading';
      case NSCFontFaceStatus.Unloaded:
        return 'unloaded';
      case NSCFontFaceStatus.Error:
        return 'error';
    }
  }

  get style() {
    return this.native_.fontDescriptors.style.toString();
  }

  set style(value: string) {
    const obliqueMatch = /^oblique\s*(.*)$/.exec(value);
    if (obliqueMatch) {
      this.native_.setFontStyleAngle('oblique', obliqueMatch[1] || '0deg');
    } else {
      this.native_.setFontStyleAngle(value, '');
    }
  }

  get weight() {
    switch (this.native_.fontDescriptors.weight) {
      case NSCFontWeight.Thin:
        return 'thin';
      case NSCFontWeight.ExtraLight:
        return 'extra-light';
      case NSCFontWeight.Light:
        return 'light';
      case NSCFontWeight.Normal:
        return 'normal';
      case NSCFontWeight.Medium:
        return 'medium';
      case NSCFontWeight.SemiBold:
        return 'semi-bold';
      case NSCFontWeight.Bold:
        return 'bold';
      case NSCFontWeight.ExtraBold:
        return 'extra-bold';
      case NSCFontWeight.Black:
        return 'black';
    }
  }

  set weight(value: string) {
    this.native_.setFontWeight(value);
  }

  get kerning() {
    return this.native_.fontDescriptors.kerning;
  }

  set kerning(value: string) {
    this.native_.fontDescriptors.kerning = value;
  }

  get variantLigatures() {
    return this.native_.fontDescriptors.variantLigatures;
  }

  set variantLigatures(value: string) {
    this.native_.fontDescriptors.variantLigatures = value;
  }

  updateDescriptor(css: string) {
    this.native_.updateDescriptor(css);
  }

  static fromNative(native: any): FontFace | null {
    if (!(native instanceof NSCFontFace)) {
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
