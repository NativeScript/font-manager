#import "NSCFontFace.h"
#import "NSCFontDescriptors.h"
#import "NSCFontFaceSet.h"
#import "NSCFontResolver.h"

@interface NSCFontFace ()
@property (nonatomic, copy, nullable) NSString *localOrRemoteSource;
@property (nonatomic, copy, nullable) NSString *fontPath;
@property (nonatomic, assign) BOOL reloadPending;
@end

@implementation NSCFontFace

static dispatch_queue_t NSCFontFaceQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("NSCFontFace.queue", DISPATCH_QUEUE_SERIAL); });
    return q;
}

- (instancetype)initWithFamily:(NSString *)family {
    if (self = [super init]) {
        _fontDescriptors = [[NSCFontDescriptors alloc] initWithFamily:family];
        _status = NSCFontFaceStatusUnloaded;
        _reloadPending = NO;
    }
    return self;
}

- (instancetype)initWithFamily:(NSString *)family source:(NSString *)source {
    if (self = [self initWithFamily:family]) {
        _localOrRemoteSource = [source hasPrefix:@"/"]
            ? [@"file://" stringByAppendingString:source]
            : source;
    }
    return self;
}

- (instancetype)initWithFamily:(NSString *)family data:(NSData *)data {
    if (self = [self initWithFamily:family]) {
        _fontData = data;
    }
    return self;
}

- (instancetype)initWithFontDescriptor:(NSCFontDescriptors *)fontDescriptor {
    if (self = [super init]) {
        _fontDescriptors = fontDescriptor;
        _status = NSCFontFaceStatusUnloaded;
        _reloadPending = NO;
    }
    return self;
}

- (instancetype)initWithFontDescriptor:(NSCFontDescriptors *)fontDescriptor source:(NSString *)source {
    if (self = [self initWithFontDescriptor:fontDescriptor]) {
        _localOrRemoteSource = [source hasPrefix:@"/"]
            ? [@"file://" stringByAppendingString:source]
            : source;
    }
    return self;
}

- (instancetype)initWithFontDescriptor:(NSCFontDescriptors *)fontDescriptor data:(NSData *)data {
    if (self = [self initWithFontDescriptor:fontDescriptor]) {
        _fontData = data;
    }
    return self;
}

#pragma mark - Descriptor properties with auto-reload

- (NSString *)family { return self.fontDescriptors.family; }

- (NSCFontDisplay)display { return self.fontDescriptors.display; }
- (void)setDisplay:(NSCFontDisplay)display {
    self.fontDescriptors.display = display;
    [self _scheduleReloadIfNeeded];
}

- (NSCFontWeight)weight { return self.fontDescriptors.weight; }
- (void)setWeight:(NSCFontWeight)weight {
    self.fontDescriptors.weight = weight;
    [self _scheduleReloadIfNeeded];
}

- (NSCFontStyle)style { return self.fontDescriptors.style; }
- (void)setStyle:(NSCFontStyle)style {
    self.fontDescriptors.style = style;
    [self _scheduleReloadIfNeeded];
}

- (NSString *)variant { return self.fontDescriptors.variant; }
- (void)setVariant:(NSString *)variant {
    self.fontDescriptors.variant = variant;
    [self _scheduleReloadIfNeeded];
}

- (NSString *)stretch { return self.fontDescriptors.stretch; }
- (void)setStretch:(NSString *)stretch {
    self.fontDescriptors.stretch = stretch;
    [self _scheduleReloadIfNeeded];
}

- (NSString *)unicodeRange { return self.fontDescriptors.unicodeRange; }
- (void)setUnicodeRange:(NSString *)unicodeRange {
    self.fontDescriptors.unicodeRange = unicodeRange;
}

- (NSString *)featureSettings { return self.fontDescriptors.featureSettings; }
- (void)setFeatureSettings:(NSString *)featureSettings {
    self.fontDescriptors.featureSettings = featureSettings;
}

- (NSString *)variationSettings { return self.fontDescriptors.variationSettings; }
- (void)setVariationSettings:(NSString *)variationSettings {
    self.fontDescriptors.variationSettings = variationSettings;
}

- (NSString *)ascentOverride { return self.fontDescriptors.ascentOverride; }
- (void)setAscentOverride:(NSString *)ascentOverride {
    self.fontDescriptors.ascentOverride = ascentOverride;
}

- (NSString *)descentOverride { return self.fontDescriptors.descentOverride; }
- (void)setDescentOverride:(NSString *)descentOverride {
    self.fontDescriptors.descentOverride = descentOverride;
}

- (NSString *)lineGapOverride { return self.fontDescriptors.lineGapOverride; }
- (void)setLineGapOverride:(NSString *)lineGapOverride {
    self.fontDescriptors.lineGapOverride = lineGapOverride;
}

#pragma mark - String setters

- (void)setFontWeight:(NSString *)value {
    [self.fontDescriptors setFontWeightFromString:value];
    [self _scheduleReloadIfNeeded];
}

- (void)setFontStyle:(NSString *)value angle:(NSString *)angle {
    NSString *combined = angle.length > 0
        ? [NSString stringWithFormat:@"%@ %@", value, angle]
        : value;
    [self.fontDescriptors setFontStyleFromString:combined];
    [self _scheduleReloadIfNeeded];
}

- (void)setFontDisplay:(NSString *)value {
    [self.fontDescriptors setFontDisplayFromString:value];
    [self _scheduleReloadIfNeeded];
}

- (void)setFontVariant:(NSString *)value { self.fontDescriptors.variant = value; }
- (void)setFontStretch:(NSString *)value { self.fontDescriptors.stretch = value; [self _scheduleReloadIfNeeded]; }
- (void)setFontUnicodeRange:(NSString *)value { self.fontDescriptors.unicodeRange = value; }
- (void)setFontFeatureSettings:(NSString *)value { self.fontDescriptors.featureSettings = value; }
- (void)setFontVariationSettings:(NSString *)value { self.fontDescriptors.variationSettings = value; }
- (void)setFontAscentOverride:(NSString *)value { self.fontDescriptors.ascentOverride = value; }
- (void)setFontDescentOverride:(NSString *)value { self.fontDescriptors.descentOverride = value; }
- (void)setFontLineGapOverride:(NSString *)value { self.fontDescriptors.lineGapOverride = value; }

- (void)updateDescriptor:(NSString *)value {
    [self.fontDescriptors update:value];
    [self _scheduleReloadIfNeeded];
}

- (void)updateDescriptorWithValue:(NSString *)value {
    [self updateDescriptor:value];
}

#pragma mark - Auto-reload


- (void)addReloadListener:(void (^)(NSCFontFace *, NSString *))listener {
    @synchronized (self) { [_onReloadListeners addObject:listener]; }
}
- (void)removeOnReloadListener:(void (^)(NSCFontFace *, NSString *))listener {
    @synchronized (self) { [_onReloadListeners removeObject:listener]; }
}

- (void)removeAllReloadListeners {
    @synchronized (self) { [_onReloadListeners removeAllObjects]; }
}


- (void)_scheduleReloadIfNeeded {
    if (self.status != NSCFontFaceStatusLoaded) return;

    @synchronized (self) {
        if (self.reloadPending) return;
        self.reloadPending = YES;
    }

    self.status = NSCFontFaceStatusUnloaded;

    dispatch_async(NSCFontFaceQueue(), ^{
        @synchronized (self) { self.reloadPending = NO; }
        [self _loadInternalWithCompletion:^(NSString * _Nullable error) {
          
          NSArray *listeners;
          
          @synchronized (self) {
            if(_onReloadListeners.count > 0){
              listeners = [_onReloadListeners copy];
            }
          }
          
          for (void(^cb)(NSCFontFace *, NSString * _Nullable) in listeners) cb(self, error);
          
        }];
    });
}

#pragma mark - Load

- (void)load:(void (^)(NSString *_Nullable error))callback {
    if (self.status == NSCFontFaceStatusLoaded) {
        callback(nil);
        return;
    }
    self.status = NSCFontFaceStatusLoading;
    dispatch_async(NSCFontFaceQueue(), ^{
        [self _loadInternalWithCompletion:callback];
    });
}

- (void)loadSync:(NSString * _Nullable * _Nullable)outError {
    if (self.status == NSCFontFaceStatusLoaded) return;

    self.status = NSCFontFaceStatusLoading;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSString *loadError = nil;

    [self _loadInternalWithCompletion:^(NSString * _Nullable error) {
        loadError = error;
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (outError) *outError = loadError;
}

- (nullable NSData *)rawData {
    if (self.fontData) return self.fontData;
    if (self.fontPath) return [NSData dataWithContentsOfFile:self.fontPath];
    return nil;
}

- (void)_loadInternalWithCompletion:(void (^)(NSString * _Nullable))callback {
    NSString *family = self.fontDescriptors.family;
    NSString *src = self.localOrRemoteSource;

    if (self.fontData && src == nil) {
        NSError *error = nil;
        CGFontRef font = [[NSCFontResolver shared] registerFontFromData:self.fontData error:&error];
        if (font) {
            self.font = font;
            self.status = NSCFontFaceStatusLoaded;
            callback(nil);
        } else {
            self.status = NSCFontFaceStatusError;
            callback(error.localizedDescription ?: @"Failed to register font");
        }
        return;
    }

    [[NSCFontResolver shared]
        resolveFontWithFamily:family
                          src:src
                   completion:^(CGFontRef font, NSData *data, NSError *error) {
                       if (error) {
                           self.status = NSCFontFaceStatusError;
                           callback(error.localizedDescription);
                           return;
                       }

                       self.font = font;
                       if (data) self->_fontData = data;

                       if ([src hasPrefix:@"file://"]) {
                           self->_fontPath = [src substringFromIndex:7];
                       } else if ([src hasPrefix:@"/"]) {
                           self->_fontPath = src;
                       }

                       self.status = NSCFontFaceStatusLoaded;
                       callback(nil);
                   }];
}

#pragma mark - Class methods

+ (void)clearFontCache {
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(
        NSCachesDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"ns_fonts_cache"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:cacheDir]) {
            [fm removeItemAtPath:cacheDir error:nil];
        }
    });
}

+ (void)importFromRemote:(NSString *)url
                    load:(BOOL)load
              completion:(void(^)(NSArray<NSCFontFace *> *fonts, NSString * _Nullable error))completion {
    [[NSCFontResolver shared] importFromRemoteWithURL:url load:load
        completion:^(NSArray<NSCFontFace *> *fonts, NSError *error) {
            if (error) {
                completion(@[], error.localizedDescription);
                return;
            }
            for (NSCFontFace *face in fonts) {
                [[NSCFontFaceSet instance] add:face];
            }
            completion(fonts ?: @[], nil);
        }];
}

@end
