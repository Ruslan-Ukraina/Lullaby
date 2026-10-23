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
 *   PACER_MODE=meter    only listens: the frame rate and the evenness of what reaches the screen, every 5 s (any Metal game)
 *   PACER_MODE=adaptive the time each drawable is asked to be shown at is made even (see "the pacer" below)
 *   PACER_CAP=<fps>     with adaptive: never faster than this (0 = no cap)
 *   PACER_LOG=<path>    where the lines go (default: stderr, i.e. the game's log)
 * The modes that change a frame's time come after the probe has said which path to take. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <dispatch/dispatch.h>
#include <math.h>
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

typedef enum { SIG_OBJ, SIG_OBJ_DOUBLE, SIG_VOID, SIG_DOUBLE, SIG_PTR_COUNT, SIG_PTR_COUNT_OPT, SIG_RET_OBJ, SIG_BOOL, SIG_UINT, SIG_GENERIC } sig_kind;

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
    BOOL is_target, describe;
    _Atomic int described;
    _Atomic unsigned long long nsamples;
    unsigned long long word_samples[6];
    double double_samples[6];
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

/* The last targets D3DMetal asked a drawable to be shown at (seconds, the clock of mach_absolute_time), and the moment of each ask. */
#define TARGET_RING 240
static double gTargetAt[TARGET_RING], gTargetNow[TARGET_RING];
static _Atomic unsigned long long gTargetCount;
static mach_timebase_info_data_t gTimebase;

static double seconds_now(void)
{
    return (double)mach_absolute_time() * gTimebase.numer / gTimebase.denom / 1e9;
}

static void note_target(double target)
{
    unsigned long long n = atomic_fetch_add(&gTargetCount, 1);
    gTargetAt[n % TARGET_RING] = target;
    gTargetNow[n % TARGET_RING] = seconds_now();
}

static void summarize_targets(void)
{
    unsigned long long n = atomic_load(&gTargetCount);
    if (n < 30) return;
    unsigned m = n < TARGET_RING ? (unsigned)n : TARGET_RING;
    double ahead_min = 1e9, ahead_max = -1e9, ahead_sum = 0, step_min = 1e9, step_max = -1e9, step_sum = 0, step_sq = 0, prev = 0;
    unsigned steps = 0, zeros = 0, past = 0;
    for (unsigned k = 0; k < m; k++) {
        unsigned idx = (unsigned)((n - m + k) % TARGET_RING);
        double t = gTargetAt[idx], now = gTargetNow[idx];
        if (t == 0) { zeros++; continue; }
        double ahead = (t - now) * 1000.0;
        if (ahead < 0) past++;
        if (ahead < ahead_min) ahead_min = ahead;
        if (ahead > ahead_max) ahead_max = ahead;
        ahead_sum += ahead;
        if (prev != 0) {
            double st = (t - prev) * 1000.0;
            steps++; step_sum += st; step_sq += st * st;
            if (st < step_min) step_min = st;
            if (st > step_max) step_max = st;
        }
        prev = t;
    }
    if (!steps) return;
    double mean = step_sum / steps;
    say("targets (last %u asks): ahead of now %.2f .. %.2f ms (mean %.2f, %u already past, %u zero); step between targets mean %.2f ms (%.1f fps), min %.2f, max %.2f, std %.2f",
        m, ahead_min, ahead_max, ahead_sum / (m - zeros ? m - zeros : 1), past, zeros, mean, 1000.0 / mean, step_min, step_max,
        sqrt(step_sq / steps - mean * mean > 0 ? step_sq / steps - mean * mean : 0));
}

/* The first call or two of presentWithOptions: say what the options object is: its class, its properties, its description. */
static void describe_object(hook_t *h, uintptr_t a1)
{
    if (!h->describe || atomic_fetch_add(&h->described, 1) >= 2 || !a1) return;
    @try {
        id obj = (__bridge id)(void *)a1;
        Class c = object_getClass(obj);
        say("  options object: class %s, description %s", class_getName(c), [[obj description] UTF8String]);
        for (Class k = c; k && k != [NSObject class]; k = class_getSuperclass(k)) {
            unsigned np = 0;
            objc_property_t *props = class_copyPropertyList(k, &np);
            for (unsigned i = 0; i < np; i++) {
                NSString *pn = [NSString stringWithUTF8String:property_getName(props[i])];
                id v = nil;
                @try { v = [obj valueForKey:pn]; } @catch (NSException *e) { v = @"(not readable)"; }
                say("    %s.%s = %s", class_getName(k), [pn UTF8String], [[v description] UTF8String]);
            }
            free(props);
            unsigned ni = 0;
            Ivar *ivars = class_copyIvarList(k, &ni);
            for (unsigned i = 0; i < ni; i++) say("    ivar %s.%s (%s)", class_getName(k), ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]));
            free(ivars);
        }
    } @catch (NSException *e) {
        say("  options object: could not be described (%s)", [[e reason] UTF8String]);
    }
}

static void note_words(hook_t *h, uintptr_t a1, double d1)
{
    describe_object(h, a1);
    unsigned long long n = atomic_fetch_add(&h->nsamples, 1);
    if (n < 6) { h->word_samples[n] = a1; h->double_samples[n] = d1; }
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
    h->is_target = strcmp(sel_getName(sel), "setTargetPresentationTimestamp:") == 0;
    h->describe = strcmp(sel_getName(sel), "presentWithOptions:") == 0;
    IMP replacement = NULL;
    switch (kind) {
    case SIG_OBJ:
        replacement = imp_implementationWithBlock(^(id self, id a) {
            note(h, 0, NO);
            ((void (*)(id, SEL, id))h->orig)(self, sel, a); });
        break;
    case SIG_OBJ_DOUBLE:
        replacement = imp_implementationWithBlock(^(id self, id a, double d) {
            note(h, d, YES);
            ((void (*)(id, SEL, id, double))h->orig)(self, sel, a, d); });
        break;
    case SIG_VOID:
        replacement = imp_implementationWithBlock(^(id self) {
            note(h, 0, NO);
            ((void (*)(id, SEL))h->orig)(self, sel); });
        break;
    case SIG_DOUBLE:
        replacement = imp_implementationWithBlock(^(id self, double d) {
            note(h, d, YES);
            ((void (*)(id, SEL, double))h->orig)(self, sel, d); });
        break;
    case SIG_PTR_COUNT:
        replacement = imp_implementationWithBlock(^(id self, const void *p, NSUInteger n) {
            note(h, 0, NO);
            ((void (*)(id, SEL, const void *, NSUInteger))h->orig)(self, sel, p, n); });
        break;
    case SIG_PTR_COUNT_OPT:
        replacement = imp_implementationWithBlock(^(id self, const void *p, NSUInteger n, id o) {
            note(h, 0, NO);
            ((void (*)(id, SEL, const void *, NSUInteger, id))h->orig)(self, sel, p, n, o); });
        break;
    case SIG_RET_OBJ:
        replacement = imp_implementationWithBlock(^id(id self) {
            note(h, 0, NO);
            return ((id (*)(id, SEL))h->orig)(self, sel); });
        break;
    case SIG_BOOL:
        replacement = imp_implementationWithBlock(^(id self, BOOL b) {
            note(h, b, YES);
            ((void (*)(id, SEL, BOOL))h->orig)(self, sel, b); });
        break;
    case SIG_GENERIC:
        /* Any method of up to four integer-class arguments and two doubles: the registers the original reads are the
         * ones passed on (System V and AAPCS64 hand integers and doubles out of separate register files), whatever the
         * order the original declares them in. The return is a word (or void). */
        replacement = imp_implementationWithBlock(^uintptr_t(id self, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, double d1, double d2) {
            note(h, d1, NO); note_words(h, a1, d1);
            if (h->is_target) note_target(d1);
            return ((uintptr_t (*)(id, SEL, uintptr_t, uintptr_t, uintptr_t, uintptr_t, double, double))h->orig)(self, sel, a1, a2, a3, a4, d1, d2); });
        break;
    case SIG_UINT:
        replacement = imp_implementationWithBlock(^(id self, NSUInteger u) {
            note(h, (double)u, YES);
            ((void (*)(id, SEL, NSUInteger))h->orig)(self, sel, u); });
        break;
    }
    method_setImplementation(m, replacement);
    say("hooked -[%s %s]", class_getName(cls), sel_getName(sel));
}

/* A method whose name says it presents or deals in a drawable, with a call shape the generic wrapper can pass on. */
static BOOL passable(Method m)
{
    char ret[16];
    method_getReturnType(m, ret, sizeof ret);
    if (ret[0] == 'd' || ret[0] == 'f' || ret[0] == '{' || ret[0] == '(' || ret[0] == '[') return NO;
    unsigned args = method_getNumberOfArguments(m), ints = 0, dbls = 0;
    for (unsigned a = 2; a < args; a++) {
        char t[16];
        method_getArgumentType(m, a, t, sizeof t);
        if (t[0] == 'd') dbls++;
        else if (t[0] == 'f' || t[0] == '{' || t[0] == '(' || t[0] == '[') return NO;
        else ints++;
    }
    return ints <= 4 && dbls <= 2;
}

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
        if (strstr(name, "NSKVONotifying") || strstr(name, "HUD") || strstr(name, "NSHMD")) continue;
        unsigned count = 0;
        Method *list = class_copyMethodList(cls, &count);
        for (unsigned k = 0; k < count; k++) {
            SEL sel = method_getName(list[k]);
            const char *sn = sel_getName(sel);
            if (!(strstr(sn, "resent") || strstr(sn, "rawable") || strstr(sn, "DisplaySync") || strstr(sn, "aximumDrawable"))) continue;
            if (!passable(list[k])) continue;
            BOOL done = NO;
            int have = atomic_load(&gHookCount);
            for (int h = 0; h < have && !done; h++) done = gHooks[h].cls == cls && gHooks[h].sel == sel;
            if (!done) install(cls, sel, SIG_GENERIC);
        }
        free(list);
    }
    free(classes);
}

/* Metal's and D3DMetal's classes come as the game starts its renderer, which can be a minute after the process starts:
 * look again whenever the number of classes has changed. */
/* ---- the pacer: the time each drawable is asked to be shown at --------------------------------------------------
 *
 * D3DMetal's Metal 4 path sets -[CAMetalDrawable setTargetPresentationTimestamp:] once per frame (S8-2 probe): a time in
 * seconds on the clock of mach_absolute_time, 8..17 ms after the call, a step on the display's 120 Hz grid (so a frame
 * that misses a slot waits for the next: 8.3 / 16.7 / 25 ms intervals, the stairs). The display here is variable (24..120 Hz,
 * NSScreen), so the frames are asked for at an even interval instead:
 *   interval T  = the frame interval the game really produces (the gaps between the asks, p95 of the last 120, x1.03 and
 *                 smoothed), within the display's range, not below 1/PACER_CAP when a cap is set;
 *   target      = the last target + T; a frame that arrives after its slot is shown at once (the target is its original
 *                 one), and the next slot counts from the moment it went.
 * Only the target moves; the frame is the game's, the drawable the engine's. A call that is not a plain double is not touched. */
static struct {
    double last_ask, last_target, interval, cap_interval;
    double gaps[120];
    unsigned ngaps;
    unsigned long long frames, on_time, late;
} gPace;

static double pace_target(double original)
{
    double now = seconds_now();
    if (gPace.last_ask > 0) {
        double gap = now - gPace.last_ask;
        if (gap > 0 && gap < 0.5) gPace.gaps[gPace.ngaps++ % 120] = gap;   /* a pause (loading) is not a frame */
    }
    gPace.last_ask = now;
    gPace.frames++;
    unsigned n = gPace.ngaps < 120 ? gPace.ngaps : 120;
    if (n < 30) { gPace.last_target = original; return original; }
    double sorted[120];
    memcpy(sorted, gPace.gaps, n * sizeof(double));
    for (unsigned i = 1; i < n; i++) {   /* insertion sort: n is small */
        double v = sorted[i]; unsigned j = i;
        while (j > 0 && sorted[j - 1] > v) { sorted[j] = sorted[j - 1]; j--; }
        sorted[j] = v;
    }
    double want = sorted[(unsigned)(n * 0.95) < n ? (unsigned)(n * 0.95) : n - 1] * 1.03;
    if (want < 1.0 / 120.0) want = 1.0 / 120.0;
    if (want > 1.0 / 24.0) want = 1.0 / 24.0;
    if (gPace.cap_interval > want) want = gPace.cap_interval;
    /* smoothing; the interval moves only when the wish differs by more than 3 %, so a steady game keeps one interval */
    if (gPace.interval == 0) gPace.interval = want;
    else if (fabs(want - gPace.interval) / gPace.interval > 0.03) gPace.interval += (want - gPace.interval) * 0.1;
    double target = gPace.last_target + gPace.interval;
    if (gPace.last_target == 0 || target < now) {   /* late (or the first): shown at once, the slots count from here */
        gPace.late++;
        gPace.last_target = original < now ? now : original;
        if (gPace.last_target > now + gPace.interval) gPace.last_target = now;
        return gPace.last_target;
    }
    if (target > now + 2.0 * gPace.interval) target = now + gPace.interval;   /* never far ahead of the game */
    gPace.on_time++;
    gPace.last_target = target;
    return target;
}

static void summarize_pace(void)
{
    if (!gPace.frames) return;
    say("pace: interval %.2f ms (%.1f fps), %llu frames, %llu on their slot, %llu late (shown at once)",
        gPace.interval * 1000.0, gPace.interval > 0 ? 1.0 / gPace.interval : 0.0, gPace.frames, gPace.on_time, gPace.late);
}

static void install_pacer(Class cls, SEL sel)
{
    int idx = atomic_fetch_add(&gHookCount, 1);
    if (idx >= MAX_HOOKS) { atomic_fetch_sub(&gHookCount, 1); return; }
    hook_t *h = &gHooks[idx];
    Method m = class_getInstanceMethod(cls, sel);
    h->cls = cls;
    h->sel = sel;
    h->orig = method_getImplementation(m);
    h->kind = SIG_DOUBLE;
    IMP replacement = imp_implementationWithBlock(^(id self, double t) {
        atomic_fetch_add(&h->calls, 1);
        ((void (*)(id, SEL, double))h->orig)(self, sel, pace_target(t));
    });
    method_setImplementation(m, replacement);
    say("pacer hook on -[%s %s]", class_getName(cls), sel_getName(sel));
}

static void hook_pacer(void)
{
    SEL sel = sel_registerName("setTargetPresentationTimestamp:");
    unsigned n = 0;
    Class *classes = objc_copyClassList(&n);
    for (unsigned i = 0; i < n; i++) {
        const char *name = class_getName(classes[i]);
        if (!strstr(name, "Drawable") || strstr(name, "NSKVONotifying")) continue;
        unsigned count = 0;
        Method *list = class_copyMethodList(classes[i], &count);
        for (unsigned k = 0; k < count; k++) {
            if (method_getName(list[k]) != sel) continue;
            char t[16];
            if (method_getNumberOfArguments(list[k]) != 3) continue;
            method_getArgumentType(list[k], 2, t, sizeof t);
            if (t[0] != 'd') continue;
            BOOL done = NO;
            int have = atomic_load(&gHookCount);
            for (int h = 0; h < have && !done; h++) done = gHooks[h].cls == classes[i] && gHooks[h].sel == sel;
            if (!done) install_pacer(classes[i], sel);
        }
        free(list);
    }
    free(classes);
}

/* ---- the meter: when each frame of any Metal game reached the screen -------------------------------------------------
 *
 * -[CAMetalDrawable didPresentAtTime:] is the system telling a drawable that it was shown (a time in seconds on the
 * clock of mach_absolute_time), once per frame, whoever presented it: D3DMetal, DXMT or a native game alike. Mode
 * "meter" only listens and logs, every 5 s: the frame rate, the intervals' p50/p95/p99/max/std, the share of frames
 * within 1 ms of the median, and the share whose interval is a whole number of 120 Hz refreshes (8.33 ms: the grid
 * the stairs stand on). */
#define METER_RING 600
static double gShown[METER_RING];
static _Atomic unsigned long long gShownCount;
static unsigned long long gShownSeen;

static void note_shown(double t)
{
    if (t <= 0) return;
    unsigned long long n = atomic_fetch_add(&gShownCount, 1);
    gShown[n % METER_RING] = t;
}

static int cmp_double(const void *a, const void *b)
{
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

static void summarize_meter(void)
{
    unsigned long long n = atomic_load(&gShownCount);
    if (n < gShownSeen + 60) { if (n == gShownSeen) say("meter: no frame was shown in the last 5 s"); return; }
    gShownSeen = n;
    unsigned m = n < METER_RING ? (unsigned)n : METER_RING;
    double t[METER_RING], iv[METER_RING];
    for (unsigned k = 0; k < m; k++) t[k] = gShown[(n - m + k) % METER_RING];
    qsort(t, m, sizeof(double), cmp_double);
    unsigned c = 0;
    double sum = 0;
    for (unsigned k = 1; k < m; k++) {
        double d = (t[k] - t[k - 1]) * 1000.0;
        if (d > 0 && d < 500) { iv[c++] = d; sum += d; }
    }
    if (c < 30) return;
    double mean = sum / c, sq = 0;
    for (unsigned k = 0; k < c; k++) sq += (iv[k] - mean) * (iv[k] - mean);
    double sorted[METER_RING];
    memcpy(sorted, iv, c * sizeof(double));
    qsort(sorted, c, sizeof(double), cmp_double);
    double p50 = sorted[c / 2], p95 = sorted[(unsigned)(c * 0.95)], p99 = sorted[(unsigned)(c * 0.99)], mx = sorted[c - 1];
    unsigned flat = 0, grid = 0;
    for (unsigned k = 0; k < c; k++) {
        if (fabs(iv[k] - p50) <= 1.0) flat++;
        double r = fmod(iv[k], 1000.0 / 120.0);
        if (r < 0.6 || 1000.0 / 120.0 - r < 0.6) grid++;
    }
    say("meter: %u frames, %.1f fps, interval p50 %.2f p95 %.2f p99 %.2f max %.2f ms, std %.2f, %u%% within 1 ms of the median, %u%% on the 120 Hz grid",
        c + 1, 1000.0 / mean, p50, p95, p99, mx, sqrt(sq / c), flat * 100 / c, grid * 100 / c);
}

static void install_meter(Class cls, SEL sel)
{
    int idx = atomic_fetch_add(&gHookCount, 1);
    if (idx >= MAX_HOOKS) { atomic_fetch_sub(&gHookCount, 1); return; }
    hook_t *h = &gHooks[idx];
    Method m = class_getInstanceMethod(cls, sel);
    h->cls = cls;
    h->sel = sel;
    h->orig = method_getImplementation(m);
    h->kind = SIG_DOUBLE;
    method_setImplementation(m, imp_implementationWithBlock(^(id self, double t) {
        atomic_fetch_add(&h->calls, 1);
        note_shown(t);
        ((void (*)(id, SEL, double))h->orig)(self, sel, t);
    }));
    say("meter hook on -[%s %s]", class_getName(cls), sel_getName(sel));
}

static void hook_meter(void)
{
    SEL sel = sel_registerName("didPresentAtTime:");
    unsigned n = 0;
    Class *classes = objc_copyClassList(&n);
    for (unsigned i = 0; i < n; i++) {
        const char *name = class_getName(classes[i]);
        if (!strstr(name, "Drawable") || strstr(name, "NSKVONotifying")) continue;
        unsigned count = 0;
        Method *list = class_copyMethodList(classes[i], &count);
        for (unsigned k = 0; k < count; k++) {
            if (method_getName(list[k]) != sel || method_getNumberOfArguments(list[k]) != 3) continue;
            char t[16];
            method_getArgumentType(list[k], 2, t, sizeof t);
            if (t[0] != 'd') continue;
            BOOL done = NO;
            int have = atomic_load(&gHookCount);
            for (int q = 0; q < have && !done; q++) done = gHooks[q].cls == classes[i] && gHooks[q].sel == sel;
            if (!done) install_meter(classes[i], sel);
        }
        free(list);
    }
    free(classes);
}

static void rescan_if_new_classes(void)
{
    static int known;
    int now = objc_getClassList(NULL, 0);
    if (now == known) return;
    known = now;
    hook_all();
}

static void summarize(void)
{
    rescan_if_new_classes();
    summarize_targets();
    int n = atomic_load(&gHookCount);
    BOOL any = NO;
    for (int i = 0; i < n; i++) {
        unsigned long long calls = atomic_load(&gHooks[i].calls), last = atomic_load(&gHooks[i].last_calls);
        if (calls == last) continue;
        any = YES;
        atomic_store(&gHooks[i].last_calls, calls);
        const char *sn = sel_getName(gHooks[i].sel);
        if ((strstr(sn, "Timestamp") || strstr(sn, "Duration") || strstr(sn, "AtTime") || strstr(sn, "Options")) && atomic_load(&gHooks[i].nsamples) > 0 && atomic_load(&gHooks[i].nsamples) < 1000) {
            unsigned long long n = atomic_load(&gHooks[i].nsamples);
            for (unsigned long long k = 0; k < (n < 6 ? n : 6); k++)
                say("  sample %llu of -[%s %s]: word 0x%llx (%llu), double %g", k, class_getName(gHooks[i].cls), sn,
                    gHooks[i].word_samples[k], gHooks[i].word_samples[k], gHooks[i].double_samples[k]);
            say("  clocks now: mach_absolute_time %llu, mach_continuous_time %llu", (unsigned long long)mach_absolute_time(),
                (unsigned long long)mach_continuous_time());
            atomic_store(&gHooks[i].nsamples, 1000);   /* printed once */
        }
        say("-[%s %s] %llu calls (+%llu in 5 s), first thread %llu, main thread %llu%s", class_getName(gHooks[i].cls),
            sel_getName(gHooks[i].sel), calls, calls - last, atomic_load(&gHooks[i].first_thread),
            atomic_load(&gHooks[i].main_thread_calls),
            "");
    }
    if (!any) say("no hooked call was made in the last 5 s");
}

__attribute__((constructor)) static void pacer_init(void)
{
    const char *name = getprogname();
    if (!name || strncmp(name, "wine", 4) || !strcmp(name, "wineserver")) return;   /* the Wine loader's processes only */
    mach_timebase_info(&gTimebase);
    gQueue = dispatch_queue_create("lullaby.pacer", DISPATCH_QUEUE_SERIAL);
    /* The engine applies the game's env files a little after this library is loaded: look then. */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), gQueue, ^{
        NSString *mode = setting(@"PACER_MODE") ?: @"off";
        if ([mode isEqualToString:@"off"]) return;
        gMode = mode;
        NSString *log = setting(@"PACER_LOG");
        if (log.length) gLog = fopen([log UTF8String], "a");
        say("mode %s", [gMode UTF8String]);
        if ([gMode isEqualToString:@"adaptive"]) {
            NSString *cap = setting(@"PACER_CAP");
            if (cap.intValue > 0) gPace.cap_interval = 1.0 / cap.intValue;
            hook_pacer();
            dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
            dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 2ull * NSEC_PER_SEC), 5ull * NSEC_PER_SEC, NSEC_PER_SEC / 10);
            dispatch_source_set_event_handler(t, ^{
                static int known;
                int now = objc_getClassList(NULL, 0);
                if (now != known) { known = now; hook_pacer(); }   /* the drawable classes come with the renderer */
                summarize_pace();
            });
            dispatch_resume(t);
            static dispatch_source_t keep_pace;
            keep_pace = t;
            (void)keep_pace;
        }
        if ([gMode isEqualToString:@"meter"]) {
            hook_meter();
            dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
            dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 5ull * NSEC_PER_SEC), 5ull * NSEC_PER_SEC, NSEC_PER_SEC / 10);
            dispatch_source_set_event_handler(t, ^{
                static int known;
                int now = objc_getClassList(NULL, 0);
                if (now != known) { known = now; hook_meter(); }
                summarize_meter();
            });
            dispatch_resume(t);
            static dispatch_source_t keep_meter;
            keep_meter = t;
            (void)keep_meter;
        }
        if ([gMode isEqualToString:@"probe"]) {
            hook_all();
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
