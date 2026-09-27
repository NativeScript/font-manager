# NativeScript.FontManager

Native **C++/WinRT Windows Runtime Component** backing [`@nativescript/font-manager`](https://github.com/NativeScript/font-manager)
— a Web Font Loading API (`FontFace` / `FontFaceSet`) built on DirectWrite.

Add a `PackageReference` and the bundled MSBuild targets will:

1. copy the active-architecture `NativeScript.FontManager.dll` (+ `.winmd`) to your build output;
2. register the runtimeclasses (`FontFace`, `FontFaceSet`, `FontDescriptors`) as activatable
   in-proc classes in your app's `Package.appxmanifest`;
3. for **C++/WinRT consumers** (e.g. `@nativescript/canvas`) only, add the `.winmd` so cppwinrt
   generates the projection (`#include <winrt/NativeScript.FontManager.h>`).

Any other project type, such as the C# host app of a NativeScript Windows app, gets steps 1 and 2.

```xml
<PackageReference Include="NativeScript.FontManager" Version="1.0.2" />
```

Supported architectures: `x64`, `arm64`. License: Apache-2.0.
