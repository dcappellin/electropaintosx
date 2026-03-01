/*
 * ElectropaintView.mm
 * ElectropaintOSX — Metal renderer
 *
 * Ported from Kent Rosenkoetter's electropaint.cpp
 * Original Obj-C++ wrapper by Douglas McInnes (2004)
 * Metal conversion (2026)
 *
 * GPL v2 or later — see gpl.txt
 */

#import "ElectropaintView.h"
#import "ElectropaintRenderer.h"
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// Per-instance state stored as associated object (avoids ivar offset
// collisions with ScreenSaverView private ivars on macOS 26).
// ---------------------------------------------------------------------------

@interface EPViewState : NSObject
@property (nonatomic, strong) ElectropaintRenderer *renderer;
@property (nonatomic)         BOOL                  running;
@end
@implementation EPViewState @end

static const void * const kEPViewStateKey = &kEPViewStateKey;

static EPViewState *ep_state(id obj) {
    return objc_getAssociatedObject(obj, kEPViewStateKey);
}
static void ep_set_state(id obj, EPViewState *s) {
    objc_setAssociatedObject(obj, kEPViewStateKey, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// ---------------------------------------------------------------------------
// Visibility tracking.
//
// On macOS 26 the ScreenSaver framework often does NOT call stopAnimation
// when the screensaver is dismissed.  The legacyScreenSaver process creates
// multiple views per process and may leave some running.
//
// We keep a static set of all live views.  When ANY view detects dismissal
// (via notification, viewDidMoveToWindow, or the animateOneFrame watchdog)
// we soft-stop ALL views: set their per-instance running flag to NO and
// call [super stopAnimation] on each to kill the framework's _oneStep:
// timer.  Metal state is kept alive so startAnimation can resume later.
// ---------------------------------------------------------------------------

static NSHashTable<ElectropaintView *> *gAllViews = nil;

@implementation ElectropaintView

- (id)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        [self setAnimationTimeInterval:1.0/60.0];
        if (!gAllViews) gAllViews = [NSHashTable weakObjectsHashTable];
        [gAllViews addObject:self];
    }
    return self;
}

- (void)startAnimation {
    [self setAnimationTimeInterval:self.isPreview ? 1.0/10.0 : 1.0/60.0];

    EPViewState *state = ep_state(self);
    if (!state) {
        state = [[EPViewState alloc] init];
        ep_set_state(self, state);
    }

    if (!state.renderer) {
        state.renderer = [[ElectropaintRenderer alloc] initWithView:self];
        [state.renderer startRendering];
    }
    state.running = YES;

    // Update size in case view was resized while stopped
    NSSize size = self.bounds.size;
    if (size.width > 0 && size.height > 0) {
        CGFloat scale = self.window ? self.window.backingScaleFactor : 2.0;
        [state.renderer resize:size scale:scale];
    }

    // Observe window visibility for soft-stop
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.window) {
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(ep_windowGone:)
                   name:NSWindowWillCloseNotification
                 object:self.window];
    }

    [super startAnimation];
    NSLog(@"[Electropaint] startAnimation view=%p isPreview=%d", self, (int)self.isPreview);
}

- (void)stopAnimation {
    EPViewState *state = ep_state(self);
    if (state) state.running = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super stopAnimation];
    NSLog(@"[Electropaint] stopAnimation view=%p", self);
}

// Soft-stop a single view: halt rendering + kill framework timer.
- (void)ep_softStopSelf {
    EPViewState *state = ep_state(self);
    if (!state || !state.running) return;
    state.running = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super stopAnimation];
    NSLog(@"[Electropaint] softStop view=%p", self);
}

// Soft-stop ALL views in this process.
+ (void)ep_softStopAll {
    for (ElectropaintView *v in [gAllViews allObjects]) {
        [v ep_softStopSelf];
    }
}

// Window closed or ordered off screen
- (void)ep_windowGone:(NSNotification *)note {
    [ElectropaintView ep_softStopAll];
}

// View removed from window hierarchy
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) {
        [ElectropaintView ep_softStopAll];
    }
}

- (void)drawRect:(NSRect)rect {
    [super drawRect:rect];
}

- (void)animateOneFrame {
    EPViewState *state = ep_state(self);
    if (!state || !state.running) return;

    // Watchdog: if the window is gone or hidden, stop ALL views.
    if (!self.window || !self.window.isVisible) {
        [ElectropaintView ep_softStopAll];
        return;
    }

    [state.renderer tick];
}

- (BOOL)hasConfigureSheet { return NO; }
- (NSWindow *)configureSheet { return nil; }

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    if (newSize.width <= 0 || newSize.height <= 0) return;

    EPViewState *state = ep_state(self);
    if (!state || !state.renderer) {
        // Lazy init: preview starts with {0,0} and gets a real size here
        if ([self isAnimating]) {
            state = ep_state(self);
            if (!state) {
                state = [[EPViewState alloc] init];
                ep_set_state(self, state);
            }
            if (!state.renderer) {
                state.renderer = [[ElectropaintRenderer alloc] initWithView:self];
                [state.renderer startRendering];
                state.running = YES;
            }
        }
        if (!state || !state.renderer) return;
    }
    CGFloat scale = self.window ? self.window.backingScaleFactor : 2.0;
    [state.renderer resize:newSize scale:scale];
}

@end
