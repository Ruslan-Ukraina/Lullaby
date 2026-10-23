/* The injected library in a process that has a "WineWindow": the state it keeps and puts back.
 * The window is shown off screen; the notifications AppKit would send are posted by hand, so the
 * test needs no active app. Native fullscreen is not entered here (it would take the screen); its
 * decision is in core_test.c.
 *
 *   wine-windowstate-test save FILE W H      resize to WxH, leave, and expect the file to say so
 *   wine-windowstate-test restore FILE W H   a 640x480 window must come back to WxH
 *   wine-windowstate-test late FILE 1 0      the window is an ordinary one first (a launcher) and becomes the screen-covering one
 *                                            later, in the same window: native full screen is asked for once, then
 *   wine-windowstate-test relayout FILE 1 0  the engine's layout of the picture is asked for again after the window changes, only for a covering window
 *   wine-windowstate-test launcher FILE 1 0  the file says native full screen was a screen-covering window's state, this window is a launcher: left alone
 *   wine-windowstate-test retry FILE 1 0     the window is knocked out of full screen (the stub never enters it): asked again after a
 *                                            few seconds, not at once, and not more than the limit
 *   wine-windowstate-test both FILE 1 0      the file says native and the window is the screen-covering one: one toggle, not two
 *   wine-windowstate-test fullscreen FILE 1|0   a screen-covering game's window (presentationWindowed): with the
 *                                            switch 1 the library asks for native full screen once, with 0 never
 * LULLABY_WINDOWSTATE_DYLIB names the library; the program's name starts with "wine" like the loader's. */
#import <AppKit/AppKit.h>
#include <dlfcn.h>

static int gToggles, gRelayouts;

@interface WineWindow : NSWindow
@property (readonly) BOOL presentationWindowed;
@end
@implementation WineWindow
- (BOOL)presentationWindowed { return getenv("LBWS_TEST_PRESENTATION") != NULL; }
- (void)layoutPresentation { gRelayouts++; }          /* the engine's own layout of the scaled picture */
- (void)toggleFullScreen:(id)sender { gToggles++; }   /* not entered: it would take the screen */
@end

static void spin(double seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc < 5) { fprintf(stderr, "usage: save|restore FILE W H\n"); return 2; }
        const char *phase = argv[1];
        double w = atof(argv[3]), h = atof(argv[4]);
        setenv("LULLABY_WINDOW_STATE_FILE", argv[2], 1);
        if (!strcmp(phase, "launcher"))
            [@"{\"version\":1,\"state\":\"native\",\"width\":960,\"height\":540,\"covering\":true}\n" writeToFile:[NSString stringWithUTF8String:argv[2]]
                atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if (!strcmp(phase, "both"))
            [@"{\"version\":1,\"state\":\"native\",\"width\":960,\"height\":540}\n" writeToFile:[NSString stringWithUTF8String:argv[2]]
                atomically:YES encoding:NSUTF8StringEncoding error:nil];
        const char *dylib = getenv("LULLABY_WINDOWSTATE_DYLIB");
        if (!dylib || !dlopen(dylib, RTLD_NOW)) { fprintf(stderr, "no library: %s\n", dlerror()); return 3; }

        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSWindow *win = [[WineWindow alloc] initWithContentRect:NSMakeRect(-20000, -20000, 640, 480)
                                                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                        backing:NSBackingStoreBuffered defer:NO];
        if (!strcmp(phase, "both")) {
            setenv("LBWS_TEST_PRESENTATION", "1", 1);
            setenv("LULLABY_NATIVE_FULLSCREEN", "1", 1);
            [win setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
        }
        if (!strcmp(phase, "fullscreen")) {
            setenv("LBWS_TEST_PRESENTATION", "1", 1);
            setenv("LULLABY_NATIVE_FULLSCREEN", argv[3], 1);
            [win setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
        }
        [win orderFrontRegardless];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc postNotificationName:NSWindowDidBecomeMainNotification object:win];
        if (!strcmp(phase, "retry")) {
            setenv("LBWS_TEST_PRESENTATION", "1", 1);
            setenv("LULLABY_NATIVE_FULLSCREEN", "1", 1);
            [win setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
            spin(2.5);
            BOOL first = gToggles == 1;                         /* asked once, and not again within 4 seconds */
            spin(7.5);                                          /* the 8 second check asks again */
            BOOL ok = first && gToggles == 2;
            printf("%s: knocked out of full screen: %d request(s) in 10 s, wanted 2 (one at once, one after the pause)\n",
                   ok ? "ok" : "FAIL", gToggles);
            return ok ? 0 : 1;
        }
        if (!strcmp(phase, "both")) {
            spin(3.0);
            BOOL ok = gToggles == 1;
            printf("%s: the saved state and the setting both say native full screen: %d toggle(s), wanted 1\n",
                   ok ? "ok" : "FAIL", gToggles);
            return ok ? 0 : 1;
        }
        if (!strcmp(phase, "late")) {
            setenv("LULLABY_NATIVE_FULLSCREEN", "1", 1);
            [win setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
            spin(1.5);
            BOOL early = gToggles == 0;                         /* an ordinary window is left alone */
            setenv("LBWS_TEST_PRESENTATION", "1", 1);           /* the game goes to its screen-covering window */
            [win setContentSize:NSMakeSize(1200, 700)];
            [nc postNotificationName:NSWindowDidResizeNotification object:win];
            spin(1.0);
            BOOL waited = gToggles == 0;                        /* the window was resized a moment ago: left alone while it settles */
            spin(2.2);
            BOOL asked = gToggles == 1;
            for (int i = 0; i < 2; i++) {                       /* more changes after: not asked again within the pause */
                [nc postNotificationName:NSWindowDidResizeNotification object:win];
                spin(0.6);
            }
            BOOL ok = early && waited && asked && gToggles == 1;
            printf("%s: ordinary window left alone %d, waited while resizing %d, asked once %d (toggles %d)\n",
                   ok ? "ok" : "FAIL", early, waited, asked, gToggles);
            return ok ? 0 : 1;
        }
        if (!strcmp(phase, "relayout")) {
            setenv("LULLABY_NATIVE_FULLSCREEN", "0", 1);        /* only the layout is under test: no full screen is asked for */
            setenv("LBWS_TEST_PRESENTATION", "1", 1);
            spin(0.5);
            int before = gRelayouts;
            [nc postNotificationName:NSWindowDidEnterFullScreenNotification object:win];
            spin(2.2);
            BOOL asked = gRelayouts > before;
            unsetenv("LBWS_TEST_PRESENTATION");                 /* an ordinary window: the engine's layout is not touched */
            before = gRelayouts;
            [nc postNotificationName:NSWindowDidResizeNotification object:win];
            spin(2.2);
            BOOL ok = asked && gRelayouts == before;
            printf("%s: layout asked for after a change of a covering window %d, an ordinary window left alone %d\n",
                   ok ? "ok" : "FAIL", asked, gRelayouts == before);
            return ok ? 0 : 1;
        }
        if (!strcmp(phase, "launcher")) {
            /* The file says native full screen was the state of a screen-covering window: an ordinary (launcher) window is not put there. */
            spin(3.0);
            BOOL ok = gToggles == 0;
            printf("%s: a saved covering-window state does not take a launcher window to full screen (%d toggle(s))\n",
                   ok ? "ok" : "FAIL", gToggles);
            return ok ? 0 : 1;
        }
        if (!strcmp(phase, "fullscreen")) {
            spin(2.5);
            [nc postNotificationName:NSWindowDidBecomeMainNotification object:win];   /* the window becomes main again */
            spin(1.5);
            int want = atoi(argv[3]) ? 1 : 0;
            BOOL ok = gToggles == want;
            printf("%s: the switch %s, native full screen asked for %d time(s), wanted %d\n", ok ? "ok" : "FAIL", argv[3],
                   gToggles, want);
            return ok ? 0 : 1;
        }
        if (!strcmp(phase, "damaged")) {
            // The state file holds the wrong types: the library must come up and leave the window alone.
            spin(2.0);
            NSSize c = [win contentRectForFrameRect:[win frame]].size;
            BOOL ok = c.width == 640 && c.height == 480;
            printf("%s: a damaged file leaves the window at %.0fx%.0f\n", ok ? "ok" : "FAIL", c.width, c.height);
            return ok ? 0 : 1;
        }
        if (!strcmp(phase, "save")) {
            spin(0.3);
            /* Several changes with a save after each, the autorelease pool drained between them: what the library
               keeps in its statics has to outlive a pool (a second save once read a freed string). */
            for (int i = 0; i < 3; i++) {
                @autoreleasepool {
                    [win setContentSize:NSMakeSize(w - 100 + i * 50, h - 60 + i * 30)];
                    [nc postNotificationName:NSWindowDidResizeNotification object:win];
                    spin(1.4);
                }
            }
            [win setContentSize:NSMakeSize(w, h)];
            [nc postNotificationName:NSWindowDidResizeNotification object:win];
            spin(1.8);
            NSData *d = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
            id o = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
            BOOL ok = [o isKindOfClass:[NSDictionary class]] && [[o objectForKey:@"state"] isEqual:@"window"] &&
                      [[o objectForKey:@"width"] doubleValue] == w && [[o objectForKey:@"height"] doubleValue] == h;
            printf("%s: saved %s\n", ok ? "ok" : "FAIL", d ? (const char *)[[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] UTF8String] : "nothing");
            return ok ? 0 : 1;
        }
        spin(2.0);
        NSSize c = [win contentRectForFrameRect:[win frame]].size;
        BOOL ok = c.width == w && c.height == h;
        printf("%s: window is %.0fx%.0f, wanted %.0fx%.0f\n", ok ? "ok" : "FAIL", c.width, c.height, w, h);
        return ok ? 0 : 1;
    }
}
