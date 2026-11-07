declare const __LINUX__: boolean;

declare module interop {
  function stringFromCString(pointer: any): string;
}

declare function FcConfigGetCurrent(): interop.Pointer | interop.Reference<any> | null;
declare function FcConfigAppFontAddFile(config: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, file: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): number;
declare function FcFreeTypeQuery(file: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, id: number, blanks: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, count: interop.Pointer | interop.Reference<number> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;
declare function FcPatternGetString(p: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, object: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, n: number, s: interop.Pointer | interop.Reference<interop.Pointer | interop.Reference<any> | null> | ArrayBufferLike | ArrayBufferView | null): FcResult;
declare function FcPatternDestroy(p: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): void;
declare function FcWeightFromOpenType(ot_weight: number): number;
declare function FcConfigParseAndLoadFromMemory(config: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, buffer: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, complain: number): number;
declare function FcNameParse(name: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;
declare function FcConfigSubstitute(config: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, p: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, kind: FcMatchKind): number;
declare function FcDefaultSubstitute(pattern: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): void;
declare function FcFontMatch(config: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, p: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, result: interop.Pointer | interop.Reference<FcResult> | ArrayBufferLike | ArrayBufferView | null): interop.Pointer | interop.Reference<any> | null;
declare function pango_cairo_font_map_get_default(): interop.Pointer | interop.Reference<any> | null;
declare function pango_fc_font_map_config_changed(fcfontmap: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): void;
declare function g_mkdir_with_parents(pathname: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, mode: number): number;
declare function g_file_set_contents(filename: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, contents: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, length: number, error: interop.Pointer | interop.Reference<interop.Pointer | interop.Reference<any> | null> | ArrayBufferLike | ArrayBufferView | null): number;
declare function g_file_get_contents(filename: string | interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null, contents: interop.Pointer | interop.Reference<interop.Pointer | interop.Reference<any> | null> | ArrayBufferLike | ArrayBufferView | null, length: interop.Pointer | interop.Reference<number> | ArrayBufferLike | ArrayBufferView | null, error: interop.Pointer | interop.Reference<interop.Pointer | interop.Reference<any> | null> | ArrayBufferLike | ArrayBufferView | null): number;
declare function g_free(mem: interop.Pointer | interop.Reference<any> | ArrayBufferLike | ArrayBufferView | null): void;
