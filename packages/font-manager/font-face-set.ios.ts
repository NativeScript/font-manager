import { Observable } from '@nativescript/core';
import { FontFace } from '.';

export class FontFaceSet extends Observable {
  native_: NSCFontFaceSet;
  constructor() {
    super();
    this.native_ = NSCFontFaceSet.instance();
    const ref = new WeakRef(this);

    this.native_.addOnStatusListener((status) => {
      const owner = ref.get();
      if (!owner) return;
      const value = status === NSCFontFaceSetStatus.Loading ? 'loading' : 'loaded';
      owner.notify({ eventName: 'status', object: owner, status: value });
    });

    this.native_.addOnLoadingListener((face) => {
      const owner = ref.get();
      if (!owner) return;
      owner.notify({ eventName: 'loading', object: owner, fontfaces: [(FontFace as any).fromNative(face)] });
    });

    this.native_.addOnLoadingDoneListener((face) => {
      const owner = ref.get();
      if (!owner) return;
      owner.notify({ eventName: 'loadingdone', object: owner, fontfaces: [(FontFace as any).fromNative(face)] });
    });

    this.native_.addOnLoadingErrorListener((face, error) => {
      const owner = ref.get();
      if (!owner) return;
      owner.notify({ eventName: 'loadingerror', object: owner, fontfaces: [(FontFace as any).fromNative(face)], error });
    });
  }

  static get instance(): FontFaceSet {
    if (!FontFaceSet._instance) {
      FontFaceSet._instance = new FontFaceSet();
    }
    return FontFaceSet._instance;
  }
  private static _instance: FontFaceSet;

  ready: Promise<void> = Promise.resolve();

  get size(): number {
    return this.native_.size();
  }

  add(font: FontFace) {
    this.native_.add((font as any).native_);
  }

  *entries() {
    const iter: NSEnumerator<NSCFontFace> = this.native_.iter();
    let done = false;
    return {
      next() {
        const object = iter.nextObject();
        let value: [FontFace, FontFace] | null = null;
        if (object) {
          const font = (FontFace as any).fromNative(object);
          value = [font, font];
        } else {
          done = true;
        }
        return { value, done: done };
      },
    };
  }

  *keys() {
    const iter: NSEnumerator<NSCFontFace> = this.native_.iter();
    let done = false;
    return {
      next() {
        const object = iter.nextObject();
        let value: FontFace | null = null;
        if (object) {
          const font = (FontFace as any).fromNative(object);
          value = font;
        } else {
          done = true;
        }
        return { value, done: done };
      },
    };
  }

  *values() {
    const iter: NSEnumerator<NSCFontFace> = this.native_.iter();
    let done = false;
    return {
      next() {
        const object = iter.nextObject();
        let value: FontFace | null = null;
        if (object) {
          const font = (FontFace as any).fromNative(object);
          value = font;
        } else {
          done = true;
        }
        return { value, done: done };
      },
    };
  }

  forEach(callback: (value: FontFace, key: FontFace, parent: FontFaceSet) => void, thisArg?: any) {
    const array = this.native_.array();
    const count = array.count;
    for (let i = 0; i < count; i++) {
      const item = array.objectAtIndex(i);
      const font = (FontFace as any).fromNative(item);
      callback.call(thisArg, font, font, this);
    }
  }

  check(font: string, text?: string): boolean {
    return this.native_.checkText(font, text ?? '');
  }

  clear() {
    this.native_.clear();
  }

  delete(font: FontFace) {
    this.native_.delete((font as any).native_);
  }

  load(font: string, text?: string) {
    return new Promise<FontFace[]>((resolve, reject) => {
      this.native_.loadTextCallback(font, text ?? '', (fonts, error) => {
        if (error) {
          reject(error);
        } else {
          const count = fonts.count;
          const ret = new Array<FontFace>(count);
          for (let i = 0; i < count; i++) {
            ret[i] = (FontFace as any).fromNative(fonts.objectAtIndex(i));
          }
          resolve(ret);
        }
      });
    });
  }
}
