import { Observable, Utils } from '@nativescript/core';
import { FontFace } from '.';
declare const kotlin: any;

function listToFaces(list: java.util.List<org.nativescript.fontmanager.FontFace>): FontFace[] {
  const out: FontFace[] = [];
  const count = list ? list.size() : 0;
  for (let i = 0; i < count; i++) {
    const face = (FontFace as any).fromNative(list.get(i));
    if (face) out.push(face);
  }
  return out;
}
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
        invoke(_face: org.nativescript.fontmanager.FontFace) {
          const owner = ref.get();
          if (!owner) return;
          owner.notify({ eventName: 'loading', object: owner, fontfaces: [] });
        },
      }),
    );

    (this.native_ as any).addOnLoadingDoneFacesListener(
      new kotlin.jvm.functions.Function1({
        invoke(faces: java.util.List<org.nativescript.fontmanager.FontFace>) {
          const owner = ref.get();
          if (!owner) return;
          owner.notify({ eventName: 'loadingdone', object: owner, fontfaces: listToFaces(faces) });
        },
      }),
    );

    (this.native_ as any).addOnLoadingErrorFacesListener(
      new kotlin.jvm.functions.Function2({
        invoke(faces: java.util.List<org.nativescript.fontmanager.FontFace>, error: string) {
          const owner = ref.get();
          if (!owner) return;
          owner.notify({ eventName: 'loadingerror', object: owner, fontfaces: listToFaces(faces), error });
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

  /** Resolves once no loads are outstanding. */
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

  *values(): IterableIterator<FontFace> {
    const array = this.native_.getArray();
    const count = array.length;
    for (let i = 0; i < count; i++) {
      yield (FontFace as any).fromNative(array[i]);
    }
  }

  forEach(callback: (value: FontFace, key: FontFace, parent: FontFaceSet) => void, thisArg?: any) {
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
