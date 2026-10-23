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
 *
 * A state counts as the game's when it has stood for a second: a game leaving full screen only because
 * it is closing, or a window mid-animation, is not the state to come back to. */
#import <AppKit/AppKit.h>
#include <dispatch/dispatch.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "windowstate_core.h"

static NSString *gPath;
static NSWindow *gPrimary;           /* the game's main window: the largest one seen; held until it closes */
static NSHashTable *gTried;          /* windows a restore was tried for */
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

static void load(void)
{
    NSData *data = [NSData dataWithContentsOfFile:gPath];
    if (!data) return;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *d = obj;
    lbws_state s;
    if (!lbws_parse([[d objectForKey:@"state"] UTF8String], &s)) return;
    gSavedState = s;
    gSavedW = [[d objectForKey:@"width"] doubleValue];
    gSavedH = [[d objectForKey:@"height"] doubleValue];
    gWinW = gSavedW;
    gWinH = gSavedH;
    gHaveSaved = YES;
    say("saved state %s, window %.0fx%.0f", lbws_name(s), gSavedW, gSavedH);
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
    NSString *text = [NSString stringWithFormat:@"{\"version\":1,\"state\":\"%s\",\"width\":%.0f,\"height\":%.0f}\n",
                      lbws_name(s), gWinW, gWinH];
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

static void tryRestore(NSWindow *w, int attempt)
{
    if (!w || gClosing || ![w isVisible] || !gHaveSaved) return;
    BOOL now = isNative(w);
    BOOL canNative = ([w collectionBehavior] & NSWindowCollectionBehaviorFullScreenPrimary) != 0;
    BOOL resizable = ([w styleMask] & NSWindowStyleMaskResizable) != 0;
    NSSize cur = [w contentRectForFrameRect:[w frame]].size;
    lbws_plan p = lbws_plan_restore(gSavedState, gSavedW, gSavedH, now, canNative, resizable, cur.width, cur.height);
    switch (p.action) {
    case LBWS_SET_SIZE:
        say("window back to %.0fx%.0f (was %.0fx%.0f)", p.w, p.h, cur.width, cur.height);
        [w setContentSize:NSMakeSize(p.w, p.h)];
        break;
    case LBWS_ENTER_NATIVE:
        say("native fullscreen back");
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

static void becameMain(NSWindow *w)
{
    if (!isGameWindow(w)) return;
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

static void changed(NSWindow *w)
{
    if (!isGameWindow(w)) return;
    if (!gPrimary) gPrimary = w;
    if (w == gPrimary) scheduleSave();
}

__attribute__((constructor)) static void lbws_init(void)
{
    const char *name = getprogname();
    if (!name || strncmp(name, "wine", 4) || !strcmp(name, "wineserver")) return;   /* the Wine loader's processes only */
    const char *off = getenv("LULLABY_WINDOW_STATE");
    const char *file = getenv("LULLABY_WINDOW_STATE_FILE");
    if ((off && !strcmp(off, "0")) || !file || !*file) return;
    gPath = [NSString stringWithUTF8String:file];
    gTried = [NSHashTable weakObjectsHashTable];
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
