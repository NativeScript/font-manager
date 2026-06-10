import { Observable } from '@nativescript/core';
import { FontFace } from '.';

export class FontFaceSet extends Observable {
  readonly ready: Promise<void>;
  readonly size: number;

  add(font: FontFace): void;

  entries(): IterableIterator<[FontFace, FontFace]>;

  keys(): IterableIterator<FontFace>;

  values(): IterableIterator<FontFace>;

  forEach(callback: (value: FontFace, key: FontFace, parent: FontFaceSet) => void, thisArg?: any): void;

  check(font: string, text?: string): boolean;

  clear(): void;

  delete(font: FontFace): void;

  load(font: string, text?: string): Promise<FontFace[]>;
}
