#import <Foundation/Foundation.h>
#import "NSCFontTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSCFontParseResult : NSObject

@property (nonatomic, assign) NSCFontStyle style;
@property (nonatomic, assign) NSInteger weight;
@property (nonatomic, assign) NSInteger sizePx;
@property (nonatomic, strong, nullable) NSNumber *lineHeight;
@property (nonatomic, copy) NSArray<NSString *> *families;

@end

@interface NSCFontParser : NSObject

+ (nullable NSCFontParseResult *)parse:(NSString *)input;

@end

NS_ASSUME_NONNULL_END