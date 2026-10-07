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
#include <libproc.h>
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

// One Dock icon (steam_osx hidden while Steam Helper is regular) ends Steam: about
// 30 s after steam_osx becomes a background app, loginwindow asks Background Task
// Management whether Steam may run in the background, hears no and quits it
// (DECISIONS W16, W18). So by default steam_osx keeps its icon. The file
// notproton/steam-windows-oneicon turns hiding on for diagnosis; then the Apple
// Events steam_osx receives are traced (who sends quit or steam://exit).
static BOOL kHideOsxIcon = NO;

static BOOL one_icon_requested(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/notproton/steam-windows-oneicon"];
    return [NSFileManager.defaultManager fileExistsAtPath:path];
}

// MARK: Apple Event trace (steam_osx, one-icon diagnosis)

typedef struct { AEEventHandlerUPP handler; SRefCon refcon; } np_ae_original_t;
static np_ae_original_t g_quit_original, g_url_original;

static NSString *ae_sender(const AppleEvent *event) {
    pid_t pid = 0;
    DescType type;
    Size size;
    if (AEGetAttributePtr(event, keySenderPIDAttr, typeSInt32, &type, &pid, sizeof(pid), &size) != noErr)
        return @"unknown";
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    char path[1024] = {0};
    proc_pidpath(pid, path, sizeof(path));
    return [NSString stringWithFormat:@"pid %d %@ (%s)", pid, app.localizedName ?: @"?", path];
}

static OSErr np_quit_handler(const AppleEvent *event, AppleEvent *reply, SRefCon refcon) {
    FOCUS_LOG("Apple Event quit received from %s", ae_sender(event).UTF8String);
    return g_quit_original.handler ? g_quit_original.handler(event, reply, g_quit_original.refcon) : errAEEventNotHandled;
}

static OSErr np_url_handler(const AppleEvent *event, AppleEvent *reply, SRefCon refcon) {
    char url[512] = {0};
    DescType type;
    Size size;
    AEGetParamPtr(event, keyDirectObject, typeUTF8Text, &type, url, sizeof(url) - 1, &size);
    FOCUS_LOG("Apple Event open URL %s from %s", url, ae_sender(event).UTF8String);
    return g_url_original.handler ? g_url_original.handler(event, reply, g_url_original.refcon) : errAEEventNotHandled;
}

static void trace_apple_events(void) {
    if (AEGetEventHandler(kCoreEventClass, kAEQuitApplication, &g_quit_original.handler, &g_quit_original.refcon, false) == noErr)
        AEInstallEventHandler(kCoreEventClass, kAEQuitApplication, NewAEEventHandlerUPP(np_quit_handler), 0, false);
    if (AEGetEventHandler(kInternetEventClass, kAEGetURL, &g_url_original.handler, &g_url_original.refcon, false) == noErr)
        AEInstallEventHandler(kInternetEventClass, kAEGetURL, NewAEEventHandlerUPP(np_url_handler), 0, false);
    FOCUS_LOG("tracing quit and open-URL Apple Events (originals %p %p)",
              g_quit_original.handler, g_url_original.handler);
}

// steam_osx sets itself regular again on its own (seen when a game starts). While
// Steam Helper holds the Dock icon that would bring the second icon back, so the
// request is answered without being carried out.
static IMP o_set_policy;
static BOOL helper_holds_icon(void);

static BOOL t_set_policy(id self, SEL _cmd, NSApplicationActivationPolicy policy) {
    FOCUS_LOG("setActivationPolicy:%ld from %s", (long)policy, callers().UTF8String);
    if (kHideOsxIcon && g_is_osx && policy == NSApplicationActivationPolicyRegular && helper_holds_icon()) {
        if (g_suppressed++ < 40)
            FOCUS_LOG("kept steam_osx without a Dock icon: Steam Helper holds it (from %s)", callers().UTF8String);
        return YES;
    }
    return ((BOOL (*)(id, SEL, NSApplicationActivationPolicy))o_set_policy)(self, _cmd, policy);
}

// Who asks steam_osx to quit (seen: Steam exiting as a game starts while steam_osx
// has no Dock icon).
static IMP o_terminate;

static void t_terminate(id self, SEL _cmd, id sender) {
    FOCUS_LOG("NSApp terminate: (sender %s) from %s", sender ? class_getName([sender class]) : "nil",
              callers().UTF8String);
    ((void (*)(id, SEL, id))o_terminate)(self, _cmd, sender);
}

static void trace_calls(void) {
    o_terminate = swap_in([NSApplication class], @selector(terminate:), (IMP)t_terminate);
    o_set_policy = swap_in([NSApplication class], @selector(setActivationPolicy:), (IMP)t_set_policy);
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

// Steam Helper.app's Info.plist says "Steam Helper" and has no icon, and it cannot be
// changed: Steam's bootstrapper checks that file at every start and reinstalls its
// package when it differs, which turned an edit at start into a relaunch loop
// (DECISIONS W15). The name "Steam" and the bundle icon come from files NotProton.app
// adds next to it (SteamHelperFiles.swift, W17). At run time Steam Helper also takes
// Steam.app's icon before it becomes regular, so the Dock tile is created with it,
// and asks LaunchServices for the name "Steam" the way Chromium does (base/mac
// SetProcessName); that call alone did not change the Dock title.
static void set_dock_name(NSString *name) {
    void *ls = dlopen("/System/Library/Frameworks/CoreServices.framework/Frameworks/"
                      "LaunchServices.framework/LaunchServices", RTLD_LAZY);
    CFTypeRef (*get_asn)(void) = ls ? dlsym(ls, "_LSGetCurrentApplicationASN") : NULL;
    OSStatus (*set_item)(int, CFTypeRef, CFStringRef, CFTypeRef, CFDictionaryRef *) =
        ls ? dlsym(ls, "_LSSetApplicationInformationItem") : NULL;
    CFStringRef *key = ls ? dlsym(ls, "_kLSDisplayNameKey") : NULL;
    if (!get_asn || !set_item || !key || !*key) {
        FOCUS_LOG("Dock name: LaunchServices calls not found");
        return;
    }
    OSStatus st = set_item(-2 /* kLSDefaultSessionID */, get_asn(), *key, (__bridge CFStringRef)name, NULL);
    FOCUS_LOG("Dock name %s: %d", name.UTF8String, (int)st);
}

// iconForFile: answers a 32 pt image (with representations up to 2048 px); the Dock
// draws the tile from the image's size, so it is set to the largest tile first.
static NSImage *steam_app_icon(void) {
    NSImage *icon = [NSWorkspace.sharedWorkspace iconForFile:@"/Applications/Steam.app"];
    icon.size = NSMakeSize(1024, 1024);
    return icon;
}

static void become_steam_in_dock(void) {
    NSApp.applicationIconImage = steam_app_icon();
    FOCUS_LOG("Dock icon: Steam.app's, %.0f pt", NSApp.applicationIconImage.size.width);
    set_dock_name(@"Steam");
}

static BOOL g_helper_regular;
static int g_without_windows;

static void helper_tick(void) {
    BOOL has = NO;
    for (NSWindow *w in NSApp.windows)
        if (is_person_window(w)) { has = YES; break; }
    // Steam hides its windows (for instance when a game starts): hidden is not
    // closed, so the icon stays with Helper until a window is really gone.
    if (NSApp.isHidden && g_helper_regular)
        has = YES;
    g_without_windows = has ? 0 : g_without_windows + 1;
    BOOL want = has || (g_helper_regular && g_without_windows < 5);
    if (want == g_helper_regular)
        return;
    g_helper_regular = want;
    if (want)
        become_steam_in_dock();
    [NSApp setActivationPolicy:want ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
    FOCUS_LOG("Steam Helper is now %s (%s)", want ? "regular" : "accessory",
              want ? "a Steam window is open" : "no Steam window: steam_osx keeps the Dock icon");
    if (want)
        NSApp.applicationIconImage = steam_app_icon();
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

static BOOL helper_holds_icon(void) {
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:kHelperID])
        if (!app.isTerminated && app.activationPolicy == NSApplicationActivationPolicyRegular)
            return YES;
    return NO;
}

static void osx_tick(void) {
    BOOL helper_regular = helper_holds_icon();
    NSApplicationActivationPolicy want = helper_regular ? NSApplicationActivationPolicyAccessory
                                                        : NSApplicationActivationPolicyRegular;
    if (NSApp.activationPolicy == want)
        return;
    // Without a Dock icon and windows steam_osx would be a candidate for macOS's
    // automatic termination; it must stay up.
    static BOOL held;
    if (helper_regular && !held) {
        [NSProcessInfo.processInfo disableAutomaticTermination:@"NotProton: Steam Helper holds Steam's Dock icon"];
        [NSProcessInfo.processInfo disableSuddenTermination];
        held = YES;
    } else if (!helper_regular && held) {
        [NSProcessInfo.processInfo enableAutomaticTermination:@"NotProton: Steam Helper holds Steam's Dock icon"];
        [NSProcessInfo.processInfo enableSuddenTermination];
        held = NO;
    }
    BOOL ok = ((BOOL (*)(id, SEL, NSApplicationActivationPolicy))o_set_policy)(
        NSApp, @selector(setActivationPolicy:), want);
    FOCUS_LOG("steam_osx %s its Dock icon (%d)", helper_regular ? "hides" : "shows", ok);
}

static void start_osx_dock(void) {
    kHideOsxIcon = one_icon_requested();
    if (!kHideOsxIcon)
        return;
    FOCUS_LOG("one Dock icon (diagnosis): steam_osx hides its icon while Steam Helper holds it");
    trace_apple_events();
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
