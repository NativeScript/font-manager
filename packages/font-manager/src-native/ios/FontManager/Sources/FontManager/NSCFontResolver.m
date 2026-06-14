#import "NSCFontResolver.h"
#include "NSCFontDescriptors.h"
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST
#import <UIKit/UIKit.h>
#endif

static NSDictionary<NSString *, NSString *> *NSCGenericFontFamilies(void) {
    return @{
        @"serif": @"Times New Roman",
        @"sans-serif": @"Helvetica",
        @"monospace": @"Courier",
        @"cursive": @"Snell Roundhand",
        @"fantasy": @"Papyrus",
        @"system-ui": @"San Francisco",
        @"ui-serif": @"Times New Roman",
        @"ui-sans-serif": @"San Francisco",
        @"ui-monospace": @"Menlo",
        @"ui-rounded": @"SF Rounded",
        @"emoji": @"Apple Color Emoji"
    };
}

@interface NSCFontResolver ()

@property(nonatomic, strong) NSCache *cgFontCache;
@property(nonatomic, strong) dispatch_queue_t queue;

@end

@implementation NSCFontResolver

+ (instancetype)shared {
    static NSCFontResolver *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[NSCFontResolver alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _cgFontCache = [[NSCache alloc] init];
        _queue = dispatch_queue_create("NSCFontResolver.queue",
                                       DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)resolveFontWithFamily:(NSString *)family
                          src:(NSString *)src
                   completion:(NSCFontResolverCompletion)completion {

    dispatch_async(self.queue, ^{

        NSError *error = nil;
        NSData *data = nil;
        CGFontRef font = NULL;

        NSString *resolvedFamily = [self resolveGenericFamily:family];

        font = [self systemFontForFamily:resolvedFamily];

        if (src.length > 0) {
            data = [self loadFontDataFromURL:src error:&error];

            if (!data) {
                completion(NULL, NULL, error);
                return;
            }

            font = [self registerFontFromData:data error:&error];

            if (!font) {
                completion(NULL, data, error);
                return;
            }
        }

        if (!font) {
            font = [self systemFontForFamily:resolvedFamily];
        }

        completion(font, data, nil);
    });
}

- (NSString *)resolveGenericFamily:(NSString *)family {
    NSString *mapped = NSCGenericFontFamilies()[family];
    return mapped ?: family;
}

- (CGFontRef)systemFontForFamily:(NSString *)family {

    UIFont *font = [UIFont fontWithName:family size:16.0];

    if (!font) {
        font = [UIFont systemFontOfSize:16.0];
    }

    return CGFontCreateWithFontName((__bridge CFStringRef)font.fontName);
}

- (NSData *)loadFontDataFromURL:(NSString *)src
                          error:(NSError **)error {

    NSURL *url = [NSURL URLWithString:src];

    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"FontResolver"
                                         code:1
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Invalid font URL"
            }];
        }
        return nil;
    }

    NSString *scheme = url.scheme.lowercaseString;

    if ([scheme isEqualToString:@"http"] ||
        [scheme isEqualToString:@"https"]) {

        return [NSData dataWithContentsOfURL:url];
    }

    if ([scheme isEqualToString:@"file"] ||
        [src hasPrefix:@"/"]) {

        NSString *path = url.path;
        return [NSData dataWithContentsOfFile:path];
    }

    if ([scheme isEqualToString:@"data"]) {
        return nil;
    }

    if (error) {
        *error = [NSError errorWithDomain:@"FontResolver"
                                     code:2
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Unsupported font scheme"
        }];
    }

    return nil;
}

- (CGFontRef)registerFontFromData:(NSData *)data
                            error:(NSError **)error {

    if (!data) return NULL;

    NSString *cacheKey = [NSString stringWithFormat:@"%lu",
                          (unsigned long)data.length];

    CGFontRef cached = (__bridge CGFontRef)
        [self.cgFontCache objectForKey:cacheKey];

    if (cached) {
        return cached;
    }

    CGDataProviderRef provider =
        CGDataProviderCreateWithCFData((__bridge CFDataRef)data);

    CGFontRef font = CGFontCreateWithDataProvider(provider);

    CGDataProviderRelease(provider);

    if (!font) {
        if (error) {
            *error = [NSError errorWithDomain:@"FontResolver"
                                         code:3
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Failed to create CGFont"
            }];
        }
        return NULL;
    }

    CFErrorRef ctError = NULL;

    if (!CTFontManagerRegisterGraphicsFont(font, &ctError)) {
        CFIndex code = CFErrorGetCode(ctError);
        CTFontManagerError err = (CTFontManagerError)code;

        if (err != kCTFontManagerErrorAlreadyRegistered &&
            err != kCTFontManagerErrorDuplicatedName) {

            if (error && ctError) {
                *error = CFBridgingRelease(ctError);
            }

            CFRelease(font);
            return NULL;
        }

        if (ctError) CFRelease(ctError);
    }

    [self.cgFontCache setObject:(__bridge id)font forKey:cacheKey];

    return font;
}


- (void)importFromRemoteWithURL:(NSString *)url
                           load:(BOOL)load
                      completion:(void (^)(NSArray<NSCFontFace *> * _Nullable fonts,
                                           NSError * _Nullable error))completion
{
    NSURL *nsURL = [NSURL URLWithString:url];

    if (!nsURL) {
        completion(nil, [NSError errorWithDomain:@"FontResolver"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}]);
        return;
    }

    NSURLSessionDataTask *task =
    [[NSURLSession sharedSession] dataTaskWithURL:nsURL
                                completionHandler:^(NSData *data,
                                                    NSURLResponse *response,
                                                    NSError *error)
    {
        if (error || !data) {
            completion(nil, error ?: [NSError errorWithDomain:@"FontResolver"
                                                          code:2
                                                      userInfo:@{NSLocalizedDescriptionKey: @"No data"}]);
            return;
        }

        NSString *css = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

        if (!css) {
            completion(nil, [NSError errorWithDomain:@"FontResolver"
                                                code:3
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid CSS"}]);
            return;
        }

        NSMutableArray *fonts = [NSMutableArray array];

        NSArray *rules = [NSCFontDescriptors parseFontFaceRules:css];

        for (NSDictionary *rule in rules) {

            NSString *family = rule[@"font-family"];
            NSString *srcURL = rule[@"src"];

            if (!family) continue;

            NSCFontFace *face =
                [[NSCFontFace alloc] initWithFamily:family source:srcURL];

            NSString *fontStyle = rule[@"font-style"];
            if (fontStyle) [face setFontStyle:fontStyle angle:nil];

            NSString *fontWeight = rule[@"font-weight"];
            if (fontWeight) [face setFontWeight:fontWeight];

            NSString *fontDisplay = rule[@"font-display"];
            if (fontDisplay) [face setFontDisplay:fontDisplay];

            if (load) {
                [face load:^(NSString * _Nullable error) {}];
            }

            [fonts addObject:face];
        }

        completion(fonts, nil);
    }];

    [task resume];
}

@end