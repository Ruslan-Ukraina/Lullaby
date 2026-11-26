// lby-photofinish-stream without a game: frames presented through a CAMetalLayer, the Metal 3 way (presentDrawable:)
// and the Metal 4 way (signalDrawable:, as D3DMetal does), must reach a Syphon client with their pixels and the right
// way up. Run directly (not through `arch`, which drops DYLD_INSERT_LIBRARIES):
//   LULLABY_STREAM=1 DYLD_INSERT_LIBRARIES=<lullaby-stream.dylib> stream_test
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

enum { W = 256, H = 128 };

// Top half one colour, bottom half another (BGRA8).
static void fill(id<MTLCommandBuffer> cb, id<MTLTexture> t, uint32_t top, uint32_t bottom) {
    id<MTLBuffer> b = [cb.device newBufferWithLength:W * H * 4 options:MTLResourceStorageModeShared];
    uint32_t *p = b.contents;
    for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) p[y * W + x] = y < H / 2 ? top : bottom;
    id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
    [e copyFromBuffer:b sourceOffset:0 sourceBytesPerRow:W * 4 sourceBytesPerImage:W * H * 4 sourceSize:MTLSizeMake(W, H, 1)
            toTexture:t destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)];
    [e endEncoding];
}

static void spin(double s) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }

// The client's latest frame: its top-left and bottom-left pixels.
static BOOL readBack(id client, id<MTLDevice> dev, id<MTLCommandQueue> q, uint32_t *top, uint32_t *bottom) {
    id<MTLTexture> img = ((id (*)(id, SEL))objc_msgSend)(client, sel_registerName("newFrameImage"));
    if (!img) return NO;
    id<MTLBuffer> b = [dev newBufferWithLength:img.width * img.height * 4 options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
    [e copyFromTexture:img sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(img.width, img.height, 1)
              toBuffer:b destinationOffset:0 destinationBytesPerRow:img.width * 4 destinationBytesPerImage:img.width * img.height * 4];
    [e endEncoding];
    [cb commit]; [cb waitUntilCompleted];
    const uint32_t *p = b.contents;
    *top = p[4 * img.width + 4]; *bottom = p[(img.height - 5) * img.width + 4];
    return img.width == W && img.height == H;
}

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *own = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/lullaby/components/stream/Syphon.framework"];
        if (!getenv("LULLABY_SYPHON_FRAMEWORK") && ![fm fileExistsAtPath:own]
            && ![fm fileExistsAtPath:@"/Applications/OBS.app/Contents/Frameworks/Syphon.framework"]) {
            printf("==> stream_test: SKIP (no Syphon.framework: neither OBS nor components/stream)\n");
            return 0;
        }
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        id<MTLCommandQueue> q = [dev newCommandQueue];
        id<MTL4CommandQueue> q4 = [dev newMTL4CommandQueue];
        CAMetalLayer *layer = [CAMetalLayer layer];
        layer.device = dev; layer.pixelFormat = MTLPixelFormatBGRA8Unorm; layer.drawableSize = CGSizeMake(W, H);
        layer.allowsNextDrawableTimeout = YES;
        int fails = 0;
        const struct { const char *name; BOOL mtl4; uint32_t top, bottom; } cases[] = {
            {"Metal 3 presentDrawable:", NO, 0xff00ff00, 0xffff0000},
            {"Metal 4 signalDrawable:", YES, 0xff0000ff, 0xffffff00},
        };
        id client = nil;
        for (int c = 0; c < 2; c++) {
            for (int f = 0; f < 3; f++) {
                id<CAMetalDrawable> d = [layer nextDrawable];
                if (!d) { printf("FAIL %s: no drawable\n", cases[c].name); return 1; }
                id<MTLCommandBuffer> cb = [q commandBuffer];
                fill(cb, d.texture, cases[c].top, cases[c].bottom);
                if (!cases[c].mtl4) { [cb presentDrawable:d]; [cb commit]; [cb waitUntilCompleted]; }
                else { [cb commit]; [cb waitUntilCompleted]; [q4 signalDrawable:d]; [d present]; }
                spin(0.1);
                if (!client) {
                    Class dir = NSClassFromString(@"SyphonServerDirectory");
                    if (!dir) { printf("FAIL: Syphon not loaded (is the library injected, LULLABY_STREAM=1?)\n"); return 1; }
                    id shared = ((id (*)(id, SEL))objc_msgSend)(dir, sel_registerName("sharedDirectory"));
                    for (int i = 0; i < 30 && !client; i++) {
                        NSArray *servers = ((id (*)(id, SEL))objc_msgSend)(shared, sel_registerName("servers"));
                        for (NSDictionary *s in servers)
                            if ([s[@"SyphonServerDescriptionNameKey"] isEqual:@"Lullaby"])
                                client = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)([NSClassFromString(@"SyphonMetalClient") alloc],
                                    sel_registerName("initWithServerDescription:device:options:newFrameHandler:"), s, dev, nil, nil);
                        if (!client) spin(0.1);
                    }
                    if (!client) { printf("FAIL: no Syphon server named Lullaby\n"); return 1; }
                }
            }
            spin(0.3);
            uint32_t top = 0, bottom = 0;
            BOOL sized = readBack(client, dev, q, &top, &bottom);
            BOOL ok = sized && top == cases[c].top && bottom == cases[c].bottom;
            printf("%s %-26s top %08x bottom %08x (want %08x %08x)%s\n", ok ? "ok  " : "FAIL", cases[c].name, top, bottom,
                   cases[c].top, cases[c].bottom, sized ? "" : ", wrong size or no frame");
            fails += !ok;
        }
        printf("==> stream_test: %s\n", fails ? "FAILED" : "frames reach Syphon from both present paths");
        return fails != 0;
    }
}
