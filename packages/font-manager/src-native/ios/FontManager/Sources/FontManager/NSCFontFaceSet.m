#import "NSCFontFaceSet.h"
#import "NSCFontParser.h"
#import "NSCFontResolver.h"
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION
#import <UIKit/UIKit.h>
#endif

FOUNDATION_EXTERN void NSCRunOnMain(dispatch_block_t block);

@interface NSCFontFaceSet (NSCFontFaceLoading)
+ (void)_faceDidStartLoading:(NSCFontFace *)face;
+ (void)_faceDidSettle:(NSCFontFace *)face error:(nullable NSString *)error;
@end

@interface NSCFontFaceSet ()

@property (nonatomic, strong) NSMutableOrderedSet<NSCFontFace *> *fontCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSCFontFace *> *> *fontsByFamily;
@property (nonatomic, strong) NSHashTable<id<NSCFontFaceSetListener>> *listeners;
@property (nonatomic, strong) NSMutableArray<NSCFontFace *> *loadingFaces;
@property (nonatomic, strong) NSMutableArray<NSCFontFace *> *loadedFaces;
@property (nonatomic, strong) NSMutableArray<NSCFontFace *> *failedFaces;
@property (nonatomic, copy, nullable) NSString *lastError;
@property (nonatomic, strong) NSMutableArray<void(^)(NSCFontFaceSet *)> *readyCallbacks;
@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFaceSetStatus)> *statusListeners;
@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFace *)> *loadingListeners;
@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFace *)> *loadingDoneListeners;
@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFace *, NSString *)> *loadingErrorListeners;
@property (nonatomic, strong) NSMutableArray<void (^)(NSArray<NSCFontFace *> *)> *loadingDoneFacesListeners;
@property (nonatomic, strong) NSMutableArray<void (^)(NSArray<NSCFontFace *> *, NSString *)> *loadingErrorFacesListeners;
@property (nonatomic, strong) NSMutableArray<void (^)(void)> *changedListeners;

@end

@implementation NSCFontFaceSet

static NSHashTable<NSCFontFaceSet *> *NSCAllFontFaceSets(void) {
    static NSHashTable *sets;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ sets = [NSHashTable weakObjectsHashTable]; });
    return sets;
}

+ (instancetype)instance {
    static NSCFontFaceSet *sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[NSCFontFaceSet alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _fontCache = [NSMutableOrderedSet orderedSet];
        _fontsByFamily = [NSMutableDictionary dictionary];
        _listeners = [NSHashTable weakObjectsHashTable];
        _loadingFaces = [NSMutableArray array];
        _loadedFaces = [NSMutableArray array];
        _failedFaces = [NSMutableArray array];
        _readyCallbacks = [NSMutableArray array];
        _statusListeners = [NSMutableArray array];
        _loadingListeners = [NSMutableArray array];
        _loadingDoneListeners = [NSMutableArray array];
        _loadingErrorListeners = [NSMutableArray array];
        _loadingDoneFacesListeners = [NSMutableArray array];
        _loadingErrorFacesListeners = [NSMutableArray array];
        _changedListeners = [NSMutableArray array];
        NSHashTable *sets = NSCAllFontFaceSets();
        @synchronized (sets) { [sets addObject:self]; }
    }
    return self;
}

- (NSCFontFaceSetStatus)status {
    @synchronized (self) {
        return _loadingFaces.count == 0 ? NSCFontFaceSetStatusLoaded : NSCFontFaceSetStatusLoading;
    }
}

#pragma mark - Internal events

- (void)_emitEvent:(NSCFontFaceSetEventType)event face:(NSCFontFace *)face family:(NSString *)family {
    NSArray *listeners;
    @synchronized (self) { listeners = [self.listeners allObjects]; }
    for (id<NSCFontFaceSetListener> listener in listeners) {
        if ([listener respondsToSelector:@selector(fontFaceSetDidEmitEvent:face:family:)]) {
            [listener fontFaceSetDidEmitEvent:event face:face family:family];
        }
    }
}

- (void)addOnStatusListener:(void (^)(NSCFontFaceSetStatus))listener {
    @synchronized (self) { [_statusListeners addObject:listener]; }
}
- (void)removeOnStatusListener:(void (^)(NSCFontFaceSetStatus))listener {
    @synchronized (self) { [_statusListeners removeObject:listener]; }
}

- (void)addOnLoadingListener:(void (^)(NSCFontFace *))listener {
    @synchronized (self) { [_loadingListeners addObject:listener]; }
}
- (void)removeOnLoadingListener:(void (^)(NSCFontFace *))listener {
    @synchronized (self) { [_loadingListeners removeObject:listener]; }
}

- (void)addOnLoadingDoneListener:(void (^)(NSCFontFace *))listener {
    @synchronized (self) { [_loadingDoneListeners addObject:listener]; }
}
- (void)removeOnLoadingDoneListener:(void (^)(NSCFontFace *))listener {
    @synchronized (self) { [_loadingDoneListeners removeObject:listener]; }
}

- (void)addOnLoadingErrorListener:(void (^)(NSCFontFace *, NSString *))listener {
    @synchronized (self) { [_loadingErrorListeners addObject:listener]; }
}
- (void)removeOnLoadingErrorListener:(void (^)(NSCFontFace *, NSString *))listener {
    @synchronized (self) { [_loadingErrorListeners removeObject:listener]; }
}

- (void)addOnLoadingDoneFacesListener:(void (^)(NSArray<NSCFontFace *> *))listener {
    @synchronized (self) { [_loadingDoneFacesListeners addObject:listener]; }
}
- (void)removeOnLoadingDoneFacesListener:(void (^)(NSArray<NSCFontFace *> *))listener {
    @synchronized (self) { [_loadingDoneFacesListeners removeObject:listener]; }
}

- (void)addOnLoadingErrorFacesListener:(void (^)(NSArray<NSCFontFace *> *, NSString *))listener {
    @synchronized (self) { [_loadingErrorFacesListeners addObject:listener]; }
}
- (void)removeOnLoadingErrorFacesListener:(void (^)(NSArray<NSCFontFace *> *, NSString *))listener {
    @synchronized (self) { [_loadingErrorFacesListeners removeObject:listener]; }
}

- (void)addOnChangedListener:(void (^)(void))listener {
    @synchronized (self) { [_changedListeners addObject:listener]; }
}
- (void)removeOnChangedListener:(void (^)(void))listener {
    @synchronized (self) { [_changedListeners removeObject:listener]; }
}

#pragma mark - Loading periods

- (void)_faceDidStartLoading:(NSCFontFace *)face {
    NSArray *statusListeners, *loadingListeners;
    @synchronized (self) {
        if (![_fontCache containsObject:face] || face.status != NSCFontFaceStatusLoading ||
            [_loadingFaces containsObject:face]) return;
        BOOL started = _loadingFaces.count == 0;
        [_loadingFaces addObject:face];
        if (!started) return;
        statusListeners = [_statusListeners copy];
        loadingListeners = [_loadingListeners copy];
    }
    NSCRunOnMain(^{
        for (void(^cb)(NSCFontFaceSetStatus) in statusListeners) cb(NSCFontFaceSetStatusLoading);
        for (void(^cb)(NSCFontFace *) in loadingListeners) cb(face);
    });
}

- (void)_faceDidSettle:(NSCFontFace *)face error:(nullable NSString *)error {
    BOOL member;
    BOOL ended = NO;
    @synchronized (self) {
        member = [_fontCache containsObject:face];
        if ([_loadingFaces containsObject:face]) {
            [_loadingFaces removeObject:face];
            if (error) {
                [_failedFaces addObject:face];
                _lastError = error;
            } else {
                [_loadedFaces addObject:face];
            }
            ended = _loadingFaces.count == 0;
        }
    }
    if (member) [self _notifyChanged];
    if (ended) [self _endPeriod];
}

- (void)_endPeriod {
    NSArray *loaded, *failed, *callbacks, *status, *done, *doneFaces, *errors, *errorFaces;
    NSString *error;
    @synchronized (self) {
        if (_loadingFaces.count != 0) return;
        loaded = [_loadedFaces copy];
        failed = [_failedFaces copy];
        error = _lastError;
        [_loadedFaces removeAllObjects];
        [_failedFaces removeAllObjects];
        _lastError = nil;
        callbacks = [_readyCallbacks copy];
        [_readyCallbacks removeAllObjects];
        status = [_statusListeners copy];
        done = [_loadingDoneListeners copy];
        doneFaces = [_loadingDoneFacesListeners copy];
        errors = [_loadingErrorListeners copy];
        errorFaces = [_loadingErrorFacesListeners copy];
    }
    for (NSCFontFace *face in loaded) {
        if (face.fontData) [self _emitEvent:NSCFontFaceSetEventAdd face:face family:face.family.lowercaseString];
    }
    NSCRunOnMain(^{
        for (void(^cb)(NSCFontFaceSetStatus) in status) cb(NSCFontFaceSetStatusLoaded);
        for (NSCFontFace *face in loaded) {
            for (void(^cb)(NSCFontFace *) in done) cb(face);
        }
        for (void(^cb)(NSArray<NSCFontFace *> *) in doneFaces) cb(loaded);
        if (failed.count > 0) {
            for (NSCFontFace *face in failed) {
                for (void(^cb)(NSCFontFace *, NSString *) in errors) cb(face, error ?: @"");
            }
            for (void(^cb)(NSArray<NSCFontFace *> *, NSString *) in errorFaces) cb(failed, error);
        }
        for (void(^cb)(NSCFontFaceSet *) in callbacks) cb(self);
    });
}

- (void)_notifyChanged {
    NSArray *listeners;
    @synchronized (self) { listeners = [_changedListeners copy]; }
    if (listeners.count == 0) return;
    NSCRunOnMain(^{
        for (void(^cb)(void) in listeners) cb();
    });
}

#pragma mark - Collection

- (void)add:(NSCFontFace *)font {
    @synchronized (self) {
        if ([_fontCache containsObject:font]) return;
        [_fontCache addObject:font];
        NSString *key = font.family.lowercaseString;
        NSMutableArray *faces = _fontsByFamily[key];
        if (!faces) _fontsByFamily[key] = faces = [NSMutableArray array];
        [faces addObject:font];
    }

    if (font.fontData) {
        [self _emitEvent:NSCFontFaceSetEventAdd face:font family:font.family.lowercaseString];
    }
    [self _notifyChanged];
    if (font.status == NSCFontFaceStatusLoading) [self _faceDidStartLoading:font];
}

- (void)delete:(NSCFontFace *)font {
    BOOL ended = NO;
    @synchronized (self) {
        if (![_fontCache containsObject:font]) return;
        [_fontCache removeObject:font];
        NSString *key = font.family.lowercaseString;
        [_fontsByFamily[key] removeObject:font];
        if (_fontsByFamily[key].count == 0) [_fontsByFamily removeObjectForKey:key];
        if ([_loadingFaces containsObject:font]) {
            [_loadingFaces removeObject:font];
            ended = _loadingFaces.count == 0;
        }
    }
    [self _emitEvent:NSCFontFaceSetEventRemove face:font family:font.family.lowercaseString];
    [self _notifyChanged];
    if (ended) [self _endPeriod];
}

- (void)clear {
    BOOL ended = NO;
    @synchronized (self) {
        if (_fontCache.count == 0) return;
        [_fontCache removeAllObjects];
        [_fontsByFamily removeAllObjects];
        if (_loadingFaces.count > 0) {
            [_loadingFaces removeAllObjects];
            ended = YES;
        }
    }
    [self _emitEvent:NSCFontFaceSetEventClear face:nil family:nil];
    [self _notifyChanged];
    if (ended) [self _endPeriod];
}

- (BOOL)has:(NSCFontFace *)font {
    @synchronized (self) {
        return [_fontCache containsObject:font];
    }
}

#pragma mark - Resolution

- (BOOL)_isGeneric:(NSString *)family {
    NSString *f = family.lowercaseString;
    return [@[@"serif", @"sans-serif", @"monospace", @"cursive", @"fantasy",
              @"system-ui", @"ui-serif", @"ui-sans-serif", @"ui-monospace",
              @"ui-rounded", @"math", @"emoji", @"fangsong"] containsObject:f];
}

- (NSArray<NSCFontFace *> *)_resolveFonts:(NSCFontParseResult *)parsed {
    for (NSString *family in parsed.families) {
        NSString *key = family.lowercaseString;
        NSArray *candidates;
        @synchronized (self) { candidates = [_fontsByFamily[key] copy]; }

        if (!candidates.count) {
            if ([self _isGeneric:family]) return @[];
            continue;
        }

        NSCFontFace *best = nil;
        NSInteger bestScore = NSIntegerMax;
        for (NSCFontFace *face in candidates) {
            NSInteger score =
                labs(face.fontDescriptors.weight - parsed.weight) +
                (face.fontDescriptors.style.type == parsed.style.type ? 0 : 1000);
            if (score < bestScore) { bestScore = score; best = face; }
        }
        if (best) return @[best];
    }
    return @[];
}

- (BOOL)check:(NSString *)font text:(NSString *)text {
    NSCFontParseResult *parsed = [NSCFontParser parse:font];
    if (!parsed) return NO;
    for (NSCFontFace *face in [self _resolveFonts:parsed]) {
        if (face.status != NSCFontFaceStatusLoaded) return NO;
    }
    return YES;
}

- (void)load:(NSString *)font
        text:(NSString *)text
    callback:(nullable void(^)(NSArray<NSCFontFace *> *, NSString * _Nullable))callback {

    NSCFontParseResult *parsed = [NSCFontParser parse:font];
    NSArray<NSCFontFace *> *resolved = parsed ? [self _resolveFonts:parsed] : nil;

    if (resolved.count == 0) {
        NSString *error = parsed ? nil : @"Failed to parse font";
        if (callback) NSCRunOnMain(^{ callback(@[], error); });
        return;
    }

    __block NSUInteger remaining = resolved.count;
    __block NSString *firstError = nil;
    for (NSCFontFace *face in resolved) {
        [face load:^(NSString * _Nullable error) {
            if (error && !firstError) firstError = error;
            if (--remaining == 0 && callback) callback(resolved, firstError);
        }];
    }
}

- (void)ready:(void(^)(NSCFontFaceSet *))callback {
    BOOL idle;
    @synchronized (self) {
        idle = _loadingFaces.count == 0;
        if (!idle) [_readyCallbacks addObject:[callback copy]];
    }
    if (idle) NSCRunOnMain(^{ callback(self); });
}

#pragma mark - Enumeration

- (NSEnumerator *)iter { return [[self array] objectEnumerator]; }
- (NSArray<NSCFontFace *> *)array {
    @synchronized (self) { return [_fontCache.array copy]; }
}
- (NSInteger)size {
    @synchronized (self) { return (NSInteger)_fontCache.count; }
}
- (void)forEach:(void(^)(NSCFontFace *))block {
    for (NSCFontFace *face in [self array]) block(face);
}

@end

@implementation NSCFontFaceSet (NSCFontFaceLoading)

+ (NSArray<NSCFontFaceSet *> *)_allSets {
    NSHashTable *sets = NSCAllFontFaceSets();
    @synchronized (sets) { return [sets allObjects]; }
}

+ (void)_faceDidStartLoading:(NSCFontFace *)face {
    for (NSCFontFaceSet *set in [self _allSets]) [set _faceDidStartLoading:face];
}

+ (void)_faceDidSettle:(NSCFontFace *)face error:(nullable NSString *)error {
    for (NSCFontFaceSet *set in [self _allSets]) [set _faceDidSettle:face error:error];
}

@end
