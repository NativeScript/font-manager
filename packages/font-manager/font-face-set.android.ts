import { Observable, Utils } from '@nativescript/core';
import { FontFace } from '.';
declare const kotlin: any;
export class FontFaceSet extends Observable {
  native_: org.nativescript.fontmanager.FontFaceSet;
  constructor() {
    super();
    this.native_ = org.nativescript.fontmanager.FontFaceSet.getInstance();
    const ref = new WeakRef(this);

    (this.native_ as any).addOnStatusListener(
      new kotlin.jvm.functions.Function1({
        invoke(status: org.nativescript.fontmanager.FontFaceSet.Status) {
          const owner = ref.get();
          if (!owner) return;
          const value = status === org.nativescript.fontmanager.FontFaceSet.Status.Loading ? 'loading' : 'loaded';
          owner.notify({ eventName: 'status', object: owner, status: value });
        },
      }),
    );

    (this.native_ as any).addOnLoadingListener(
      new kotlin.jvm.functions.Function1({
        invoke(face: org.nativescript.fontmanager.FontFace) {
          const owner = ref.get();
          if (!owner) return;
          owner.notify({ eventName: 'loading', object: owner, fontfaces: [(FontFace as any).fromNative(face)] });
        },
      }),
    );

    (this.native_ as any).addOnLoadingDoneListener(
      new kotlin.jvm.functions.Function1({
        invoke(face: org.nativescript.fontmanager.FontFace) {
          const owner = ref.get();
          if (!owner) return;
          const font = (FontFace as any).fromNative(face);
          owner.notify({ eventName: 'loadingdone', object: owner, fontfaces: [font] });
        },
      }),
    );

    (this.native_ as any).addOnLoadingErrorListener(
      new kotlin.jvm.functions.Function2({
        invoke(face: org.nativescript.fontmanager.FontFace, error: string) {
          const owner = ref.get();
          if (!owner) return;
          const font = (FontFace as any).fromNative(face);
          owner.notify({ eventName: 'loadingerror', object: owner, fontfaces: [font], error });
        },
      }),
    );
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
    return this.native_.getSize();
  }

  add(font: FontFace) {
    this.native_.add((font as any).native_);
  }

  *entries() {
    const iter = this.native_.getIter();
    let done = false;
    return {
      next() {
        const object = iter.next();
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
    const iter = this.native_.getIter();
    let done = false;
    return {
      next() {
        const object = iter.next();
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
    const iter = this.native_.getIter();
    let done = false;
    return {
      next() {
        const object = iter.next();
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
    const array = this.native_.getArray();
    const count = array.length;
    for (let i = 0; i < count; i++) {
      const item = array[i];
      const font = (FontFace as any).fromNative(item);
      callback.call(thisArg, font, font, this);
    }
  }

  check(font: string, text?: string): boolean {
    return this.native_.check(font, text);
  }

  clear() {
    this.native_.clear();
  }

  delete(font: FontFace) {
    this.native_.delete((font as any).native_);
  }

  load(font: string, text?: string) {
    return new Promise<FontFace[]>((resolve, reject) => {
      const cb = new kotlin.jvm.functions.Function2({
        invoke(fonts: java.util.List<org.nativescript.fontmanager.FontFace>, error: string) {
          if (error) {
            reject(error);
          } else {
            const count = fonts.size();
            const ret = new Array<FontFace>(count);
            for (let i = 0; i < count; i++) {
              ret.push((FontFace as any).fromNative(fonts.get(i)));
            }
            resolve(ret);
          }
        },
      });
      //@ts-ignore
      this.native_.load(Utils.android.getApplicationContext(), font, text ?? null, cb);
    });
  }
}
