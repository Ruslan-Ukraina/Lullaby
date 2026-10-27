/* The injected library in a process that runs "WineMetalGL" (WINEDLLOVERRIDES names it): the list of pixel formats and a
 * texture given the label WineMetalGL uses. The program's name starts with "wine" like the loader's, and the library comes in
 * with DYLD_INSERT_LIBRARIES (the dlsym lookup is taken by dyld's interposing, which only an inserted library gets).
 *
 *   wine-glfixes-test formats FAKECORE.dylib 32|24   the formats' colour bits after the lookup: 32 where RGBA8, 16 stays
 *   wine-glfixes-test texture clear|keep             a texture labelled "default framebuffer" is black afterwards (clear),
 *                                                    one with another label keeps its colour (keep), both (off) when switched off */
#import <Metal/Metal.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

struct fmt { int draw_to_window, draw_to_pbuffer, double_buffer, stereo, color_bits, red_bits, green_bits, blue_bits, alpha_bits; };
typedef unsigned (*get_t)(struct fmt *, unsigned, unsigned *);

static int check(int ok, const char *what) { printf("%s %s\n", ok ? "ok:" : "FAIL:", what); return ok ? 0 : 1; }

static int formats(const char *lib, int want)
{
    void *h = dlopen(lib, RTLD_NOW);
    get_t get = h ? (get_t)dlsym(h, "wmgl_get_pixel_formats") : NULL;
    struct fmt f[3] = {{0}};
    unsigned on = 0, n = get ? get(f, 3, &on) : 0;
    int bad = check(get && n == 3 && on == 3, "the call returns the count and the onscreen count");
    bad += check(f[0].color_bits == want && f[1].color_bits == want, want == 32 ? "RGBA8 formats say 32" : "RGBA8 formats are left at 24");
    bad += check(f[2].color_bits == 16, "the RGB565 format stays 16");
    return bad;
}

static unsigned firstPixel(id<MTLTexture> t)
{
    unsigned p = 0;
    [t getBytes:&p bytesPerRow:4 fromRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0];
    return p;
}

static id<MTLTexture> red(id<MTLDevice> d)
{
    MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
    desc.storageMode = MTLStorageModeShared;
    desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    id<MTLTexture> t = [d newTextureWithDescriptor:desc];
    unsigned px[16];
    for (int i = 0; i < 16; i++) px[i] = 0xFF0000FF;   /* RGBA: red */
    [t replaceRegion:MTLRegionMake2D(0, 0, 4, 4) mipmapLevel:0 withBytes:px bytesPerRow:16];
    return t;
}

static int texture(const char *mode)
{
    id<MTLDevice> d = MTLCreateSystemDefaultDevice();
    id<MTLTexture> fb = red(d), other = red(d);
    fb.label = @"default framebuffer";
    other.label = @"something else";
    int bad = 0;
    if (!strcmp(mode, "clear")) {
        bad += check(firstPixel(fb) == 0xFF000000, "the framebuffer texture is black (alpha 1) after its label is set");
        bad += check(firstPixel(other) == 0xFF0000FF, "a texture with another label keeps its colour");
    } else {
        bad += check(firstPixel(fb) == 0xFF0000FF && firstPixel(other) == 0xFF0000FF, "switched off: both keep their colour");
    }
    return bad;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc >= 4 && !strcmp(argv[1], "formats")) return formats(argv[2], atoi(argv[3])) ? 1 : 0;
        if (argc >= 3 && !strcmp(argv[1], "texture")) return texture(argv[2]) ? 1 : 0;
    }
    fprintf(stderr, "usage: see the head of this file\n");
    return 2;
}
