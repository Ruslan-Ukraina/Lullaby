/* lby-derpy-fixes: two faults of WineMetalGL (OpenGL on Metal) worked around from outside, until the author mends them.
 * Injected into the Wine loader's process (DYLD_INSERT_LIBRARIES, like lby-pinkiepie-windowstate); does nothing unless the
 * process runs WineMetalGL (WINEDLLOVERRIDES names winemetalgl). Uses names only (a symbol, a label), no offsets.
 *
 *   GLF-02  The colour texture of a window ("default framebuffer", private storage) is never cleared, at the start and when
 *           the window changes size. A game that swaps before it has drawn (a loading screen) showed the GPU's old memory,
 *           a flat magenta rectangle at the switch to native full screen. The texture is given its label the moment it is
 *           made: a texture given that label is cleared to black at once, before WineMetalGL copies the old picture into
 *           it. LULLABY_GL_CLEAR=0 turns it off.
 *
 *   MTL-01  A Metal mesh render pipeline that has a colour attachment but no fragment function aborts the process in Metal's own
 *           descriptor validation ("Mesh Render Pipeline Descriptor Validation, fragmentFunction must not be nil"). DXMT builds such
 *           a pipeline for a Direct3D 11 pass that has tessellation, a render target and no pixel shader (Modern Warfare Remastered,
 *           after a mission loads). Direct3D 11 means "no colour is written" there, so the pipeline gets an empty fragment function
 *           and a colour write mask of none, in the two calls that take a mesh descriptor (the device's pipeline creation and a
 *           binary archive's addMeshRenderPipelineFunctions). Not tied to one game. LULLABY_MESH_FS=0 turns it off.
 *
 * GLF-02 goes when WineMetalGL mends it; MTL-01 goes when DXMT does (agent report: winemetalgl-issue-draft-resize-uninitialised). */
#import <Metal/Metal.h>
#include <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void say(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fputs("glfixes: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}

static BOOL runsWineMetalGL(void)
{
    const char *over = getenv("WINEDLLOVERRIDES");
    return over && strstr(over, "winemetalgl");
}

static BOOL switchedOff(const char *name)
{
    const char *v = getenv(name);
    return v && !strcmp(v, "0");
}

/* ---- GLF-02 ---------------------------------------------------------------------------------------------------------- */

static IMP gOrigSetLabel;

static void clearToBlack(id<MTLTexture> texture)
{
    static id<MTLCommandQueue> queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = [[texture device] newCommandQueue]; });
    if (!queue || !(texture.usage & MTLTextureUsageRenderTarget)) return;
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLCommandBuffer> buffer = [queue commandBuffer];
    [[buffer renderCommandEncoderWithDescriptor:pass] endEncoding];
    [buffer commit];
    [buffer waitUntilCompleted];   /* before WineMetalGL's own commands touch the texture */
}

static void labelHook(id self, SEL _cmd, NSString *label)
{
    ((void (*)(id, SEL, NSString *))gOrigSetLabel)(self, _cmd, label);
    if ([label isEqualToString:@"default framebuffer"] && [self conformsToProtocol:@protocol(MTLTexture)])
        clearToBlack((id<MTLTexture>)self);
}

static void hookTextureLabel(void)
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return;
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
    d.storageMode = MTLStorageModePrivate;
    d.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> probe = [device newTextureWithDescriptor:d];
    Method m = probe ? class_getInstanceMethod(object_getClass(probe), @selector(setLabel:)) : NULL;
    if (!m) return;
    gOrigSetLabel = method_getImplementation(m);
    method_setImplementation(m, (IMP)labelHook);
    say("new window textures are cleared to black");
}

/* ---- MTL-01 ---------------------------------------------------------------------------------------------------------- */

static IMP gOrigMeshNew, gOrigMeshArchive;
static int gMeshFixed;

static id<MTLFunction> emptyFragment(id<MTLDevice> device)
{
    static id<MTLFunction> fn;
    static id<MTLDevice> owner;
    @synchronized ([NSNull null]) {
        if (fn && owner == device) return fn;
        NSError *e = nil;
        id<MTLLibrary> lib = [device newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nfragment void lullaby_empty_fragment() {}\n"
                                                  options:nil error:&e];
        fn = lib ? [lib newFunctionWithName:@"lullaby_empty_fragment"] : nil;
        owner = device;
        if (!fn) say("MTL-01: the empty fragment function did not compile: %s", e ? [[e description] UTF8String] : "?");
        return fn;
    }
}

/* A mesh descriptor that would abort: rasterization on, a colour attachment, no fragment function. */
static void fixMeshDescriptor(MTLMeshRenderPipelineDescriptor *d, id<MTLDevice> device)
{
    if (!d || ![d isKindOfClass:[MTLMeshRenderPipelineDescriptor class]] || d.fragmentFunction || !d.rasterizationEnabled) return;
    BOOL color = NO;
    for (NSUInteger i = 0; i < 8; i++)
        if (d.colorAttachments[i].pixelFormat != MTLPixelFormatInvalid) { color = YES; break; }
    if (!color) return;
    id<MTLFunction> fn = emptyFragment(device);
    if (!fn) return;
    d.fragmentFunction = fn;
    for (NSUInteger i = 0; i < 8; i++)
        if (d.colorAttachments[i].pixelFormat != MTLPixelFormatInvalid) d.colorAttachments[i].writeMask = MTLColorWriteMaskNone;
    if (gMeshFixed++ == 0) say("MTL-01: a mesh pipeline without a fragment function got an empty one (no colour written, as in Direct3D 11)");
}

static id meshNewHook(id self, SEL _cmd, MTLMeshRenderPipelineDescriptor *d, MTLPipelineOption options, void *reflection, NSError **error)
{
    fixMeshDescriptor(d, (id<MTLDevice>)self);
    return ((id (*)(id, SEL, id, MTLPipelineOption, void *, NSError **))gOrigMeshNew)(self, _cmd, d, options, reflection, error);
}

static BOOL meshArchiveHook(id self, SEL _cmd, MTLMeshRenderPipelineDescriptor *d, NSError **error)
{
    if ([self respondsToSelector:@selector(device)]) fixMeshDescriptor(d, [(id<MTLBinaryArchive>)self device]);
    return ((BOOL (*)(id, SEL, id, NSError **))gOrigMeshArchive)(self, _cmd, d, error);
}

static void hookMeshPipelines(void)
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return;
    SEL sel = @selector(newRenderPipelineStateWithMeshDescriptor:options:reflection:error:);
    Method m = class_getInstanceMethod(object_getClass(device), sel);
    if (m) {
        gOrigMeshNew = method_getImplementation(m);
        method_setImplementation(m, (IMP)meshNewHook);
    }
    NSError *e = nil;
    id<MTLBinaryArchive> archive = [device newBinaryArchiveWithDescriptor:[MTLBinaryArchiveDescriptor new] error:&e];
    SEL asel = @selector(addMeshRenderPipelineFunctionsWithDescriptor:error:);
    Method am = archive ? class_getInstanceMethod(object_getClass(archive), asel) : NULL;
    if (am) {
        gOrigMeshArchive = method_getImplementation(am);
        method_setImplementation(am, (IMP)meshArchiveHook);
    }
    if (m || am) say("MTL-01 armed (device call %s, archive call %s)", m ? "yes" : "no", am ? "yes" : "no");
}

__attribute__((constructor)) static void glf_init(void)
{
    const char *name = getprogname();
    if (!name || strncmp(name, "wine", 4) || !strcmp(name, "wineserver")) return;   /* the Wine loader's processes only */
    if (runsWineMetalGL() && !switchedOff("LULLABY_GL_CLEAR")) hookTextureLabel();
    if (!switchedOff("LULLABY_MESH_FS")) hookMeshPipelines();
}
