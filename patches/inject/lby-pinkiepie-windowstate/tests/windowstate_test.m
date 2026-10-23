/* The injected library in a process that has a "WineWindow": the state it keeps and puts back.
 * The window is shown off screen; the notifications AppKit would send are posted by hand, so the
 * test needs no active app. Native fullscreen is not entered here (it would take the screen); its
 * decision is in core_test.c.
 *
 *   wine-windowstate-test save FILE W H      resize to WxH, leave, and expect the file to say so
 *   wine-windowstate-test restore FILE W H   a 640x480 window must come back to WxH
 * LULLABY_WINDOWSTATE_DYLIB names the library; the program's name starts with "wine" like the loader's. */
#import <AppKit/AppKit.h>
#include <dlfcn.h>

@interface WineWindow : NSWindow
@end
@implementation WineWindow
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
        const char *dylib = getenv("LULLABY_WINDOWSTATE_DYLIB");
        if (!dylib || !dlopen(dylib, RTLD_NOW)) { fprintf(stderr, "no library: %s\n", dlerror()); return 3; }

        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSWindow *win = [[WineWindow alloc] initWithContentRect:NSMakeRect(-20000, -20000, 640, 480)
                                                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                        backing:NSBackingStoreBuffered defer:NO];
        [win orderFrontRegardless];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc postNotificationName:NSWindowDidBecomeMainNotification object:win];
        if (!strcmp(phase, "save")) {
            spin(0.3);
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
