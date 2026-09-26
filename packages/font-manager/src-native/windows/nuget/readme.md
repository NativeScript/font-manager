# NativeScript.FontManager

Native **C++/WinRT Windows Runtime Component** backing [`@nativescript/font-manager`](https://github.com/NativeScript/font-manager)
— a Web Font Loading API (`FontFace` / `FontFaceSet`) built on DirectWrite.

This package is for **C++/WinRT consumers** (e.g. `@nativescript/canvas`) that want to call
FontManager types from native code. Add a `PackageReference` and the bundled MSBuild targets will:

1. add the `.winmd` so cppwinrt generates the projection (`#include <winrt/NativeScript.FontManager.h>`);
2. copy the active-architecture `NativeScript.FontManager.dll` to your build output;
3. register the runtimeclasses (`FontFace`, `FontFaceSet`, `FontDescriptors`) as activatable
   in-proc classes in your app's `Package.appxmanifest`.

```xml
<PackageReference Include="NativeScript.FontManager" Version="1.0.2" />
```

Supported architectures: `x64`, `arm64`. License: Apache-2.0.
