@import XCTest;
@import FontManager;
@import UIKit;
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>

#pragma mark - Support

static NSString *FixturePath(NSString *name) {
    return [[SWIFTPM_MODULE_BUNDLE.resourcePath stringByAppendingPathComponent:@"Fixtures"]
        stringByAppendingPathComponent:name];
}

static NSData *FontBytes(NSString *name) {
    return [NSData dataWithContentsOfFile:FixturePath(name)];
}

static NSString *FontFile(NSString *name) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [FontBytes(@"stix_two_text_regular.ttf") writeToFile:path atomically:YES];
    return path;
}

@interface TestServer : NSObject
@property (nonatomic, readonly) NSString *base;
@property (nonatomic, readonly) uint16_t port;
- (instancetype)initWithHandler:(void (^)(NSString *path, int fd))handler;
- (void)stop;
+ (void)respond:(int)fd status:(int)status body:(NSData *)body announcedLength:(NSInteger)length;
+ (void)respond:(int)fd body:(NSData *)body;
@end

@implementation TestServer {
    int _listener;
    void (^_handler)(NSString *, int);
}

- (instancetype)initWithHandler:(void (^)(NSString *, int))handler {
    if (self = [super init]) {
        _handler = handler;
        _listener = socket(AF_INET, SOCK_STREAM, 0);
        int yes = 1;
        setsockopt(_listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
        struct sockaddr_in addr = {0};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        addr.sin_port = 0;
        bind(_listener, (struct sockaddr *)&addr, sizeof(addr));
        listen(_listener, 16);
        socklen_t len = sizeof(addr);
        getsockname(_listener, (struct sockaddr *)&addr, &len);
        _port = ntohs(addr.sin_port);
        _base = [NSString stringWithFormat:@"http://127.0.0.1:%u", _port];
        int listener = _listener;
        void (^serve)(NSString *, int) = handler;
        [NSThread detachNewThreadWithBlock:^{
            for (;;) {
                int fd = accept(listener, NULL, NULL);
                if (fd < 0) return;
                [NSThread detachNewThreadWithBlock:^{
                    NSMutableData *request = [NSMutableData data];
                    char buffer[4096];
                    while (![[[NSString alloc] initWithData:request encoding:NSUTF8StringEncoding] containsString:@"\r\n\r\n"]) {
                        ssize_t n = read(fd, buffer, sizeof(buffer));
                        if (n <= 0) break;
                        [request appendBytes:buffer length:(NSUInteger)n];
                    }
                    NSString *line = [[[NSString alloc] initWithData:request encoding:NSUTF8StringEncoding]
                                      componentsSeparatedByString:@"\r\n"].firstObject;
                    NSArray *parts = [line componentsSeparatedByString:@" "];
                    serve(parts.count > 1 ? parts[1] : @"/", fd);
                    close(fd);
                }];
            }
        }];
    }
    return self;
}

- (void)stop {
    shutdown(_listener, SHUT_RDWR);
    close(_listener);
}

+ (void)respond:(int)fd status:(int)status body:(NSData *)body announcedLength:(NSInteger)length {
    NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %d X\r\nContent-Length: %ld\r\nConnection: close\r\n\r\n",
                      status, (long)length];
    NSMutableData *out = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [out appendData:body];
    const uint8_t *bytes = out.bytes;
    NSUInteger sent = 0;
    while (sent < out.length) {
        ssize_t n = write(fd, bytes + sent, out.length - sent);
        if (n <= 0) return;
        sent += (NSUInteger)n;
    }
}

+ (void)respond:(int)fd body:(NSData *)body {
    [self respond:fd status:200 body:body announcedLength:(NSInteger)body.length];
}

@end

@interface FontManagerTests : XCTestCase
@end

@implementation FontManagerTests

- (NSString *)loadAndWait:(NSCFontFace *)face {
    XCTestExpectation *done = [self expectationWithDescription:@"load"];
    __block NSString *result = @"not called";
    [face load:^(NSString *error) {
        result = error;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:10];
    return result;
}

- (BOOL)isItalic:(UIFont *)font {
    return (font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitItalic) != 0;
}

#pragma mark - Parser

- (void)testParsesFractionalAndNonPxSizes {
    NSDictionary<NSString *, NSNumber *> *cases = @{
        @"16.5px Foo": @17, @"12pt Foo": @16, @"1.5em Foo": @24, @"2rem Foo": @32,
        @"150% Foo": @24, @"large Foo": @18, @"bold 20px Foo": @20,
    };
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *input, NSNumber *px, BOOL *stop) {
        NSCFontParseResult *result = [NSCFontParser parse:input];
        XCTAssertNotNil(result, @"%@", input);
        XCTAssertEqual(result.sizePx, px.integerValue, @"%@", input);
        XCTAssertEqualObjects(result.families, @[@"Foo"], @"%@", input);
    }];
    XCTAssertNil([NSCFontParser parse:@"not-a-font"]);
}

- (void)testParsesTheSizeSlashLineHeightShorthand {
    NSCFontParseResult *result = [NSCFontParser parse:@"italic bold 16px/1.5 Roboto, serif"];
    XCTAssertNotNil(result);
    XCTAssertEqual(result.sizePx, 16);
    XCTAssertEqualWithAccuracy(result.lineHeight.floatValue, 1.5f, 0.0001f);
    XCTAssertEqualObjects(result.families, (@[@"Roboto", @"serif"]));
    XCTAssertEqual(result.weight, 700);
    XCTAssertEqual(result.style.type, NSCFontStyleTypeItalic);

    NSCFontParseResult *plain = [NSCFontParser parse:@"20px Roboto"];
    XCTAssertEqual(plain.sizePx, 20);
    XCTAssertNil(plain.lineHeight);
}

- (void)testBucketsNumericWeights {
    XCTAssertEqual([NSCFontParser parse:@"450 16px Foo"].weight, 400);
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"Foo"];
    [face setFontWeight:@"450"];
    XCTAssertEqual(face.weight, NSCFontWeightNormal);
    [face setFontWeight:@"950"];
    XCTAssertEqual(face.weight, NSCFontWeightBlack);
}

#pragma mark - FontFaceSet

- (void)testKeepsEveryWeightOfAFamilyAndPicksTheClosest {
    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];
    NSCFontFace *regular = [[NSCFontFace alloc] initWithFamily:@"Stix" source:FontFile(@"set-regular.ttf")];
    NSCFontFace *bold = [[NSCFontFace alloc] initWithFamily:@"Stix" source:FontFile(@"set-bold.ttf")];
    bold.weight = NSCFontWeightBold;
    [set add:regular];
    [set add:bold];
    [set add:regular];
    XCTAssertEqual(set.size, 2);
    XCTAssertEqualObjects(set.array, (@[regular, bold]));

    XCTestExpectation *done = [self expectationWithDescription:@"load"];
    __block NSArray *loaded;
    [set load:@"bold 16px Stix" text:nil callback:^(NSArray<NSCFontFace *> *fonts, NSString *error) {
        XCTAssertNil(error);
        loaded = fonts;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:10];
    XCTAssertEqualObjects(loaded, @[bold]);
}

- (void)testCheckIsTrueOnlyWhenUsingTheFontWouldNotStartALoad {
    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];
    [set add:[[NSCFontFace alloc] initWithFamily:@"Pending" source:FontFile(@"check-pending.ttf")]];
    NSCFontFace *loaded = [[NSCFontFace alloc] initWithFamily:@"serif"];
    XCTAssertNil([self loadAndWait:loaded]);
    [set add:loaded];

    XCTAssertFalse([set check:@"16px Pending" text:nil]);
    XCTAssertTrue([set check:@"16px serif" text:nil]);
    XCTAssertTrue([set check:@"16px NoSuchFamily" text:nil]);
    XCTAssertFalse([set check:@"not-a-font" text:nil]);
}

- (void)testStatusIsLoadingUntilEveryLoadHasFinished {
    NSData *font = FontBytes(@"stix_two_text_regular.ttf");
    TestServer *server = [[TestServer alloc] initWithHandler:^(NSString *path, int fd) {
        [NSThread sleepForTimeInterval:0.5];
        [TestServer respond:fd body:font];
    }];
    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];
    NSCFontFace *slow = [[NSCFontFace alloc] initWithFamily:@"Slow" source:[server.base stringByAppendingString:@"/slow.ttf"]];
    [set add:slow];

    XCTestExpectation *loaded = [self expectationWithDescription:@"load"];
    XCTestExpectation *ready = [self expectationWithDescription:@"ready"];
    __block NSString *error = @"not called";
    [set load:@"16px Slow" text:nil callback:^(NSArray *fonts, NSString *e) {
        XCTAssertTrue([NSThread isMainThread]);
        error = e;
        [loaded fulfill];
    }];
    [set load:@"16px NotRegistered" text:nil callback:nil];
    XCTAssertEqual(set.status, NSCFontFaceSetStatusLoading);
    [set ready:^(NSCFontFaceSet *s) {
        XCTAssertEqual(slow.status, NSCFontFaceStatusLoaded, @"ready fired before the pending load finished");
        [ready fulfill];
    }];

    [self waitForExpectations:@[loaded, ready] timeout:10];
    XCTAssertNil(error);
    XCTAssertEqual(set.status, NSCFontFaceSetStatusLoaded);
    [server stop];
}

- (void)testADescriptorChangeFiresNoSetEvents {
    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"serif"];
    XCTAssertNil([self loadAndWait:face]);
    __block NSInteger events = 0;
    [set addOnLoadingListener:^(NSCFontFace *f) { events++; }];
    [set addOnLoadingDoneListener:^(NSCFontFace *f) { events++; }];
    [set addOnStatusListener:^(NSCFontFaceSetStatus status) { events++; }];
    [set add:face];

    face.weight = NSCFontWeightBold;
    [face setFontStyle:@"italic" angle:nil];

    XCTAssertEqual(events, 0);
    XCTAssertEqual(face.status, NSCFontFaceStatusLoaded);
    XCTAssertEqual(set.status, NSCFontFaceSetStatusLoaded);
}

#pragma mark - Loading periods

- (void)drainMain {
    XCTestExpectation *drained = [self expectationWithDescription:@"drain"];
    dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; });
    [self waitForExpectations:@[drained] timeout:10];
}

- (NSMutableArray<NSString *> *)record:(NSCFontFaceSet *)set {
    NSMutableArray<NSString *> *events = [NSMutableArray array];
    [set addOnStatusListener:^(NSCFontFaceSetStatus status) {
        [events addObject:status == NSCFontFaceSetStatusLoading ? @"status:Loading" : @"status:Loaded"];
    }];
    [set addOnLoadingListener:^(NSCFontFace *f) { [events addObject:[@"loading:" stringByAppendingString:f.family]]; }];
    [set addOnLoadingDoneListener:^(NSCFontFace *f) { [events addObject:[@"done:" stringByAppendingString:f.family]]; }];
    [set addOnLoadingDoneFacesListener:^(NSArray<NSCFontFace *> *faces) {
        [events addObject:[@"doneFaces:" stringByAppendingString:[[faces valueForKey:@"family"] componentsJoinedByString:@","]]];
    }];
    [set addOnLoadingErrorFacesListener:^(NSArray<NSCFontFace *> *faces, NSString *error) {
        [events addObject:[@"errorFaces:" stringByAppendingString:[[faces valueForKey:@"family"] componentsJoinedByString:@","]]];
    }];
    [set addOnChangedListener:^{ [events addObject:@"changed"]; }];
    return events;
}

- (void)testAMemberFacesOwnLoadRunsOneLoadingPeriod {
    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];
    NSMutableArray *events = [self record:set];
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"PeriodA" source:FontFile(@"period/a.ttf")];
    [set add:face];
    [set add:face];
    XCTAssertEqual(set.size, 1);
    XCTAssertNil([self loadAndWait:face]);
    [self drainMain];
    NSArray *expected = @[@"changed", @"status:Loading", @"loading:PeriodA", @"changed", @"status:Loaded",
                          @"done:PeriodA", @"doneFaces:PeriodA"];
    XCTAssertEqualObjects(events, expected);
    XCTAssertEqual(set.status, NSCFontFaceSetStatusLoaded);
}

- (void)testConcurrentLoadsShareAPeriodAndReportFailuresTogether {
    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];
    NSCFontFace *good = [[NSCFontFace alloc] initWithFamily:@"PeriodB" source:FontFile(@"period/b.ttf")];
    NSCFontFace *bad = [[NSCFontFace alloc] initWithFamily:@"PeriodC" source:@"file:///no/such/file.ttf"];
    [set add:good];
    [set add:bad];
    NSMutableArray *events = [self record:set];
    XCTestExpectation *goodDone = [self expectationWithDescription:@"good"];
    XCTestExpectation *badDone = [self expectationWithDescription:@"bad"];
    __block NSString *badError = nil;
    [good load:^(NSString *e) { [goodDone fulfill]; }];
    [bad load:^(NSString *e) { badError = e; [badDone fulfill]; }];
    [self waitForExpectations:@[goodDone, badDone] timeout:10];
    [self drainMain];
    XCTAssertNotNil(badError);
    NSPredicate *loadingStatus = [NSPredicate predicateWithFormat:@"SELF == 'status:Loading'"];
    NSPredicate *loadedStatus = [NSPredicate predicateWithFormat:@"SELF == 'status:Loaded'"];
    NSPredicate *doneFaces = [NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'doneFaces:'"];
    XCTAssertEqual([events filteredArrayUsingPredicate:loadingStatus].count, 1);
    XCTAssertEqual([events filteredArrayUsingPredicate:loadedStatus].count, 1);
    XCTAssertEqual([events filteredArrayUsingPredicate:doneFaces].count, 1);
    XCTAssertTrue([events containsObject:@"doneFaces:PeriodB"]);
    XCTAssertTrue([events containsObject:@"errorFaces:PeriodC"]);
}

- (void)testAddingAFaceThatHasAlreadyLoadedOnlyRaisesChanged {
    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"PeriodD" source:FontFile(@"period/d.ttf")];
    XCTAssertNil([self loadAndWait:face]);
    NSMutableArray *events = [self record:set];
    [set add:face];
    [self drainMain];
    XCTAssertEqualObjects(events, @[@"changed"]);
}

- (void)testLoadingAFaceThatHasAlreadyLoadedThroughTheSetRaisesNothing {
    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"PeriodE" source:FontFile(@"period/e.ttf")];
    [set add:face];
    XCTAssertNil([self loadAndWait:face]);
    [self drainMain];
    NSMutableArray *events = [self record:set];
    XCTestExpectation *done = [self expectationWithDescription:@"load"];
    [set load:@"16px PeriodE" text:nil callback:^(NSArray *fonts, NSString *e) { [done fulfill]; }];
    [self waitForExpectations:@[done] timeout:10];
    [self drainMain];
    XCTAssertEqualObjects(events, @[]);
}

- (void)testRemovingAFaceRaisesChanged {
    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"PeriodF" source:FontFile(@"period/f.ttf")];
    [set add:face];
    NSMutableArray *events = [self record:set];
    [set delete:face];
    [set delete:face];
    [self drainMain];
    XCTAssertEqualObjects(events, @[@"changed"]);
}

#pragma mark - Remote

- (void)testImportsEveryFaceInParallelAndAnswersOnceAllAreLoaded {
    NSData *font = FontBytes(@"stix_two_text_regular.ttf");
    NSInteger faces = 4;
    NSTimeInterval delay = 0.6;
    __block uint16_t port = 0;
    TestServer *server = [[TestServer alloc] initWithHandler:^(NSString *path, int fd) {
        if ([path isEqualToString:@"/fonts.css"]) {
            NSMutableString *css = [NSMutableString string];
            for (NSInteger i = 0; i < faces; i++) {
                [css appendFormat:@"@font-face { font-family: 'Remote%ld'; font-weight: 400; src: url(http://127.0.0.1:%u/f%ld.ttf) format('truetype'); }\n",
                 (long)i, port, (long)i];
            }
            [TestServer respond:fd body:[css dataUsingEncoding:NSUTF8StringEncoding]];
        } else {
            [NSThread sleepForTimeInterval:delay];
            [TestServer respond:fd body:font];
        }
    }];
    port = server.port;

    XCTestExpectation *done = [self expectationWithDescription:@"import"];
    __block NSArray<NSCFontFace *> *result = nil;
    __block NSString *error = @"not called";
    NSDate *started = [NSDate date];
    [NSCFontFace importFromRemote:[server.base stringByAppendingString:@"/fonts.css"] load:YES
                       completion:^(NSArray<NSCFontFace *> *fonts, NSString *e) {
        XCTAssertTrue([NSThread isMainThread]);
        result = fonts;
        error = e;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:20];
    NSTimeInterval elapsed = -started.timeIntervalSinceNow;

    XCTAssertNil(error);
    XCTAssertEqual(result.count, (NSUInteger)faces);
    for (NSCFontFace *face in result) {
        XCTAssertEqual(face.status, NSCFontFaceStatusLoaded);
        XCTAssertTrue(face.font != NULL);
        XCTAssertTrue([[NSCFontFaceSet instance] has:face]);
        [[NSCFontFaceSet instance] delete:face];
    }
    XCTAssertLessThan(elapsed, delay * 3, @"%ld downloads of %.1fs took %.2fs", (long)faces, delay, elapsed);
    [server stop];
}

- (void)testRejectsHttpErrorsAndTruncatedDownloads {
    NSData *font = FontBytes(@"stix_two_text_regular.ttf");
    TestServer *server = [[TestServer alloc] initWithHandler:^(NSString *path, int fd) {
        if ([path isEqualToString:@"/missing.ttf"]) {
            [TestServer respond:fd status:404 body:[@"nope" dataUsingEncoding:NSUTF8StringEncoding] announcedLength:4];
        } else {
            [TestServer respond:fd status:200 body:[font subdataWithRange:NSMakeRange(0, font.length / 2)]
                announcedLength:(NSInteger)font.length];
        }
    }];

    NSCFontFace *missing = [[NSCFontFace alloc] initWithFamily:@"Missing" source:[server.base stringByAppendingString:@"/missing.ttf"]];
    NSString *missingError = [self loadAndWait:missing];
    XCTAssertTrue([missingError containsString:@"404"], @"%@", missingError);
    XCTAssertEqual(missing.status, NSCFontFaceStatusError);

    NSCFontFace *truncated = [[NSCFontFace alloc] initWithFamily:@"Truncated" source:[server.base stringByAppendingString:@"/truncated.ttf"]];
    XCTAssertNotNil([self loadAndWait:truncated]);
    XCTAssertEqual(truncated.status, NSCFontFaceStatusError);
    [server stop];
}

#pragma mark - FontFace

- (void)testDifferentFontsOfEqualLengthDoNotShareACGFont {
    NSData *bold = FontBytes(@"stix_two_text_bold.ttf");
    NSMutableData *regular = [FontBytes(@"stix_two_text_regular.ttf") mutableCopy];
    XCTAssertLessThan(regular.length, bold.length);
    regular.length = bold.length;

    CGFontRef a = [[NSCFontResolver shared] registerFontFromData:regular error:nil];
    CGFontRef b = [[NSCFontResolver shared] registerFontFromData:bold error:nil];
    XCTAssertTrue(a != NULL && b != NULL);
    NSString *aName = CFBridgingRelease(CGFontCopyPostScriptName(a));
    NSString *bName = CFBridgingRelease(CGFontCopyPostScriptName(b));
    XCTAssertNotEqualObjects(aName, bName);
}

- (void)testConcurrentLoadsShareOneLoadAndAnswerOnceOnTheMainThread {
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"Shared" source:FontFile(@"shared.ttf")];
    NSInteger callers = 8;
    XCTestExpectation *done = [self expectationWithDescription:@"loads"];
    done.expectedFulfillmentCount = callers;
    done.assertForOverFulfill = YES;
    for (NSInteger i = 0; i < callers; i++) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [face load:^(NSString *error) {
                XCTAssertTrue([NSThread isMainThread]);
                XCTAssertNil(error);
                [done fulfill];
            }];
        });
    }
    [self waitForExpectations:@[done] timeout:10];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    XCTAssertEqual(face.status, NSCFontFaceStatusLoaded);
}

- (void)testLoadSyncWorksOnAndOffTheMainThread {
    NSCFontFace *system = [[NSCFontFace alloc] initWithFamily:@"monospace"];
    NSString *error = @"unset";
    [system loadSync:&error];
    XCTAssertNil(error);
    XCTAssertEqual(system.status, NSCFontFaceStatusLoaded);

    NSCFontFace *file = [[NSCFontFace alloc] initWithFamily:@"SyncFile" source:FontFile(@"sync.ttf")];
    XCTestExpectation *done = [self expectationWithDescription:@"loadSync"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *e = @"unset";
        [file loadSync:&e];
        XCTAssertNil(e);
        XCTAssertEqual(file.status, NSCFontFaceStatusLoaded);
        [done fulfill];
    });
    [self waitForExpectations:@[done] timeout:10];
}

- (void)testASystemFaceLoadsOnTheCallingThread {
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"serif"];
    [face load:^(NSString *error) {}];
    XCTAssertEqual(face.status, NSCFontFaceStatusLoaded);
    XCTAssertNotNil(face.uiFont);
}

- (void)testAFileFaceKeepsItsFontWhenItsDescriptorsChange {
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"StixFile" source:FontFile(@"reload-stix.ttf")];
    XCTAssertNil([self loadAndWait:face]);
    CGFontRef loaded = face.font;
    UIFont *loadedUIFont = face.uiFont;
    __block NSInteger reloads = 0;
    [face addReloadListener:^(NSCFontFace *f, NSString *error) { reloads++; }];

    face.display = NSCFontDisplaySwap;
    face.weight = NSCFontWeightBold;
    [face setFontStretch:@"condensed"];
    [face setFontStyle:@"italic" angle:nil];

    XCTAssertEqual(face.status, NSCFontFaceStatusLoaded);
    XCTAssertTrue(face.font == loaded);
    XCTAssertEqualObjects(face.uiFont, loadedUIFont);
    XCTAssertFalse([self isItalic:face.uiFont], @"a descriptor describes the font, it does not restyle it");
    XCTAssertEqual(reloads, 0);
}

- (void)testASystemFaceSwapsItsFontOnlyForChangesThatPickADifferentOne {
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"serif"];
    XCTAssertNil([self loadAndWait:face]);
    __block NSInteger reloads = 0;
    [face addReloadListener:^(NSCFontFace *f, NSString *error) {
        XCTAssertTrue([NSThread isMainThread]);
        XCTAssertNil(error);
        reloads++;
    }];

    face.display = NSCFontDisplaySwap;
    XCTAssertEqual(reloads, 0);

    face.weight = NSCFontWeightBold;
    XCTAssertEqual(reloads, 1);
    XCTAssertEqual(face.status, NSCFontFaceStatusLoaded);
    XCTAssertTrue(face.uiFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold);

    [face setFontStyle:@"italic" angle:nil];
    XCTAssertEqual(reloads, 2);
    XCTAssertEqual(face.status, NSCFontFaceStatusLoaded);
    XCTAssertTrue([self isItalic:face.uiFont]);
}

- (void)testAWeightChangeDuringALoadIsNotLost {
    NSInteger stale = 0;
    for (NSInteger i = 0; i < 200; i++) {
        NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"serif"];
        XCTestExpectation *done = [self expectationWithDescription:@"load"];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [face load:^(NSString *error) { [done fulfill]; }];
        });
        [NSThread sleepForTimeInterval:(i % 20) * 0.00005];
        face.weight = NSCFontWeightBold;
        [self waitForExpectations:@[done] timeout:10];
        XCTAssertNil([self loadAndWait:face]);
        if (!(face.uiFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold)) stale++;
    }
    XCTAssertEqual(stale, 0, @"loads that kept the pre-change weight");
}

- (void)testGenericFamiliesHonourWeightStyleAndSystemDesigns {
    NSCFontFace *serif = [[NSCFontFace alloc] initWithFamily:@"serif"];
    serif.weight = NSCFontWeightBold;
    [serif setFontStyle:@"italic" angle:nil];
    XCTAssertNil([self loadAndWait:serif]);
    UIFontDescriptorSymbolicTraits traits = serif.uiFont.fontDescriptor.symbolicTraits;
    XCTAssertTrue(traits & UIFontDescriptorTraitBold, @"%@", serif.uiFont);
    XCTAssertTrue(traits & UIFontDescriptorTraitItalic, @"%@", serif.uiFont);

    NSCFontFace *mono = [[NSCFontFace alloc] initWithFamily:@"ui-monospace"];
    XCTAssertNil([self loadAndWait:mono]);
    XCTAssertTrue(mono.uiFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitMonoSpace, @"%@", mono.uiFont);

    NSCFontFace *rounded = [[NSCFontFace alloc] initWithFamily:@"ui-rounded"];
    XCTAssertNil([self loadAndWait:rounded]);
    XCTAssertTrue([rounded.uiFont.fontName.lowercaseString containsString:@"rounded"], @"%@", rounded.uiFont);

    NSCFontFace *system = [[NSCFontFace alloc] initWithFamily:@"system-ui"];
    XCTAssertNil([self loadAndWait:system]);
    XCTAssertEqualObjects(system.uiFont.familyName, [UIFont systemFontOfSize:17].familyName);
}

- (void)testLoadsABarePathContainingSpaces {
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"Spaced" source:FontFile(@"dir with space/My Font.ttf")];
    XCTAssertNil([self loadAndWait:face]);
    XCTAssertEqual(face.status, NSCFontFaceStatusLoaded);
    XCTAssertNotNil(face.rawData);
}

- (void)testAnUnsupportedSourceFailsInsteadOfLoadingNothing {
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"Data" source:@"data:font/ttf;base64,AAAA"];
    XCTAssertNotNil([self loadAndWait:face]);
    XCTAssertEqual(face.status, NSCFontFaceStatusError);
}

@end
