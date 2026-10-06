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

#include <dlfcn.h>
#include <string.h>
#include <unistd.h>

static const char *g_who = "?";
static int g_lines;

#define FOCUS_LOG(fmt, ...) do { \
    if (g_lines++ < 2000) NP_LOG("focus[%s] " fmt, g_who, ##__VA_ARGS__); \
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

static IMP o_activate_ignoring, o_activate, o_ra_activate, o_ra_activate_from;

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

static void trace_calls(void) {
    o_activate_ignoring = swap_in([NSApplication class], @selector(activateIgnoringOtherApps:), (IMP)t_activate_ignoring);
    o_activate = swap_in([NSApplication class], @selector(activate), (IMP)t_activate);
    o_ra_activate = swap_in([NSRunningApplication class], @selector(activateWithOptions:), (IMP)t_ra_activate);
    o_ra_activate_from = swap_in([NSRunningApplication class], @selector(activateFromApplication:options:),
                                 (IMP)t_ra_activate_from);
}

static void trace_notifications(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[NSApplicationDidBecomeActiveNotification, NSApplicationDidResignActiveNotification]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            FOCUS_LOG("%s (key window %p)", n.name.UTF8String, NSApp.keyWindow);
        }];
    }
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            NSRunningApplication *app = n.userInfo[NSWorkspaceApplicationKey];
            FOCUS_LOG("workspace: %s (pid %d) is now active", app.localizedName.UTF8String, app.processIdentifier);
        }];
}

// MARK: One Dock icon
//
// Steam Helper is regular (and has the Dock icon) only while it has a window a
// person uses; steam_osx hides its own icon only while Steam Helper is alive and
// regular. Any other state, including Helper quitting, crashing or restarting,
// gives steam_osx its icon back within a second: Steam is never without one.

static NSString *const kHelperID = @"com.valvesoftware.steam.helper";

static void use_steam_icon(void);

static BOOL is_person_window(NSWindow *w) {
    return [NSStringFromClass([w class]) containsString:@"SDL"] && w.canBecomeMainWindow && !w.parentWindow
        && !(w.collectionBehavior & NSWindowCollectionBehaviorIgnoresCycle) && w.level == NSNormalWindowLevel
        && (w.isVisible || w.isMiniaturized);
}

// Steam's strings in the client's language (Steam Helper runs with -lang=uk_UA etc.).
static NSDictionary<NSString *, NSString *> *g_strings;

static void load_strings(void) {
    NSString *lang = @"english";
    for (NSString *arg in NSProcessInfo.processInfo.arguments) {
        if (![arg hasPrefix:@"-lang="])
            continue;
        NSDictionary *names = @{@"uk": @"ukrainian", @"ru": @"russian", @"de": @"german", @"fr": @"french",
                                @"es": @"spanish", @"it": @"italian", @"pl": @"polish", @"pt": @"portuguese",
                                @"ja": @"japanese", @"ko": @"koreana", @"zh": @"schinese", @"tr": @"turkish"};
        NSString *code = [[arg substringFromIndex:6] substringToIndex:MIN(2, arg.length - 6)];
        lang = names[code] ?: lang;
    }
    NSURL *dir = [[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"../../MacOS/steamui/localization"]
        URLByStandardizingPath];
    NSString *text = [NSString stringWithContentsOfURL:[dir URLByAppendingPathComponent:
        [NSString stringWithFormat:@"steamui_%@-json.js", lang]] encoding:NSUTF8StringEncoding error:nil];
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"Menu_Store", @"Menu_Library", @"Menu_Friends"]) {
        NSRange r = [text rangeOfString:[NSString stringWithFormat:@"\"%@\":\"", key]];
        if (r.location == NSNotFound)
            continue;
        NSUInteger start = NSMaxRange(r);
        NSRange end = [text rangeOfString:@"\"" options:0 range:NSMakeRange(start, MIN(80, text.length - start))];
        if (end.location != NSNotFound)
            found[key] = [text substringWithRange:NSMakeRange(start, end.location - start)];
    }
    g_strings = found;
    FOCUS_LOG("Dock menu strings (%s): %lu", lang.UTF8String, (unsigned long)found.count);
}

@interface NPSteamDock : NSObject
@end

@implementation NPSteamDock {
    NSTimeInterval _lastQuit;
}

- (void)open:(NSMenuItem *)item {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:item.representedObject]];
}

// A click on the Dock icon: Steam's library, as steam_osx's icon does.
- (void)reopen:(NSAppleEventDescriptor *)event withReply:(NSAppleEventDescriptor *)reply {
    FOCUS_LOG("Dock icon clicked: opening the library");
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"steam://open/games"]];
}

// Quit from the Dock icon or Cmd-Q quits Steam, not only its windows. A second
// request within ten seconds (Steam itself winding Helper down) is let through.
- (void)quit:(NSAppleEventDescriptor *)event withReply:(NSAppleEventDescriptor *)reply {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (_lastQuit && now - _lastQuit < 10) {
        FOCUS_LOG("quit requested again: Steam Helper terminates");
        [NSApp terminate:nil];
        return;
    }
    _lastQuit = now;
    FOCUS_LOG("quit requested: asking Steam to exit (steam://exit)");
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"steam://exit"]];
}

- (NSMenu *)menu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Steam"];
    NSArray *items = @[@[@"Menu_Store", @"Store", @"steam://store"],
                       @[@"Menu_Library", @"Library", @"steam://open/games"],
                       @[@"Menu_Friends", @"Friends", @"steam://open/friends"]];
    for (NSArray *spec in items) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:g_strings[spec[0]] ?: spec[1]
                                                      action:@selector(open:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = spec[2];
        [menu addItem:item];
    }
    return menu;
}
@end

static NPSteamDock *g_dock;

static NSMenu *np_dock_menu(id self, SEL _cmd, NSApplication *app) {
    return [g_dock menu];
}

// The Dock tile's name: the private call Chromium uses for the same purpose
// (base/mac: SetProcessName). Missing symbols leave "Steam Helper".
static void set_dock_name(NSString *name) {
    void *ls = dlopen("/System/Library/Frameworks/CoreServices.framework/Frameworks/"
                      "LaunchServices.framework/LaunchServices", RTLD_LAZY);
    CFTypeRef (*get_asn)(void) = ls ? dlsym(ls, "_LSGetCurrentApplicationASN") : NULL;
    OSStatus (*set_item)(int, CFTypeRef, CFStringRef, CFTypeRef, CFDictionaryRef *) =
        ls ? dlsym(ls, "_LSSetApplicationInformationItem") : NULL;
    CFStringRef *key = ls ? dlsym(ls, "_kLSDisplayNameKey") : NULL;
    if (!get_asn || !set_item || !key || !*key) {
        FOCUS_LOG("Dock name: LaunchServices calls not found, the tile keeps its name");
        return;
    }
    OSStatus st = set_item(-2 /* kLSDefaultSessionID */, get_asn(), *key, (__bridge CFStringRef)name, NULL);
    FOCUS_LOG("Dock name set to %s: %d", name.UTF8String, (int)st);
}

static void become_steam_in_dock(void) {
    use_steam_icon();
    set_dock_name(@"Steam");
}

static BOOL g_helper_regular;
static int g_without_windows;

static void helper_tick(void) {
    BOOL has = NO;
    for (NSWindow *w in NSApp.windows)
        if (is_person_window(w)) { has = YES; break; }
    g_without_windows = has ? 0 : g_without_windows + 1;
    BOOL want = has || (g_helper_regular && g_without_windows < 3);
    if (want == g_helper_regular)
        return;
    g_helper_regular = want;
    [NSApp setActivationPolicy:want ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
    FOCUS_LOG("Steam Helper is now %s (%s)", want ? "regular" : "accessory",
              want ? "a Steam window is open" : "no Steam window: steam_osx keeps the Dock icon");
    if (want)
        become_steam_in_dock();
}

static void start_helper_dock(void) {
    load_strings();
    g_dock = [NPSteamDock new];
    NSAppleEventManager *events = NSAppleEventManager.sharedAppleEventManager;
    [events setEventHandler:g_dock andSelector:@selector(reopen:withReply:)
              forEventClass:kCoreEventClass andEventID:kAEReopenApplication];
    [events setEventHandler:g_dock andSelector:@selector(quit:withReply:)
              forEventClass:kCoreEventClass andEventID:kAEQuitApplication];
    Class delegate = [(id)NSApp.delegate class];
    if (delegate) {
        Method m = class_getInstanceMethod(delegate, @selector(applicationDockMenu:));
        if (m)
            method_setImplementation(m, (IMP)np_dock_menu);
        else
            class_addMethod(delegate, @selector(applicationDockMenu:), (IMP)np_dock_menu, "@@:@");
    }
    FOCUS_LOG("Dock: reopen, quit and menu handled (delegate %s)", delegate ? class_getName(delegate) : "none");
    helper_tick();
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) { helper_tick(); }];
}

static void osx_tick(void) {
    BOOL helper_regular = NO;
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:kHelperID])
        if (!app.isTerminated && app.activationPolicy == NSApplicationActivationPolicyRegular)
            helper_regular = YES;
    NSApplicationActivationPolicy want = helper_regular ? NSApplicationActivationPolicyAccessory
                                                        : NSApplicationActivationPolicyRegular;
    if (NSApp.activationPolicy == want)
        return;
    BOOL ok = [NSApp setActivationPolicy:want];
    FOCUS_LOG("steam_osx %s its Dock icon (%d)", helper_regular ? "hides" : "shows", ok);
}

static void start_osx_dock(void) {
    osx_tick();
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) { osx_tick(); }];
    NSNotificationCenter *ws = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSString *name in @[NSWorkspaceDidTerminateApplicationNotification, NSWorkspaceDidLaunchApplicationNotification]) {
        [ws addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            NSRunningApplication *app = n.userInfo[NSWorkspaceApplicationKey];
            if ([app.bundleIdentifier isEqualToString:kHelperID])
                osx_tick();
        }];
    }
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
                start_helper_dock();
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
            if (!make_regular)
                start_osx_dock();
            FOCUS_LOG("tracing in pid %d, policy %ld", getpid(), (long)NSApp.activationPolicy);
        });
    });
}
