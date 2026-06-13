// Ambient declarations for the projected C++/WinRT NativeScript.FontManager runtime component
// (src-native/windows/FontManager) and the @nativescript/windows runtime's WinRT async bridge.
// The runtime projects WinRT classes by their fully-qualified namespace with PascalCase members.

declare namespace NativeScript.FontManager {
  enum FontDisplay {
    Auto = 0,
    Block = 1,
    Fallback = 2,
    Optional = 3,
    Swap = 4,
  }

  enum FontWeight {
    Thin = 100,
    ExtraLight = 200,
    Light = 300,
    Normal = 400,
    Medium = 500,
    SemiBold = 600,
    Bold = 700,
    ExtraBold = 800,
    Black = 900,
  }

  enum FontFaceStatus {
    Unloaded = 0,
    Loading = 1,
    Loaded = 2,
    Error = 3,
  }

  enum FontFaceSetStatus {
    Loading = 0,
    Loaded = 1,
  }

  class FontDescriptors {
    constructor(family: string);
    Weight: FontWeight;
    readonly Family: string;
    Style: string;
    ObliqueAngle: string;
    Variant: string;
    AscentOverride: string;
    DescentOverride: string;
    Display: FontDisplay;
    Stretch: string;
    UnicodeRange: string;
    FeatureSettings: string;
    LineGapOverride: string;
    VariationSettings: string;
    Kerning: string;
    VariantLigatures: string;
    Update(value: string): void;
    SetFontWeightFromString(value: string): void;
    SetFontStyleFromString(value: string): void;
    SetFontDisplayFromString(value: string): void;
  }

  class FontFace {
    static FromFamily(family: string): FontFace;
    static FromFamilySource(family: string, source: string): FontFace;
    static FromFamilyData(family: string, data: any): FontFace;
    static FromDescriptor(descriptor: FontDescriptors): FontFace;
    static FromDescriptorSource(descriptor: FontDescriptors, source: string): FontFace;
    static FromDescriptorData(descriptor: FontDescriptors, data: any): FontFace;

    readonly Family: string;
    readonly Status: FontFaceStatus;
    readonly Descriptors: FontDescriptors;
    readonly FontUri: string;
    readonly Display: FontDisplay;
    readonly Weight: FontWeight;
    readonly Style: string;
    readonly Stretch: string;
    readonly UnicodeRange: string;
    readonly FeatureSettings: string;
    readonly VariationSettings: string;
    readonly AscentOverride: string;
    readonly DescentOverride: string;
    readonly LineGapOverride: string;
    readonly Kerning: string;
    readonly VariantLigatures: string;

    SetFontWeight(value: string): void;
    SetFontStyle(value: string, angle: string): void;
    SetFontDisplay(value: string): void;
    SetFontStretch(value: string): void;
    SetFontUnicodeRange(value: string): void;
    SetFontFeatureSettings(value: string): void;
    SetFontVariationSettings(value: string): void;
    SetFontAscentOverride(value: string): void;
    SetFontDescentOverride(value: string): void;
    SetFontLineGapOverride(value: string): void;
    SetFontKerning(value: string): void;
    SetFontVariantLigatures(value: string): void;
    UpdateDescriptor(css: string): void;

    LoadAsync(): any;
    static ImportFromRemoteAsync(url: string, load: boolean): any;
  }

  class FontFaceSetEventArgs {
    readonly Status: FontFaceSetStatus;
    readonly Face: FontFace;
    readonly Error: string;
  }

  class FontFaceSet {
    static Instance(): FontFaceSet;
    readonly Size: number;
    Add(font: FontFace): void;
    Delete(font: FontFace): void;
    Clear(): void;
    Has(font: FontFace): boolean;
    Check(font: string, text: string): boolean;
    LoadAsync(font: string, text: string): any;
    GetArray(): any;
    // WinRT events project as assignable delegate properties (assign an NSWinRT.asDelegate result;
    // assign null to detach).
    StatusChanged: any;
    Loading: any;
    LoadingDone: any;
    LoadingError: any;
  }
}

// @nativescript/windows runtime WinRT interop helpers.
declare const NSWinRT: {
  // Turns a WinRT IAsyncOperation/IAsyncAction into a Promise.
  toPromise<T = any>(op: any): Promise<T>;
  // Wraps a JS function as a WinRT delegate. Pass the delegate's full type name (required for
  // generic delegates whose parameterized GUID can't be inferred), e.g.
  // 'Windows.Foundation.TypedEventHandler`2<Ns.Sender,Ns.Args>'.
  asDelegate(typeName: string, fn: (...args: any[]) => any): any;
  asDelegate(fn: (...args: any[]) => any): any;
};
