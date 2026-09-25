#import "NSCFontFaceSet.h"
#import "NSCFontParser.h"
#import "NSCFontResolver.h"
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION
#import <UIKit/UIKit.h>
#endif

FOUNDATION_EXTERN void NSCRunOnMain(dispatch_block_t block);

@interface NSCFontFaceSet ()

@property (nonatomic, strong) NSMutableOrderedSet<NSCFontFace *> *fontCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSCFontFace *> *> *fontsByFamily;
@property (nonatomic, strong) NSHashTable<id<NSCFontFaceSetListener>> *listeners;
@property (nonatomic, assign) NSInteger pendingLoads;
@property (nonatomic, strong) NSMutableArray<void(^)(NSCFontFaceSet *)> *readyCallbacks;
@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFaceSetStatus)> *statusListeners;
@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFace *)> *loadingListeners;
@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFace *)> *loadingDoneListeners;
@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFace *, NSString *)> *loadingErrorListeners;

@end

@implementation NSCFontFaceSet

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
        _pendingLoads = 0;
        _readyCallbacks = [NSMutableArray array];
        _statusListeners = [NSMutableArray array];
        _loadingListeners = [NSMutableArray array];
        _loadingDoneListeners = [NSMutableArray array];
        _loadingErrorListeners = [NSMutableArray array];
    }
    return self;
}

- (NSCFontFaceSetStatus)status {
    @synchronized (self) {
        return _pendingLoads == 0 ? NSCFontFaceSetStatusLoaded : NSCFontFaceSetStatusLoading;
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

- (void)_beginLoad {
    NSArray *listeners;
    @synchronized (self) {
        _pendingLoads++;
        listeners = [_statusListeners copy];
    }
    NSCRunOnMain(^{
        for (void(^cb)(NSCFontFaceSetStatus) in listeners) cb(NSCFontFaceSetStatusLoading);
    });
}

- (void)_endLoad {
    NSArray *listeners, *callbacks;
    @synchronized (self) {
        if (--_pendingLoads != 0) return;
        listeners = [_statusListeners copy];
        callbacks = [_readyCallbacks copy];
        [_readyCallbacks removeAllObjects];
    }
    NSCRunOnMain(^{
        for (void(^cb)(NSCFontFaceSetStatus) in listeners) cb(NSCFontFaceSetStatusLoaded);
        for (void(^cb)(NSCFontFaceSet *) in callbacks) cb(self);
    });
}

- (void)_notifyLoadingDone:(NSCFontFace *)face {
    NSArray *listeners;
    @synchronized (self) { listeners = [_loadingDoneListeners copy]; }
    for (void(^cb)(NSCFontFace *) in listeners) cb(face);
    if (face.fontData) {
        [self _emitEvent:NSCFontFaceSetEventAdd face:face family:face.family.lowercaseString];
    }
}

- (void)_notifyLoadingError:(NSCFontFace *)face error:(NSString *)error {
    NSArray *listeners;
    @synchronized (self) { listeners = [_loadingErrorListeners copy]; }
    for (void(^cb)(NSCFontFace *, NSString *) in listeners) cb(face, error);
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
}

- (void)delete:(NSCFontFace *)font {
    @synchronized (self) {
        if (![_fontCache containsObject:font]) return;
        [_fontCache removeObject:font];
        NSString *key = font.family.lowercaseString;
        [_fontsByFamily[key] removeObject:font];
        if (_fontsByFamily[key].count == 0) [_fontsByFamily removeObjectForKey:key];
    }
    [self _emitEvent:NSCFontFaceSetEventRemove face:font family:font.family.lowercaseString];
}

- (void)clear {
    @synchronized (self) {
        [_fontCache removeAllObjects];
        [_fontsByFamily removeAllObjects];
    }
    [self _emitEvent:NSCFontFaceSetEventClear face:nil family:nil];
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

    [self _beginLoad];

    NSCFontParseResult *parsed = [NSCFontParser parse:font];
    NSArray<NSCFontFace *> *resolved = parsed ? [self _resolveFonts:parsed] : nil;

    if (resolved.count == 0) {
        NSString *error = parsed ? nil : @"Failed to parse font";
        [self _endLoad];
        if (callback) NSCRunOnMain(^{ callback(@[], error); });
        return;
    }

    // Only touched on main.
    __block NSUInteger remaining = resolved.count;
    __block NSString *firstError = nil;
    NSArray *loadingListeners;
    @synchronized (self) { loadingListeners = [_loadingListeners copy]; }

    for (NSCFontFace *face in resolved) {
        NSCRunOnMain(^{
            for (void(^cb)(NSCFontFace *) in loadingListeners) cb(face);
        });
        [face load:^(NSString * _Nullable error) {
            if (error) {
                if (!firstError) firstError = error;
                [self _notifyLoadingError:face error:error];
            } else {
                [self _notifyLoadingDone:face];
            }
            if (--remaining == 0) {
                [self _endLoad];
                if (callback) callback(resolved, firstError);
            }
        }];
    }
}

- (void)ready:(void(^)(NSCFontFaceSet *))callback {
    BOOL idle;
    @synchronized (self) {
        idle = _pendingLoads == 0;
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
