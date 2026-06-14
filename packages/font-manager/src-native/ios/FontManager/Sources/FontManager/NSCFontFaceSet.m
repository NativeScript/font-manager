#import "NSCFontFaceSet.h"
#import "NSCFontParser.h"
#import "NSCFontResolver.h"
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST
#import <UIKit/UIKit.h>
#endif

@interface NSCFontFaceSet ()

@property (nonatomic, strong) NSMutableSet<NSCFontFace *> *fontCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSCFontFace *> *> *fontsByFamily;
@property (nonatomic, strong) dispatch_queue_t loaderQueue;
@property (nonatomic, strong) NSHashTable<id<NSCFontFaceSetListener>> *listeners;
@property (nonatomic, assign) NSInteger pendingLoads;
@property (nonatomic, strong) NSMutableArray<void(^)(NSCFontFaceSet *)> *readyCallbacks;
@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFaceSetStatus)> *statusListeners;
@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFace *)> *loadingListeners;
@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFace *)> *loadingDoneListeners;
@property (nonatomic, strong) NSMutableArray<void (^)(NSCFontFace *, NSString *)> *loadingErrorListeners;
@property (nonatomic, strong) NSMapTable<NSCFontFace *, id> *reloadListenersByFace;

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
        _fontCache = [NSMutableSet set];
        _fontsByFamily = [NSMutableDictionary dictionary];
        _loaderQueue = dispatch_queue_create("NSCFontFaceSet.Loader", DISPATCH_QUEUE_SERIAL);
        _status = NSCFontFaceSetStatusLoaded;
        _listeners = [NSHashTable weakObjectsHashTable];
        _pendingLoads = 0;
        _readyCallbacks = [NSMutableArray array];
        _statusListeners = [NSMutableArray array];
        _loadingListeners = [NSMutableArray array];
        _loadingDoneListeners = [NSMutableArray array];
        _loadingErrorListeners = [NSMutableArray array];
        _reloadListenersByFace = [NSMapTable strongToStrongObjectsMapTable];
    }
    return self;
}

#pragma mark - Internal events

- (void)_emitEvent:(NSCFontFaceSetEventType)event face:(NSCFontFace *)face family:(NSString *)family {
    for (id<NSCFontFaceSetListener> listener in self.listeners) {
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

- (void)_beginLoad:(NSCFontFace *)face {
    @synchronized (self) { _pendingLoads++; }
    self.status = NSCFontFaceSetStatusLoading;
    NSArray *sl, *ll;
    @synchronized (self) { sl = [_statusListeners copy]; ll = [_loadingListeners copy]; }
    for (void(^cb)(NSCFontFaceSetStatus) in sl) cb(NSCFontFaceSetStatusLoading);
    for (void(^cb)(NSCFontFace *) in ll) cb(face);
}

- (void)_endLoadSuccess:(NSCFontFace *)face {
    NSArray *dl;
    @synchronized (self) { dl = [_loadingDoneListeners copy]; }
    for (void(^cb)(NSCFontFace *) in dl) cb(face);
    [self _decrementPending];
}

- (void)_endLoadError:(NSCFontFace *)face error:(NSString *)error {
    NSArray *el;
    @synchronized (self) { el = [_loadingErrorListeners copy]; }
    for (void(^cb)(NSCFontFace *, NSString *) in el) cb(face, error);
    [self _decrementPending];
}

- (void)_decrementPending {
    NSInteger remaining;
    @synchronized (self) { remaining = --_pendingLoads; }
    if (remaining <= 0) {
        self.status = NSCFontFaceSetStatusLoaded;
        NSArray *sl;
        @synchronized (self) { sl = [_statusListeners copy]; }
        for (void(^cb)(NSCFontFaceSetStatus) in sl) cb(NSCFontFaceSetStatusLoaded);
        [self _flushReadyCallbacks];
    }
}

- (void)_flushReadyCallbacks {
    NSArray *callbacks;
    @synchronized (self) {
        callbacks = [_readyCallbacks copy];
        [_readyCallbacks removeAllObjects];
    }
    for (void(^cb)(NSCFontFaceSet *) in callbacks) {
        cb(self);
    }
}

#pragma mark - Collection

- (void)add:(NSCFontFace *)font {
    @synchronized (self) {
        NSString *key = font.family.lowercaseString;
        if (_fontsByFamily[key].count > 0) {
            return;
        }
      
        [_fontCache addObject:font];
        if (!_fontsByFamily[key]) _fontsByFamily[key] = [NSMutableArray array];
        [_fontsByFamily[key] addObject:font];
      
      
        __weak typeof(self) weakSelf = self;
        void (^reloadListener)(NSCFontFace *, NSString *) = ^(NSCFontFace *reloadedFace, NSString *error) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error) {
                [strongSelf _endLoadError:reloadedFace error:error];
            } else {
                [strongSelf _endLoadSuccess:reloadedFace];
                if (reloadedFace.fontData) {
                    [strongSelf _emitEvent:NSCFontFaceSetEventAdd
                                      face:reloadedFace
                                    family:reloadedFace.family.lowercaseString];
                }
            }
        };
        [_reloadListenersByFace setObject:reloadListener forKey:font];
        [font addReloadListener:reloadListener];

    }

  
    if (font.fontData) {
        [self _emitEvent:NSCFontFaceSetEventAdd face:font family:font.family.lowercaseString];
    }
}

- (void)delete:(NSCFontFace *)font {
    @synchronized (self) {
        [_fontCache removeObject:font];
        NSString *key = font.family.lowercaseString;
        [_fontsByFamily[key] removeObject:font];
        if (_fontsByFamily[key].count == 0) [_fontsByFamily removeObjectForKey:key];
    }
    void (^reloadListener)(NSCFontFace *, NSString *) = [_reloadListenersByFace objectForKey:font];
    if (reloadListener) {
        [font removeOnReloadListener:reloadListener];
        [_reloadListenersByFace removeObjectForKey:font];
    }
    [self _emitEvent:NSCFontFaceSetEventRemove face:font family:font.family.lowercaseString];
}

- (void)clear {
    NSArray *snapshot;
    @synchronized (self) {
        snapshot = [_fontCache allObjects];
        [_fontCache removeAllObjects];
        [_fontsByFamily removeAllObjects];
    }
    for (NSCFontFace *face in snapshot) {
        void (^reloadListener)(NSCFontFace *, NSString *) = [_reloadListenersByFace objectForKey:face];
        if (reloadListener) {
            [face removeOnReloadListener:reloadListener];
        }
    }
    [_reloadListenersByFace removeAllObjects];
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
        @synchronized (self) { candidates = _fontsByFamily[key]; }

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
    return [self _resolveFonts:parsed].count > 0;
}

- (void)load:(NSString *)font
        text:(NSString *)text
    callback:(void(^)(NSArray<NSCFontFace *> *, NSString * _Nullable))callback {

    dispatch_async(_loaderQueue, ^{
        NSCFontParseResult *parsed = [NSCFontParser parse:font];
        if (!parsed) { callback(@[], @"Failed to parse font"); return; }

        NSArray *resolved = [self _resolveFonts:parsed];
        NSCFontFace *face = resolved.firstObject;
        if (!face) { callback(@[], nil); return; }

        [self _beginLoad:face];

        [face load:^(NSString * _Nullable error) {
            if (error) {
                [self _endLoadError:face error:error];
                callback(@[face], error);
            } else {
                [self _endLoadSuccess:face];
                if (face.fontData) {
                    [self _emitEvent:NSCFontFaceSetEventAdd face:face family:face.family];
                }
                callback(@[face], nil);
            }
        }];
    });
}

- (void)ready:(void(^)(NSCFontFaceSet *))callback {
    @synchronized (self) {
        if (_pendingLoads <= 0 && self.status == NSCFontFaceSetStatusLoaded) {
            callback(self);
        } else {
            [_readyCallbacks addObject:[callback copy]];
        }
    }
}

#pragma mark - Enumeration

- (NSEnumerator *)iter { return [self.fontCache objectEnumerator]; }
- (NSArray<NSCFontFace *> *)array { return [self.fontCache allObjects]; }
- (NSInteger)size { return (NSInteger)self.fontCache.count; }
- (void)forEach:(void(^)(NSCFontFace *))block {
    for (NSCFontFace *face in [self.fontCache copy]) block(face);
}

@end
