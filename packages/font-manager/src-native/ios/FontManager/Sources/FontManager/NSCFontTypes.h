#import <Foundation/Foundation.h>
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST
#import <UIKit/UIKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NSCFontDisplay) {
    NSCFontDisplayAuto = 0,
    NSCFontDisplayBlock = 1,
    NSCFontDisplayFallback = 2,
    NSCFontDisplayOptional = 3,
    NSCFontDisplaySwap = 4
};

typedef NS_ENUM(NSInteger, NSCFontWeight) {
    NSCFontWeightThin = 100,
    NSCFontWeightExtraLight = 200,
    NSCFontWeightLight = 300,
    NSCFontWeightNormal = 400,
    NSCFontWeightMedium = 500,
    NSCFontWeightSemiBold = 600,
    NSCFontWeightBold = 700,
    NSCFontWeightExtraBold = 800,
    NSCFontWeightBlack = 900
};

typedef NS_ENUM(NSInteger, NSCFontFaceStatus) {
    NSCFontFaceStatusUnloaded = 0,
    NSCFontFaceStatusLoading = 1,
    NSCFontFaceStatusLoaded = 2,
    NSCFontFaceStatusError = 3
};

typedef NS_ENUM(NSInteger, NSCFontStyle) {
    NSCFontStyleNormal  = 0,
    NSCFontStyleItalic  = 1,
    NSCFontStyleOblique = 2,
};

#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST
FOUNDATION_EXPORT UIFontWeight NSCUIFontWeight(NSCFontWeight weight);
#endif
FOUNDATION_EXPORT NSCFontStyle NSCFontStyleFromString(NSString *value);
FOUNDATION_EXPORT NSString    *NSCFontStyleToString(NSCFontStyle style);

NS_ASSUME_NONNULL_END