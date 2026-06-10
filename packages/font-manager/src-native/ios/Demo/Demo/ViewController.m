#import "ViewController.h"
@import FontManager;

@interface ViewController ()
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIButton *testButton;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.testButton setTitle:@"Run FontManager Tests" forState:UIControlStateNormal];
    self.testButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.testButton addTarget:self action:@selector(runTests) forControlEvents:UIControlEventTouchUpInside];

    self.logView = [[UITextView alloc] init];
    self.logView.editable = NO;
    self.logView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.logView.text = @"Tap the button to run tests.";

    self.testButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.testButton];
    [self.view addSubview:self.logView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.testButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:20],
        [self.testButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.logView.topAnchor constraintEqualToAnchor:self.testButton.bottomAnchor constant:16],
        [self.logView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
        [self.logView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
        [self.logView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
    ]];
}

- (void)log:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[FontManager] %@", message);
        self.logView.text = [self.logView.text stringByAppendingFormat:@"\n%@", message];
        NSRange bottom = NSMakeRange(self.logView.text.length - 1, 1);
        [self.logView scrollRangeToVisible:bottom];
    });
}

- (void)runTests {
    self.logView.text = @"=== FontManager Tests ===";
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self test_systemFont];
        [self test_descriptorSetters];
        [self test_fontFaceSet];
        [self test_fontFaceSetLoad];
        [self test_forEach];
        [self test_updateDescriptor];
        [self test_autoReload];
        [self test_onReloadCallback];
        [self test_fontFaceSetEvents];
        [self test_ready];
        [self test_has];
        [self test_clearCache];
        [self test_localFont];
        [self test_remoteFont];
        [self test_remoteFontFaceSet];
        [self test_importFromRemote];
        [self log:@"\n=== All tests complete ==="];
    });
}

// Test 1: load a generic system font
- (void)test_systemFont {
    [self log:@"\n[1] System font load"];

    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"sans-serif"];
    [self log:[NSString stringWithFormat:@"  family: %@", face.family]];
    [self log:[NSString stringWithFormat:@"  status before load: %ld", (long)face.status]];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSString *loadError = nil;
    [face load:^(NSString *error) {
        loadError = error;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    [self log:[NSString stringWithFormat:@"  status after load: %ld (expected %ld=Loaded)",
               (long)face.status, (long)NSCFontFaceStatusLoaded]];
    [self log:[NSString stringWithFormat:@"  font != NULL: %@", face.font != NULL ? @"YES" : @"NO"]];
    if (loadError) [self log:[NSString stringWithFormat:@"  ERROR: %@", loadError]];
}

// Test 2: descriptor setters
- (void)test_descriptorSetters {
    [self log:@"\n[2] Descriptor setters"];

    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"serif"];
    [face setFontWeight:@"700"];
    [face setFontStyle:@"italic" angle:nil];
    [face setFontDisplay:@"swap"];
    face.stretch = @"condensed";
    face.unicodeRange = @"U+0025-00FF";
    face.featureSettings = @"\"smcp\"";

    [self log:[NSString stringWithFormat:@"  weight: %ld (expected 700)", (long)face.weight]];
    [self log:[NSString stringWithFormat:@"  style: %@ (expected italic)", face.style]];
    [self log:[NSString stringWithFormat:@"  display: %ld (expected %ld=Swap)", (long)face.display, (long)NSCFontDisplaySwap]];
    [self log:[NSString stringWithFormat:@"  stretch: %@", face.stretch]];
    [self log:[NSString stringWithFormat:@"  unicodeRange: %@", face.unicodeRange]];
    [self log:[NSString stringWithFormat:@"  featureSettings: %@", face.featureSettings]];
}

// Test 3: FontFaceSet add / delete / check
- (void)test_fontFaceSet {
    [self log:@"\n[3] FontFaceSet add/delete/check"];

    NSCFontFaceSet *set = [NSCFontFaceSet instance];
    [set clear];

    NSCFontFace *serif = [[NSCFontFace alloc] initWithFamily:@"serif"];
    [set add:serif];
    [self log:[NSString stringWithFormat:@"  size after add: %ld (expected 1)", (long)set.size]];

    BOOL found = [set check:@"16px serif" text:nil];
    [self log:[NSString stringWithFormat:@"  check '16px serif': %@ (expected YES)", found ? @"YES" : @"NO"]];

    BOOL notFound = [set check:@"16px 'NonExistentFont'" text:nil];
    [self log:[NSString stringWithFormat:@"  check '16px NonExistentFont': %@ (expected NO)", notFound ? @"YES" : @"NO"]];

    [set delete:serif];
    [self log:[NSString stringWithFormat:@"  size after delete: %ld (expected 0)", (long)set.size]];
}

// Test 4: FontFaceSet load
- (void)test_fontFaceSetLoad {
    [self log:@"\n[4] FontFaceSet load"];

    NSCFontFaceSet *set = [NSCFontFaceSet instance];
    [set clear];

    NSCFontFace *mono = [[NSCFontFace alloc] initWithFamily:@"monospace"];
    [set add:mono];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSArray *loadedFaces = nil;
    [set load:@"16px monospace" text:nil callback:^(NSArray<NSCFontFace *> *faces, NSString *error) {
        loadedFaces = faces;
        if (error) [self log:[NSString stringWithFormat:@"  ERROR: %@", error]];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    [self log:[NSString stringWithFormat:@"  loaded faces: %lu (expected 1)", (unsigned long)loadedFaces.count]];
    if (loadedFaces.count > 0) {
        NSCFontFace *f = loadedFaces[0];
        [self log:[NSString stringWithFormat:@"  face family: %@, status: %ld", f.family, (long)f.status]];
    }
}

// Test 5: forEach
- (void)test_forEach {
    [self log:@"\n[5] forEach"];

    NSCFontFaceSet *set = [NSCFontFaceSet instance];

    NSCFontFace *a = [[NSCFontFace alloc] initWithFamily:@"serif"];
    NSCFontFace *b = [[NSCFontFace alloc] initWithFamily:@"monospace"];
    [set add:a];
    [set add:b];

    __block NSInteger count = 0;
    [set forEach:^(NSCFontFace *face) {
        [self log:[NSString stringWithFormat:@"  face: %@", face.family]];
        count++;
    }];
    [self log:[NSString stringWithFormat:@"  iterated %ld faces", (long)count]];
}

// Test 6: updateDescriptor
- (void)test_updateDescriptor {
    [self log:@"\n[6] updateDescriptor"];

    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"Roboto"];
    [face updateDescriptor:@"@font-face { font-weight: 300; font-style: italic; font-display: swap; }"];

    [self log:[NSString stringWithFormat:@"  weight: %ld (expected 300)", (long)face.weight]];
    [self log:[NSString stringWithFormat:@"  style: %@ (expected italic)", face.style]];
    [self log:[NSString stringWithFormat:@"  display: %ld (expected %ld=Swap)", (long)face.display, (long)NSCFontDisplaySwap]];
}

// Test 7: auto-reload on descriptor change
- (void)test_autoReload {
    [self log:@"\n[7] Auto-reload on descriptor change"];

    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"serif"];

    // Load initial
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [face load:^(NSString *error) { dispatch_semaphore_signal(sem); }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    [self log:[NSString stringWithFormat:@"  status after initial load: %ld (expected %ld=Loaded)",
               (long)face.status, (long)NSCFontFaceStatusLoaded]];

    // Changing weight on a loaded face should trigger a reload
    face.weight = NSCFontWeightBold;
    [self log:[NSString stringWithFormat:@"  status immediately after weight change: %ld (expected %ld=Unloaded)",
               (long)face.status, (long)NSCFontFaceStatusUnloaded]];

    // Give reload a moment to finish
    [NSThread sleepForTimeInterval:0.5];
    [self log:[NSString stringWithFormat:@"  status after 500ms (reload should complete): %ld (expected %ld=Loaded)",
               (long)face.status, (long)NSCFontFaceStatusLoaded]];
}

// Test 8: onReload callback notifies caller
- (void)test_onReloadCallback {
    [self log:@"\n[8] onReload callback"];

    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"sans-serif"];

    dispatch_semaphore_t loadSem = dispatch_semaphore_create(0);
    [face load:^(NSString *e) { dispatch_semaphore_signal(loadSem); }];
    dispatch_semaphore_wait(loadSem, DISPATCH_TIME_FOREVER);

    __block BOOL reloadFired = NO;
    __block NSString *reloadError = nil;
    dispatch_semaphore_t reloadSem = dispatch_semaphore_create(0);

    face.onReload = ^(NSCFontFace *f, NSString *error) {
        reloadFired = YES;
        reloadError = error;
        dispatch_semaphore_signal(reloadSem);
    };

    // Changing style triggers a reload
    [face setFontStyle:@"italic" angle:nil];

    dispatch_semaphore_wait(reloadSem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));

    [self log:[NSString stringWithFormat:@"  onReload fired: %@ (expected YES)", reloadFired ? @"YES" : @"NO"]];
    [self log:[NSString stringWithFormat:@"  reload error: %@ (expected nil)", reloadError ?: @"nil"]];
    [self log:[NSString stringWithFormat:@"  face status: %ld (expected %ld=Loaded)", (long)face.status, (long)NSCFontFaceStatusLoaded]];
}

// Test 9: FontFaceSet loading/done/error events
- (void)test_fontFaceSetEvents {
    [self log:@"\n[9] FontFaceSet events (onLoading/onLoadingDone/onLoadingError)"];

    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];

    __block NSInteger loadingCount = 0;
    __block NSInteger doneCount = 0;

    set.onLoading = ^(NSCFontFace *f) { loadingCount++; };
    set.onLoadingDone = ^(NSCFontFace *f) {
        doneCount++;
        [self log:[NSString stringWithFormat:@"  onLoadingDone: %@", f.family]];
    };
    set.onLoadingError = ^(NSCFontFace *f, NSString *error) {
        [self log:[NSString stringWithFormat:@"  onLoadingError: %@ — %@", f.family, error]];
    };

    NSCFontFace *mono = [[NSCFontFace alloc] initWithFamily:@"monospace"];
    [set add:mono];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [set load:@"16px monospace" text:nil callback:^(NSArray *faces, NSString *error) {
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));

    [self log:[NSString stringWithFormat:@"  onLoading calls: %ld (expected 1)", (long)loadingCount]];
    [self log:[NSString stringWithFormat:@"  onLoadingDone calls: %ld (expected 1)", (long)doneCount]];
}

// Test 10: FontFaceSet.ready
- (void)test_ready {
    [self log:@"\n[10] FontFaceSet.ready"];

    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];

    __block BOOL readyFired = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    // Should fire immediately (no pending loads)
    [set ready:^(NSCFontFaceSet *s) {
        readyFired = YES;
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
    [self log:[NSString stringWithFormat:@"  ready fired immediately: %@ (expected YES)", readyFired ? @"YES" : @"NO"]];

    // Now load a font and check ready fires after load completes
    NSCFontFace *serif = [[NSCFontFace alloc] initWithFamily:@"serif"];
    [set add:serif];

    __block BOOL readyAfterLoad = NO;
    dispatch_semaphore_t sem2 = dispatch_semaphore_create(0);

    [set load:@"16px serif" text:nil callback:^(NSArray *f, NSString *e) {}];
    [set ready:^(NSCFontFaceSet *s) {
        readyAfterLoad = YES;
        dispatch_semaphore_signal(sem2);
    }];

    dispatch_semaphore_wait(sem2, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    [self log:[NSString stringWithFormat:@"  ready fired after load: %@ (expected YES)", readyAfterLoad ? @"YES" : @"NO"]];
}

// Test 11: FontFaceSet.has
- (void)test_has {
    [self log:@"\n[11] FontFaceSet.has"];

    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"cursive"];

    [self log:[NSString stringWithFormat:@"  has before add: %@ (expected NO)", [set has:face] ? @"YES" : @"NO"]];
    [set add:face];
    [self log:[NSString stringWithFormat:@"  has after add: %@ (expected YES)", [set has:face] ? @"YES" : @"NO"]];
    [set delete:face];
    [self log:[NSString stringWithFormat:@"  has after delete: %@ (expected NO)", [set has:face] ? @"YES" : @"NO"]];
}

// Test 12: clearFontCache
- (void)test_clearCache {
    [self log:@"\n[7] clearFontCache"];
    [NSCFontFace clearFontCache];
    [self log:@"  clearFontCache called (no error)"];
}

// Test 13: local font file path
- (void)test_localFont {
    [self log:@"\n[8] Local font (bundle resource)"];

    // Look for any .ttf or .otf bundled with the demo
    NSArray *exts = @[@"ttf", @"otf"];
    NSString *fontPath = nil;
    for (NSString *ext in exts) {
        fontPath = [[NSBundle mainBundle] pathForResource:nil ofType:ext];
        if (fontPath) break;
    }

    if (!fontPath) {
        [self log:@"  No bundled font found — skipping local font test"];
        return;
    }

    [self log:[NSString stringWithFormat:@"  Loading: %@", fontPath.lastPathComponent]];

    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"TestFont" source:fontPath];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [face load:^(NSString *error) {
        if (error) {
            [self log:[NSString stringWithFormat:@"  ERROR: %@", error]];
        } else {
            [self log:[NSString stringWithFormat:@"  status: %ld (expected %ld=Loaded)", (long)face.status, (long)NSCFontFaceStatusLoaded]];
            [self log:[NSString stringWithFormat:@"  fontPath: %@", face.fontPath ?: @"(nil)"]];
        }
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
}

// Test 14: single remote font file (direct .woff2 URL)
- (void)test_remoteFont {
    [self log:@"\n[14] Remote font file (direct URL)"];

    NSString *url = @"https://fonts.gstatic.com/s/roboto/v32/KFOmCnqEu92Fr1Mu4mxKKTU1Kg.woff2";
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"RobotoRemote" source:url];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [face load:^(NSString *error) {
        if (error) {
            [self log:[NSString stringWithFormat:@"  ERROR: %@", error]];
        } else {
            [self log:[NSString stringWithFormat:@"  family: %@", face.family]];
            [self log:[NSString stringWithFormat:@"  status: %ld (expected %ld=Loaded)", (long)face.status, (long)NSCFontFaceStatusLoaded]];
            [self log:[NSString stringWithFormat:@"  font != NULL: %@", face.font != NULL ? @"YES" : @"NO"]];
            [self log:[NSString stringWithFormat:@"  fontData bytes: %lu", (unsigned long)face.fontData.length]];
        }
        dispatch_semaphore_signal(sem);
    }];
    BOOL ok = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) == 0;
    if (!ok) [self log:@"  TIMEOUT waiting for remote font"];
}

// Test 15: remote FontFace loaded through FontFaceSet.load
- (void)test_remoteFontFaceSet {
    [self log:@"\n[15] FontFaceSet.load with remote font"];

    NSString *url = @"https://fonts.gstatic.com/s/montserrat/v26/JTUSjIg1_i6t8kCHKm459WlhyyTh89Y.woff2";
    NSCFontFace *face = [[NSCFontFace alloc] initWithFamily:@"MontserratRemote" source:url];

    NSCFontFaceSet *set = [[NSCFontFaceSet alloc] init];
    [set add:face];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [set load:@"16px MontserratRemote" text:nil callback:^(NSArray<NSCFontFace *> *faces, NSString *error) {
        if (error) {
            [self log:[NSString stringWithFormat:@"  ERROR: %@", error]];
        } else {
            [self log:[NSString stringWithFormat:@"  resolved faces: %lu", (unsigned long)faces.count]];
            NSCFontFace *f = faces.firstObject;
            if (f) [self log:[NSString stringWithFormat:@"  face: %@, status: %ld", f.family, (long)f.status]];
        }
        dispatch_semaphore_signal(sem);
    }];
    BOOL ok = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) == 0;
    if (!ok) [self log:@"  TIMEOUT waiting for set.load remote font"];
}

// Test 16: importFromRemote parses a Google Fonts CSS stylesheet
- (void)test_importFromRemote {
    [self log:@"\n[16] NSCFontFace importFromRemote (CSS stylesheet)"];

    NSString *cssURL = @"https://fonts.googleapis.com/css2?family=Roboto:wght@400;700&display=swap";

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [NSCFontFace importFromRemote:cssURL load:YES completion:^(NSArray<NSCFontFace *> *fonts, NSString *error) {
        if (error) {
            [self log:[NSString stringWithFormat:@"  ERROR: %@", error]];
        } else {
            [self log:[NSString stringWithFormat:@"  imported %lu face(s)", (unsigned long)fonts.count]];
            for (NSCFontFace *face in fonts) {
                [self log:[NSString stringWithFormat:@"  - %@ weight=%ld status=%ld",
                           face.family, (long)face.weight, (long)face.status]];
            }
        }
        dispatch_semaphore_signal(sem);
    }];
    BOOL ok = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) == 0;
    if (!ok) { [self log:@"  TIMEOUT waiting for importFromRemote"]; return; }

    // Verify the imported faces are in the global FontFaceSet
    BOOL inSet = [[NSCFontFaceSet instance] check:@"16px Roboto" text:nil];
    [self log:[NSString stringWithFormat:@"  'Roboto' in global FontFaceSet: %@", inSet ? @"YES" : @"NO"]];
}

@end
