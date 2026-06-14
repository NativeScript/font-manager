#import "NSCFontParser.h"
#import "NSCFontStyle.h"

@implementation NSCFontParseResult
@end

@implementation NSCFontParser

+ (NSRegularExpression *)tokenRegex {
    static NSRegularExpression *regex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:
                 @"'[^']*'|\"[^\"]*\"|[^,\\s]+|,"
                                                               options:0
                                                                 error:nil];
    });
    return regex;
}

+ (nullable NSCFontParseResult *)parse:(NSString *)input {

    NSArray<NSString *> *tokens = [self tokenize:input];

    NSCFontStyle *style = [NSCFontStyle normal];
    NSInteger weight = 400;
    NSInteger size = -1;
    NSNumber *lineHeight = nil;

    NSMutableArray<NSString *> *families = [NSMutableArray array];
    NSMutableString *familyBuffer = [NSMutableString string];

    BOOL readingFamilies = NO;

    for (NSString *token in tokens) {

        if ([token isEqualToString:@","]) {
            [self flushFamilyBuffer:familyBuffer into:families];
            continue;
        }

        if ([token isEqualToString:@"italic"]) {

            style = [NSCFontStyle italic];

        } else if ([token hasPrefix:@"oblique"]) {

            NSString *rest = [[token substringFromIndex:@"oblique".length]
                              stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSString *digits = [rest hasSuffix:@"deg"] ? [rest substringToIndex:rest.length - 3] : rest;
            NSInteger angle = digits.length > 0 ? digits.integerValue : 0;
            style = [NSCFontStyle obliqueWithAngle:angle];

        } else if ([token isEqualToString:@"bold"]) {

            weight = 700;

        } else {

            NSInteger numericWeight = token.integerValue;
            if (numericWeight >= 100 &&
                numericWeight <= 900 &&
                [token isEqualToString:[NSString stringWithFormat:@"%ld",
                                        (long)numericWeight]]) {

                weight = numericWeight;

            } else if ([token hasSuffix:@"px"]) {

                NSArray<NSString *> *parts =
                    [token componentsSeparatedByString:@"/"];

                NSString *sizePart = parts.firstObject;
                sizePart = [sizePart stringByReplacingOccurrencesOfString:@"px"
                                                               withString:@""];

                size = sizePart.integerValue;

                if (parts.count > 1) {
                    lineHeight = @([parts[1] floatValue]);
                }

                readingFamilies = YES;

            } else if (readingFamilies) {

                if (familyBuffer.length > 0) {
                    [familyBuffer appendString:@" "];
                }

                NSString *clean =
                    [[token stringByReplacingOccurrencesOfString:@"\""
                                                      withString:@""]
                     stringByReplacingOccurrencesOfString:@"'"
                                               withString:@""];

                [familyBuffer appendString:clean];
            }
        }
    }

    [self flushFamilyBuffer:familyBuffer into:families];

    if (size < 0) {
        return nil;
    }

    NSCFontParseResult *result = [NSCFontParseResult new];
    result.style = style;
    result.weight = weight;
    result.sizePx = size;
    result.lineHeight = lineHeight;
    result.families = families;

    return result;
}

+ (NSArray<NSString *> *)tokenize:(NSString *)input {

    NSMutableArray<NSString *> *tokens = [NSMutableArray array];

    NSArray<NSTextCheckingResult *> *matches =
        [[self tokenRegex] matchesInString:input
                                   options:0
                                     range:NSMakeRange(0, input.length)];

    for (NSTextCheckingResult *match in matches) {
        [tokens addObject:[input substringWithRange:match.range]];
    }

    return tokens;
}

+ (void)flushFamilyBuffer:(NSMutableString *)buffer
                     into:(NSMutableArray<NSString *> *)outFamilies {

    NSString *trimmed =
        [buffer stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];

    if (trimmed.length > 0) {
        [outFamilies addObject:trimmed];
        [buffer setString:@""];
    }
}

@end