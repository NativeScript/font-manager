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

  /**
   * Resolves once no loads are outstanding. This was hardcoded to an
   * already-resolved promise, so awaiting it never actually waited.
   */
  get ready(): Promise<void> {
    return new Promise<void>((resolve) => {
      const cb = new kotlin.jvm.functions.Function1({
        invoke() {
          resolve();
        },
      });
      (this.native_ as any).ready(cb);
    });
  }

  get size(): number {
    return this.native_.getSize();
  }

  add(font: FontFace) {
    this.native_.add((font as any).native_);
  }

  *entries(): IterableIterator<[FontFace, FontFace]> {
    for (const font of this.values()) {
      yield [font, font];
    }
  }

  *keys(): IterableIterator<FontFace> {
    yield* this.values();
  }

  // These were declared as generators but `return`ed an iterator object, so nothing
  // was ever yielded. The object also treated an exhausted iterator as falsy, while
  // a Kotlin Iterator throws NoSuchElementException — hence hasNext().
  *values(): IterableIterator<FontFace> {
    const iter = this.native_.getIter();
    while (iter.hasNext()) {
      yield (FontFace as any).fromNative(iter.next());
    }
  }

  forEach(callback: (value: FontFace, key: FontFace, parent: FontFaceSet) => void, thisArg?: any) {
    // Iterating avoids getArray()'s Kotlin-side copy of the whole set plus a
    // bridge crossing per element.
    for (const font of this.values()) {
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
              ret[i] = (FontFace as any).fromNative(fonts.get(i));
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
