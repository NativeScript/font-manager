import { Observable } from '@nativescript/core';
import { FontFace } from '.';
import { hasFamily } from './fontconfig.linux';

const GENERIC = new Set(['serif', 'sans-serif', 'monospace', 'cursive', 'fantasy', 'system-ui', 'emoji', 'math', 'ui-serif', 'ui-sans-serif', 'ui-monospace', 'ui-rounded']);

/** The family list of a CSS `font` shorthand (whatever follows the size). */
function familiesOf(font: string): string[] {
  const rest = /(?:^|\s)[\d.]+(?:px|pt|em|rem|%|vh|vw)?(?:\s*\/\s*\S+)?\s+(.*)$/i.exec(font.trim())?.[1] ?? font;
  return rest
    .split(',')
    .map((f) => f.trim().replace(/^(['"])(.*)\1$/, '$2'))
    .filter(Boolean);
}

export class FontFaceSet extends Observable {
  private _faces = new Set<FontFace>();
  private _pending = 0;
  private _ready: Promise<void> = Promise.resolve();
  private _resolveReady?: () => void;

  constructor() {
    super();
    (global as any).__fontManagerSet = this;
  }

  static get instance(): FontFaceSet {
    if (!FontFaceSet._instance) {
      FontFaceSet._instance = new FontFaceSet();
    }
    return FontFaceSet._instance;
  }
  private static _instance: FontFaceSet;

  get ready(): Promise<void> {
    return this._ready;
  }

  get size(): number {
    return this._faces.size;
  }

  get status(): 'loading' | 'loaded' {
    return this._pending > 0 ? 'loading' : 'loaded';
  }

  add(font: FontFace) {
    this._faces.add(font);
    return this;
  }

  entries(): IterableIterator<[FontFace, FontFace]> {
    return Array.from(this._faces, (f) => [f, f] as [FontFace, FontFace])[Symbol.iterator]();
  }

  keys(): IterableIterator<FontFace> {
    return this._faces.values();
  }

  values(): IterableIterator<FontFace> {
    return this._faces.values();
  }

  [Symbol.iterator]() {
    return this._faces.values();
  }

  forEach(callback: (value: FontFace, key: FontFace, parent: FontFaceSet) => void, thisArg?: any) {
    for (const font of this._faces) callback.call(thisArg, font, font, this);
  }

  /** Whether every named family can be used without loading anything. */
  check(font: string, _text?: string): boolean {
    return familiesOf(font).every((family) => {
      if (GENERIC.has(family.toLowerCase())) return true;
      const faces = this._matching(family);
      if (faces.length) return faces.every((f) => f.status === 'loaded');
      return hasFamily(family);
    });
  }

  clear() {
    this._faces.clear();
  }

  delete(font: FontFace) {
    return this._faces.delete(font);
  }

  /** Loads the set's faces for the families in a CSS `font` shorthand. */
  async load(font: string, _text?: string): Promise<FontFace[]> {
    const faces = familiesOf(font).flatMap((family) => this._matching(family));
    await Promise.all(faces.map((f) => f.load()));
    return faces;
  }

  private _matching(family: string): FontFace[] {
    const key = family.toLowerCase();
    return Array.from(this._faces).filter((f) => f.family.toLowerCase() === key);
  }

  _loading(face: FontFace) {
    if (this._pending++ === 0) {
      this._ready = new Promise((resolve) => (this._resolveReady = resolve));
      this.notify({ eventName: 'status', object: this, status: 'loading' } as any);
    }
    this.notify({ eventName: 'loading', object: this, fontfaces: [face] } as any);
  }

  _loaded(face: FontFace) {
    this.notify({ eventName: 'loadingdone', object: this, fontfaces: [face] } as any);
    this._settle();
  }

  _failed(face: FontFace, error: unknown) {
    this.notify({ eventName: 'loadingerror', object: this, fontfaces: [face], error } as any);
    this._settle();
  }

  private _settle() {
    if (--this._pending === 0) {
      this._resolveReady?.();
      this._resolveReady = undefined;
      this.notify({ eventName: 'status', object: this, status: 'loaded' } as any);
    }
  }
}

// The set exists from the start, so faces loaded on their own still report to it.
void FontFaceSet.instance;
