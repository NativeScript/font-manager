import { Observable } from '@nativescript/core';
import { FontFace } from '.';

// WinRT IVectorView<FontFace> -> FontFace[] (tolerates either projection shape).
function viewToFaces(view: any): FontFace[] {
  const out: FontFace[] = [];
  if (!view) return out;
  const count = typeof view.Size === 'number' ? view.Size : typeof view.size === 'number' ? view.size : view.length ?? 0;
  for (let i = 0; i < count; i++) {
    const native = typeof view.GetAt === 'function' ? view.GetAt(i) : view[i];
    const face = (FontFace as any).fromNative(native);
    if (face) out.push(face);
  }
  return out;
}

// Delegate type for all FontFaceSet notifications (TypedEventHandler<FontFaceSet,
// FontFaceSetEventArgs>). A WinRT event is wired by assigning a delegate to the event-named
// property; the runtime can't derive a generic delegate's parameterized GUID from a plain
// assignment, so the delegate is built with NSWinRT.asDelegate(<type>, fn) — the same pattern
// @nativescript/core uses for ListView's generic TypedEventHandler events. Assigning null detaches.
const FONT_FACE_SET_HANDLER = 'Windows.Foundation.TypedEventHandler`2<NativeScript.FontManager.FontFaceSet,NativeScript.FontManager.FontFaceSetEventArgs>';

export class FontFaceSet extends Observable {
  native_: NativeScript.FontManager.FontFaceSet;
  // Retains the asDelegate instances so the native event subscriptions aren't garbage-collected.
  private _delegates: any[] = [];
  constructor() {
    super();
    this.native_ = NativeScript.FontManager.FontFaceSet.Instance();
    const ref = new WeakRef(this);

    const wire = (name: 'StatusChanged' | 'Loading' | 'LoadingDone' | 'LoadingError', handler: (sender: any, args: any) => void) => {
      try {
        const delegate = NSWinRT.asDelegate(FONT_FACE_SET_HANDLER, handler);
        (this.native_ as any)[name] = delegate;
        this._delegates.push(delegate);
      } catch {
        // building a generic delegate can throw on some hosts; the rest of the API is unaffected
      }
    };

    wire('StatusChanged', (_sender, args) => {
      const owner = ref.get();
      if (!owner) return;
      const value = args?.Status === NativeScript.FontManager.FontFaceSetStatus.Loading ? 'loading' : 'loaded';
      owner.notify({ eventName: 'status', object: owner, status: value });
    });

    wire('Loading', (_sender, args) => {
      const owner = ref.get();
      if (!owner) return;
      owner.notify({ eventName: 'loading', object: owner, fontfaces: [(FontFace as any).fromNative(args?.Face)] });
    });

    wire('LoadingDone', (_sender, args) => {
      const owner = ref.get();
      if (!owner) return;
      owner.notify({ eventName: 'loadingdone', object: owner, fontfaces: [(FontFace as any).fromNative(args?.Face)] });
    });

    wire('LoadingError', (_sender, args) => {
      const owner = ref.get();
      if (!owner) return;
      owner.notify({ eventName: 'loadingerror', object: owner, fontfaces: [(FontFace as any).fromNative(args?.Face)], error: args?.Error });
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
    return this.native_.Size;
  }

  add(font: FontFace) {
    this.native_.Add((font as any).native_);
  }

  *entries() {
    const faces = viewToFaces(this.native_.GetArray());
    let index = 0;
    return {
      next() {
        if (index < faces.length) {
          const font = faces[index++];
          return { value: [font, font] as [FontFace, FontFace], done: false };
        }
        return { value: null, done: true };
      },
    };
  }

  *keys() {
    const faces = viewToFaces(this.native_.GetArray());
    let index = 0;
    return {
      next() {
        if (index < faces.length) {
          return { value: faces[index++], done: false };
        }
        return { value: null, done: true };
      },
    };
  }

  *values() {
    const faces = viewToFaces(this.native_.GetArray());
    let index = 0;
    return {
      next() {
        if (index < faces.length) {
          return { value: faces[index++], done: false };
        }
        return { value: null, done: true };
      },
    };
  }

  forEach(callback: (value: FontFace, key: FontFace, parent: FontFaceSet) => void, thisArg?: any) {
    const faces = viewToFaces(this.native_.GetArray());
    for (const font of faces) {
      callback.call(thisArg, font, font, this);
    }
  }

  check(font: string, text?: string): boolean {
    return this.native_.Check(font, text ?? '');
  }

  clear() {
    this.native_.Clear();
  }

  delete(font: FontFace) {
    this.native_.Delete((font as any).native_);
  }

  load(font: string, text?: string) {
    return new Promise<FontFace[]>((resolve, reject) => {
      NSWinRT.toPromise(this.native_.LoadAsync(font, text ?? '')).then(
        (fonts) => resolve(viewToFaces(fonts)),
        (error) => reject(error),
      );
    });
  }
}
