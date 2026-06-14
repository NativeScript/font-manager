#import "NSCFontTypes.h"


#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST
UIFontWeight NSCUIFontWeight(NSCFontWeight weight) {
    switch (weight) {
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