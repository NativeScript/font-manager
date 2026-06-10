#import "NSCFontDescriptors.h"
#import "NSCFontRegex.h"

@implementation NSCFontDescriptors

- (instancetype)initWithFamily:(NSString *)family {
    self = [super init];

    if (self) {
        _weight = NSCFontWeightNormal;
        _family = [family copy];
        _style = @"normal";
        _obliqueAngle = nil;
        _variant = @"normal";
        _ascentOverride = @"normal";
        _descentOverride = @"normal";
        _display = NSCFontDisplayAuto;
        _stretch = @"normal";
        _unicodeRange = @"U+0-10FFFF";
        _featureSettings = @"normal";
        _variationSettings = @"normal";
        _lineGapOverride = @"normal";
        _kerning = @"auto";
        _variantLigatures = @"normal";
    }

    return self;
}

+ (NSArray<NSDictionary *> *)parseFontFaceRules:(NSString *)css {
    NSMutableArray *results = [NSMutableArray array];

    NSRegularExpression *blockRegex =
        [NSRegularExpression regularExpressionWithPattern:NSCFontFacePattern options:0 error:nil];

    NSRegularExpression *propRegex =
        [NSRegularExpression regularExpressionWithPattern:NSCPropertyPattern options:0 error:nil];

    // Regex to extract URL from src: url(...) format(...)
    NSRegularExpression *srcURLRegex =
        [NSRegularExpression regularExpressionWithPattern:@"url\\(([^)]+)\\)"
                                                  options:0
                                                    error:nil];

    NSArray *blocks =
        [blockRegex matchesInString:css options:0 range:NSMakeRange(0, css.length)];

    for (NSTextCheckingResult *match in blocks) {

        NSString *block =
            [css substringWithRange:[match rangeAtIndex:1]];

        NSMutableDictionary *props = [NSMutableDictionary dictionary];

        NSArray *matches =
            [propRegex matchesInString:block options:0 range:NSMakeRange(0, block.length)];

        for (NSTextCheckingResult *m in matches) {
            NSString *key = [block substringWithRange:[m rangeAtIndex:1]];
            NSString *value = [block substringWithRange:[m rangeAtIndex:2]];

            key = [[key lowercaseString] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

            // Extract URL from src property
            if ([key isEqualToString:@"src"]) {
                NSTextCheckingResult *urlMatch =
                    [srcURLRegex firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
                if (urlMatch) {
                    NSString *rawURL = [value substringWithRange:[urlMatch rangeAtIndex:1]];
                    // Strip surrounding quotes if present
                    rawURL = [rawURL stringByTrimmingCharactersInSet:
                              [NSCharacterSet characterSetWithCharactersInString:@"'\""]];
                    props[@"src"] = rawURL;
                } else {
                    props[@"src"] = value;
                }
                continue;
            }

            // Strip surrounding quotes from font-family value
            if ([key isEqualToString:@"font-family"]) {
                value = [value stringByTrimmingCharactersInSet:
                         [NSCharacterSet characterSetWithCharactersInString:@"'\""]];
            }

            props[key] = value;
        }

        [results addObject:props];
    }

    return results;
}

- (void)update:(NSString *)value {

    NSArray *values = [NSCFontDescriptors parseFontFaceRules:value];

    if (values.count == 0) {
        return;
    }

    NSDictionary *first = values.firstObject;

    NSString *weight = first[@"font-weight"];
    if (weight) [self setFontWeightFromString:weight];

    NSString *style = first[@"font-style"];
    if (style) [self setFontStyleFromString:style];

    NSString *display = first[@"font-display"];
    if (display) [self setFontDisplayFromString:display];

    NSString *variant = first[@"font-variant"];
    if (variant) _variant = variant;

    NSString *stretch = first[@"font-stretch"];
    if (stretch) _stretch = stretch;

    NSString *featureSettings = first[@"font-feature-settings"];
    if (featureSettings) _featureSettings = featureSettings;

    NSString *variationSettings = first[@"font-variation-settings"];
    if (variationSettings) _variationSettings = variationSettings;

    NSString *unicodeRange = first[@"unicode-range"];
    if (unicodeRange) _unicodeRange = unicodeRange;

    NSString *ascentOverride = first[@"ascent-override"];
    if (ascentOverride) _ascentOverride = ascentOverride;

    NSString *descentOverride = first[@"descent-override"];
    if (descentOverride) _descentOverride = descentOverride;

    NSString *lineGapOverride = first[@"line-gap-override"];
    if (lineGapOverride) _lineGapOverride = lineGapOverride;

    NSString *kerning = first[@"font-kerning"];
    if (kerning) _kerning = kerning;

    NSString *variantLigatures = first[@"font-variant-ligatures"];
    if (variantLigatures) _variantLigatures = variantLigatures;
}

- (void)setFontWeightFromString:(NSString *)value {

    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

    if ([trimmed isEqualToString:@"normal"]) {
        _weight = NSCFontWeightNormal;
        return;
    }

    if ([trimmed isEqualToString:@"bold"]) {
        _weight = NSCFontWeightBold;
        return;
    }

    NSInteger intValue = trimmed.integerValue;
    if (intValue > 0) {
        _weight = (NSCFontWeight)intValue;
    }
}

- (void)setFontStyleFromString:(NSString *)value {

    NSString *trimmed = [[value lowercaseString]
                         stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

    if ([trimmed hasPrefix:@"oblique"]) {
        _style = @"oblique";

        NSString *rest = [trimmed substringFromIndex:@"oblique".length];
        rest = [rest stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

        _obliqueAngle = rest.length > 0 ? rest : @"0deg";
        return;
    }

    if ([trimmed isEqualToString:@"italic"] || [trimmed isEqualToString:@"normal"]) {
        _style = trimmed;
        _obliqueAngle = nil;
    }
}

- (void)setFontDisplayFromString:(NSString *)value {
    NSString *trimmed = [[value lowercaseString]
                         stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

    if ([trimmed isEqualToString:@"auto"]) {
        _display = NSCFontDisplayAuto;
    } else if ([trimmed isEqualToString:@"block"]) {
        _display = NSCFontDisplayBlock;
    } else if ([trimmed isEqualToString:@"fallback"]) {
        _display = NSCFontDisplayFallback;
    } else if ([trimmed isEqualToString:@"optional"]) {
        _display = NSCFontDisplayOptional;
    } else if ([trimmed isEqualToString:@"swap"]) {
        _display = NSCFontDisplaySwap;
    }
}

@end
