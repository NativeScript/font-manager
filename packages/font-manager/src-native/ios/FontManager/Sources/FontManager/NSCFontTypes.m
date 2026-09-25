#import "NSCFontTypes.h"

NSCFontWeight NSCFontWeightFromValue(NSInteger value) {
    if (value < 200) return NSCFontWeightThin;
    if (value >= 900) return NSCFontWeightBlack;
    return (NSCFontWeight)(value / 100 * 100);
}

#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION
UIFontWeight NSCUIFontWeight(NSCFontWeight weight) {
    switch (NSCFontWeightFromValue(weight)) {
        case NSCFontWeightThin:       return UIFontWeightThin;
        case NSCFontWeightExtraLight: return UIFontWeightUltraLight;
        case NSCFontWeightLight:      return UIFontWeightLight;
        case NSCFontWeightNormal:     return UIFontWeightRegular;
        case NSCFontWeightMedium:     return UIFontWeightMedium;
        case NSCFontWeightSemiBold:   return UIFontWeightSemibold;
        case NSCFontWeightBold:       return UIFontWeightBold;
        case NSCFontWeightExtraBold:  return UIFontWeightHeavy;
        case NSCFontWeightBlack:      return UIFontWeightBlack;
    }
}
#endif
