/* The injected library in a process that runs "WineMetalGL" (WINEDLLOVERRIDES names it): a
 * texture given the label WineMetalGL uses. The program's name starts with "wine" like the loader's, and the library comes in
 * with DYLD_INSERT_LIBRARIES .
 *
 *   wine-glfixes-test texture clear|keep             a texture labelled "default framebuffer" is black afterwards (clear),
 *                                                    one with another label keeps its colour (keep), both (off) when switched off */
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>

static int check(int ok, const char *what) { printf("%s %s\n", ok ? "ok:" : "FAIL:", what); return ok ? 0 : 1; }

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
        if (argc >= 3 && !strcmp(argv[1], "texture")) return texture(argv[2]) ? 1 : 0;
    }
    fprintf(stderr, "usage: see the head of this file\n");
    return 2;
}
