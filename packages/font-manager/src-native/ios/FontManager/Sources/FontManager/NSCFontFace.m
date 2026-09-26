#import "NSCFontFace.h"
#import "NSCFontDescriptors.h"
#import "NSCFontFaceSet.h"
#import "NSCFontResolver.h"
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION
#import <UIKit/UIKit.h>
#endif

__attribute__((visibility("hidden")))
void NSCRunOnMain(dispatch_block_t block) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

__attribute__((visibility("hidden")))
void NSCLoadFaces(NSArray<NSCFontFace *> *faces, dispatch_block_t done) {
    dispatch_group_t group = dispatch_group_create();
    for (NSCFontFace *face in faces) {
        dispatch_group_enter(group);
        [face load:^(NSString * _Nullable error) { dispatch_group_leave(group); }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), done);
}

typedef struct {
    NSCFontWeight weight;
    BOOL italic;
} NSCFontTraits;

@interface NSCFontFace ()
@property (nonatomic, copy, nullable) NSString *localOrRemoteSource;
@end

#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION
static inline CGFloat NSCDefaultLabelFontSize(void) {
#if TARGET_OS_TV
    // tvOS POC: UIFont.labelFontSize is unavailable on tvOS; 17pt matches the iOS default.
    return 17.0;
#else
    return UIFont.labelFontSize;
#endif
}
#endif

@implementation NSCFontFace {
    CGFontRef _font;
    NSData *_fontData;
    NSString *_fontPath;
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION
    UIFont *_uiFont;
#endif
    BOOL _loadInFlight;
    NSMutableArray<void (^)(NSString *)> *_pendingCallbacks;
    NSMutableArray<void (^)(NSString *)> *_pendingWaiters;
    NSCFontTraits _wantedTraits;
    NSCFontTraits _loadedTraits;
}

- (instancetype)initWithFamily:(NSString *)family {
    return [self initWithFontDescriptor:[[NSCFontDescriptors alloc] initWithFamily:family]];
}

- (instancetype)initWithFamily:(NSString *)family source:(NSString *)source {
    return [self initWithFontDescriptor:[[NSCFontDescriptors alloc] initWithFamily:family] source:source];
}

- (instancetype)initWithFamily:(NSString *)family data:(NSData *)data {
    return [self initWithFontDescriptor:[[NSCFontDescriptors alloc] initWithFamily:family] data:data];
}

- (instancetype)initWithFontDescriptor:(NSCFontDescriptors *)fontDescriptor {
    if (self = [super init]) {
        _fontDescriptors = fontDescriptor;
        _status = NSCFontFaceStatusUnloaded;
        _onReloadListeners = [NSMutableArray array];
        _pendingCallbacks = [NSMutableArray array];
        _pendingWaiters = [NSMutableArray array];
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

- (void)dealloc {
    if (_font) CGFontRelease(_font);
}

#pragma mark - Loaded state

- (CGFontRef)font {
    CGFontRef font;
    @synchronized (self) {
        font = _font ? CGFontRetain(_font) : NULL;
    }
    return font ? (CGFontRef)CFAutorelease(font) : NULL;
}

- (void)setFont:(CGFontRef)font {
    @synchronized (self) { [self _setFontLocked:font]; }
}

- (void)_setFontLocked:(CGFontRef)font {
    if (font == _font) return;
    if (font) CGFontRetain(font);
    if (_font) CGFontRelease(_font);
    _font = font;
}

- (NSData *)fontData {
    @synchronized (self) { return _fontData; }
}

- (NSString *)fontPath {
    @synchronized (self) { return _fontPath; }
}

#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION
- (UIFont *)uiFont {
    @synchronized (self) { return _uiFont; }
}
#endif

#pragma mark - Descriptor properties with auto-reload

- (NSString *)family { return self.fontDescriptors.family; }

- (NSCFontDisplay)display { return self.fontDescriptors.display; }
- (void)setDisplay:(NSCFontDisplay)display {
    self.fontDescriptors.display = display;
    [self _descriptorsChanged];
}

- (NSCFontWeight)weight { return self.fontDescriptors.weight; }
- (void)setWeight:(NSCFontWeight)weight {
    self.fontDescriptors.weight = weight;
    [self _descriptorsChanged];
}

- (NSCFontStyle *)style { return self.fontDescriptors.style; }
- (void)setStyle:(NSCFontStyle *)style {
    self.fontDescriptors.style = style;
    [self _descriptorsChanged];
}

- (NSString *)variant { return self.fontDescriptors.variant; }
- (void)setVariant:(NSString *)variant {
    self.fontDescriptors.variant = variant;
    [self _descriptorsChanged];
}

- (NSString *)stretch { return self.fontDescriptors.stretch; }
- (void)setStretch:(NSString *)stretch {
    self.fontDescriptors.stretch = stretch;
    [self _descriptorsChanged];
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
    [self _descriptorsChanged];
}

- (void)setFontStyle:(NSString *)value angle:(NSString *)angle {
    NSString *combined = angle.length > 0
        ? [NSString stringWithFormat:@"%@ %@", value, angle]
        : value;
    [self.fontDescriptors setFontStyleFromString:combined];
    [self _descriptorsChanged];
}

- (void)setFontDisplay:(NSString *)value {
    [self.fontDescriptors setFontDisplayFromString:value];
    [self _descriptorsChanged];
}

- (void)setFontVariant:(NSString *)value { self.fontDescriptors.variant = value; }
- (void)setFontStretch:(NSString *)value { self.fontDescriptors.stretch = value; [self _descriptorsChanged]; }
- (void)setFontUnicodeRange:(NSString *)value { self.fontDescriptors.unicodeRange = value; }
- (void)setFontFeatureSettings:(NSString *)value { self.fontDescriptors.featureSettings = value; }
- (void)setFontVariationSettings:(NSString *)value { self.fontDescriptors.variationSettings = value; }
- (void)setFontAscentOverride:(NSString *)value { self.fontDescriptors.ascentOverride = value; }
- (void)setFontDescentOverride:(NSString *)value { self.fontDescriptors.descentOverride = value; }
- (void)setFontLineGapOverride:(NSString *)value { self.fontDescriptors.lineGapOverride = value; }

- (void)updateDescriptor:(NSString *)value {
    [self.fontDescriptors update:value];
    [self _descriptorsChanged];
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

- (NSCFontTraits)_requestedTraits {
    NSCFontStyleType type = self.fontDescriptors.style.type;
    return (NSCFontTraits){
        .weight = self.fontDescriptors.weight,
        .italic = type == NSCFontStyleTypeItalic || type == NSCFontStyleTypeOblique,
    };
}

/// Sourced faces ignore weight/style; they're only used for matching.
- (BOOL)_traits:(NSCFontTraits)a pickSameFontAs:(NSCFontTraits)b {
    if (_localOrRemoteSource != nil || _fontData != nil) return YES;
    return a.italic == b.italic && a.weight == b.weight;
}

/// Per spec, stays loaded; system faces swap font in place.
- (void)_descriptorsChanged {
    NSCFontTraits wanted = [self _requestedTraits];
    BOOL repick;
    @synchronized (self) {
        _wantedTraits = wanted;
        repick = self.status == NSCFontFaceStatusLoaded && ![self _traits:_loadedTraits pickSameFontAs:wanted];
    }
    if (!repick) return;

    UIFont *uiFont = [self _uiFontFromFamily:self.fontDescriptors.family traits:wanted size:NSCDefaultLabelFontSize()];
    CGFontRef font = CTFontCopyGraphicsFont((__bridge CTFontRef)uiFont, NULL);
    BOOL published = NO;
    NSArray *listeners = nil;
    @synchronized (self) {
        if (self.status == NSCFontFaceStatusLoaded && !_loadInFlight &&
            [self _traits:wanted pickSameFontAs:_wantedTraits] && ![self _traits:_loadedTraits pickSameFontAs:wanted]) {
            [self _setFontLocked:font];
            _uiFont = uiFont;
            _loadedTraits = wanted;
            published = YES;
            listeners = [_onReloadListeners copy];
        }
    }
    if (font) CGFontRelease(font);
    if (!published || listeners.count == 0) return;

    NSCRunOnMain(^{
        for (void (^listener)(NSCFontFace *, NSString * _Nullable) in listeners) listener(self, nil);
    });
}

#pragma mark - Load

- (void)load:(void (^)(NSString *_Nullable error))callback {
    [self _admitCallback:callback waiter:nil];
}

- (void)loadSync:(NSString * _Nullable * _Nullable)outError {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSString *loadError = nil;
    BOOL alreadyLoaded = [self _admitCallback:nil waiter:^(NSString * _Nullable error) {
        loadError = error;
        dispatch_semaphore_signal(done);
    }];
    if (!alreadyLoaded) dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (outError) *outError = loadError;
}

/// One load per face. `callback` runs on main, `waiter` inline. YES if already loaded.
- (BOOL)_admitCallback:(nullable void (^)(NSString * _Nullable))callback
                waiter:(nullable void (^)(NSString * _Nullable))waiter {
    NSCFontTraits wanted = [self _requestedTraits];
    BOOL alreadyLoaded = NO;
    BOOL claimed = NO;
    @synchronized (self) {
        _wantedTraits = wanted;
        if (self.status == NSCFontFaceStatusLoaded) {
            alreadyLoaded = YES;
        } else {
            if (callback) [_pendingCallbacks addObject:[callback copy]];
            if (waiter) [_pendingWaiters addObject:[waiter copy]];
            if (!_loadInFlight) {
                _loadInFlight = YES;
                self.status = NSCFontFaceStatusLoading;
                claimed = YES;
            }
        }
    }
    if (alreadyLoaded) {
        if (callback) NSCRunOnMain(^{ callback(nil); });
        return YES;
    }
    if (claimed) [self _runLoad:wanted];
    return NO;
}

- (void)_runLoad:(NSCFontTraits)traits {
    NSString *family = self.fontDescriptors.family;
    NSString *src;
    NSData *data;
    @synchronized (self) {
        src = _localOrRemoteSource;
        data = _fontData;
    }

    if (src == nil && data == nil) {
        // No I/O, so resolve inline.
        UIFont *uiFont = [self _uiFontFromFamily:family traits:traits size:NSCDefaultLabelFontSize()];
        CGFontRef font = CTFontCopyGraphicsFont((__bridge CTFontRef)uiFont, NULL);
        [self _finishWithFont:font uiFont:uiFont data:nil path:nil traits:traits error:nil];
        if (font) CGFontRelease(font);
        return;
    }

    if (src == nil) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = nil;
            CGFontRef font = [[NSCFontResolver shared] registerFontFromData:data error:&error];
            if (!font) {
                [self _finishWithFont:NULL uiFont:nil data:nil path:nil traits:traits
                                error:error.localizedDescription ?: @"Failed to register font"];
                return;
            }
            UIFont *uiFont = [self _uiFontFromCGFont:font size:NSCDefaultLabelFontSize()];
            [self _finishWithFont:font uiFont:uiFont data:nil path:nil traits:traits error:nil];
        });
        return;
    }

    [[NSCFontResolver shared]
        resolveFontWithFamily:family
                          src:src
                   completion:^(CGFontRef font, NSData *fetched, NSError *error) {
                       if (error || !font) {
                           [self _finishWithFont:NULL uiFont:nil data:nil path:nil traits:traits
                                           error:error.localizedDescription ?: @"Failed to load font"];
                           return;
                       }
                       NSString *path = [src hasPrefix:@"file://"] ? [src substringFromIndex:7] : nil;
                       UIFont *uiFont = [self _uiFontFromCGFont:font size:NSCDefaultLabelFontSize()];
                       [self _finishWithFont:font uiFont:uiFont data:fetched path:path traits:traits error:nil];
                   }];
}

- (void)_finishWithFont:(nullable CGFontRef)font
                 uiFont:(nullable UIFont *)uiFont
                   data:(nullable NSData *)data
                   path:(nullable NSString *)path
                 traits:(NSCFontTraits)traits
                  error:(nullable NSString *)error {
    NSArray *callbacks = nil;
    NSArray *waiters = nil;
    BOOL stale = NO;
    NSCFontTraits wanted;
    @synchronized (self) {
        if (!_loadInFlight) return;
        wanted = _wantedTraits;
        // Descriptors changed mid-load: resolve again.
        stale = error == nil && ![self _traits:traits pickSameFontAs:wanted];
        if (!stale) {
            if (error == nil) {
                [self _setFontLocked:font];
                _uiFont = uiFont;
                if (data) _fontData = data;
                if (path) _fontPath = path;
                _loadedTraits = traits;
            }
            _loadInFlight = NO;
            self.status = error ? NSCFontFaceStatusError : NSCFontFaceStatusLoaded;
            callbacks = [_pendingCallbacks copy];
            waiters = [_pendingWaiters copy];
            [_pendingCallbacks removeAllObjects];
            [_pendingWaiters removeAllObjects];
        }
    }

    if (stale) {
        [self _runLoad:wanted];
        return;
    }

    for (void (^waiter)(NSString * _Nullable) in waiters) waiter(error);
    if (callbacks.count > 0) {
        NSCRunOnMain(^{
            for (void (^callback)(NSString * _Nullable) in callbacks) callback(error);
        });
    }
}

- (nullable NSData *)rawData {
    NSData *data = self.fontData;
    if (data) return data;
    NSString *path = self.fontPath;
    if (path) return [NSData dataWithContentsOfFile:path];
    return nil;
}

#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION

// Keeps existing traits, so bold stays bold.
- (UIFont *)_applyItalic:(BOOL)italic toFont:(UIFont *)base size:(CGFloat)size {
    if (!italic) return base;
    UIFontDescriptorSymbolicTraits traits = base.fontDescriptor.symbolicTraits | UIFontDescriptorTraitItalic;
    UIFontDescriptor *desc = [base.fontDescriptor fontDescriptorWithSymbolicTraits:traits];
    UIFont *styled = desc ? [UIFont fontWithDescriptor:desc size:size] : nil;
    return styled ?: base;
}

// System/generic families; never nil. Memoized: every NSCFontFace instance
// pointed at the same family/traits/size (e.g. several "sans-serif" labels)
// otherwise redoes this UIFontDescriptor/UIFont resolution independently.
- (UIFont *)_uiFontFromFamily:(NSString *)family traits:(NSCFontTraits)traits size:(CGFloat)size {
    UIFontWeight w = NSCUIFontWeight(traits.weight);

    static NSCache<NSString *, UIFont *> *resolvedFontCache;
    static dispatch_once_t cacheOnce;
    dispatch_once(&cacheOnce, ^{
        resolvedFontCache = [NSCache new];
        resolvedFontCache.countLimit = 256;
    });
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%.3f|%d|%.2f", family, w, traits.italic, size];
    UIFont *cached = [resolvedFontCache objectForKey:cacheKey];
    if (cached) return cached;

    static NSDictionary<NSString *, UIFontDescriptorSystemDesign> *systemDesigns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        systemDesigns = @{
            @"system-ui": UIFontDescriptorSystemDesignDefault,
            @"ui-sans-serif": UIFontDescriptorSystemDesignDefault,
            @"ui-serif": UIFontDescriptorSystemDesignSerif,
            @"ui-monospace": UIFontDescriptorSystemDesignMonospaced,
            @"ui-rounded": UIFontDescriptorSystemDesignRounded,
        };
    });

    UIFont *base = nil;
    UIFontDescriptorSystemDesign design = systemDesigns[family.lowercaseString];
    if (design) {
        UIFont *system = [UIFont systemFontOfSize:size weight:w];
        UIFontDescriptor *desc = [system.fontDescriptor fontDescriptorWithDesign:design];
        base = desc ? [UIFont fontWithDescriptor:desc size:size] : system;
    } else {
        NSString *resolved = [[NSCFontResolver shared] resolveGenericFamily:family];
        UIFontDescriptor *desc = [UIFontDescriptor fontDescriptorWithFontAttributes:@{
            UIFontDescriptorFamilyAttribute: resolved,
            UIFontDescriptorTraitsAttribute: @{ UIFontWeightTrait: @(w) }
        }];
        base = desc ? [UIFont fontWithDescriptor:desc size:size] : nil;
        if (!base) {
            base = [UIFont fontWithName:resolved size:size];
        }
    }
    if (!base) {
        base = [UIFont systemFontOfSize:size weight:w];
    }
    UIFont *result = [self _applyItalic:traits.italic toFont:base size:size];
    [resolvedFontCache setObject:result forKey:cacheKey];
    return result;
}

// Custom fonts, by PostScript name.
- (nullable UIFont *)_uiFontFromCGFont:(CGFontRef)cgFont size:(CGFloat)size {
    CFStringRef psRef = CGFontCopyPostScriptName(cgFont);
    if (!psRef) return nil;
    NSString *psName = (__bridge_transfer NSString *)psRef;
    return [UIFont fontWithName:psName size:size];
}

- (nullable UIFont *)uiFontWithSize:(CGFloat)size {
    return [self.uiFont fontWithSize:size];
}

#endif

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
    [[NSCFontResolver shared] importFromRemoteWithURL:url load:NO
        completion:^(NSArray<NSCFontFace *> *fonts, NSError *error) {
            if (error) {
                NSCRunOnMain(^{ completion(@[], error.localizedDescription); });
                return;
            }
            NSArray<NSCFontFace *> *faces = fonts ?: @[];
            for (NSCFontFace *face in faces) {
                [[NSCFontFaceSet instance] add:face];
            }
            if (!load || faces.count == 0) {
                NSCRunOnMain(^{ completion(faces, nil); });
                return;
            }
            NSCLoadFaces(faces, ^{ completion(faces, nil); });
        }];
}

@end
