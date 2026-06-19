#import <Foundation/Foundation.h>

#if TARGET_OS_IOS || TARGET_OS_VISION
#import <UIKit/UIKit.h>
#endif

#import <CoreText/CoreText.h>
#import "NSCFontFace.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSCFontResolverResult : NSObject

@property(nonatomic, assign) CGFontRef font;
@property(nonatomic, strong, nullable) NSData *data;

@end

typedef void (^NSCFontResolverCompletion)(
    CGFontRef _Nullable font,
    NSData * _Nullable data,
    NSError * _Nullable error
);

@interface NSCFontResolver : NSObject

+ (instancetype)shared;

- (void)resolveFontWithFamily:(NSString *)family
                          src:(nullable NSString *)src
                   completion:(NSCFontResolverCompletion)completion;

- (nullable NSData *)loadFontDataFromURL:(NSString *)src error:(NSError **)error;
- (nullable CGFontRef)registerFontFromData:(NSData *)data error:(NSError **)error;
- (NSString *)resolveGenericFamily:(NSString *)family;
- (void)importFromRemoteWithURL:(NSString *)url
                          load:(BOOL)load
                     completion:(void (^)(NSArray<NSCFontFace *> * _Nullable fonts,
                                          NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
