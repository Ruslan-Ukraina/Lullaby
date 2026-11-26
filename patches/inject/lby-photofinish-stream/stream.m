// lby-photofinish-stream: the game's frame to OBS (or any Syphon client) without capturing the screen.
//
// Loaded into the Wine loader's process (DYLD_INSERT_LIBRARIES) when LULLABY_STREAM=1. Every drawable the game presents
// is copied, on the GPU, into a Syphon server's IOSurface just before it goes to the screen; OBS's "Syphon Client" source
// reads that surface. The game keeps its window, its settings and direct-to-display: nothing is drawn into its frame and
// no screen capture runs. Syphon.framework (BSD) comes from LULLABY_SYPHON_FRAMEWORK, components/stream/ or OBS itself;
// without it the library does nothing.
//
// Two present paths are covered:
//   Metal 3  -[MTLCommandBuffer presentDrawable:...]: the copy goes into the game's own command buffer, before the present.
//   Metal 4  -[MTL4CommandQueue signalDrawable:] (D3DMetal): the game's queue signals a shared event once its frame is
//            done, a Metal 3 queue of ours waits for it and copies. The present does not wait for the copy unless
//            LULLABY_STREAM_SYNC=1 (a drawable goes back to the layer's pool only after a later one is on the screen,
//            long after a copy of one frame).
// The layer must allow reads of its drawables: framebufferOnly is turned off for layers while streaming.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdatomic.h>

static BOOL gOn, gSync;
static FILE *gLog;
static __unsafe_unretained dispatch_queue_t gHookQueue;
static Class gServerClass;
static id gServer;                       // SyphonMetalServer
static id<MTLDevice> gDevice;
static id<MTLCommandQueue> gQueue;       // ours, Metal 3
static id<MTLSharedEvent> gReady, gCopied;
static uint64_t gValue;
static const void *gLastDrawable;        // a wrapper queue and the one it wraps both see a drawable: copy it once
                                         // (a pointer only: drawables need not allow weak references)
static NSLock *gLock;
static atomic_long gFrames, gSkipped;

static void slog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void slog(const char *fmt, ...) {
    FILE *f = gLog ? gLog : stderr;
    va_list ap; va_start(ap, fmt);
    fputs("photofinish: ", f); vfprintf(f, fmt, ap); fputc('\n', f); fflush(f);
    va_end(ap);
}

static BOOL loadSyphon(void) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    const char *e = getenv("LULLABY_SYPHON_FRAMEWORK");
    if (e && *e) [paths addObject:@(e)];
    [paths addObject:[NSHomeDirectory() stringByAppendingPathComponent:
                      @"Library/Application Support/lullaby/components/stream/Syphon.framework"]];
    [paths addObject:@"/Applications/OBS.app/Contents/Frameworks/Syphon.framework"];
    for (NSString *p in paths) {
        NSString *bin = [p stringByAppendingPathComponent:@"Syphon"];
        if (!dlopen(bin.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) continue;
        gServerClass = NSClassFromString(@"SyphonMetalServer");
        if (gServerClass) { slog("Syphon from %s", p.UTF8String); return YES; }
    }
    slog("no Syphon.framework (OBS not installed, none in components/stream): streaming off");
    return NO;
}

static NSString *serverName(void) {
    const char *n = getenv("LULLABY_STREAM_NAME");
    return n && *n ? @(n) : @"Lullaby";
}

// Under gLock. A device change (another GPU) starts over.
static BOOL ready(id<MTLDevice> dev) {
    if (gServer && gDevice == dev) return YES;
    gDevice = dev;
    gServer = ((id (*)(id, SEL, id, id, id))objc_msgSend)([gServerClass alloc],
        sel_registerName("initWithName:device:options:"), serverName(), dev, nil);
    gQueue = [dev newCommandQueue];
    gQueue.label = @"lullaby stream";
    gReady = [dev newSharedEvent]; gCopied = [dev newSharedEvent]; gValue = 0;
    slog("Syphon server \"%s\" on %s", serverName().UTF8String, dev.name.UTF8String);
    return gServer && gQueue && gReady && gCopied;
}

static BOOL wanted(id drawable, id<MTLTexture> *tex) {
    if (!drawable || (__bridge const void *)drawable == gLastDrawable || ![drawable respondsToSelector:@selector(texture)]) return NO;
    id<MTLTexture> t = ((id<CAMetalDrawable>)drawable).texture;
    if (!t) return NO;
    if (t.framebufferOnly) {   // a layer made before our hook: nothing can read it
        if (atomic_fetch_add(&gSkipped, 1) == 0) slog("a drawable is framebuffer-only: frame not streamed");
        return NO;
    }
    gLastDrawable = (__bridge const void *)drawable;
    *tex = t;
    return YES;
}

static void publish(id<MTLTexture> t, id<MTLCommandBuffer> cb) {
    ((void (*)(id, SEL, id, id, NSRect, BOOL))objc_msgSend)(gServer,
        sel_registerName("publishFrameTexture:onCommandBuffer:imageRegion:flipped:"), t, cb,
        NSMakeRect(0, 0, t.width, t.height), NO);   // Metal rows run top down, as Syphon wants them unflipped
    long n = atomic_fetch_add(&gFrames, 1) + 1;
    if (n == 1 || n % 3600 == 0) slog("%ld frames streamed (%lux%lu)", n, (unsigned long)t.width, (unsigned long)t.height);
}

// Metal 3: into the game's command buffer, before its present.
static void streamOnCommandBuffer(id<MTLCommandBuffer> cb, id drawable) {
    @autoreleasepool {
        [gLock lock];
        id<MTLTexture> t;
        if (wanted(drawable, &t) && ready(t.device)) publish(t, cb);
        [gLock unlock];
    }
}

// Metal 4: after the game's work on its queue, on ours.
static void streamOnQueue(id queue, id drawable) {
    @autoreleasepool {
        [gLock lock];
        id<MTLTexture> t;
        if (wanted(drawable, &t) && ready(t.device)) {
            uint64_t v = ++gValue;
            ((void (*)(id, SEL, id, uint64_t))objc_msgSend)(queue, sel_registerName("signalEvent:value:"), gReady, v);
            id<MTLCommandBuffer> cb = [gQueue commandBufferWithUnretainedReferences];
            [cb encodeWaitForEvent:gReady value:v];
            publish(t, cb);
            if (gSync) [cb encodeSignalEvent:gCopied value:v];
            [cb commit];
            if (gSync) ((void (*)(id, SEL, id, uint64_t))objc_msgSend)(queue, sel_registerName("waitForEvent:value:"), gCopied, v);
        }
        [gLock unlock];
    }
}

static NSMutableSet<NSString *> *gHooked;

static void hookMethod(Class cls, SEL sel, int kind) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    NSString *key = [NSString stringWithFormat:@"%s %s", class_getName(cls), sel_getName(sel)];
    if ([gHooked containsObject:key]) return;
    [gHooked addObject:key];
    IMP o = method_getImplementation(m);
    switch (kind) {
    case 0:   // presentDrawable:
        method_setImplementation(m, imp_implementationWithBlock(^(id self, id d) {
            streamOnCommandBuffer(self, d); ((void (*)(id, SEL, id))o)(self, sel, d); }));
        break;
    case 1:   // presentDrawable:atTime: / afterMinimumDuration:
        method_setImplementation(m, imp_implementationWithBlock(^(id self, id d, double t) {
            streamOnCommandBuffer(self, d); ((void (*)(id, SEL, id, double))o)(self, sel, d, t); }));
        break;
    case 2:   // presentDrawable:options:
        method_setImplementation(m, imp_implementationWithBlock(^(id self, id d, id opt) {
            streamOnCommandBuffer(self, d); ((void (*)(id, SEL, id, id))o)(self, sel, d, opt); }));
        break;
    case 3:   // MTL4CommandQueue signalDrawable:
        method_setImplementation(m, imp_implementationWithBlock(^(id self, id d) {
            streamOnQueue(self, d); ((void (*)(id, SEL, id))o)(self, sel, d); }));
        break;
    case 4:   // CAMetalLayer setFramebufferOnly:
        method_setImplementation(m, imp_implementationWithBlock(^(id self, BOOL b) {
            (void)b; ((void (*)(id, SEL, BOOL))o)(self, sel, NO); }));
        break;
    case 5:   // CAMetalLayer nextDrawable: a layer made before the hook gets framebufferOnly off at its first drawable
        method_setImplementation(m, imp_implementationWithBlock(^id(CAMetalLayer *self) {
            if (self.framebufferOnly) self.framebufferOnly = NO;
            return ((id (*)(id, SEL))o)(self, sel); }));
        break;
    }
    slog("hooked -[%s %s]", class_getName(cls), sel_getName(sel));
}

static void hookClass(Class cls) {
    unsigned n = 0;
    Method *list = class_copyMethodList(cls, &n);
    for (unsigned i = 0; i < n; i++) {
        const char *s = sel_getName(method_getName(list[i]));
        int kind = !strcmp(s, "presentDrawable:") ? 0
                 : !strcmp(s, "presentDrawable:atTime:") || !strcmp(s, "presentDrawable:afterMinimumDuration:") ? 1
                 : !strcmp(s, "presentDrawable:options:") ? 2
                 : !strcmp(s, "signalDrawable:") ? 3 : -1;
        if (kind == 3 && !class_conformsToProtocol(cls, objc_getProtocol("MTL4CommandQueue"))) {
            // a command queue that does not say so (driver classes often conform only through a superclass)
            BOOL q = NO;
            for (Class c = cls; c && !q; c = class_getSuperclass(c)) q = class_conformsToProtocol(c, objc_getProtocol("MTL4CommandQueue"));
            if (!q && !strstr(class_getName(cls), "CommandQueue")) kind = -1;
        }
        if (kind >= 0) hookMethod(cls, method_getName(list[i]), kind);
    }
    free(list);
}

static void scanImage(void *arg) {
    char *path = arg;
    @autoreleasepool {
        [gLock lock];
        unsigned n = 0;
        const char **names = objc_copyClassNamesForImage(path, &n);
        for (unsigned i = 0; i < n; i++) {
            if (!strstr(names[i], "CommandBuffer") && !strstr(names[i], "CommandQueue")) continue;
            Class c = objc_getClass(names[i]);
            if (c) hookClass(c);
        }
        free(names);
        Class layer = objc_getClass("CAMetalLayer");
        if (layer) {
            hookMethod(layer, @selector(setFramebufferOnly:), 4);
            hookMethod(layer, @selector(nextDrawable), 5);
        }
        [gLock unlock];
    }
    free(path);
}

// With the runtime's lock held: plain C only, the scan runs off this thread.
static void imageAdded(const struct mach_header *mh) {
    Dl_info di;
    if (!dladdr(mh, &di) || !di.dli_fname) return;
    const char *p = di.dli_fname;
    if (!strstr(p, "/Metal.framework/") && !strstr(p, "/QuartzCore.framework/") && !strstr(p, "AGXMetal")
        && !strstr(p, "libMTLHud") && !strstr(p, "MTLTools") && !strstr(p, "MTLDebug") && !strstr(p, "MTLCounters")) return;
    dispatch_async_f(gHookQueue, strdup(p), scanImage);
}

__attribute__((constructor)) static void photofinishInit(void) {
    const char *on = getenv("LULLABY_STREAM");
    if (!on || strcmp(on, "1")) return;
    const char *lp = getenv("LULLABY_STREAM_LOG");
    if (lp && *lp) gLog = fopen(lp, "a");
    const char *s = getenv("LULLABY_STREAM_SYNC");
    gSync = s && !strcmp(s, "1");
    @autoreleasepool {
        if (!loadSyphon()) return;
        gOn = YES;
        gLock = [NSLock new];
        gHooked = [NSMutableSet set];
        gHookQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        objc_addLoadImageFunc(imageAdded);
        slog("waiting for Metal (present waits for the copy: %s)", gSync ? "yes" : "no");
    }
}

__attribute__((destructor)) static void photofinishFini(void) {
    if (gOn) slog("%ld frames streamed, %ld skipped", atomic_load(&gFrames), atomic_load(&gSkipped));
}
