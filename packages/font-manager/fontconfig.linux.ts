import { Application, knownFolders } from '@nativescript/core';

const FcResultMatch = 0;
const pointer: interop.Type<any> = (interop.types as any).pointer;

let config: any = null;
function fc() {
  return (config ??= FcConfigGetCurrent());
}

/** Registers a font file; returns the families it contains, or null if fontconfig refused it. */
export function registerFile(file: string): string[] | null {
  if (!FcConfigAppFontAddFile(fc(), file)) return null;
  const families: string[] = [];
  const count = new interop.Reference(interop.types.int32, 0);
  const pattern = FcFreeTypeQuery(file, 0, null, count);
  if (pattern) {
    const out = new interop.Reference(pointer, null);
    for (let i = 0; FcPatternGetString(pattern, 'family', i, out) === FcResultMatch; i++) {
      families.push(interop.stringFromCString(out.value));
    }
    FcPatternDestroy(pattern);
  }
  return families;
}

const escape = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** CSS weight to fontconfig's scale. */
export function fcWeight(cssWeight: number): number {
  return FcWeightFromOpenType(cssWeight);
}

/**
 * Makes `css` resolve to `actual`. With a weight or slant, only requests for that weight / slant
 * do, so faces of one CSS family can live in differently named font families.
 */
export function alias(css: string, actual: string, weight?: number, italic?: boolean): void {
  if (!css || !actual || css.toLowerCase() === actual.toLowerCase()) return;
  const tests = [`<test name="family" qual="any" ignore-blanks="true"><string>${escape(css)}</string></test>`];
  if (weight != null) tests.push(`<test name="weight" compare="eq"><int>${fcWeight(weight)}</int></test>`);
  if (italic != null) tests.push(`<test name="slant" compare="${italic ? 'not_eq' : 'eq'}"><int>0</int></test>`);
  const xml = `<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><match target="pattern">${tests.join('')}<edit name="family" mode="prepend" binding="strong"><string>${escape(actual)}</string></edit></match></fontconfig>`;
  FcConfigParseAndLoadFromMemory(fc(), xml, 1);
}

/** Whether fontconfig has a family by that exact name. */
export function hasFamily(family: string): boolean {
  const pattern = FcNameParse(family.replace(/[\\:-]/g, (c) => '\\' + c));
  if (!pattern) return false;
  FcConfigSubstitute(fc(), pattern, 0 /* FcMatchPattern */);
  FcDefaultSubstitute(pattern);
  const result = new interop.Reference(interop.types.int32, 0);
  const match = FcFontMatch(fc(), pattern, result);
  FcPatternDestroy(pattern);
  if (!match) return false;
  const out = new interop.Reference(pointer, null);
  const found = FcPatternGetString(match, 'family', 0, out) === FcResultMatch && interop.stringFromCString(out.value).toLowerCase() === family.toLowerCase();
  FcPatternDestroy(match);
  return found;
}

/** Pango picks up new fonts, and views re-measure their text (Mason listens to `fontsChanged`). */
export function fontsChanged(): void {
  const map = pango_cairo_font_map_get_default();
  if (map) pango_fc_font_map_config_changed(map as any);
  Application.notify({ eventName: 'fontsChanged', object: Application } as any);
}

function extensionOf(bytes: Uint8Array): string {
  const tag = String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]);
  if (tag === 'wOF2') return 'woff2';
  if (tag === 'wOFF') return 'woff';
  if (tag === 'OTTO') return 'otf';
  return 'ttf';
}

let written = 0;

/** Font bytes as a file fontconfig can load, in the app's cache. */
export function writeFontFile(family: string, data: ArrayBuffer | ArrayBufferView): string {
  const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
  const dir = `${knownFolders.temp().path}/fonts`;
  g_mkdir_with_parents(dir, 0o700);
  const safe = family.replace(/[^A-Za-z0-9_-]/g, '_') || 'font';
  const file = `${dir}/${safe}-${Date.now().toString(36)}-${written++}.${extensionOf(bytes)}`;
  if (!g_file_set_contents(file, bytes, bytes.byteLength, null)) throw new Error(`Couldn't write ${file}`);
  return file;
}

function base64Bytes(data: string): Uint8Array {
  const binary = atob(data);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/** A local path for a font source: app paths and files directly, remote and data: URLs cached. */
export async function localFile(family: string, url: string): Promise<string> {
  if (url.startsWith('data:')) {
    const comma = url.indexOf(',');
    const meta = url.slice(5, comma);
    const payload = url.slice(comma + 1);
    const bytes = meta.endsWith(';base64') ? base64Bytes(payload) : new TextEncoder().encode(decodeURIComponent(payload));
    return writeFontFile(family, bytes);
  }
  if (/^https?:\/\//i.test(url)) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Failed to fetch ${url}: ${response.status}`);
    return writeFontFile(family, await response.arrayBuffer());
  }
  if (url.startsWith('file://')) return decodeURIComponent(url.slice(7));
  if (url.startsWith('~/')) return knownFolders.currentApp().path + url.slice(1);
  if (url.startsWith('/')) return url;
  return `${knownFolders.currentApp().path}/${url.replace(/^\.\//, '')}`;
}

/** Reads a stylesheet from a URL, an app path or a file. */
export async function readText(url: string): Promise<string> {
  if (/^https?:\/\//i.test(url)) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Failed to fetch ${url}: ${response.status}`);
    return response.text();
  }
  const file = await localFile('', url);
  const contents = new interop.Reference(pointer, null);
  const length = new interop.Reference<number>((interop.types as any).uint64 ?? interop.types.int64, 0);
  if (!g_file_get_contents(file, contents, length, null)) throw new Error(`Couldn't read ${file}`);
  const text = interop.stringFromCString(contents.value);
  g_free(contents.value);
  return text;
}
