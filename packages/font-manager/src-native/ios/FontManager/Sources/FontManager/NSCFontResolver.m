#import "NSCFontResolver.h"
#include "NSCFontDescriptors.h"
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION
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

static const NSTimeInterval NSCFontRequestTimeout = 15;

FOUNDATION_EXTERN void NSCLoadFaces(NSArray<NSCFontFace *> *faces, dispatch_block_t done);

static NSError *NSCFontResolverError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"FontResolver"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL NSCIsRemoteSource(NSString *src) {
    NSString *scheme = [NSURL URLWithString:src].scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

@interface NSCFontResolver ()

@property(nonatomic, strong) NSCache *cgFontCache;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) NSURLSession *session;

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
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = NSCFontRequestTimeout;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)resolveFontWithFamily:(NSString *)family
                          src:(NSString *)src
                   completion:(NSCFontResolverCompletion)completion {

    if (src.length == 0) {
        dispatch_async(self.queue, ^{
            completion([self systemFontForFamily:[self resolveGenericFamily:family]], nil, nil);
        });
        return;
    }

    [self fetchFontData:src completion:^(NSData *data, NSError *error) {
        if (!data) {
            completion(NULL, nil, error);
            return;
        }
        NSError *registerError = nil;
        CGFontRef font = [self registerFontFromData:data error:&registerError];
        if (!font) {
            completion(NULL, data, registerError ?: NSCFontResolverError(3, @"Failed to create CGFont"));
            return;
        }
        completion(font, data, nil);
    }];
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

    return (CGFontRef)CFAutorelease(CTFontCopyGraphicsFont((__bridge CTFontRef)font, NULL));
}

- (void)fetchFontData:(NSString *)src completion:(void (^)(NSData * _Nullable, NSError * _Nullable))completion {
    if (NSCIsRemoteSource(src)) {
        [self downloadFontData:src completion:completion];
        return;
    }
    dispatch_async(self.queue, ^{
        NSError *error = nil;
        NSData *data = [self readLocalFontData:src error:&error];
        completion(data, error);
    });
}

- (void)downloadFontData:(NSString *)src completion:(void (^)(NSData * _Nullable, NSError * _Nullable))completion {
    NSURL *url = [NSURL URLWithString:src];
    [[self.session dataTaskWithURL:url
                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSError *failure = error ?: [self validateDownload:data response:response src:src];
        completion(failure ? nil : data, failure);
    }] resume];
}

- (nullable NSError *)validateDownload:(NSData *)data response:(NSURLResponse *)response src:(NSString *)src {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode < 200 || http.statusCode >= 300) {
            return NSCFontResolverError(4, [NSString stringWithFormat:@"Download of %@ failed with HTTP %ld",
                                            src, (long)http.statusCode]);
        }
        // Encoded responses announce the encoded length.
        NSString *encoding = [http valueForHTTPHeaderField:@"Content-Encoding"];
        BOOL identity = encoding.length == 0 || [encoding caseInsensitiveCompare:@"identity"] == NSOrderedSame;
        long long expected = response.expectedContentLength;
        if (identity && expected >= 0 && (long long)data.length != expected) {
            return NSCFontResolverError(5, [NSString stringWithFormat:@"Download of %@ ended after %lu of %lld bytes",
                                            src, (unsigned long)data.length, expected]);
        }
    }
    if (data.length == 0) {
        return NSCFontResolverError(6, [NSString stringWithFormat:@"Download of %@ was empty", src]);
    }
    return nil;
}

- (nullable NSData *)readLocalFontData:(NSString *)src error:(NSError **)error {
    NSString *path = nil;
    if ([src hasPrefix:@"file://"]) {
        path = [src substringFromIndex:7];
    } else if ([src hasPrefix:@"/"]) {
        path = src;
    }

    if (!path) {
        if (error) *error = NSCFontResolverError(2, @"Unsupported font scheme");
        return nil;
    }

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&readError];
    if (!data) {
        NSString *decoded = path.stringByRemovingPercentEncoding;
        if (decoded && ![decoded isEqualToString:path]) {
            data = [NSData dataWithContentsOfFile:decoded options:0 error:nil];
        }
    }
    if (!data && error) *error = readError;
    return data;
}

- (NSData *)loadFontDataFromURL:(NSString *)src
                          error:(NSError **)error {

    if (!NSCIsRemoteSource(src)) {
        return [self readLocalFontData:src error:error];
    }

    __block NSData *result = nil;
    __block NSError *failure = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [self downloadFontData:src completion:^(NSData *data, NSError *downloadError) {
        result = data;
        failure = downloadError;
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (!result && error) *error = failure;
    return result;
}

- (CGFontRef)registerFontFromData:(NSData *)data
                            error:(NSError **)error {

    if (!data) return NULL;

    // NSData compares by content.
    NSData *cacheKey = [data copy];

    id cached = [self.cgFontCache objectForKey:cacheKey];

    if (cached) {
        return (CGFontRef)CFAutorelease(CFRetain((__bridge CFTypeRef)cached));
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

    return (CGFontRef)CFAutorelease(font);
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
    [self.session dataTaskWithURL:nsURL
                completionHandler:^(NSData *data,
                                    NSURLResponse *response,
                                    NSError *error)
    {
        NSError *failure = error ?: [self validateDownload:data response:response src:url];
        if (failure) {
            completion(nil, failure);
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

            [fonts addObject:face];
        }

        if (!load) {
            completion(fonts, nil);
            return;
        }
        NSCLoadFaces(fonts, ^{ completion(fonts, nil); });
    }];

    [task resume];
}

@end
