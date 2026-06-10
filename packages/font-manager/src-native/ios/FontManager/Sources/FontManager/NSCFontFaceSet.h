#import <Foundation/Foundation.h>
#import "NSCFontFace.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NSCFontFaceSetEventType) {
    NSCFontFaceSetEventAdd,
    NSCFontFaceSetEventRemove,
    NSCFontFaceSetEventClear,
};

@protocol NSCFontFaceSetListener <NSObject>
@optional
- (void)fontFaceSetDidEmitEvent:(NSCFontFaceSetEventType)event
                           face:(NSCFontFace * _Nullable)face
                         family:(NSString * _Nullable)family;
@end

typedef NS_ENUM(NSInteger, NSCFontFaceSetStatus) {
    NSCFontFaceSetStatusLoading,
    NSCFontFaceSetStatusLoaded
};

@interface NSCFontFaceSet : NSObject

@property (nonatomic, assign) NSCFontFaceSetStatus status;

- (void)addOnStatusListener:(void (^)(NSCFontFaceSetStatus))listener;
- (void)removeOnStatusListener:(void (^)(NSCFontFaceSetStatus))listener;

- (void)addOnLoadingListener:(void (^)(NSCFontFace *))listener;
- (void)removeOnLoadingListener:(void (^)(NSCFontFace *))listener;

- (void)addOnLoadingDoneListener:(void (^)(NSCFontFace *))listener;
- (void)removeOnLoadingDoneListener:(void (^)(NSCFontFace *))listener;

- (void)addOnLoadingErrorListener:(void (^)(NSCFontFace *, NSString *))listener;
- (void)removeOnLoadingErrorListener:(void (^)(NSCFontFace *, NSString *))listener;

+ (instancetype)instance;

- (void)add:(NSCFontFace *)font;
- (void)delete:(NSCFontFace *)font;
- (void)clear;
- (BOOL)has:(NSCFontFace *)font;

- (BOOL)check:(NSString *)font text:(nullable NSString *)text;

- (void)load:(NSString *)font
        text:(nullable NSString *)text
    callback:(void(^)(NSArray<NSCFontFace *> *fonts, NSString * _Nullable error))callback;

/**
 * Calls `callback` immediately if the set is already loaded (no pending
 * font loads), otherwise waits until all current loads complete.
 */
- (void)ready:(void(^)(NSCFontFaceSet *set))callback;

- (NSEnumerator *)iter;
- (NSArray<NSCFontFace *> *)array;
- (NSInteger)size;
- (void)forEach:(void(^)(NSCFontFace *face))block;

@end

NS_ASSUME_NONNULL_END
