#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NSCFontStyleType) {
    NSCFontStyleTypeNormal  = 0,
    NSCFontStyleTypeItalic  = 1,
    NSCFontStyleTypeOblique = 2,
};

@interface NSCFontStyle : NSObject <NSCopying>

@property (nonatomic, readonly) NSCFontStyleType type;
/// Slant angle in degrees. Only meaningful when type == NSCFontStyleTypeOblique; 0 otherwise.
@property (nonatomic, readonly) NSInteger obliqueAngle;

+ (instancetype)normal;
+ (instancetype)italic;
+ (instancetype)obliqueWithAngle:(NSInteger)angle;

+ (instancetype)fromString:(NSString *)value;

- (NSString *)toString;

@end

NS_ASSUME_NONNULL_END
