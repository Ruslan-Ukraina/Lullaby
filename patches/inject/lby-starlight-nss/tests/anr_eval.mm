// ANR on recorded game frames (an agent/nss-set dump): for frames n and n+2 it generates the middle one through the real
// MetalFX frame-interpolator hook, and writes it beside the dump's own frame n+1 so a script can measure how far the
// generated frame is from the real one (overall, and at depth edges, where a halo shows).
//   anr_eval <fsr4 root> <anr runtime> <dump dir> <first,last> <out dir>
// The dump's "metalfx" frames (the game's upscaled picture, RGB9E5) are the colour; its depth and motion are the game's.
// Motion of frame n+2 covers one frame, so it is doubled for the two-frame step (constant speed assumed).
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#include "src/anr/anr_live.h"
#include "src/common/fsr4_fg_settings.h"
#include <cmath>
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
    t.storageMode = m; t.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;
    return [d newTextureWithDescriptor:t];
}
static std::vector<uint8_t> slurp(const std::string &p) {
    FILE *f = fopen(p.c_str(), "rb"); need(f, ("missing " + p).c_str());
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> b(n); need(fread(b.data(), 1, n, f) == (size_t)n, "short read"); fclose(f); return b;
}
// RGB9E5 -> RGBA half
static void rgb9e5ToHalf(const uint32_t *in, _Float16 *out, size_t n) {
    for (size_t i = 0; i < n; ++i) {
        const uint32_t v = in[i]; const float s = ldexpf(1.f, int(v >> 27) - 15 - 9);
        out[i * 4 + 0] = (_Float16)((v & 511) * s); out[i * 4 + 1] = (_Float16)(((v >> 9) & 511) * s);
        out[i * 4 + 2] = (_Float16)(((v >> 18) & 511) * s); out[i * 4 + 3] = (_Float16)1;
    }
}

int main(int argc, char **argv) { @autoreleasepool { try {
    need(argc >= 6, "usage: anr_eval <fsr4 root> <anr runtime> <dump dir> <first,last> <out dir>");
    const std::string dump = argv[3], outDir = argv[5];
    int first = 0, last = 0; need(sscanf(argv[4], "%d,%d", &first, &last) == 2, "range first,last");
    setenv("FSR4_ROOT", argv[1], 1); setenv("FSR4_ANR_RUNTIME", argv[2], 1); setenv("FSR4_ANR_STATUS_DISABLED", "1", 1);
    setenv("FSR4_ANR_COLOR", "linear", 1); setenv("FSR4_FG", "metalfx", 1); setenv("FSR4_FG_SETTINGS", "none", 1);
    fsr4_anr_refresh_settings();
    const unsigned W = 2294, H = 1290, RW = 1530, RH = 860;
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice(); need(dev, "no device");
    MTLFXFrameInterpolatorDescriptor *d = [MTLFXFrameInterpolatorDescriptor new];
    d.inputWidth = RW; d.inputHeight = RH; d.outputWidth = W; d.outputHeight = H;
    d.colorTextureFormat = d.outputTextureFormat = d.uiTextureFormat = MTLPixelFormatRGBA16Float;
    d.depthTextureFormat = MTLPixelFormatR32Float; d.motionTextureFormat = MTLPixelFormatRG16Float;
    NSError *err = nil;
    id<MTL4Compiler> compiler = [dev newCompilerWithDescriptor:[MTL4CompilerDescriptor new] error:&err];
    id fg = [d newFrameInterpolatorWithDevice:dev compiler:compiler]; need(fg, "no frame interpolator");
    char dir[] = "/tmp/anr-eval-XXXXXX"; need(mkdtemp(dir), "mkdtemp");
    const std::string pref = std::string(dir) + "/fg-settings.conf";
    const bool native = getenv("ANR_EVAL_NATIVE") != nullptr;   // MetalFX frame generation on the same frames, for comparison
    need(fsr4_fg::write_settings(pref, native ? fsr4_fg::Mode::MetalFX : fsr4_fg::Mode::ANR), "preference");
    setenv("FSR4_FG_SETTINGS", pref.c_str(), 1); setenv("FSR4_FG", native ? "metalfx" : "anr", 1);
    std::this_thread::sleep_for(std::chrono::milliseconds(700));
    need(fsr4_anr_selected_mode() == (native ? 0 : 1), "FG mode not selected");
    id<MTLFXFrameInterpolatorBase> b = fg;
    id<MTLTexture> c0 = tex(dev, W, H, MTLPixelFormatRGBA16Float), c1 = tex(dev, W, H, MTLPixelFormatRGBA16Float);
    id<MTLTexture> z = tex(dev, RW, RH, MTLPixelFormatR32Float), mv = tex(dev, RW, RH, MTLPixelFormatRG16Float);
    id<MTLTexture> out = tex(dev, W, H, MTLPixelFormatRGBA16Float);
    id<MTL4CommandQueue> q4 = [dev newMTL4CommandQueue]; id<MTL4CommandAllocator> alloc = [dev newCommandAllocator];
    id<MTLSharedEvent> ev = [dev newSharedEvent]; uint64_t token = 0;
    id<MTLResidencySet> res = [dev newResidencySetWithDescriptor:[MTLResidencySetDescriptor new] error:&err];
    for (id<MTLTexture> t : @[c0, c1, z, mv, out]) [res addAllocation:t];
    [res commit];
    id<MTLFence> fence = [dev newFence]; b.fence = fence;
    b.depthTexture = z; b.motionTexture = mv; b.outputTexture = out;
    b.nearPlane = .1f; b.farPlane = 1000; b.fieldOfView = 60; b.aspectRatio = float(W) / H; b.deltaTime = 1.f / 30;
    b.depthReversed = getenv("ANR_EVAL_DEPTH_FWD") ? NO : YES;   // RE9 reverses depth; the switch measures a wrong flag
    std::vector<_Float16> half(size_t(W) * H * 4);
    auto loadColor = [&](id<MTLTexture> t, int n) {
        char p[64]; snprintf(p, sizeof p, "/%03d-%s.raw", n, getenv("ANR_EVAL_FRAME") ? getenv("ANR_EVAL_FRAME") : "metalfx");
        auto raw = slurp(dump + p); need(raw.size() == size_t(W) * H * 4, "metalfx frame size");
        rgb9e5ToHalf((const uint32_t *)raw.data(), half.data(), size_t(W) * H);
        [t replaceRegion:MTLRegionMake2D(0, 0, W, H) mipmapLevel:0 withBytes:half.data() bytesPerRow:W * 8];
    };
    auto loadDM = [&](int n) {
        char p[64]; snprintf(p, sizeof p, "/%03d-depth.raw", n);
        auto zr = slurp(dump + p); need(zr.size() == size_t(RW) * RH * 4, "depth size");
        [z replaceRegion:MTLRegionMake2D(0, 0, RW, RH) mipmapLevel:0 withBytes:zr.data() bytesPerRow:RW * 4];
        snprintf(p, sizeof p, "/%03d-motion.raw", n);
        auto mr = slurp(dump + p); need(mr.size() == size_t(RW) * RH * 4, "motion size");
        [mv replaceRegion:MTLRegionMake2D(0, 0, RW, RH) mipmapLevel:0 withBytes:mr.data() bytesPerRow:RW * 4];
    };
    auto encode = [&] {
        id<MTL4CommandBuffer> cb = [dev newCommandBuffer]; [alloc reset]; [cb beginCommandBufferWithAllocator:alloc];
        [cb useResidencySet:res];
        id<MTL4ComputeCommandEncoder> e = [cb computeCommandEncoder]; [e updateFence:fence afterEncoderStages:MTLStageDispatch]; [e endEncoding];
        [(id<MTL4FXFrameInterpolator>)fg encodeToCommandBuffer:cb]; [cb endCommandBuffer];
        id<MTL4CommandBuffer> list[] = {cb}; [q4 commit:list count:1]; [q4 signalEvent:ev value:++token];
        need([ev waitUntilSignaledValue:token timeoutMS:20000], "GPU timeout");
    };
    // motion in the dump is in render pixels scaled by mvscale (meta: 1530,860 = UV); doubled for two frames
    const float mvs = getenv("ANR_EVAL_MVMUL") ? (float)atof(getenv("ANR_EVAL_MVMUL")) : 2.f;
    b.motionVectorScaleX = RW * mvs; b.motionVectorScaleY = RH * mvs;
    int made = 0;
    for (int n = first; n + 2 <= last; n += 2) {
        // prime with frame n, then frame n+2 generates the middle
        loadColor(c0, n); loadDM(n); b.colorTexture = c0; b.prevColorTexture = c0; b.shouldResetHistory = YES; encode();
        if (getenv("ANR_EVAL_ONETEX")) {   // one colour texture for every frame, as Lullaby's offset adapter hands ANR
            loadColor(c0, n + 2); loadDM(n + 2); b.colorTexture = c0; b.prevColorTexture = c0; b.shouldResetHistory = NO; encode();
        } else {
        loadColor(c1, n + 2); loadDM(n + 2); b.colorTexture = c1; b.prevColorTexture = c0; b.shouldResetHistory = NO; encode();
        }
        Fsr4AnrStatus s = {}; fsr4_anr_get_status(&s);
        need(native || s.active, s.reason[0] ? s.reason : "ANR inactive");
        id<MTLBuffer> rb = [dev newBufferWithLength:size_t(W) * H * 8 options:MTLResourceStorageModeShared];
        id<MTLCommandQueue> q = [dev newCommandQueue]; id<MTLCommandBuffer> cb = [q commandBuffer];
        id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
        [bl copyFromTexture:out sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(W, H, 1)
                   toBuffer:rb destinationOffset:0 destinationBytesPerRow:W * 8 destinationBytesPerImage:size_t(W) * H * 8];
        [bl endEncoding]; [cb commit]; [cb waitUntilCompleted];
        char p[64]; snprintf(p, sizeof p, "/%03d-gen.f16", n + 1);
        FILE *f = fopen((outDir + p).c_str(), "wb"); need(f, "out file");
        fwrite(rb.contents, 1, size_t(W) * H * 8, f); fclose(f); ++made;
    }
    unlink(pref.c_str()); rmdir(dir);
    printf("anr_eval: %d generated frames in %s\n", made, outDir.c_str());
    return 0;
} catch (const std::exception &e) { fprintf(stderr, "anr_eval: %s\n", e.what()); return 1; } } }
