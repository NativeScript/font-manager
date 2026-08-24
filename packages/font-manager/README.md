# @nativescript/font-manager

```
npm install @nativescript/font-manager
```

A NativeScript polyfill for the [CSS Font Loading API](https://developer.mozilla.org/en-US/docs/Web/API/CSS_Font_Loading_API). If you've used `document.fonts` on the web, this works the same way - `FontFace` and `FontFaceSet` behave identically, so font-loading logic can be shared across platforms.

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

## License

Apache License Version 2.0
