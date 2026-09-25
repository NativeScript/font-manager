#import "NSCFontStyle.h"

@interface NSCFontStyle ()
@property (nonatomic, readwrite) NSCFontStyleType type;
@property (nonatomic, readwrite) NSInteger obliqueAngle;
@end

@implementation NSCFontStyle

+ (instancetype)normal {
    static NSCFontStyle *instance;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ instance = [[self alloc] initWithType:NSCFontStyleTypeNormal angle:0]; });
    return instance;
}

+ (instancetype)italic {
    static NSCFontStyle *instance;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ instance = [[self alloc] initWithType:NSCFontStyleTypeItalic angle:0]; });
    return instance;
}

+ (instancetype)obliqueWithAngle:(NSInteger)angle {
    return [[self alloc] initWithType:NSCFontStyleTypeOblique angle:angle];
}

+ (instancetype)fromString:(NSString *)value {
    NSString *trimmed = [value.lowercaseString
                         stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

    if ([trimmed isEqualToString:@"italic"]) return [self italic];

    if ([trimmed hasPrefix:@"oblique"]) {
        NSString *rest = [[trimmed substringFromIndex:@"oblique".length]
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

        NSString *digits = [rest hasSuffix:@"deg"]
            ? [rest substringToIndex:rest.length - 3]
            : rest;
        NSInteger angle = digits.length > 0 ? digits.integerValue : 0;
        return [self obliqueWithAngle:angle];
    }

    return [self normal];
}

- (instancetype)initWithType:(NSCFontStyleType)type angle:(NSInteger)angle {
    if (self = [super init]) {
        _type = type;
        _obliqueAngle = angle;
    }
    return self;
}

- (NSString *)toString {
    switch (_type) {
        case NSCFontStyleTypeItalic:  return @"italic";
        case NSCFontStyleTypeOblique:
            return _obliqueAngle == 0
                ? @"oblique"
                : [NSString stringWithFormat:@"oblique %ldeg", (long)_obliqueAngle];
        case NSCFontStyleTypeNormal:  return @"normal";
    }
}

- (id)copyWithZone:(nullable NSZone *)zone {
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[NSCFontStyle class]]) return NO;
    NSCFontStyle *other = object;
    return _type == other.type && _obliqueAngle == other.obliqueAngle;
}

- (NSUInteger)hash {
    return (NSUInteger)_type ^ (NSUInteger)(_obliqueAngle << 4);
}

- (NSString *)description {
    return [self toString];
}

@end
