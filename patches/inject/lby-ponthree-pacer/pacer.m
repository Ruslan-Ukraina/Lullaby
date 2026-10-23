/* lby-ponthree-pacer: frame pacing of a game's presentation on Metal (S8, docs/DECISIONS.md).
 *
 * Injected into the Wine loader's process (DYLD_INSERT_LIBRARIES, like lby-pinkiepie-windowstate); D3DMetal and
 * Dormison's WineMetalLayer live in that process, so the Metal calls a game's frames go through can be seen and, later,
 * timed from here without touching either.
 *
 * It does nothing unless asked. The setting is PACER_MODE, read a moment after start (the engine applies the game's
 * env files after this library is loaded), from the environment or from <prefix>/.sevo/lullaby-pacer.conf (KEY=VALUE):
 *   PACER_MODE=off      nothing at all (the default)
 *   PACER_MODE=probe    only counts which present calls the game's Metal path makes, and logs a summary every 5 s
 *   PACER_LOG=<path>    where the lines go (default: stderr, i.e. the game's log)
 * The modes that change a frame's time come after the probe has said which path to take. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_HOOKS 96

typedef enum { SIG_OBJ, SIG_OBJ_DOUBLE, SIG_VOID, SIG_DOUBLE, SIG_PTR_COUNT, SIG_PTR_COUNT_OPT, SIG_RET_OBJ, SIG_BOOL, SIG_UINT } sig_kind;

typedef struct {
    Class cls;
    SEL sel;
    IMP orig;
    sig_kind kind;
    _Atomic unsigned long long calls;
    _Atomic unsigned long long last_calls;
    _Atomic unsigned long long first_thread;
    _Atomic unsigned long long main_thread_calls;
    double arg_min, arg_max;
} hook_t;

static hook_t gHooks[MAX_HOOKS];
static _Atomic int gHookCount;
static FILE *gLog;
static NSString *gMode = @"off";
static dispatch_queue_t gQueue;

static void say(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    FILE *out = gLog ? gLog : stderr;
    fputs("pacer: ", out);
    vfprintf(out, fmt, ap);
    fputc('\n', out);
    fflush(out);
    va_end(ap);
}

static unsigned long long tid(void)
{
    uint64_t t = 0;
    pthread_threadid_np(NULL, &t);
    return t;
}

/* The setting: environment first, then the prefix's file. */
static NSString *setting(NSString *key)
{
    const char *env = getenv([key UTF8String]);
    if (env && *env) return [NSString stringWithUTF8String:env];
    const char *prefix = getenv("WINEPREFIX");
    if (!prefix) return nil;
    NSString *path = [NSString stringWithFormat:@"%s/.sevo/lullaby-pacer.conf", prefix];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location == NSNotFound || [line hasPrefix:@"#"]) continue;
        if ([[line substringToIndex:eq.location] isEqualToString:key])
            return [[line substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    return nil;
}

static hook_t *find_hook(id self, SEL sel)
{
    int n = atomic_load(&gHookCount);
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c))
        for (int i = 0; i < n; i++)
            if (gHooks[i].cls == c && gHooks[i].sel == sel) return &gHooks[i];
    return NULL;
}

static void note(hook_t *h, double arg, BOOL hasArg)
{
    unsigned long long t = tid();
    unsigned long long zero = 0;
    atomic_compare_exchange_strong(&h->first_thread, &zero, t);
    atomic_fetch_add(&h->calls, 1);
    if (pthread_main_np()) atomic_fetch_add(&h->main_thread_calls, 1);
    if (hasArg) {
        if (h->arg_max == 0 && h->arg_min == 0) h->arg_min = h->arg_max = arg;
        if (arg < h->arg_min) h->arg_min = arg;
        if (arg > h->arg_max) h->arg_max = arg;
    }
}

/* One replacement implementation per call shape; each counts and calls the original. */
static void install(Class cls, SEL sel, sig_kind kind)
{
    int idx = atomic_fetch_add(&gHookCount, 1);
    if (idx >= MAX_HOOKS) { atomic_fetch_sub(&gHookCount, 1); return; }
    hook_t *h = &gHooks[idx];
    Method m = class_getInstanceMethod(cls, sel);
    h->cls = cls;
    h->sel = sel;
    h->orig = method_getImplementation(m);
    h->kind = kind;
    IMP replacement = NULL;
    switch (kind) {
    case SIG_OBJ:
        replacement = imp_implementationWithBlock(^(id self, id a) {
            hook_t *x = find_hook(self, sel); if (x) note(x, 0, NO);
            ((void (*)(id, SEL, id))x->orig)(self, sel, a); });
        break;
    case SIG_OBJ_DOUBLE:
        replacement = imp_implementationWithBlock(^(id self, id a, double d) {
            hook_t *x = find_hook(self, sel); if (x) note(x, d, YES);
            ((void (*)(id, SEL, id, double))x->orig)(self, sel, a, d); });
        break;
    case SIG_VOID:
        replacement = imp_implementationWithBlock(^(id self) {
            hook_t *x = find_hook(self, sel); if (x) note(x, 0, NO);
            ((void (*)(id, SEL))x->orig)(self, sel); });
        break;
    case SIG_DOUBLE:
        replacement = imp_implementationWithBlock(^(id self, double d) {
            hook_t *x = find_hook(self, sel); if (x) note(x, d, YES);
            ((void (*)(id, SEL, double))x->orig)(self, sel, d); });
        break;
    case SIG_PTR_COUNT:
        replacement = imp_implementationWithBlock(^(id self, const void *p, NSUInteger n) {
            hook_t *x = find_hook(self, sel); if (x) note(x, 0, NO);
            ((void (*)(id, SEL, const void *, NSUInteger))x->orig)(self, sel, p, n); });
        break;
    case SIG_PTR_COUNT_OPT:
        replacement = imp_implementationWithBlock(^(id self, const void *p, NSUInteger n, id o) {
            hook_t *x = find_hook(self, sel); if (x) note(x, 0, NO);
            ((void (*)(id, SEL, const void *, NSUInteger, id))x->orig)(self, sel, p, n, o); });
        break;
    case SIG_RET_OBJ:
        replacement = imp_implementationWithBlock(^id(id self) {
            hook_t *x = find_hook(self, sel); if (x) note(x, 0, NO);
            return ((id (*)(id, SEL))x->orig)(self, sel); });
        break;
    case SIG_BOOL:
        replacement = imp_implementationWithBlock(^(id self, BOOL b) {
            hook_t *x = find_hook(self, sel); if (x) note(x, b, YES);
            ((void (*)(id, SEL, BOOL))x->orig)(self, sel, b); });
        break;
    case SIG_UINT:
        replacement = imp_implementationWithBlock(^(id self, NSUInteger u) {
            hook_t *x = find_hook(self, sel); if (x) note(x, (double)u, YES);
            ((void (*)(id, SEL, NSUInteger))x->orig)(self, sel, u); });
        break;
    }
    method_setImplementation(m, replacement);
    say("hooked -[%s %s]", class_getName(cls), sel_getName(sel));
}

static BOOL declares(Class cls, SEL sel)
{
    unsigned count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned i = 0; i < count && !found; i++) found = method_getName(list[i]) == sel;
    free(list);
    return found;
}

typedef struct { const char *name; sig_kind kind; } probe_t;

/* The calls a frame can be shown through: Metal's command-buffer and drawable presents, Metal 4's queue
 * signal/wait for a drawable, and the layer's own acquire. */
static const probe_t kProbes[] = {
    { "presentDrawable:", SIG_OBJ },
    { "presentDrawable:atTime:", SIG_OBJ_DOUBLE },
    { "presentDrawable:afterMinimumDuration:", SIG_OBJ_DOUBLE },
    { "present", SIG_VOID },
    { "presentAtTime:", SIG_DOUBLE },
    { "presentAfterMinimumDuration:", SIG_DOUBLE },
    { "signalDrawable:", SIG_OBJ },
    { "waitForDrawable:", SIG_OBJ },
    { "nextDrawable", SIG_RET_OBJ },
    { "setDisplaySyncEnabled:", SIG_BOOL },
    { "setMaximumDrawableCount:", SIG_UINT },
};

static void hook_all(void)
{
    unsigned n = 0;
    Class *classes = objc_copyClassList(&n);
    for (unsigned i = 0; i < n; i++) {
        Class cls = classes[i];
        const char *name = class_getName(cls);
        /* Metal's, Core Animation's metal layers and drawables, and the engine's layer. */
        if (!(strstr(name, "CommandBuffer") || strstr(name, "CommandQueue") || strstr(name, "Drawable") ||
              strstr(name, "MetalLayer") || strstr(name, "AGX") || strncmp(name, "MTL", 3) == 0 || strncmp(name, "_MTL", 4) == 0))
            continue;
        if (strstr(name, "NSKVONotifying")) continue;
        for (unsigned p = 0; p < sizeof(kProbes) / sizeof(kProbes[0]); p++) {
            SEL sel = sel_registerName(kProbes[p].name);
            if (!declares(cls, sel)) continue;
            BOOL done = NO;
            int count = atomic_load(&gHookCount);
            for (int k = 0; k < count && !done; k++) done = gHooks[k].cls == cls && gHooks[k].sel == sel;
            if (!done) install(cls, sel, kProbes[p].kind);
        }
    }
    free(classes);
}

static void summarize(void)
{
    int n = atomic_load(&gHookCount);
    BOOL any = NO;
    for (int i = 0; i < n; i++) {
        unsigned long long calls = atomic_load(&gHooks[i].calls), last = atomic_load(&gHooks[i].last_calls);
        if (calls == last) continue;
        any = YES;
        atomic_store(&gHooks[i].last_calls, calls);
        say("-[%s %s] %llu calls (+%llu in 5 s), first thread %llu, main thread %llu%s", class_getName(gHooks[i].cls),
            sel_getName(gHooks[i].sel), calls, calls - last, atomic_load(&gHooks[i].first_thread),
            atomic_load(&gHooks[i].main_thread_calls),
            (gHooks[i].kind == SIG_OBJ_DOUBLE || gHooks[i].kind == SIG_DOUBLE || gHooks[i].kind == SIG_BOOL || gHooks[i].kind == SIG_UINT)
                ? [[NSString stringWithFormat:@", argument %g .. %g", gHooks[i].arg_min, gHooks[i].arg_max] UTF8String] : "");
    }
    if (!any) say("no hooked call was made in the last 5 s");
}

__attribute__((constructor)) static void pacer_init(void)
{
    const char *name = getprogname();
    if (!name || strncmp(name, "wine", 4) || !strcmp(name, "wineserver")) return;   /* the Wine loader's processes only */
    gQueue = dispatch_queue_create("lullaby.pacer", DISPATCH_QUEUE_SERIAL);
    /* The engine applies the game's env files a little after this library is loaded: look then. */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), gQueue, ^{
        NSString *mode = setting(@"PACER_MODE") ?: @"off";
        if ([mode isEqualToString:@"off"]) return;
        gMode = mode;
        NSString *log = setting(@"PACER_LOG");
        if (log.length) gLog = fopen([log UTF8String], "a");
        say("mode %s", [gMode UTF8String]);
        if ([gMode isEqualToString:@"probe"]) {
            /* Metal and D3DMetal load classes as the game starts its renderer: look again for a while. */
            for (int s = 0; s < 8; s++)
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * 5.0 * NSEC_PER_SEC)), gQueue, ^{ hook_all(); });
            dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
            dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 6ull * NSEC_PER_SEC), 5ull * NSEC_PER_SEC, NSEC_PER_SEC / 10);
            dispatch_source_set_event_handler(t, ^{ summarize(); });
            dispatch_resume(t);
            /* held for the life of the process */
            static dispatch_source_t keep;
            keep = t;
            (void)keep;
        }
    });
}
