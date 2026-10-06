// Native macOS chrome for Steam's windows (docs/BACKLOG.md 15, DECISIONS W1).
//
// Steam's windows belong to the CEF browser process, Steam Helper without a
// --type= argument, which loads this dylib through the inherited
// DYLD_INSERT_LIBRARIES. Steam creates them with SDL3 (class SDL3Window) as
// borderless windows and draws its own title row, traffic lights included.
// Everything here is public AppKit reached through the Objective-C runtime, no
// byte signatures, so a Steam update cannot shift it.
//
// The switch is notproton/steam-windows (steamwin_css.h):
//   off     nothing at all happens (Steam as shipped)
//   log     every window is described in notproton.log, none is changed
//   native  real windows get the macOS frame: title bar with traffic lights over
//           Steam's own row, rounded corners, system shadow, full screen, Stage
//           Manager, tiling. Menus, tooltips and dropdowns are left alone.

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#include "steamwin.h"
#include "steamwin_css.h"
#include "../util/file.h"
#include "../util/log.h"

#include <string.h>
#include <unistd.h>

static np_steamwin_mode_t g_mode = NP_SW_OFF;

int np_steamwin_is_browser_process(int argc, const char **argv) {
    const char *pn = getprogname();
    if (!pn || strcmp(pn, "Steam Helper") != 0)
        return 0;
    for (int i = 1; i < argc && argv && argv[i]; i++)
        if (strncmp(argv[i], "--type=", 7) == 0)
            return 0;
    return 1;
}

// MARK: Description

static NSString *class_chain(id object) {
    NSMutableArray *names = [NSMutableArray array];
    for (Class c = object_getClass(object); c && c != [NSObject class]; c = class_getSuperclass(c))
        [names addObject:NSStringFromClass(c)];
    return [names componentsJoinedByString:@" < "];
}

static NSString *behavior_names(NSWindowCollectionBehavior b) {
    static const struct { NSWindowCollectionBehavior bit; const char *name; } names[] = {
        {NSWindowCollectionBehaviorCanJoinAllSpaces, "canJoinAllSpaces"},
        {NSWindowCollectionBehaviorMoveToActiveSpace, "moveToActiveSpace"},
        {NSWindowCollectionBehaviorManaged, "managed"},
        {NSWindowCollectionBehaviorTransient, "transient"},
        {NSWindowCollectionBehaviorStationary, "stationary"},
        {NSWindowCollectionBehaviorParticipatesInCycle, "participatesInCycle"},
        {NSWindowCollectionBehaviorIgnoresCycle, "ignoresCycle"},
        {NSWindowCollectionBehaviorFullScreenPrimary, "fullScreenPrimary"},
        {NSWindowCollectionBehaviorFullScreenAuxiliary, "fullScreenAuxiliary"},
        {NSWindowCollectionBehaviorFullScreenNone, "fullScreenNone"},
        {NSWindowCollectionBehaviorFullScreenAllowsTiling, "allowsTiling"},
        {NSWindowCollectionBehaviorFullScreenDisallowsTiling, "disallowsTiling"},
        {NSWindowCollectionBehaviorPrimary, "primary"},
        {NSWindowCollectionBehaviorAuxiliary, "auxiliary"},
        {NSWindowCollectionBehaviorCanJoinAllApplications, "canJoinAllApplications"},
    };
    NSMutableArray *out = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++)
        if (b & names[i].bit)
            [out addObject:@(names[i].name)];
    return out.count ? [out componentsJoinedByString:@"|"] : @"default";
}

static const char *policy_name(NSApplicationActivationPolicy p) {
    switch (p) {
        case NSApplicationActivationPolicyRegular: return "regular";
        case NSApplicationActivationPolicyAccessory: return "accessory";
        case NSApplicationActivationPolicyProhibited: return "prohibited";
    }
    return "?";
}

// What decides how a window behaves with Spaces, Stage Manager and the Dock.
static NSString *describe_spaces(NSWindow *w) {
    return [NSString stringWithFormat:
        @"%p \"%@\" level=%ld behavior=[%@] floatingPanel=%d hidesOnDeactivate=%d onActiveSpace=%d "
        @"canHide=%d excludedFromWindowsMenu=%d visible=%d",
        w, w.title ?: @"", (long)w.level, behavior_names(w.collectionBehavior),
        [w isKindOfClass:[NSPanel class]] ? ((NSPanel *)w).isFloatingPanel : -1,
        w.hidesOnDeactivate, w.isOnActiveSpace, w.canHide, w.isExcludedFromWindowsMenu, w.isVisible];
}

static NSString *describe(NSWindow *w) {
    NSRect f = w.frame;
    NSView *content = w.contentView;
    return [NSString stringWithFormat:
        @"%p class=[%@] style=0x%lx level=%ld behavior=0x%lx frame=%.0fx%.0f@%.0f,%.0f "
        @"visible=%d key=%d main=%d opaque=%d shadow=%d alpha=%.2f canKey=%d canMain=%d "
        @"parent=%p children=%lu sheet=%d panel=%d mini=%d minButton=%d title=\"%@\" content=[%@] subviews=%lu",
        w, class_chain(w), (unsigned long)w.styleMask, (long)w.level,
        (unsigned long)w.collectionBehavior, f.size.width, f.size.height, f.origin.x, f.origin.y,
        w.isVisible, w.isKeyWindow, w.isMainWindow, w.isOpaque, w.hasShadow, w.alphaValue,
        w.canBecomeKeyWindow, w.canBecomeMainWindow, w.parentWindow,
        (unsigned long)w.childWindows.count, w.isSheet, [w isKindOfClass:[NSPanel class]],
        w.isMiniaturized, [w standardWindowButton:NSWindowMiniaturizeButton].isEnabled,
        w.title ?: @"", content ? class_chain(content) : @"none",
        (unsigned long)content.subviews.count];
}

// MARK: Which windows

static Class g_sdl_window;

static BOOL is_sdl(NSWindow *w) {
    return g_sdl_window && [w isKindOfClass:g_sdl_window];
}

// A window a person moves, resizes and switches to: it can be main, has no parent,
// takes part in window cycling and sits at the normal level. Menus, dropdowns and
// tooltips are child windows that cannot become main and ignore cycling.
static BOOL is_real_window(NSWindow *w) {
    return is_sdl(w) && w.canBecomeMainWindow && w.parentWindow == nil
        && !(w.collectionBehavior & NSWindowCollectionBehaviorIgnoresCycle)
        && w.level == NSNormalWindowLevel;
}

// SDL full screen (not the macOS Space kind) is a borderless window over the
// whole screen; Big Picture is one. A frame there would cover the menu bar.
static BOOL is_sdl_fullscreen(NSWindow *w) {
    NSScreen *screen = w.screen;
    return screen && NSEqualRects(w.frame, screen.frame)
        && !(w.styleMask & NSWindowStyleMaskFullScreen);
}

static const NSWindowStyleMask NP_FRAME =
    NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskFullSizeContentView;

// The bits this window gets on top of SDL's, kept with the window. A dialog
// (About, sign-in, shutting down) is a window Steam made fixed-size (no
// Resizable); Valve draws only a close button on those, so the native frame
// shows only that one too.
static const void *const NP_MANAGED = &NP_MANAGED;

static NSWindowStyleMask added_bits(NSWindow *w) {
    return [objc_getAssociatedObject(w, NP_MANAGED) unsignedIntegerValue];
}

static BOOL is_managed(NSWindow *w) {
    return added_bits(w) != 0;
}

static void set_managed(NSWindow *w, NSWindowStyleMask bits) {
    objc_setAssociatedObject(w, NP_MANAGED, bits ? @(bits) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL is_dialog(NSWindowStyleMask sdl_style) {
    return !(sdl_style & NSWindowStyleMaskResizable);
}

// MARK: Chrome

// Steam's title row centres its buttons 20 pt from the top; the bare title bar
// puts the traffic lights at 16. An empty unified-compact toolbar is the supported
// way to get the 40 pt title bar that centres them at 20 (the choice Sevoflurane
// makes too). Clicks still reach Steam: the toolbar is empty. In full screen
// AppKit moves the toolbar into a strip of its own over the top of the window,
// which would cover Steam's row, so it is taken off there and put back after.
static void set_toolbar(NSWindow *w, BOOL on) {
    if (on && !w.toolbar) {
        w.toolbar = [[NSToolbar alloc] initWithIdentifier:@"notproton.steam"];
        w.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;
    } else if (!on && [w.toolbar.identifier isEqualToString:@"notproton.steam"]) {
        w.toolbar = nil;
    }
}

// The original -[NSWindow setStyleMask:], so applying the frame does not go
// through the guard below.
static void (*g_set_style)(id, SEL, NSWindowStyleMask);

// SDL's own full screen (Big Picture) is the one style SDL sets with none of
// Titled, Miniaturizable or Resizable: a bare borderless window it then stretches
// over the screen. That window is released and framed again once SDL makes it a
// window once more.
static BOOL is_sdl_fullscreen_style(NSWindowStyleMask mask) {
    return !(mask & (NSWindowStyleMaskTitled | NSWindowStyleMaskMiniaturizable
                     | NSWindowStyleMaskResizable | NSWindowStyleMaskFullScreen));
}

// A standard window's place in Spaces, Mission Control, Stage Manager and the
// window cycle: managed and cycling, full screen as a primary window (dialogs keep
// FullScreenNone), and none of the flags that pin a window to every Space or let it
// float over other apps' full-screen Spaces.
static NSWindowCollectionBehavior standard_behavior(NSWindowCollectionBehavior b) {
    b &= ~(NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorMoveToActiveSpace
           | NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorStationary
           | NSWindowCollectionBehaviorIgnoresCycle | NSWindowCollectionBehaviorFullScreenAuxiliary
           | NSWindowCollectionBehaviorCanJoinAllApplications | NSWindowCollectionBehaviorAuxiliary);
    b |= NSWindowCollectionBehaviorManaged | NSWindowCollectionBehaviorParticipatesInCycle;
    if (!(b & NSWindowCollectionBehaviorFullScreenNone))
        b |= NSWindowCollectionBehaviorFullScreenPrimary;
    return b;
}

static void (*g_set_behavior)(id, SEL, NSWindowCollectionBehavior);

static void apply_chrome(NSWindow *w) {
    if (is_managed(w) || !is_real_window(w) || is_sdl_fullscreen(w)
        || is_sdl_fullscreen_style(w.styleMask))
        return;
    NSWindowStyleMask before = w.styleMask;
    BOOL dialog = is_dialog(before);
    // SDL marks its windows Miniaturizable already; a dialog keeps whatever it has.
    NSWindowStyleMask bits = NP_FRAME | (dialog ? 0 : NSWindowStyleMaskMiniaturizable);
    set_managed(w, bits);
    g_set_style(w, @selector(setStyleMask:), before | bits);
    w.titlebarAppearsTransparent = YES;
    w.titleVisibility = NSWindowTitleHidden;
    if (dialog) {
        [w standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
        [w standardWindowButton:NSWindowZoomButton].hidden = YES;
    }
    set_toolbar(w, YES);
    NSWindowCollectionBehavior was = w.collectionBehavior;
    g_set_behavior(w, @selector(setCollectionBehavior:), standard_behavior(was));
    NP_LOG("steamwin: behavior of %p \"%s\": [%s] -> [%s]", w, w.title.UTF8String,
           behavior_names(was).UTF8String, behavior_names(w.collectionBehavior).UTF8String);
    NP_LOG("steamwin: native frame on %p \"%s\"%s: style 0x%lx -> 0x%lx",
           w, w.title.UTF8String, dialog ? " (dialog, close button only)" : "",
           (unsigned long)before, (unsigned long)w.styleMask);
}

static NSUInteger g_restores;

// SDL sets the style again whenever it changes a window (resizable, bordered,
// leaving full screen). For a window that carries the macOS frame, the frame bits
// stay; a switch to SDL's own full screen releases the window instead.
static void np_set_style(id self, SEL _cmd, NSWindowStyleMask mask) {
    NSWindow *w = self;
    NSWindowStyleMask bits = added_bits(w);
    if (bits) {
        if (is_sdl_fullscreen_style(mask)) {
            set_managed(w, 0);
            w.toolbar = nil;
            w.titlebarAppearsTransparent = NO;
            NP_LOG("steamwin: %p \"%s\" went to SDL full screen (style 0x%lx), frame released",
                   w, w.title.UTF8String, (unsigned long)mask);
        } else if ((mask & bits) != bits) {
            if (g_restores++ < 50)
                NP_LOG("steamwin: Steam set style 0x%lx on %p, keeping the macOS frame (0x%lx)",
                       (unsigned long)mask, w, (unsigned long)(mask | bits));
            mask |= bits;
        }
    }
    g_set_style(self, _cmd, mask);
}

// What a double click on a title bar does, as set in System Settings (Desktop &
// Dock, "Double-click a window's title bar to").
static void title_double_click(NSWindow *w) {
    NSString *action = [NSUserDefaults.standardUserDefaults stringForKey:@"AppleActionOnDoubleClick"];
    if ([action isEqualToString:@"Minimize"])
        [w performMiniaturize:nil];
    else if (![action isEqualToString:@"None"])
        [w performZoom:nil];
    NP_LOG("steamwin: double click on the title area of %p: %s", w, action ? action.UTF8String : "Maximize");
}

// SDL sets the collection behavior again when it changes a window (resizable, full
// screen); a window with the macOS frame keeps a standard one.
static void np_set_behavior(id self, SEL _cmd, NSWindowCollectionBehavior b) {
    NSWindow *w = self;
    if (is_managed(w)) {
        NSWindowCollectionBehavior fixed = standard_behavior(b);
        if (fixed != b && g_restores++ < 50)
            NP_LOG("steamwin: Steam set behavior [%s] on %p, keeping [%s]",
                   behavior_names(b).UTF8String, w, behavior_names(fixed).UTF8String);
        b = fixed;
    }
    g_set_behavior(self, _cmd, b);
}

static void (*g_send_event)(id, SEL, NSEvent *);

// The view a click at this point of the window reaches.
static NSView *hit_view(NSWindow *w, NSPoint in_window) {
    NSView *frameView = w.contentView.superview;
    return [frameView hitTest:[frameView convertPoint:in_window fromView:nil]];
}

// Steam marks its draggable parts with -webkit-app-region: drag, and CEF lays a
// CefDraggableView over each one (its buttons get a CefNonDraggableView; both
// answer mouseDownCanMoveWindow, so the class is what tells them apart). A double
// click there did nothing; on a title bar it zooms or minimizes. Should CEF rename
// the view, double clicks simply stay Steam's.
static BOOL is_drag_area(NSView *view) {
    NSString *name = NSStringFromClass([view class]);
    return [name containsString:@"Draggable"] && ![name containsString:@"NonDraggable"];
}

static void np_send_event(id self, SEL _cmd, NSEvent *event) {
    NSWindow *w = self;
    if (is_managed(w) && event.type == NSEventTypeLeftMouseDown && event.clickCount == 2) {
        NSView *hit = hit_view(w, event.locationInWindow);
        if (is_drag_area(hit)) {
            title_double_click(w);
            return;
        }
    }
    g_send_event(self, _cmd, event);
}

// Replaces `sel` for `cls` only, keeping the inherited implementation to call.
static IMP override(Class cls, SEL sel, IMP replacement) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m)
        return NULL;
    IMP original = method_getImplementation(m);
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(m)))
        original = method_setImplementation(class_getInstanceMethod(cls, sel), replacement);
    return original;
}

// MARK: Survey

static NSMapTable<NSWindow *, NSString *> *g_seen;

static void survey(NSString *why) {
    for (NSWindow *w in NSApp.windows) {
        if (g_mode == NP_SW_NATIVE)
            apply_chrome(w);
        NSString *now = describe(w);
        NSString *before = [g_seen objectForKey:w];
        if ([before isEqualToString:now])
            continue;
        [g_seen setObject:now forKey:w];
        NP_LOG("steamwin: %s %s %s", before ? "changed" : "new", why.UTF8String, now.UTF8String);
    }
}

// MARK: Debug commands
//
// notproton/steam-windows-debug, one command per line, run once and deleted. For
// checking the frame without a mouse: Steam Helper acts on its own windows, and
// events it sends itself need no accessibility permission. Target: the window
// whose title contains @<text>, else the main window "Steam".
//   dump                     describe windows and what a click would hit along the top
//   zoom | fullscreen | miniaturize | deminiaturize
//   click X Y | dblclick X Y points from the window's top left corner
//   key CODE                 a key press (53 is Escape)

static NSWindow *debug_target(NSString *title) {
    NSWindow *fallback = nil;
    for (NSWindow *w in NSApp.windows) {
        if (!is_real_window(w) && !(w.isMiniaturized && is_sdl(w)))
            continue;
        if (title.length && [w.title rangeOfString:title].location != NSNotFound)
            return w;
        if (!title.length && [w.title isEqualToString:@"Steam"])
            fallback = w;
    }
    return title.length ? nil : fallback;
}

static void dump_hits(NSWindow *w) {
    NSView *frameView = w.contentView.superview;
    NSRect b = frameView.bounds;
    for (CGFloat y = 4; y <= 52; y += 8) {
        NSMutableArray *row = [NSMutableArray array];
        for (CGFloat x = 10; x < b.size.width; x += (b.size.width - 20) / 6) {
            NSPoint p = NSMakePoint(x, b.size.height - y);
            NSView *hit = [frameView hitTest:p];
            [row addObject:[NSString stringWithFormat:@"%.0f:%@%@", x, hit ? NSStringFromClass([hit class]) : @"-",
                                                      hit.mouseDownCanMoveWindow ? @"(moves)" : @""]];
        }
        NP_LOG("steamwin: debug hit y=%.0f %s", y, [row componentsJoinedByString:@" "].UTF8String);
    }
    NSButton *close = [w standardWindowButton:NSWindowCloseButton];
    NSRect cf = [close convertRect:close.bounds toView:nil];
    NP_LOG("steamwin: debug close button at %.1f,%.1f %.0fx%.0f (from top %.1f), titlebar %.0f",
           cf.origin.x, cf.origin.y, cf.size.width, cf.size.height,
           w.frame.size.height - NSMaxY(cf), w.frame.size.height - w.contentLayoutRect.size.height);
}

static void dump_tree(NSView *view, int depth) {
    if (depth > 6)
        return;
    CALayer *layer = view.layer;
    NP_LOG("steamwin: debug tree %*s%s frame=%.0fx%.0f@%.0f,%.0f hidden=%d layer=%s(%lu) contents=%d",
           depth * 2, "", class_getName([view class]), view.frame.size.width, view.frame.size.height,
           view.frame.origin.x, view.frame.origin.y, view.isHidden,
           layer ? class_getName([layer class]) : "-", (unsigned long)layer.sublayers.count,
           layer.contents != nil);
    for (CALayer *sub in layer.sublayers)
        if (depth < 3)
            NP_LOG("steamwin: debug tree %*s  [layer %s %.0fx%.0f hidden=%d contents=%d]", depth * 2, "",
                   class_getName([sub class]), sub.bounds.size.width, sub.bounds.size.height,
                   sub.isHidden, sub.contents != nil);
    for (NSView *child in view.subviews)
        dump_tree(child, depth + 1);
}

static void send_mouse(NSWindow *w, NSPoint top_left, NSInteger clicks) {
    NSPoint p = NSMakePoint(top_left.x, w.frame.size.height - top_left.y);
    for (NSInteger n = 1; n <= clicks; n++) {
        NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:p modifierFlags:0
                                          timestamp:NSProcessInfo.processInfo.systemUptime
                                       windowNumber:w.windowNumber context:nil eventNumber:0
                                         clickCount:n pressure:1];
        NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:p modifierFlags:0
                                        timestamp:NSProcessInfo.processInfo.systemUptime
                                     windowNumber:w.windowNumber context:nil eventNumber:0
                                       clickCount:n pressure:0];
        // The release is queued first, so a tracking loop the press starts ends.
        [NSApp postEvent:up atStart:NO];
        [NSApp sendEvent:down];
    }
}

static void run_debug(NSString *line) {
    NSMutableArray<NSString *> *words = [[line componentsSeparatedByCharactersInSet:
        NSCharacterSet.whitespaceCharacterSet] mutableCopy];
    [words removeObject:@""];
    if (!words.count)
        return;
    NSString *title = nil;
    if ([words.firstObject hasPrefix:@"@"]) {
        title = [words.firstObject substringFromIndex:1];
        [words removeObjectAtIndex:0];
    }
    NSString *cmd = words.firstObject;
    NSWindow *w = debug_target(title);
    NP_LOG("steamwin: debug '%s' on %p \"%s\"", line.UTF8String, w, w.title.UTF8String);
    if (!w && ![cmd isEqualToString:@"dump"] && ![cmd isEqualToString:@"spaces"]
        && ![cmd isEqualToString:@"policy"])
        return;
    if ([cmd isEqualToString:@"dump"]) {
        [g_seen removeAllObjects];
        survey(@"dump");
        if (w)
            dump_hits(w);
    } else if ([cmd isEqualToString:@"methods"]) {
        for (Class c = object_getClass(w); c && c != [NSWindow class]; c = class_getSuperclass(c)) {
            unsigned int n = 0;
            Method *list = class_copyMethodList(c, &n);
            NSMutableArray *names = [NSMutableArray array];
            for (unsigned int i = 0; i < n; i++)
                [names addObject:NSStringFromSelector(method_getName(list[i]))];
            free(list);
            NP_LOG("steamwin: debug %s methods: %s", class_getName(c), [names componentsJoinedByString:@" "].UTF8String);
        }
        NP_LOG("steamwin: debug delegate %s", w.delegate ? class_getName([(id)w.delegate class]) : "none");
        if (w.delegate) {
            unsigned int n = 0;
            Method *list = class_copyMethodList([(id)w.delegate class], &n);
            NSMutableArray *names = [NSMutableArray array];
            for (unsigned int i = 0; i < n; i++)
                [names addObject:NSStringFromSelector(method_getName(list[i]))];
            free(list);
            NP_LOG("steamwin: debug delegate methods: %s", [names componentsJoinedByString:@" "].UTF8String);
        }
    } else if ([cmd isEqualToString:@"spaces"]) {
        NP_LOG("steamwin: debug app policy=%s active=%d hidden=%d", policy_name(NSApp.activationPolicy),
               NSApp.isActive, NSApp.isHidden);
        for (NSWindow *each in NSApp.windows)
            if (is_sdl(each) && (each.isVisible || each.isMiniaturized))
                NP_LOG("steamwin: debug spaces %s", describe_spaces(each).UTF8String);
    } else if ([cmd isEqualToString:@"policy"] && words.count >= 2) {
        NSApplicationActivationPolicy p = [words[1] isEqualToString:@"regular"]
            ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory;
        BOOL ok = [NSApp setActivationPolicy:p];
        NP_LOG("steamwin: debug setActivationPolicy(%s) -> %d, now %s", policy_name(p), ok,
               policy_name(NSApp.activationPolicy));
    } else if ([cmd isEqualToString:@"tree"]) {
        dump_tree(w.contentView.superview, 0);
    } else if ([cmd isEqualToString:@"front"]) {
        [NSApp activate];
        [w makeKeyAndOrderFront:nil];
    } else if ([cmd isEqualToString:@"zoom"]) {
        [w performZoom:nil];
    } else if ([cmd isEqualToString:@"fullscreen"]) {
        [w toggleFullScreen:nil];
    } else if ([cmd isEqualToString:@"miniaturize"]) {
        [w performMiniaturize:nil];
        NP_LOG("steamwin: debug after performMiniaturize: mini=%d", w.isMiniaturized);
        if (!w.isMiniaturized) {
            [w miniaturize:nil];
            NP_LOG("steamwin: debug after miniaturize: mini=%d", w.isMiniaturized);
        }
    } else if ([cmd isEqualToString:@"deminiaturize"]) {
        [w deminiaturize:nil];
    } else if (([cmd isEqualToString:@"click"] || [cmd isEqualToString:@"dblclick"]) && words.count >= 3) {
        send_mouse(w, NSMakePoint(words[1].doubleValue, words[2].doubleValue),
                   [cmd isEqualToString:@"click"] ? 1 : 2);
    } else if ([cmd isEqualToString:@"key"] && words.count >= 2) {
        unsigned short code = (unsigned short)words[1].intValue;
        NSEvent *down = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                        timestamp:NSProcessInfo.processInfo.systemUptime
                                     windowNumber:w.windowNumber context:nil characters:@"\x1b"
                      charactersIgnoringModifiers:@"\x1b" isARepeat:NO keyCode:code];
        NSEvent *up = [NSEvent keyEventWithType:NSEventTypeKeyUp location:NSZeroPoint modifierFlags:0
                                      timestamp:NSProcessInfo.processInfo.systemUptime
                                   windowNumber:w.windowNumber context:nil characters:@"\x1b"
                    charactersIgnoringModifiers:@"\x1b" isARepeat:NO keyCode:code];
        // The release is queued first, so a tracking loop the press starts ends.
        [NSApp postEvent:up atStart:NO];
        [NSApp sendEvent:down];
    }
}

static NSString *g_debug_path;

static void poll_debug(void) {
    NSString *text = [NSString stringWithContentsOfFile:g_debug_path encoding:NSUTF8StringEncoding error:nil];
    if (!text)
        return;
    [NSFileManager.defaultManager removeItemAtPath:g_debug_path error:nil];
    for (NSString *line in [text componentsSeparatedByString:@"\n"])
        run_debug(line);
}

// MARK: Start

static void observe(void) {
    g_seen = [NSMapTable weakToStrongObjectsMapTable];
    g_sdl_window = NSClassFromString(@"SDL3Window");
    if (!g_sdl_window)
        NP_WARN("steamwin: no SDL3Window class in Steam Helper, windows are left as they are");

    if (g_mode == NP_SW_NATIVE && g_sdl_window) {
        g_set_style = (void (*)(id, SEL, NSWindowStyleMask))override(
            g_sdl_window, @selector(setStyleMask:), (IMP)np_set_style);
        g_send_event = (void (*)(id, SEL, NSEvent *))override(
            g_sdl_window, @selector(sendEvent:), (IMP)np_send_event);
        g_set_behavior = (void (*)(id, SEL, NSWindowCollectionBehavior))override(
            g_sdl_window, @selector(setCollectionBehavior:), (IMP)np_set_behavior);
        if (!g_set_style || !g_send_event || !g_set_behavior) {
            NP_ERR("steamwin: could not wrap SDL3Window, falling back to log mode");
            g_mode = NP_SW_LOG;
        }
    }

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSArray *names = @[
        NSWindowDidBecomeKeyNotification, NSWindowDidBecomeMainNotification,
        NSWindowDidResizeNotification, NSWindowDidEnterFullScreenNotification,
        NSWindowDidExitFullScreenNotification, NSWindowDidMiniaturizeNotification,
        NSWindowDidChangeOcclusionStateNotification,
    ];
    for (NSString *name in names) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *note) { survey(note.name); }];
    }
    if (g_mode == NP_SW_NATIVE) {
        [center addObserverForName:NSWindowWillEnterFullScreenNotification object:nil
                             queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (is_managed(note.object))
                set_toolbar(note.object, NO);
        }];
        [center addObserverForName:NSWindowDidExitFullScreenNotification object:nil
                             queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (is_managed(note.object))
                set_toolbar(note.object, YES);
        }];
    }

    char path[512];
    np_support_path(path, sizeof(path), np_home_dir() ?: "/tmp", "steam-windows-debug");
    g_debug_path = @(path);

    // New windows are framed here at the latest; a light poll also sees menus and
    // tooltips, which never become key.
    [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t) {
        survey(@"poll");
        poll_debug();
    }];
    survey(@"start");
    NP_LOG("steamwin: watching windows (mode %s), Steam Helper activation policy %s",
           g_mode == NP_SW_NATIVE ? "native" : "log", policy_name(NSApp.activationPolicy));
}

// NSApp exists once Chromium has started its application; until then, retry.
static void await_app(int attempt) {
    if (NSApp && (NSApp.isRunning || NSApp.windows.count > 0)) {
        observe();
        return;
    }
    if (attempt > 600) {
        NP_WARN("steamwin: no running NSApplication after 60 s, leaving windows alone");
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        await_app(attempt + 1);
    });
}

void np_steamwin_start(void) {
    g_mode = np_steamwin_mode();
    if (g_mode == NP_SW_OFF)
        return;
    np_log_init();
    NP_LOG("steamwin: Steam Helper pid %d, mode %s", getpid(), g_mode == NP_SW_NATIVE ? "native" : "log");
    dispatch_async(dispatch_get_main_queue(), ^{ await_app(0); });
}
