/* lby-pinkiepie-windowstate: remembers the state a game's window was left in (a Window and its
 * size, macOS Native Fullscreen, or a Window (full screen)) and puts it back at the next launch.
 *
 * Injected into the Wine loader's process (DYLD_INSERT_LIBRARIES, like the overlay shim); it touches
 * Dormison's winemac only through AppKit's public NSWindow API and notifications, so the engine
 * stays as its author signed it. The state is kept in a file of the game's own prefix, never in
 * the game's files.
 *
 * LULLABY_WINDOW_STATE_FILE  where the state lives (set by compat_run.sh); without it nothing happens
 * LULLABY_WINDOW_STATE=0     off for the run (a launch option)
 * LULLABY_NATIVE_FULLSCREEN  0: a game that covers the screen stays in the window the engine shows it in;
 *                            anything else: it goes on to macOS's native full screen (the game's setting)
 * LULLABY_LAYER_DUMP=1       (or a file named layer-dump beside the state file) a diagnosis: the window's layer tree (class, frame, bounds, position, anchor, transform) goes to the log
 *                            three seconds after the window enters or leaves native full screen
 * LULLABY_KEEP_BUNDLE_ICON=1 the launcher bundle has Lullaby's icon: the engine's later -setApplicationIconImage:
 *                            (the program's own window icon, unstyled) is left out, so the Dock keeps it
 *
 * A state counts as the game's when it has stood for a second: a game leaving full screen only because
 * it is closing, or a window mid-animation, is not the state to come back to. */
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#include <dispatch/dispatch.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "windowstate_core.h"

static NSString *gPath;
static NSWindow *gPrimary;           /* the game's main window: the largest one seen; held until it closes */
static NSHashTable *gTried;          /* windows a restore was tried for */
static NSMapTable *gAskedCount;      /* window -> how many times native full screen was asked for */
static NSMapTable *gAskedAt;         /* window -> when it was asked for last (seconds, monotonic) */
static NSMapTable *gFirstSeen;       /* window -> when it was first seen as a game window */
static NSMapTable *gLastChange;      /* window -> when it last changed (resized, moved to another state) */
static BOOL gSavedCovering;          /* the file says the window was a screen-covering one the engine shows in a window */
static BOOL gDumpLayers;
static uint64_t gDumpToken;
static NSHashTable *gPending;        /* windows with a native full screen check waiting */
static lbws_state gSavedState = LBWS_WINDOW;
static double gSavedW, gSavedH;      /* the Window size the file holds, 0 when unknown */
static double gWinW, gWinH;          /* the Window size now known: file's, then the player's */
static BOOL gHaveSaved, gClosing, gTerminating;
static uint64_t gToken;              /* a newer change cancels the save waiting on an older one */
static NSString *gLastWritten;

static void say(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fputs("windowstate: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}

static BOOL isGameWindow(NSWindow *w)
{
    static Class wine;
    if (!wine) wine = NSClassFromString(@"WineWindow");
    if (!wine || ![w isKindOfClass:wine]) return NO;
    NSSize s = [w contentRectForFrameRect:[w frame]].size;
    return s.width >= LBWS_MIN_W && s.height >= LBWS_MIN_H;
}

static double area(NSWindow *w) { NSSize s = [w frame].size; return s.width * s.height; }

static lbws_rect rect(NSRect r) { lbws_rect o = { r.origin.x, r.origin.y, r.size.width, r.size.height }; return o; }

static BOOL isNative(NSWindow *w) { return ([w styleMask] & NSWindowStyleMaskFullScreen) != 0; }

/* The engine shows a game's screen-covering window as a window (WineWindow.presentationWindowed). Read through
 * key-value coding, so an engine without it only loses this. */
static BOOL windowedPresentation(NSWindow *w)
{
    @try {
        id v = [w valueForKey:@"presentationWindowed"];
        return [v isKindOfClass:[NSNumber class]] && [v boolValue];
    } @catch (NSException *e) {
    }
    return NO;
}

/* Read when it is needed: the engine applies the game's env file after this library is loaded. */
static BOOL wantNative(void) { return lbws_want_native(getenv("LULLABY_NATIVE_FULLSCREEN")); }

static void load(void)
{
    @try {
        NSData *data = [NSData dataWithContentsOfFile:gPath];
        if (!data) return;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![obj isKindOfClass:[NSDictionary class]]) return;
        NSDictionary *d = obj;
        // A file somebody edited or half wrote: every field is checked for its type, none is trusted.
        id name = [d objectForKey:@"state"], width = [d objectForKey:@"width"], height = [d objectForKey:@"height"];
        lbws_state s;
        if (![name isKindOfClass:[NSString class]] || !lbws_parse([name UTF8String], &s)) return;
        gSavedState = s;
        id covering = [d objectForKey:@"covering"];
        gSavedCovering = [covering isKindOfClass:[NSNumber class]] && [covering boolValue];
        gSavedW = [width isKindOfClass:[NSNumber class]] ? [width doubleValue] : 0;
        gSavedH = [height isKindOfClass:[NSNumber class]] ? [height doubleValue] : 0;
        if (!(gSavedW >= 0 && gSavedW < 20000 && gSavedH >= 0 && gSavedH < 20000)) gSavedW = gSavedH = 0;   // also NaN
        gWinW = gSavedW;
        gWinH = gSavedH;
        gHaveSaved = YES;
        say("saved state %s, window %.0fx%.0f", lbws_name(s), gSavedW, gSavedH);
    } @catch (NSException *e) {
        say("the state file could not be read: %s", [[e reason] UTF8String]);
    }
}

static void save(void)
{
    NSWindow *w = gPrimary;
    if (!w || gClosing || ![w isVisible]) return;
    NSScreen *screen = [w screen] ?: [NSScreen mainScreen];
    lbws_state s = lbws_classify(isNative(w), ([w styleMask] & NSWindowStyleMaskTitled) != 0,
                                 rect([w frame]), rect([screen frame]));
    if (s == LBWS_WINDOW) {
        NSSize c = [w contentRectForFrameRect:[w frame]].size;
        gWinW = c.width;
        gWinH = c.height;
    }
    NSString *text = [NSString stringWithFormat:@"{\"version\":1,\"state\":\"%s\",\"width\":%.0f,\"height\":%.0f,\"covering\":%s}\n",
                      lbws_name(s), gWinW, gWinH, windowedPresentation(w) ? "true" : "false"];
    if ([text isEqualToString:gLastWritten]) return;
    NSString *dir = [gPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    if ([text writeToFile:gPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        gLastWritten = text;
        say("kept %s, window %.0fx%.0f", lbws_name(s), gWinW, gWinH);
    }
}

static void scheduleSave(void)
{
    if (gClosing) return;
    uint64_t token = ++gToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token == gToken && !gClosing) save();
    });
}

/* The size the engine believes the window has (WineWindow's wineContentSize). A size set from outside is
 * treated like a drag only when the program answers it within a second; a game still loading answers later,
 * and then the window is one size and the program's idea of it another, which shows as a cursor that reads
 * too high or too low. Read through key-value coding, so an engine without it only loses the check. */
static BOOL engineSize(NSWindow *w, NSSize *out)
{
    @try {
        id v = [w valueForKey:@"wineContentSize"];
        if ([v isKindOfClass:[NSValue class]]) {
            *out = [v sizeValue];
            return YES;
        }
    } @catch (NSException *e) {
    }
    return NO;
}

static void verifySize(NSWindow *w, double tw, double th, int attempt)
{
    if (!w || gClosing || w != gPrimary || isNative(w) || ![w isVisible]) return;
    NSSize real = [w contentRectForFrameRect:[w frame]].size, program;
    if (fabs(real.width - tw) > 2 || fabs(real.height - th) > 2) return;   /* the player resized it since */
    if (!engineSize(w, &program)) {
        say("size check: the engine's idea of the window size cannot be read");
        return;
    }
    BOOL same = fabs(real.width - program.width) < 1 && fabs(real.height - program.height) < 1;
    say("size check %d: window %.0fx%.0f, program %.0fx%.0f%s", attempt, real.width, real.height, program.width,
        program.height, same ? "" : ", differ");
    if (same || attempt >= 3) return;
    /* The game answers at once now: ask again. */
    [w setContentSize:NSMakeSize(tw + 2, th)];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [w setContentSize:NSMakeSize(tw, th)];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        verifySize(w, tw, th, attempt + 1);
    });
}

static double nowSeconds(void) { return [[NSProcessInfo processInfo] systemUptime]; }

/* Whether native full screen may be asked for this window now. A game that covers the screen is shown in a
 * window by the engine, and it can become one after the window is up: the game opens a small window first (a
 * launcher or a splash) and goes to the screen-covering one in the same window, and the engine can take the window
 * out of full screen again while it rearranges. So during the first 30 seconds it is asked again, up to three
 * times and not within 4 seconds of the last; after that a way out of full screen is the player's. */
static BOOL mayAsk(NSWindow *w)
{
    double now = nowSeconds();
    if (![gFirstSeen objectForKey:w]) [gFirstSeen setObject:@(now) forKey:w];
    int count = [[gAskedCount objectForKey:w] intValue];
    if (count == 0) return YES;
    if (count >= 3) return NO;
    if (now - [[gFirstSeen objectForKey:w] doubleValue] > 30.0) return NO;
    return now - [[gAskedAt objectForKey:w] doubleValue] >= 4.0;
}

static void noteAsked(NSWindow *w)
{
    [gAskedCount setObject:@([[gAskedCount objectForKey:w] intValue] + 1) forKey:w];
    [gAskedAt setObject:@(nowSeconds()) forKey:w];
}

static void autoFullscreen(NSWindow *w, int attempt)
{
    if (!w || gClosing || ![w isVisible] || !mayAsk(w)) return;
    /* While the game is still rearranging its window (a resize a moment ago) the window is left alone: asking in
     * the middle of it is what takes the window out of full screen again, and each round trip costs the size
     * the game is told one title bar (32 points). */
    NSNumber *last = [gLastChange objectForKey:w];
    double quiet = last ? nowSeconds() - [last doubleValue] : 99;
    if (quiet < 2.0 && windowedPresentation(w) && wantNative()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((2.0 - quiet + 0.1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            autoFullscreen(w, attempt);
        });
        return;
    }
    BOOL canNative = ([w collectionBehavior] & NSWindowCollectionBehaviorFullScreenPrimary) != 0;
    switch (lbws_plan_fullscreen(windowedPresentation(w), wantNative(), isNative(w), canNative)) {
    case LBWS_FS_ENTER:
        noteAsked(w);
        say("native fullscreen, as the game's setting says");
        [w toggleFullScreen:nil];
        break;
    case LBWS_FS_WAIT:
        if (attempt < 4)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                autoFullscreen(w, attempt + 1);
            });
        break;
    default:
        break;
    }
}

static void scheduleAutoFullscreen(NSWindow *w)
{
    if (!w || [gPending containsObject:w] || !windowedPresentation(w) || !wantNative() || !mayAsk(w)) return;
    [gPending addObject:w];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [gPending removeObject:w];
        autoFullscreen(w, 0);
    });
}

static void tryRestore(NSWindow *w, int attempt)
{
    if (!w || gClosing || ![w isVisible]) return;
    BOOL presentation = windowedPresentation(w);
    if (!gHaveSaved && !presentation) return;
    BOOL now = isNative(w);
    BOOL canNative = ([w collectionBehavior] & NSWindowCollectionBehaviorFullScreenPrimary) != 0;
    BOOL resizable = ([w styleMask] & NSWindowStyleMaskResizable) != 0;
    NSSize cur = [w contentRectForFrameRect:[w frame]].size;
    lbws_state saved = gSavedState;
    /* The file says the game's window was a screen-covering one in full screen; this one is not (a launcher or a
     * splash first): native full screen is for the covering window when it comes. */
    if (!presentation && gSavedCovering && saved == LBWS_NATIVE) {
        say("a saved native full screen is kept for the screen-covering window, not this one");
        return;
    }
    if (presentation) {
        /* A game that covers the screen: the switch decides, not the state it was left in. */
        if (wantNative()) {
            autoFullscreen(w, 0);
            return;
        }
        if (saved == LBWS_NATIVE) saved = LBWS_WINDOW;   /* the setting keeps it in the window */
        if (!gHaveSaved) return;
    }
    lbws_plan p = lbws_plan_restore(saved, gSavedW, gSavedH, now, canNative, resizable, cur.width, cur.height);
    switch (p.action) {
    case LBWS_SET_SIZE: {
        say("window back to %.0fx%.0f (was %.0fx%.0f)", p.w, p.h, cur.width, cur.height);
        [w setContentSize:NSMakeSize(p.w, p.h)];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            verifySize(w, p.w, p.h, 0);
        });
        break;
    }
    case LBWS_ENTER_NATIVE:
        say("native fullscreen back");
        noteAsked(w);   /* the window is on its way to full screen: a second toggle at once would take it out again */
        [w toggleFullScreen:nil];
        break;
    default:
        /* Wine sets a window's full-screen behaviour a moment after it shows it. */
        if (gSavedState == LBWS_NATIVE && !now && !canNative && attempt < 4)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                tryRestore(w, attempt + 1);
            });
        break;
    }
}

/* A window whose picture comes from a renderer's own Metal view (WineMetalGL) never has the engine's windowDidDrawContent
   called, so it stays in the clear, non-opaque state it is created in and its title bar is see-through. The engine's own
   checkTransparency (what windowDidDrawContent starts) makes it opaque again unless it really needs transparency. */
static void settleTitlebar(NSWindow *w)
{
    SEL check = NSSelectorFromString(@"checkTransparency");
    if (![w respondsToSelector:check] || !([w styleMask] & NSWindowStyleMaskTitled)) return;
    for (NSNumber *t in @[@0.5, @2, @6])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([t doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (![w isOpaque] && [w isVisible]) {
                ((void (*)(id, SEL))objc_msgSend)(w, check);
                if ([w isOpaque]) say("title bar: window made opaque (its renderer never drew through the engine)");
            }
        });
}

static void becameMain(NSWindow *w)
{
    Class wine = NSClassFromString(@"WineWindow");
    if (wine && [w isKindOfClass:wine]) settleTitlebar(w);
    if (!isGameWindow(w)) return;
    scheduleAutoFullscreen(w);
    /* A window that only later becomes the screen-covering one, with no notification the library hears. */
    for (NSNumber *t in @[@2, @4, @8, @15, @30])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([t doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            scheduleAutoFullscreen(w);
        });
    if (!gPrimary || area(w) >= area(gPrimary)) {
        gPrimary = w;
        if (!gTerminating) gClosing = NO;   /* a game that makes a new main window after closing one */
    }
    if ([gTried containsObject:w]) return;
    [gTried addObject:w];
    /* After the engine has laid the window out. */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        tryRestore(w, 0);
    });
}

/* The layer tree of a game window, to find where a layer stands that the engine's frames say should be elsewhere. */
static void dumpLayer(CALayer *l, int depth)
{
    CATransform3D t = [l transform];
    NSString *extra = @"";
    if ([NSStringFromClass([l class]) containsString:@"Host"]) {
        @try { extra = [NSString stringWithFormat:@" contextId=%@", [l valueForKey:@"contextId"]]; } @catch (NSException *e) {}
    }
    say("layer %*s%s frame=%s bounds=%s position=%s anchor=%s transform=[a %.3f d %.3f tx %.1f ty %.1f]%s", depth * 2, "",
        [NSStringFromClass([l class]) UTF8String], [NSStringFromRect(NSRectFromCGRect([l frame])) UTF8String],
        [NSStringFromRect(NSRectFromCGRect([l bounds])) UTF8String], [NSStringFromPoint(NSPointFromCGPoint([l position])) UTF8String],
        [NSStringFromPoint(NSPointFromCGPoint([l anchorPoint])) UTF8String], t.m11, t.m22, t.m41, t.m42, [extra UTF8String]);
    if (depth < 6) for (CALayer *s in [l sublayers]) dumpLayer(s, depth + 1);
}

static void dumpWindow(NSWindow *w)
{
    say("layer dump of a window, frame %s, content view frame %s, native %d", [NSStringFromRect([w frame]) UTF8String],
        [NSStringFromRect([[w contentView] frame]) UTF8String], (int)isNative(w));
    CALayer *root = [[w contentView] layer];
    if (root) dumpLayer(root, 0);
}

/* After the window changes (full screen entered or left, a resize) the engine's own layout of the scaled picture is
 * asked for once more. The engine lays the picture out at its box (scaled, centred) on every change it hears of, and
 * the layer log shows the box right; but the content view then stands at x = 0 instead of the box's x: a move of the
 * view that came after the engine's layout (AppKit's resizing of the window's views while the full-screen animation
 * ends) and that nothing laid out again, so the picture sits at the left with the empty strip on the right and the
 * pointer, which follows the box, is off by the same amount. The method is the engine's (WineWindow
 * layoutPresentation); a window or an engine without it is left alone. */
static NSHashTable *gRelayoutPending;

static void relayout(NSWindow *w)
{
    SEL layout = NSSelectorFromString(@"layoutPresentation");
    if (!w || gClosing || ![w isVisible] || ![w respondsToSelector:layout] || !windowedPresentation(w)) return;
    NSView *content = nil;
    @try { content = [w valueForKey:@"wineContentView"]; } @catch (NSException *e) {}
    NSRect before = content ? [content frame] : NSZeroRect;
    ((void (*)(id, SEL))objc_msgSend)(w, layout);
    NSRect after = content ? [content frame] : NSZeroRect;
    if (!NSEqualRects(before, after))
        say("the picture's layout put back: x %.1f -> %.1f, width %.1f -> %.1f", before.origin.x, after.origin.x,
            before.size.width, after.size.width);
}

static void scheduleRelayout(NSWindow *w)
{
    if (!w || [gRelayoutPending containsObject:w] || !windowedPresentation(w)) return;
    [gRelayoutPending addObject:w];
    for (NSNumber *t in @[@0.4, @1.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([t doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            relayout(w);
            if ([t doubleValue] > 1.0) [gRelayoutPending removeObject:w];
        });
    }
}

static void changed(NSWindow *w)
{
    if (!isGameWindow(w)) return;
    if (!gPrimary) gPrimary = w;
    [gLastChange setObject:@(nowSeconds()) forKey:w];
    scheduleRelayout(w);
    if (gDumpLayers && w == gPrimary) {
        uint64_t token = ++gDumpToken;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (token == gDumpToken) dumpWindow(w);
        });
    }
    scheduleAutoFullscreen(w);
    if (w == gPrimary) scheduleSave();
}

/* The engine sets the Dock icon from the program's window icon once the window is up, over the bundle's own.
 * With a styled icon in the bundle that would swap it for a plainer, often smaller one. */
static void keepBundleIcon(void)
{
    Method m = class_getInstanceMethod([NSApplication class], @selector(setApplicationIconImage:));
    if (!m) return;
    IMP ignore = imp_implementationWithBlock(^(id self, NSImage *image) {
        (void)self;
        (void)image;
        say("the program's own icon left out of the Dock");
    });
    method_setImplementation(m, ignore);
}

/* WineMetalGL never clears the colour texture it makes for a window ("default framebuffer", private storage), at the
   start and when the window changes size. A game that swaps before it has drawn (a loading screen) shows whatever the
   GPU's memory held: a flat magenta rectangle at the switch to native full screen. The texture gets its label the
   moment it is made, so a texture given that label is cleared to black at once, before WineMetalGL copies the old
   picture into it. Only in a process that runs WineMetalGL; LULLABY_GL_CLEAR=0 turns it off. */
static IMP gOrigSetLabel;

static void clearToBlack(id<MTLTexture> texture)
{
    static id<MTLCommandQueue> queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = [[texture device] newCommandQueue]; });
    if (!queue || !(texture.usage & MTLTextureUsageRenderTarget)) return;
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLCommandBuffer> buffer = [queue commandBuffer];
    [[buffer renderCommandEncoderWithDescriptor:pass] endEncoding];
    [buffer commit];
    [buffer waitUntilCompleted];   /* before WineMetalGL's own commands touch the texture */
}

static void labelHook(id self, SEL _cmd, NSString *label)
{
    ((void (*)(id, SEL, NSString *))gOrigSetLabel)(self, _cmd, label);
    if ([label isEqualToString:@"default framebuffer"] && [self conformsToProtocol:@protocol(MTLTexture)])
        clearToBlack((id<MTLTexture>)self);
}

static void zeroDefaultFramebuffers(void)
{
    const char *off = getenv("LULLABY_GL_CLEAR"), *over = getenv("WINEDLLOVERRIDES");
    if ((off && !strcmp(off, "0")) || !over || !strstr(over, "winemetalgl")) return;
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return;
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
    d.storageMode = MTLStorageModePrivate;
    d.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> probe = [device newTextureWithDescriptor:d];
    Method m = probe ? class_getInstanceMethod(object_getClass(probe), @selector(setLabel:)) : NULL;
    if (!m) return;
    gOrigSetLabel = method_getImplementation(m);
    method_setImplementation(m, (IMP)labelHook);
    say("WineMetalGL: new window textures are cleared to black");
}

__attribute__((constructor)) static void lbws_init(void)
{
    const char *name = getprogname();
    if (!name || strncmp(name, "wine", 4) || !strcmp(name, "wineserver")) return;   /* the Wine loader's processes only */
    zeroDefaultFramebuffers();
    const char *keep = getenv("LULLABY_KEEP_BUNDLE_ICON");
    if (keep && !strcmp(keep, "1")) keepBundleIcon();
    const char *off = getenv("LULLABY_WINDOW_STATE");
    const char *file = getenv("LULLABY_WINDOW_STATE_FILE");
    if ((off && !strcmp(off, "0")) || !file || !*file) return;
    gPath = [NSString stringWithUTF8String:file];
    gTried = [NSHashTable weakObjectsHashTable];
    gDumpLayers = (getenv("LULLABY_LAYER_DUMP") && !strcmp(getenv("LULLABY_LAYER_DUMP"), "1")) ||
                  [[NSFileManager defaultManager] fileExistsAtPath:[[gPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"layer-dump"]];
    gAskedCount = [NSMapTable weakToStrongObjectsMapTable];
    gAskedAt = [NSMapTable weakToStrongObjectsMapTable];
    gFirstSeen = [NSMapTable weakToStrongObjectsMapTable];
    gLastChange = [NSMapTable weakToStrongObjectsMapTable];
    gRelayoutPending = [NSHashTable weakObjectsHashTable];
    gPending = [NSHashTable weakObjectsHashTable];
    load();

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    void (^onMain)(NSNotification *) = ^(NSNotification *n) { becameMain([n object]); };
    void (^onChange)(NSNotification *) = ^(NSNotification *n) { changed([n object]); };
    [nc addObserverForName:NSWindowDidBecomeMainNotification object:nil queue:nil usingBlock:onMain];
    for (NSNotificationName n in @[NSWindowDidEnterFullScreenNotification, NSWindowDidExitFullScreenNotification,
                                   NSWindowDidResizeNotification, NSWindowDidEndLiveResizeNotification])
        [nc addObserverForName:n object:nil queue:nil usingBlock:onChange];
    /* The close of the game's window, or of the app, is not a state to keep: what follows it
       (leaving full screen, shrinking) is the game going away. */
    [nc addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        if ([n object] == gPrimary) {
            gClosing = YES;
            gPrimary = nil;
        }
    }];
    [nc addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        (void)n;
        gClosing = gTerminating = YES;
    }];
    say("watching, state file %s", file);
}
