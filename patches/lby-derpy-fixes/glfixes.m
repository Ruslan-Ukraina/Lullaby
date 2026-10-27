/* lby-derpy-fixes: two faults of WineMetalGL (OpenGL on Metal) worked around from outside, until the author mends them.
 * Injected into the Wine loader's process (DYLD_INSERT_LIBRARIES, like lby-pinkiepie-windowstate); does nothing unless the
 * process runs WineMetalGL (WINEDLLOVERRIDES names winemetalgl). Uses names only (a symbol, a label), no offsets.
 *
 *   GLF-01  The RGBA8 pixel formats are listed with cColorBits 24 (colour without alpha); NVIDIA, AMD, Intel and Wine's own
 *           driver say 32, and a game that asks for WGL_COLOR_BITS >= 32 finds no format (Euro Truck Simulator 2: "no devices
 *           found"). WineMetalGL's unix side gets the list with dlsym(wmgl_get_pixel_formats); this library takes that one
 *           lookup and gives back a function that sets 32 in the list the call fills. LULLABY_GL_COLOR_BITS=0 turns it off.
 *   GLF-02  The colour texture of a window ("default framebuffer", private storage) is never cleared, at the start and when
 *           the window changes size. A game that swaps before it has drawn (a loading screen) showed the GPU's old memory,
 *           a flat magenta rectangle at the switch to native full screen. The texture is given its label the moment it is
 *           made: a texture given that label is cleared to black at once, before WineMetalGL copies the old picture into
 *           it. LULLABY_GL_CLEAR=0 turns it off.
 *
 * Both go when WineMetalGL mends them (agent reports: winemetalgl-issue-draft-color-bits, ...-resize-uninitialised). */
#import <Metal/Metal.h>
#include <dlfcn.h>
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

/* ---- GLF-01 ---------------------------------------------------------------------------------------------------------- */

struct glf_wmgl_format {    /* the start of struct wmgl_pixel_format (WineMetalGL 3.x) */
    int draw_to_window, draw_to_pbuffer, double_buffer, stereo;
    int color_bits, red_bits, green_bits, blue_bits, alpha_bits;
};
typedef unsigned (*glf_get_formats_t)(struct glf_wmgl_format *, unsigned, unsigned *);
static glf_get_formats_t gRealGetFormats;
static int gFixColorBits = -1;   /* -1: not decided yet */

static unsigned fixedGetFormats(struct glf_wmgl_format *formats, unsigned max, unsigned *onscreen)
{
    unsigned n = gRealGetFormats(formats, max, onscreen);
    for (unsigned i = 0; formats && i < n && i < max; i++)
        if (formats[i].color_bits == 24 && formats[i].alpha_bits == 8) formats[i].color_bits = 32;
    return n;
}

static void *glf_dlsym(void *handle, const char *name)
{
    void *p = dlsym(handle, name);
    if (p && name && !strcmp(name, "wmgl_get_pixel_formats")) {
        if (gFixColorBits < 0) gFixColorBits = runsWineMetalGL() && !switchedOff("LULLABY_GL_COLOR_BITS");
        if (gFixColorBits) {
            gRealGetFormats = (glf_get_formats_t)p;
            return (void *)fixedGetFormats;
        }
    }
    return p;
}
#define GLF_INTERPOSE(replacement, replacee) \
    __attribute__((used)) static struct { const void *r; const void *o; } glf_interpose_##replacee \
    __attribute__((section("__DATA,__interpose"))) = { (const void *)(unsigned long)&replacement, (const void *)(unsigned long)&replacee };
GLF_INTERPOSE(glf_dlsym, dlsym)

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

__attribute__((constructor)) static void glf_init(void)
{
    const char *name = getprogname();
    if (!name || strncmp(name, "wine", 4) || !strcmp(name, "wineserver")) return;   /* the Wine loader's processes only */
    if (runsWineMetalGL() && !switchedOff("LULLABY_GL_CLEAR")) hookTextureLabel();
}
