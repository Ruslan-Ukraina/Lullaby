// Steam Helper as a regular app (notproton/steam-windows = native-app, DECISIONS W10
// option B). Steam's windows belong to Steam Helper, a UIElement app, so Spaces and
// Stage Manager treat them as an agent's windows; as a regular app they behave as
// app windows. This file traces who activates whom, in steam_osx and in Steam
// Helper, and holds the guard against the two taking focus from each other.

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#include "steamfocus.h"
#include "steamwin_css.h"
#include "../util/log.h"

#include <string.h>
#include <unistd.h>

static const char *g_who = "?";
static int g_lines;

#define FOCUS_LOG(fmt, ...) do { \
    if (g_lines++ < 600) NP_LOG("focus[%s] " fmt, g_who, ##__VA_ARGS__); \
} while (0)

// "Module:symbol" for a few frames above the traced call.
static NSString *callers(void) {
    NSArray<NSString *> *stack = [NSThread callStackSymbols];
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 2; i < stack.count && out.count < 5; i++) {
        NSArray *parts = [[stack[i] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
            filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        if (parts.count >= 4)
            [out addObject:[NSString stringWithFormat:@"%@:%@", parts[1], parts[3]]];
    }
    return [out componentsJoinedByString:@" < "];
}

static IMP swap_in(Class cls, SEL sel, IMP replacement) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m)
        return NULL;
    return method_setImplementation(m, replacement);
}

// MARK: Guard
//
// Traced (2026-10-06): with Steam Helper regular, each process answers the other's
// activation with its own `activateIgnoringOtherApps:YES` from a notification
// observer: Helper active → steam_osx activates itself → Helper activates itself
// again, dozens of times a second. steam_osx did this to keep focus on the app
// that owns the Dock icon; with Helper a regular app that is wrong, so steam_osx
// does not take focus from Helper.

static BOOL g_is_osx;
static int g_suppressed;

static BOOL helper_is_frontmost(void) {
    NSString *front = NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier;
    return [front isEqualToString:@"com.valvesoftware.steam.helper"];
}

static BOOL suppress_activation(const char *what) {
    if (!g_is_osx || !helper_is_frontmost())
        return NO;
    if (g_suppressed++ < 40)
        FOCUS_LOG("suppressed %s: Steam Helper is frontmost (from %s)", what, callers().UTF8String);
    return YES;
}

// MARK: Traced calls

static IMP o_activate_ignoring, o_activate, o_ra_activate, o_ra_activate_from, o_make_key_front,
    o_order_front_regardless;

static void t_activate_ignoring(id self, SEL _cmd, BOOL flag) {
    if (suppress_activation("activateIgnoringOtherApps"))
        return;
    FOCUS_LOG("NSApp activateIgnoringOtherApps:%d from %s", flag, callers().UTF8String);
    ((void (*)(id, SEL, BOOL))o_activate_ignoring)(self, _cmd, flag);
}

static void t_activate(id self, SEL _cmd) {
    if (suppress_activation("activate"))
        return;
    FOCUS_LOG("NSApp activate from %s", callers().UTF8String);
    ((void (*)(id, SEL))o_activate)(self, _cmd);
}

static BOOL t_ra_activate(id self, SEL _cmd, NSApplicationActivationOptions options) {
    NSRunningApplication *app = self;
    if (app.processIdentifier == getpid() && suppress_activation("activateWithOptions"))
        return NO;
    FOCUS_LOG("NSRunningApplication(%s pid %d) activateWithOptions:0x%lx from %s",
              app.localizedName.UTF8String, app.processIdentifier, (unsigned long)options,
              callers().UTF8String);
    return ((BOOL (*)(id, SEL, NSApplicationActivationOptions))o_ra_activate)(self, _cmd, options);
}

static BOOL t_ra_activate_from(id self, SEL _cmd, NSRunningApplication *from,
                               NSApplicationActivationOptions options) {
    NSRunningApplication *app = self;
    FOCUS_LOG("NSRunningApplication(%s) activateFromApplication:%s from %s",
              app.localizedName.UTF8String, from.localizedName.UTF8String, callers().UTF8String);
    return ((BOOL (*)(id, SEL, NSRunningApplication *, NSApplicationActivationOptions))o_ra_activate_from)(
        self, _cmd, from, options);
}

static void t_make_key_front(id self, SEL _cmd, id sender) {
    NSWindow *w = self;
    FOCUS_LOG("makeKeyAndOrderFront %p \"%s\" from %s", w, w.title.UTF8String, callers().UTF8String);
    ((void (*)(id, SEL, id))o_make_key_front)(self, _cmd, sender);
}

static void t_order_front_regardless(id self, SEL _cmd) {
    NSWindow *w = self;
    FOCUS_LOG("orderFrontRegardless %p \"%s\" from %s", w, w.title.UTF8String, callers().UTF8String);
    ((void (*)(id, SEL))o_order_front_regardless)(self, _cmd);
}

static void trace_calls(void) {
    o_activate_ignoring = swap_in([NSApplication class], @selector(activateIgnoringOtherApps:), (IMP)t_activate_ignoring);
    o_activate = swap_in([NSApplication class], @selector(activate), (IMP)t_activate);
    o_ra_activate = swap_in([NSRunningApplication class], @selector(activateWithOptions:), (IMP)t_ra_activate);
    o_ra_activate_from = swap_in([NSRunningApplication class], @selector(activateFromApplication:options:),
                                 (IMP)t_ra_activate_from);
    o_make_key_front = swap_in([NSWindow class], @selector(makeKeyAndOrderFront:), (IMP)t_make_key_front);
    o_order_front_regardless = swap_in([NSWindow class], @selector(orderFrontRegardless),
                                       (IMP)t_order_front_regardless);
}

static void trace_notifications(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[NSApplicationDidBecomeActiveNotification, NSApplicationDidResignActiveNotification]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            FOCUS_LOG("%s (key window %p)", n.name.UTF8String, NSApp.keyWindow);
        }];
    }
    for (NSString *name in @[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification,
                             NSWindowDidBecomeMainNotification]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            NSWindow *w = n.object;
            FOCUS_LOG("%s %p \"%s\"", n.name.UTF8String, w, w.title.UTF8String);
        }];
    }
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            NSRunningApplication *app = n.userInfo[NSWorkspaceApplicationKey];
            FOCUS_LOG("workspace: %s (pid %d) is now active", app.localizedName.UTF8String, app.processIdentifier);
        }];
}

// MARK: Start

static void await_app(int attempt, void (^ready)(void)) {
    if (NSApp && (NSApp.isRunning || attempt > 50)) {
        ready();
        return;
    }
    if (attempt > 600)
        return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        await_app(attempt + 1, ready);
    });
}

// Steam's own icon, from the client bundle Steam Helper lives in
// (Steam.AppBundle/Steam/Contents/Frameworks/Steam Helper.app), for its Dock tile.
static void use_steam_icon(void) {
    NSURL *icns = [[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"../../Resources/Steam.icns"]
        URLByStandardizingPath];
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:icns];
    if (!image)
        image = [NSWorkspace.sharedWorkspace iconForFile:@"/Applications/Steam.app"];
    NSApp.applicationIconImage = image;
    FOCUS_LOG("Dock icon from %s", image ? icns.path.UTF8String : "nowhere");
}

void np_steamfocus_start(const char *who, int make_regular) {
    if (np_steamwin_mode() != NP_SW_NATIVE_APP)
        return;
    g_who = who;
    g_is_osx = strcmp(who, "osx") == 0;
    np_log_attach();
    trace_calls();
    dispatch_async(dispatch_get_main_queue(), ^{
        await_app(0, ^{
            trace_notifications();
            if (make_regular) {
                BOOL ok = [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
                FOCUS_LOG("activation policy regular: %d", ok);
                use_steam_icon();
                // What the menu bar shows while a Steam window is focused: Steam
                // Helper's own menu, not steam_osx's.
                NSMutableArray *menus = [NSMutableArray array];
                for (NSMenuItem *item in NSApp.mainMenu.itemArray) {
                    NSMutableArray *sub = [NSMutableArray array];
                    for (NSMenuItem *entry in item.submenu.itemArray)
                        if (!entry.isSeparatorItem)
                            [sub addObject:entry.title];
                    [menus addObject:[NSString stringWithFormat:@"%@{%@}", item.title,
                                      [sub componentsJoinedByString:@", "]]];
                }
                FOCUS_LOG("Steam Helper menu bar: %s",
                          menus.count ? [menus componentsJoinedByString:@" "].UTF8String : "none");
            }
            FOCUS_LOG("tracing in pid %d, policy %ld", getpid(), (long)NSApp.activationPolicy);
        });
    });
}
