/* The moment each frame reaches the screen, taken from outside any Wine build.
 *
 * Injected into a game's process (DYLD_INSERT_LIBRARIES), it wraps -[CAMetalLayer
 * nextDrawable] on the class and on every subclass that overrides it (D3DMetal's layer
 * is one), and asks each drawable for its presented time. Both DXMT and D3DMetal take their
 * drawables from a CAMetalLayer, so this reads the same thing under any engine: the engine's
 * own counters (Dormison's .sevo/run/<pid>.stats) exist in one engine only.
 *
 *   LULLABY_FRAMETAP=<dir>        write <dir>/frametap-<pid>.csv (the folder must exist)
 *   LULLABY_FRAMETAP_LABEL=<text> noted in the file's first line
 *
 * Rows: kind,ns with kind A (a drawable handed out), P (a drawable shown, ns = its
 * presented time) or D (a drawable that was dropped). Clock: CACurrentMediaTime, in ns.
 * The file appears with the first drawable, so a process that draws nothing writes nothing.
 * The hooks go in once QuartzCore is loaded, found from a thread that wakes every second.
 *
 * A drawable's handler runs once per presentation; a drawable handed out twice before it is
 * shown would count twice (not seen with either renderer, noted here because the count is
 * what the report divides by).
 *
 * Universal (arm64 + x86_64): the engine's wineserver may be arm64, and a dylib that does not
 * load into a process makes dyld end it. Build: tools/perf/frametap.sh. */

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <os/lock.h>
#include <pthread.h>
#include <stdatomic.h>
#include <string.h>
#include <unistd.h>

typedef struct { char kind; uint64_t ns; } record_t;

#define CAPACITY (1u << 20)

static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
static record_t *buffer;
static size_t used;
static int fd = -1;
static char path[1024];
static char label[128];
static const char *directory;
static atomic_bool started;
static NSMutableSet<NSValue *> *wrapped;
/* A wrapped override that calls its wrapped super nests: only the outermost call taps, or every
   drawable would be counted twice (seen: each presented time twice in the file). */
static __thread int depth;

static uint64_t now_ns(void)
{
    return (uint64_t)(CACurrentMediaTime() * 1e9);
}

static void flush_locked(void)
{
    char line[64];
    if (!used || fd < 0) { used = 0; return; }
    for (size_t i = 0; i < used; i++)
    {
        int n = snprintf(line, sizeof(line), "%c,%llu\n", buffer[i].kind, (unsigned long long)buffer[i].ns);
        if (write(fd, line, (size_t)n) < 0) break;
    }
    used = 0;
}

static void record(char kind, uint64_t ns)
{
    os_unfair_lock_lock(&lock);
    if (fd < 0 && directory)
    {
        snprintf(path, sizeof(path), "%s/frametap-%d.csv", directory, getpid());
        fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0)
        {
            char head[320];
            int n = snprintf(head, sizeof(head), "# frametap exe=%s label=%s\nkind,ns\n", getprogname(), label);
            if (write(fd, head, (size_t)n) < 0) { close(fd); fd = -1; }
        }
    }
    if (buffer)
    {
        if (used == CAPACITY) flush_locked();
        buffer[used].kind = kind;
        buffer[used].ns = ns;
        used++;
    }
    os_unfair_lock_unlock(&lock);
}

static void tap(id drawable)
{
    if (!drawable) return;
    record('A', now_ns());
    if ([drawable respondsToSelector:@selector(addPresentedHandler:)])
    {
        [(id<MTLDrawable>)drawable addPresentedHandler:^(id<MTLDrawable> d) {
            double t = d.presentedTime;
            if (t > 0) record('P', (uint64_t)(t * 1e9));
            else record('D', now_ns());
        }];
    }
}

/* Wraps cls's own nextDrawable, if it has one it has not wrapped yet. */
static void wrap_class(Class cls)
{
    SEL sel = @selector(nextDrawable);
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method own = NULL;
    for (unsigned int i = 0; i < count; i++)
        if (method_getName(methods[i]) == sel) { own = methods[i]; break; }
    free(methods);
    if (!own) return;
    NSValue *key = [NSValue valueWithPointer:own];
    if ([wrapped containsObject:key]) return;
    IMP orig = method_getImplementation(own);
    IMP replacement = imp_implementationWithBlock(^id(id self) {
        depth++;
        id d = ((id (*)(id, SEL))orig)(self, sel);
        depth--;
        if (depth == 0) tap(d);
        return d;
    });
    method_setImplementation(own, replacement);
    [wrapped addObject:key];
}

static void sweep(void)
{
    Class layer = objc_getClass("CAMetalLayer");
    if (!layer) return;
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++)
    {
        BOOL below = classes[i] == layer;
        for (Class c = class_getSuperclass(classes[i]); !below && c; c = class_getSuperclass(c))
            below = c == layer;
        if (below) wrap_class(classes[i]);
    }
    free(classes);
}

static void *worker(void *arg)
{
    pthread_setname_np("lullaby-frametap");
    uint32_t images = 0;
    int ticks = 0;
    for (;;)
    {
        /* The class list is walked when a library has been loaded since the last time, and
           every ten seconds otherwise: walking it twice a second cost 2-5 % of a core. */
        uint32_t now = _dyld_image_count();
        if (now != images || ticks % 20 == 0)
        {
            images = now;
            @autoreleasepool { sweep(); }
        }
        ticks++;
        usleep(500000);
        os_unfair_lock_lock(&lock);
        flush_locked();
        os_unfair_lock_unlock(&lock);
    }
    return NULL;
}

static void start_once(void)
{
    if (atomic_exchange(&started, true)) return;
    pthread_t t;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&t, &attr, worker, NULL);
    pthread_attr_destroy(&attr);
}

/* The thread starts when QuartzCore appears in the process: one that never draws never starts it. */
static void image_added(const struct mach_header *header, intptr_t slide)
{
    Dl_info info;
    if (dladdr(header, &info) && info.dli_fname && strstr(info.dli_fname, "QuartzCore.framework"))
        start_once();
}

__attribute__((constructor)) static void frametap_init(void)
{
    const char *dir = getenv("LULLABY_FRAMETAP");
    const char *l = getenv("LULLABY_FRAMETAP_LABEL");
    if (!dir || !*dir) return;
    directory = strdup(dir);
    strlcpy(label, l ? l : "", sizeof(label));
    buffer = calloc(CAPACITY, sizeof(record_t));
    wrapped = [NSMutableSet set];
    _dyld_register_func_for_add_image(image_added);
}
