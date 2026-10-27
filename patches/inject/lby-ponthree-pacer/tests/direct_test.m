/* Test of the Direct part of lby-ponthree-pacer: run as a process named wine-* with the library injected.
 *   formats on   LULLABY_DIRECT=1: an RGB-ordered format becomes its BGR twin; a BGR-ordered one is left alone
 *   formats off  LULLABY_DIRECT=0 (or unset): nothing changes
 *   sync         the layer's V-Sync is what the game asked (no Wine window is in native full screen here) */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void check(const char *what, NSUInteger got, NSUInteger want)
{
    if (got == want) { printf("ok: %s (%lu)\n", what, (unsigned long)got); return; }
    printf("FAIL: %s: got %lu, wanted %lu\n", what, (unsigned long)got, (unsigned long)want);
    failures++;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc < 2) return 2;
        BOOL on = !strcmp(argv[1], "on");
        if (!strcmp(argv[1], "sync")) {
            CAMetalLayer *l = [CAMetalLayer layer];
            l.displaySyncEnabled = NO;
            check("V-Sync as the game asked, off", l.displaySyncEnabled, NO);
            l.displaySyncEnabled = YES;
            check("V-Sync as the game asked, on", l.displaySyncEnabled, YES);
            return failures;
        }
        struct { MTLPixelFormat in, onOut; } rows[] = {
            { MTLPixelFormatRGB10A2Unorm, MTLPixelFormatBGR10A2Unorm },
            { MTLPixelFormatRGBA8Unorm, MTLPixelFormatBGRA8Unorm },
            { MTLPixelFormatRGBA8Unorm_sRGB, MTLPixelFormatBGRA8Unorm_sRGB },
            { MTLPixelFormatBGRA8Unorm, MTLPixelFormatBGRA8Unorm },
            { MTLPixelFormatBGR10A2Unorm, MTLPixelFormatBGR10A2Unorm },
            { MTLPixelFormatRGBA16Float, MTLPixelFormatRGBA16Float },
        };
        for (size_t i = 0; i < sizeof rows / sizeof rows[0]; i++) {
            CAMetalLayer *l = [CAMetalLayer layer];
            l.pixelFormat = rows[i].in;
            char what[64];
            snprintf(what, sizeof what, "format %lu with the switch %s", (unsigned long)rows[i].in, on ? "on" : "off");
            check(what, l.pixelFormat, on ? rows[i].onOut : rows[i].in);
        }
    }
    return failures;
}
