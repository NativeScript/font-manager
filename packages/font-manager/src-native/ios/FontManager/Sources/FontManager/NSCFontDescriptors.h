#import <Foundation/Foundation.h>
#import "NSCFontTypes.h"
#import "NSCFontStyle.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSCFontDescriptors : NSObject

@property (nonatomic) NSCFontWeight weight;
@property (nonatomic, copy) NSString *family;
@property (nonatomic, strong) NSCFontStyle *style;
@property (nonatomic, copy) NSString *variant;
@property (nonatomic, copy) NSString *ascentOverride;
@property (nonatomic, copy) NSString *descentOverride;
@property (nonatomic) NSCFontDisplay display;
@property (nonatomic, copy) NSString *stretch;
@property (nonatomic, copy) NSString *unicodeRange;
@property (nonatomic, copy) NSString *featureSettings;
@property (nonatomic, copy) NSString *lineGapOverride;
@property (nonatomic, copy) NSString *variationSettings;
@property (nonatomic, copy) NSString *kerning;
@property (nonatomic, copy) NSString *variantLigatures;

- (instancetype)initWithFamily:(NSString *)family;

- (void)update:(NSString *)value;

- (void)setFontWeightFromString:(NSString *)value;
- (void)setFontStyleFromString:(NSString *)value;
- (void)setFontDisplayFromString:(NSString *)value;

+ (NSArray<NSDictionary *> *)parseFontFaceRules:(NSString *)css;

@end

NS_ASSUME_NONNULL_END
