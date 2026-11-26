// ANR through MetalFX's frame interpolator when the game's picture sits inside a larger texture (outputOffset), as
// D3DMetal hands RE9's letterboxed frame: fsr4-native-macos patches 0004 (2x) and 0005 (3x). Checks pixels, not counts:
// the generated frame in the output at the offset, the bars untouched, and the 3x extra frame not empty.
//   built against a patched fsr4-native-macos tree (see the README), run as
//   anr_offset_test <fsr4 root> <anr runtime dir> [2x|3x]
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#include "src/anr/anr_live.h"
#include "src/common/fsr4_fg_settings.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

static void need(bool ok, const char *why) { if (!ok) throw std::runtime_error(why); }
static id<MTLTexture> tex(id<MTLDevice> d, unsigned w, unsigned h, MTLPixelFormat f, MTLStorageMode m = MTLStorageModeShared) {
    MTLTextureDescriptor *t = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:f width:w height:h mipmapped:NO];
    t.storageMode = m;
    t.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;
    return [d newTextureWithDescriptor:t];
}
// RGB10A2 words of a region, read through a shared copy (the texture may be private)
static std::vector<uint32_t> readRGB10(id<MTLDevice> d, id<MTLCommandQueue> q, id<MTLTexture> t, unsigned x, unsigned y, unsigned w, unsigned h) {
    id<MTLBuffer> b = [d newBufferWithLength:size_t(w) * h * 4 options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
    [e copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(x, y, 0) sourceSize:MTLSizeMake(w, h, 1)
              toBuffer:b destinationOffset:0 destinationBytesPerRow:w * 4 destinationBytesPerImage:size_t(w) * h * 4];
    [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
    const uint32_t *p = (const uint32_t *)b.contents;
    return std::vector<uint32_t>(p, p + size_t(w) * h);
}
static double meanLevel(const std::vector<uint32_t> &px) {
    double s = 0;
    for (uint32_t v : px) s += (v & 1023) + ((v >> 10) & 1023) + ((v >> 20) & 1023);
    return s / (3.0 * px.size());
}

extern "C" volatile uint32_t lby_upscale_out_w, lby_upscale_out_h;   // the game's upscaled size, as fsr4_metalfx.m sets it
int main(int argc, char **argv) { @autoreleasepool { try {
    // ANR_TEST_UPW/UPH: the game's upscaled size (RE9 2294x1290), for MetalFX frame generation at that size (patch 0023,
    // FSR4_MFX_SIZE=game with "native"); ANR_TEST_WAIT=ms: a pause after the first frame for the small interpolator
    if (getenv("ANR_TEST_UPW")) { lby_upscale_out_w = (uint32_t)atoi(getenv("ANR_TEST_UPW")); lby_upscale_out_h = (uint32_t)atoi(getenv("ANR_TEST_UPH")); }
    need(argc >= 3, "usage: anr_offset_test <fsr4 root> <anr runtime> [2x|3x]");
    const bool three = argc > 3 && !strcmp(argv[3], "3x"), native = argc > 3 && !strcmp(argv[3], "native");
    setenv("FSR4_ROOT", argv[1], 1); setenv("FSR4_ANR_RUNTIME", argv[2], 1);
    setenv("FSR4_ANR_STATUS_DISABLED", "1", 1); setenv("FSR4_ANR_COLOR", "pq10", 1);
    setenv("FSR4_FG", "metalfx", 1); setenv("FSR4_FG_SETTINGS", "none", 1); fsr4_anr_refresh_settings();
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice(); need(dev, "no device");
    const unsigned W = getenv("ANR_TEST_W") ? (unsigned)atoi(getenv("ANR_TEST_W")) : 1920u, H = getenv("ANR_TEST_H") ? (unsigned)atoi(getenv("ANR_TEST_H")) : 1080u, OY = getenv("ANR_TEST_OY") ? (unsigned)atoi(getenv("ANR_TEST_OY")) : 98u, TH = H + 2 * OY;   // picture W x H at y OY of a W x TH texture
    const MTLPixelFormat F = MTLPixelFormatRGB10A2Unorm;
    MTLFXFrameInterpolatorDescriptor *d = [MTLFXFrameInterpolatorDescriptor new];
    const unsigned RW = getenv("ANR_TEST_RW") ? (unsigned)atoi(getenv("ANR_TEST_RW")) : W, RH = getenv("ANR_TEST_RH") ? (unsigned)atoi(getenv("ANR_TEST_RH")) : H;
    d.inputWidth = RW; d.inputHeight = RH; d.outputWidth = W; d.outputHeight = H;
    d.colorTextureFormat = d.outputTextureFormat = d.uiTextureFormat = F;
    d.depthTextureFormat = MTLPixelFormatR32Float; d.motionTextureFormat = MTLPixelFormatRG16Float;
    NSError *err = nil;
    id<MTL4Compiler> compiler = [dev newCompilerWithDescriptor:[MTL4CompilerDescriptor new] error:&err];
    id fg = [d newFrameInterpolatorWithDevice:dev compiler:compiler]; need(fg, "no MetalFX frame interpolator");
    // the hook from here on: ANR 2x or 3x through the saved preference, as the game would get it
    char dir[] = "/tmp/anr-offset-XXXXXX"; need(mkdtemp(dir), "mkdtemp");
    const std::string pref = std::string(dir) + "/fg-settings.conf";
    need(fsr4_fg::write_settings(pref, native ? fsr4_fg::Mode::MetalFX : three ? fsr4_fg::Mode::ANR3x : fsr4_fg::Mode::ANR), "preference");
    setenv("FSR4_FG_SETTINGS", pref.c_str(), 1); setenv("FSR4_FG", native ? "metalfx" : three ? "anr3x" : "anr", 1);
    std::this_thread::sleep_for(std::chrono::milliseconds(700));
    need(fsr4_anr_selected_mode() == (native ? 0 : three ? 2 : 1), "FG mode not selected");

    __strong id<MTLFXFrameInterpolatorBase> fgb = fg;
    id<MTLTexture> color = tex(dev, W, TH, F), ui = tex(dev, W, TH, F), out = tex(dev, W, TH, F, MTLStorageModePrivate);
    id<MTLTexture> prev = tex(dev, W, TH, F), depth = tex(dev, RW, RH, MTLPixelFormatR32Float), motion = tex(dev, RW, RH, MTLPixelFormatRG16Float);
    std::vector<uint32_t> px(size_t(W) * TH, 0xC0000000u);   // bars: black, opaque
    for (unsigned y = OY; y < OY + H; ++y) for (unsigned x = 0; x < W; ++x)
        px[size_t(y) * W + x] = getenv("ANR_TEST_SMOOTH")   // a gradient without wraps (resampling keeps its mean)
            ? 0xC0000000u | ((x * 1023 / W) << 10) | (y - OY) * 1023 / H | (512u << 20)
            : 0xC0000000u | ((x % 1024) << 10) | ((y * 3) % 1024) | (512u << 20);
    [color replaceRegion:MTLRegionMake2D(0, 0, W, TH) mipmapLevel:0 withBytes:px.data() bytesPerRow:W * 4];
    [prev replaceRegion:MTLRegionMake2D(0, 0, W, TH) mipmapLevel:0 withBytes:px.data() bytesPerRow:W * 4];
    std::vector<uint32_t> zeroUI(size_t(W) * TH, 0);
    [ui replaceRegion:MTLRegionMake2D(0, 0, W, TH) mipmapLevel:0 withBytes:zeroUI.data() bytesPerRow:W * 4];
    std::vector<float> z(size_t(RW) * RH, .5f); std::vector<uint16_t> mv(size_t(RW) * RH * 2, 0);
    [depth replaceRegion:MTLRegionMake2D(0, 0, RW, RH) mipmapLevel:0 withBytes:z.data() bytesPerRow:RW * 4];
    [motion replaceRegion:MTLRegionMake2D(0, 0, RW, RH) mipmapLevel:0 withBytes:mv.data() bytesPerRow:RW * 4];
    fgb.colorTexture = color; fgb.prevColorTexture = prev; fgb.depthTexture = depth; fgb.motionTexture = motion;
    fgb.outputTexture = out; if (!getenv("ANR_TEST_NOUI")) { fgb.uiTexture = ui; fgb.uiTextureComposited = YES; }
    if (OY) ((id<MTL4FXFrameInterpolator>)fg).outputOffsetY = OY;   // D3DMetal's letterbox
    fgb.motionVectorScaleX = fgb.motionVectorScaleY = 1; fgb.nearPlane = .1f; fgb.farPlane = 1000; fgb.fieldOfView = 60;
    fgb.aspectRatio = float(W) / H; fgb.deltaTime = 1.f / 60; fgb.depthReversed = NO;
    id<MTL4CommandQueue> q4 = [dev newMTL4CommandQueue]; id<MTL4CommandAllocator> alloc = [dev newCommandAllocator];
    id<MTLCommandQueue> q = [dev newCommandQueue]; id<MTLSharedEvent> ev = [dev newSharedEvent]; uint64_t token = 0;
    id<MTLResidencySet> res = [dev newResidencySetWithDescriptor:[MTLResidencySetDescriptor new] error:&err];
    for (id<MTLTexture> t : @[color, ui, out, prev, depth, motion]) [res addAllocation:t];
    [res commit];
    id<MTLFence> fence = [dev newFence]; fgb.fence = fence;
    auto encode = [&] {
        id<MTL4CommandBuffer> cb = [dev newCommandBuffer]; [alloc reset]; [cb beginCommandBufferWithAllocator:alloc];
        [cb useResidencySet:res];
        id<MTL4ComputeCommandEncoder> e = [cb computeCommandEncoder]; [e updateFence:fence afterEncoderStages:MTLStageDispatch]; [e endEncoding];
        [(id<MTL4FXFrameInterpolator>)fg encodeToCommandBuffer:cb]; [cb endCommandBuffer];
        id<MTL4CommandBuffer> list[] = {cb}; [q4 commit:list count:1]; [q4 signalEvent:ev value:++token];
        need([ev waitUntilSignaledValue:token timeoutMS:20000], "GPU timeout");
    };
    { const double t0 = CFAbsoluteTimeGetCurrent(); fgb.shouldResetHistory = YES; encode();
      printf("first frame (ANR set up + prime): %.1f ms\n", (CFAbsoluteTimeGetCurrent() - t0) * 1000); }
    if (const char *wt = getenv("ANR_TEST_WAIT")) std::this_thread::sleep_for(std::chrono::milliseconds(atoi(wt)));
    fgb.shouldResetHistory = NO; encode(); encode();
    Fsr4AnrStatus s = {}; fsr4_anr_get_status(&s);
    printf("status: active %u generated %llu primed %llu reason '%s'\n", s.active, (unsigned long long)s.generated,
           (unsigned long long)s.primed, s.reason);
    need(native || (s.active && s.generated >= 1), "ANR did not generate");
    if (const char *b = getenv("ANR_TEST_BENCH")) {   // GPU time of N generated frames, one command buffer each
        const int n = atoi(b); double total = 0, best = 1e9;
        for (int i = 0; i < n; ++i) {
            id<MTL4CommandBuffer> cb = [dev newCommandBuffer]; [alloc reset]; [cb beginCommandBufferWithAllocator:alloc];
            [cb useResidencySet:res];
            id<MTL4ComputeCommandEncoder> e = [cb computeCommandEncoder]; [e updateFence:fence afterEncoderStages:MTLStageDispatch]; [e endEncoding];
            [(id<MTL4FXFrameInterpolator>)fg encodeToCommandBuffer:cb]; [cb endCommandBuffer];
            id<MTL4CommandBuffer> list[] = {cb};
            const double t0 = CFAbsoluteTimeGetCurrent();
            [q4 commit:list count:1]; [q4 signalEvent:ev value:++token];
            need([ev waitUntilSignaledValue:token timeoutMS:20000], "GPU timeout");
            const double ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000; if (i >= 3) { total += ms; if (ms < best) best = ms; }
        }
        printf("bench %ux%u offset %u: %d frames, mean %.2f ms, best %.2f ms (submit to done, ANR + copies)\n", W, H, OY, n - 3, total / (n - 3), best);
    }
    const auto pic = readRGB10(dev, q, out, 0, OY, W, H), bar = OY ? readRGB10(dev, q, out, 0, 0, W, OY) : std::vector<uint32_t>(1, 0);
    const auto src = readRGB10(dev, q, color, 0, OY, W, H);
    const double lp = meanLevel(pic), ls = meanLevel(src), lb = meanLevel(bar);
    printf("output picture level %.1f (source %.1f), bar level %.1f\n", lp, ls, lb);
    need(lp > 0.5 * ls, "generated frame in the output is dark: not written at the offset");
    int rc = 0;
    if (three) {
        void *extraRaw = nullptr; double step = 0; uint64_t ticket = 0;
        const int e1 = fsr4_anr_on_present_event((__bridge void *)dev, &extraRaw, &step, &ticket);
        id<MTLTexture> extra = (__bridge_transfer id<MTLTexture>)extraRaw;
        printf("3x present event %d, extra %lux%lu format %lu\n", e1, (unsigned long)extra.width, (unsigned long)extra.height,
               (unsigned long)extra.pixelFormat);
        need(e1 == 1 && extra, "no 3x extra frame handed out");
        const auto ex = readRGB10(dev, q, extra, 0, 0, (unsigned)extra.width, (unsigned)extra.height);
        const double le = meanLevel(ex);
        printf("3x extra frame level %.1f (source %.1f)\n", le, ls);
        fsr4_anr_release_extra_ticket(ticket, 0);
        if (le < 0.5 * ls) { fprintf(stderr, "3x extra frame is dark\n"); rc = 1; }
    }
    if (getenv("ANR_TEST_REUSE")) {   // a new interpolator of the same shape, as a game makes at a scene change
        @autoreleasepool { fg = nil; fgb = nil; }
        std::this_thread::sleep_for(std::chrono::milliseconds(300));
        fg = [d newFrameInterpolatorWithDevice:dev compiler:compiler]; fgb = fg;
        fgb.colorTexture = color; fgb.prevColorTexture = prev; fgb.depthTexture = depth; fgb.motionTexture = motion;
        fgb.outputTexture = out; fgb.fence = fence;
        if (OY) ((id<MTL4FXFrameInterpolator>)fg).outputOffsetY = OY;
        fgb.motionVectorScaleX = fgb.motionVectorScaleY = 1; fgb.nearPlane = .1f; fgb.farPlane = 1000; fgb.fieldOfView = 60;
        fgb.aspectRatio = float(W) / H; fgb.deltaTime = 1.f / 60;
        const double t0 = CFAbsoluteTimeGetCurrent(); fgb.shouldResetHistory = YES; encode();
        printf("second interpolator's first frame: %.1f ms\n", (CFAbsoluteTimeGetCurrent() - t0) * 1000);
        fgb.shouldResetHistory = NO; encode();
        const auto pic2 = readRGB10(dev, q, out, 0, OY, W, H);
        printf("second interpolator picture level %.1f\n", meanLevel(pic2));
    }
    unlink(pref.c_str()); rmdir(dir);
    printf("==> anr_offset_test %s: %s\n", three ? "3x" : native ? "native" : "2x", rc ? "FAILED" : "picture in place");
    return rc;
} catch (const std::exception &e) { fprintf(stderr, "anr_offset_test: %s\n", e.what()); return 1; } } }
