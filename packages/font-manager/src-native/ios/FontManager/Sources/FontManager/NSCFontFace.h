#import <Foundation/Foundation.h>
#import "NSCFontTypes.h"
#import "NSCFontDescriptors.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSCFontFace : NSObject

@property (nonatomic, assign, nullable) CGFontRef font;
@property (nonatomic, strong, readonly, nullable) NSData *fontData;
@property (nonatomic, readonly) NSString *family;
@property (nonatomic, readonly, nullable) NSString *fontPath;
@property (atomic, assign) NSCFontFaceStatus status;
@property (nonatomic, strong, readonly) NSCFontDescriptors *fontDescriptors;

// Descriptor pass-throughs (mirrors Web FontFace API)
@property (nonatomic) NSCFontDisplay display;
@property (nonatomic) NSCFontWeight weight;
@property (nonatomic, copy) NSString *style;
@property (nonatomic, copy) NSString *variant;
@property (nonatomic, copy) NSString *stretch;
@property (nonatomic, copy) NSString *unicodeRange;
@property (nonatomic, copy) NSString *featureSettings;
@property (nonatomic, copy) NSString *variationSettings;
@property (nonatomic, copy) NSString *ascentOverride;
@property (nonatomic, copy) NSString *descentOverride;
@property (nonatomic, copy) NSString *lineGapOverride;


/**
 * Called after a descriptor-triggered reload completes.
 * `error` is nil on success. Use this to notify views that the font changed.
 */
- (void)addReloadListener:(void (^)(NSCFontFace *, NSString *))listener;

- (void)removeOnReloadListener:(void (^)(NSCFontFace *, NSString *))listener;

- (void)removeAllReloadListeners;

@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFace *face, NSString * _Nullable error)> *onReloadListeners;

- (instancetype)initWithFamily:(NSString *)family;
- (instancetype)initWithFamily:(NSString *)family source:(nullable NSString *)source;
- (instancetype)initWithFamily:(NSString *)family data:(nullable NSData *)data;

- (instancetype)initWithFontDescriptor:(NSCFontDescriptors *)fontDescriptor;
- (instancetype)initWithFontDescriptor:(NSCFontDescriptors *)fontDescriptor source:(nullable NSString *)source;
- (instancetype)initWithFontDescriptor:(NSCFontDescriptors *)fontDescriptor data:(nullable NSData *)data;

- (void)load:(void(^)(NSString * _Nullable error))callback;
- (void)loadSync:(NSString * _Nullable * _Nullable)outError;

- (void)setFontWeight:(NSString *)value;
- (void)setFontStyle:(NSString *)value angle:(nullable NSString *)angle;
- (void)setFontDisplay:(NSString *)value;
- (void)setFontVariant:(NSString *)value;
- (void)setFontStretch:(NSString *)value;
- (void)setFontUnicodeRange:(NSString *)value;
- (void)setFontFeatureSettings:(NSString *)value;
- (void)setFontVariationSettings:(NSString *)value;
- (void)setFontAscentOverride:(NSString *)value;
- (void)setFontDescentOverride:(NSString *)value;
- (void)setFontLineGapOverride:(NSString *)value;

/**
 * Returns the raw font bytes. Prefers in-memory data (data-initialized or
 * remote-downloaded fonts); falls back to reading the file at `fontPath` for
 * local file fonts. Returns nil for generic system fonts.
 */
- (nullable NSData *)rawData;

- (void)updateDescriptor:(NSString *)value;
- (void)updateDescriptorWithValue:(NSString *)value;

+ (void)clearFontCache;
+ (void)importFromRemote:(NSString *)url
                    load:(BOOL)load
              completion:(void(^)(NSArray<NSCFontFace *> *fonts, NSString * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
