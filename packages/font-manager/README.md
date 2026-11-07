# @nativescript/font-manager

```
npm install @nativescript/font-manager
```

A NativeScript polyfill for the [CSS Font Loading API](https://developer.mozilla.org/en-US/docs/Web/API/CSS_Font_Loading_API). If you've used `document.fonts` on the web, this works the same way - `FontFace` and `FontFaceSet` behave identically, so font-loading logic can be shared across platforms. Native code backs each platform: Objective‑C (iOS), Kotlin (Android) and C++/WinRT (Windows).

## Load a local font at runtime

For fonts that aren't bundled in `app/fonts/` ahead of time, or when you need control over when loading happens:

```typescript
import { FontFace, FontFaceSet } from '@nativescript/font-manager';

const face = new FontFace('Roboto', 'url(~/fonts/Roboto-Regular.ttf)');
await face.load();
FontFaceSet.instance.add(face);
```

## Load fonts from a remote stylesheet

Point it at any CSS file with `@font-face` rules and it handles downloading and registration:

```typescript
import { importFontsFromCSS } from '@nativescript/font-manager';

await importFontsFromCSS('https://fonts.googleapis.com/css2?family=Roboto');
```

If you want the `FontFace` objects back without registering them globally, use `loadFontsFromCSS` instead.

## Wait until fonts are ready before rendering

Avoids flash-of-unstyled-text when your UI depends on a custom font being present:

```typescript
await FontFaceSet.instance.ready;
// safe to render
```

## Check or load fonts by CSS query

Same string format as the web (`"<size> <family>"`):

```typescript
if (!FontFaceSet.instance.check('16px Roboto')) {
  await FontFaceSet.instance.load('16px Roboto');
}
```

## Platforms

| Platform | Native source | Backend |
| --- | --- | --- |
| iOS | `src-native/ios` | CoreText / CoreGraphics |
| Android | `src-native/android` | Android Typeface APIs |
| Windows | `src-native/windows` | C++/WinRT + DirectWrite |
| Linux | `src-native/linux` | Rust + fontconfig (`libfontmanager.so`, C API) |

On Linux a loaded face is registered with fontconfig, the registry GTK and Pango resolve families from, and its CSS family name is mapped to the family inside the file. The app then raises `Application`'s `fontsChanged` event so views lay their text out again. Needs `@nativescript/linux` 0.1.0-alpha.3 or later.

The Linux implementation is a native library, `platforms/linux/lib/<arch>/libfontmanager.so`, whose C API (`platforms/linux/include/font_manager.h`) other native code can link against too: the `FontFaceSet`, change and loading callbacks, and `fm_resolve_family` to turn a CSS `font-family` list into the family to give Pango. Build it with `tools/scripts/build-linux.sh`; `src-native/linux/bench/run.sh` runs a native benchmark.

## License

Apache License Version 2.0
