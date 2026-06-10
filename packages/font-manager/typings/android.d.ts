declare module org {
  export module nativescript {
    export module fontmanager {
      export class FontDescriptors {
        public static class: java.lang.Class<org.nativescript.fontmanager.FontDescriptors>;
        public setFontStyle(angle: string): void;
        public setFontDisplay(value: string): void;
        public getUnicodeRange(): string;
        public constructor(family: string);
        public getVariant(): string;
        public setFontWeight(value: string): void;
        public getAscentOverride(): string;
        public setFeatureSettings(value: string): void;
        public getFamily(): string;
        public setDisplay(value: org.nativescript.fontmanager.FontDisplay): void;
        public getStretch(): string;
        public getWeight(): org.nativescript.fontmanager.FontWeight;
        public setVariationSettings(value: string): void;
        public setFamily(value: string): void;
        public setDescentOverride(value: string): void;
        public getDisplay(): org.nativescript.fontmanager.FontDisplay;
        public getStyle(): org.nativescript.fontmanager.FontStyle;
        public getVariationSettings(): string;
        public setStyle(value: org.nativescript.fontmanager.FontStyle): void;
        public getDescentOverride(): string;
        public update$fontmanager(it: string): void;
        public setWeight(value: org.nativescript.fontmanager.FontWeight): void;
        public setLineGapOverride(value: string): void;
        public setVariant(value: string): void;
        public setUnicodeRange(value: string): void;
        public setStretch(value: string): void;
        public getFeatureSettings(): string;
        public setAscentOverride(value: string): void;
        public getLineGapOverride(): string;
      }
    }
  }
}

declare module org {
  export module nativescript {
    export module fontmanager {
      export class FontDisplay {
        public static class: java.lang.Class<org.nativescript.fontmanager.FontDisplay>;
        public static Auto: org.nativescript.fontmanager.FontDisplay;
        public static Block: org.nativescript.fontmanager.FontDisplay;
        public static Fallback: org.nativescript.fontmanager.FontDisplay;
        public static Optional: org.nativescript.fontmanager.FontDisplay;
        public static Swap: org.nativescript.fontmanager.FontDisplay;
        public static getEntries(): any;
        public static values(): androidNative.Array<org.nativescript.fontmanager.FontDisplay>;
        public static valueOf(value: string): org.nativescript.fontmanager.FontDisplay;
      }
    }
  }
}

declare module org {
  export module nativescript {
    export module fontmanager {
      export class FontFace {
        public static class: java.lang.Class<org.nativescript.fontmanager.FontFace>;
        public setStyle(value: org.nativescript.fontmanager.FontStyle): void;
        public getUnicodeRange(): string;
        public setVariant(value: string): void;
        public setFeatureSettings(value: string): void;
        public constructor(family: string, source: java.nio.ByteBuffer | null, descriptors: org.nativescript.fontmanager.FontDescriptors | null);
        public constructor(family: string, source: androidNative.Array<number> | null, descriptors: org.nativescript.fontmanager.FontDescriptors | null);
        public getVariant(): string;
        public constructor(family: string);
        public getOnReload(): any;
        public setFontDescentOverride(value: string): org.nativescript.fontmanager.FontFace;
        public getAscentOverride(): string;
        public constructor(family: string, source: java.nio.ByteBuffer | null);
        public setFontAscentOverride(value: string): org.nativescript.fontmanager.FontFace;
        public getStretch(): string;
        public updateDescriptor(value: string): void;
        public setFontWeight(value: string): org.nativescript.fontmanager.FontFace;
        public getWeight(): org.nativescript.fontmanager.FontWeight;
        public constructor(family: string, source: string | null);
        public setFontLineGapOverride(value: string): org.nativescript.fontmanager.FontFace;
        public setFontVariationSettings(value: string): org.nativescript.fontmanager.FontFace;
        public getStatus(): org.nativescript.fontmanager.FontFaceStatus;
        public setFontFeatureSettings(value: string): org.nativescript.fontmanager.FontFace;
        public load(context: globalAndroid.content.Context, callback: any): void;
        public setWeight(value: org.nativescript.fontmanager.FontWeight): void;
        public getFeatureSettings(): string;
        public setFontUnicodeRange(value: string): org.nativescript.fontmanager.FontFace;
        public getFontFamily(): string;
        public setUnicodeRange(value: string): void;
        public setFontStretch(value: string): org.nativescript.fontmanager.FontFace;
        public constructor(family: string, source: androidNative.Array<number> | null);
        public setFontDisplay(value: string): org.nativescript.fontmanager.FontFace;
        public setFontStyle(value: string): org.nativescript.fontmanager.FontFace;
        public getDisplay(): org.nativescript.fontmanager.FontDisplay;
        public getStyle(): org.nativescript.fontmanager.FontStyle;
        public getVariationSettings(): string;
        public setDescentOverride(value: string): void;
        public getFont(): globalAndroid.graphics.Typeface;
        public rawData(): androidNative.Array<number>;
        public setStretch(value: string): void;
        public static clearFontCache(context: globalAndroid.content.Context): void;
        public getDescentOverride(): string;
        public constuctor(family: string, source: string | null, descriptors: org.nativescript.fontmanager.FontDescriptors | null);
        public setFontVariant(value: string): org.nativescript.fontmanager.FontFace;
        public static importFromRemote(context: globalAndroid.content.Context, url: string, load: boolean, callback: any): void;
        public setAscentOverride(value: string): void;
        public setOnReload(value: any): void;
        public setDisplay(value: org.nativescript.fontmanager.FontDisplay): void;
        public getFontPath(): string;
        public setLineGapOverride(value: string): void;
        public setVariationSettings(value: string): void;
        public getLineGapOverride(): string;

        public setFontKerning(value: string): void;
        public getKerning(): string;

        public setFontVariantLigatures(value: string): void;
        public getVariantLigatures(): string;
      }
      export module FontFace {
        export class Callback {
          public static class: java.lang.Class<org.nativescript.fontmanager.FontFace.Callback>;
          /**
           * Constructs a new instance of the org.nativescript.fontmanager.FontFace$Callback interface with the provided implementation. An empty constructor exists calling super() when extending the interface class.
           */
          public constructor(implementation: { onSuccess(): void; onError(param0: string): void });
          public constructor();
          public onError(param0: string): void;
          public onSuccess(): void;
        }
        export class Companion {
          public static class: java.lang.Class<org.nativescript.fontmanager.FontFace.Companion>;
          public clearFontCache(context: globalAndroid.content.Context): void;
          public importFromRemote(e: globalAndroid.content.Context, result: string, this_: boolean, context: any): void;
        }
      }
    }
  }
}

declare module org {
  export module nativescript {
    export module fontmanager {
      export class FontFaceSet {
        public static class: java.lang.Class<org.nativescript.fontmanager.FontFaceSet>;
        public getArray(): androidNative.Array<org.nativescript.fontmanager.FontFace>;
        public forEach(this_: any): void;
        public add(answer$iv: org.nativescript.fontmanager.FontFace): void;
        public load(context: globalAndroid.content.Context, font: string, text: string, callback: any): void;
        public constructor();
        public ready(callback: any): void;
        public getStatus(): org.nativescript.fontmanager.FontFaceSet.Status;
        public has(font: org.nativescript.fontmanager.FontFace): boolean;
        public check(font: string, text?: string): boolean;
        public getSize(): number;
        public static getInstance(): org.nativescript.fontmanager.FontFaceSet;
        public delete(list: org.nativescript.fontmanager.FontFace): void;
        public clear(): void;
        public getIter(): java.util.Iterator<org.nativescript.fontmanager.FontFace>;
        public addOnStatusListener(listener: (status: org.nativescript.fontmanager.FontFaceSet.Status) => void): void;
        public removeOnStatusListener(listener: (status: org.nativescript.fontmanager.FontFaceSet.Status) => void): void;
        public addOnLoadingListener(listener: (face: org.nativescript.fontmanager.FontFace) => void): void;
        public removeOnLoadingListener(listener: (face: org.nativescript.fontmanager.FontFace) => void): void;
        public addOnLoadingDoneListener(listener: (face: org.nativescript.fontmanager.FontFace) => void): void;
        public removeOnLoadingDoneListener(listener: (face: org.nativescript.fontmanager.FontFace) => void): void;
        public addOnLoadingErrorListener(listener: (face: org.nativescript.fontmanager.FontFace, error: string) => void): void;
        public removeOnLoadingErrorListener(listener: (face: org.nativescript.fontmanager.FontFace, error: string) => void): void;
      }
      export module FontFaceSet {
        export class Companion {
          public static class: java.lang.Class<org.nativescript.fontmanager.FontFaceSet.Companion>;
          public getInstance(): org.nativescript.fontmanager.FontFaceSet;
        }
        export class Status {
          public static class: java.lang.Class<org.nativescript.fontmanager.FontFaceSet.Status>;
          public static Loading: org.nativescript.fontmanager.FontFaceSet.Status;
          public static Loaded: org.nativescript.fontmanager.FontFaceSet.Status;
          public static valueOf(value: string): org.nativescript.fontmanager.FontFaceSet.Status;
          public static values(): androidNative.Array<org.nativescript.fontmanager.FontFaceSet.Status>;
          public static getEntries(): any;
        }
      }
    }
  }
}

declare module org {
  export module nativescript {
    export module fontmanager {
      export class FontFaceStatus {
        public static class: java.lang.Class<org.nativescript.fontmanager.FontFaceStatus>;
        public static Unloaded: org.nativescript.fontmanager.FontFaceStatus;
        public static Loading: org.nativescript.fontmanager.FontFaceStatus;
        public static Loaded: org.nativescript.fontmanager.FontFaceStatus;
        public static Error: org.nativescript.fontmanager.FontFaceStatus;
        public static valueOf(value: string): org.nativescript.fontmanager.FontFaceStatus;
        public static values(): androidNative.Array<org.nativescript.fontmanager.FontFaceStatus>;
        public static getEntries(): any;
      }
    }
  }
}

declare module org {
  export module nativescript {
    export module fontmanager {
      export class FontParser {
        public static class: java.lang.Class<org.nativescript.fontmanager.FontParser>;
        public static INSTANCE: org.nativescript.fontmanager.FontParser;
        public parse(parts: string): org.nativescript.fontmanager.FontParser.Result;
      }
      export module FontParser {
        export class Result {
          public static class: java.lang.Class<org.nativescript.fontmanager.FontParser.Result>;
          public getStyle(): org.nativescript.fontmanager.FontStyle;
          public constructor(style: org.nativescript.fontmanager.FontStyle, weight: org.nativescript.fontmanager.FontWeight, sizePx: number, lineHeight: java.lang.Float, families: java.util.List<string>);
          public component3(): number;
          public component5(): java.util.List<string>;
          public getWeight(): org.nativescript.fontmanager.FontWeight;
          public component1(): org.nativescript.fontmanager.FontStyle;
          public equals(other: any): boolean;
          public component2(): org.nativescript.fontmanager.FontWeight;
          public copy(style: org.nativescript.fontmanager.FontStyle, weight: org.nativescript.fontmanager.FontWeight, sizePx: number, lineHeight: java.lang.Float, families: java.util.List<string>): org.nativescript.fontmanager.FontParser.Result;
          public toString(): string;
          public component4(): java.lang.Float;
          public getLineHeight(): java.lang.Float;
          public getFamilies(): java.util.List<string>;
          public getSizePx(): number;
          public hashCode(): number;
        }
      }
    }
  }
}

declare module org {
  export module nativescript {
    export module fontmanager {
      export abstract class FontStyle {
        public static class: java.lang.Class<org.nativescript.fontmanager.FontStyle>;
        public static NORMAL: org.nativescript.fontmanager.FontStyle.Normal;
        public static ITALIC: org.nativescript.fontmanager.FontStyle.Italic;
        public getFontStyle(): number;
        public toString(): string;
        public static oblique(angle: number): org.nativescript.fontmanager.FontStyle.Oblique;
      }
      export module FontStyle {
        export class Companion {
          public static class: java.lang.Class<org.nativescript.fontmanager.FontStyle.Companion>;
          public oblique(angle: number): org.nativescript.fontmanager.FontStyle.Oblique;
        }
        export class Italic extends org.nativescript.fontmanager.FontStyle {
          public static class: java.lang.Class<org.nativescript.fontmanager.FontStyle.Italic>;
          public static INSTANCE: org.nativescript.fontmanager.FontStyle.Italic;
        }
        export class Normal extends org.nativescript.fontmanager.FontStyle {
          public static class: java.lang.Class<org.nativescript.fontmanager.FontStyle.Normal>;
          public static INSTANCE: org.nativescript.fontmanager.FontStyle.Normal;
        }
        export class Oblique extends org.nativescript.fontmanager.FontStyle {
          public static class: java.lang.Class<org.nativescript.fontmanager.FontStyle.Oblique>;
          public constructor(angle: number);
          public getAngle(): number;
          public toString(): string;
          public constructor();
          public component1(): number;
          public equals(other: any): boolean;
          public copy(angle: number): org.nativescript.fontmanager.FontStyle.Oblique;
          public hashCode(): number;
        }
      }
    }
  }
}

declare module org {
  export module nativescript {
    export module fontmanager {
      export class FontWeight {
        public static class: java.lang.Class<org.nativescript.fontmanager.FontWeight>;
        public static Thin: org.nativescript.fontmanager.FontWeight;
        public static ExtraLight: org.nativescript.fontmanager.FontWeight;
        public static Light: org.nativescript.fontmanager.FontWeight;
        public static Normal: org.nativescript.fontmanager.FontWeight;
        public static Medium: org.nativescript.fontmanager.FontWeight;
        public static SemiBold: org.nativescript.fontmanager.FontWeight;
        public static Bold: org.nativescript.fontmanager.FontWeight;
        public static ExtraBold: org.nativescript.fontmanager.FontWeight;
        public static Black: org.nativescript.fontmanager.FontWeight;
        public static valueOf(value: string): org.nativescript.fontmanager.FontWeight;
        public getRaw(): number;
        public static values(): androidNative.Array<org.nativescript.fontmanager.FontWeight>;
        public static getEntries(): any;
        public static from(value: number): org.nativescript.fontmanager.FontWeight;
        public getWeight(): number;
      }
      export module FontWeight {
        export class Companion {
          public static class: java.lang.Class<org.nativescript.fontmanager.FontWeight.Companion>;
          public from(value: number): org.nativescript.fontmanager.FontWeight;
        }
      }
    }
  }
}

//Generics information:
