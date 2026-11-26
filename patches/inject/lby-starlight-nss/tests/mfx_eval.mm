// MetalFX frame generation on recorded game frames (an agent/nss-set dump), through the FSR 4 hook as RE9 runs it:
// the game's upscaled picture (the dump's "shown", 2294x1290) is stretched to the window (3024x1701 at y 98 of a
// 3024x1898 texture) as D3DMetal does, a MetalFX frame interpolator of the window's size makes the middle frame of frames
// n and n+2, and the hook may take it to the game's size (FSR4_MFX_SIZE=game), dilate the motion (FSR4_MFX_DILATE=1) or
// fill the screen edge (FSR4_MFX_EDGE=1). Writes the generated picture and the real middle frame, both at the window's
// size, for mfx-eval-metric.py.
//   mfx_eval <fsr4 root> <dump dir> <first,last> <out dir>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#include "src/anr/anr_live.h"
#include "src/common/fsr4_fg_settings.h"
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

extern "C" volatile uint32_t lby_upscale_out_w, lby_upscale_out_h;
extern "C" volatile int lby_upscale_depth_reversed;

static void need(bool ok, const char *why) { if (!ok) throw std::runtime_error(why); }
static std::vector<uint8_t> slurp(const std::string &p) {
    FILE *f = fopen(p.c_str(), "rb"); need(f, ("missing " + p).c_str());
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> b(n); need(fread(b.data(), 1, n, f) == (size_t)n, "short read"); fclose(f); return b;
}
static id<MTLTexture> tex(id<MTLDevice> d, unsigned w, unsigned h, MTLPixelFormat f) {
    MTLTextureDescriptor *t = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:f width:w height:h mipmapped:NO];
    t.storageMode = MTLStorageModeShared;
    t.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;
    return [d newTextureWithDescriptor:t];
}

int main(int argc, char **argv) { @autoreleasepool { try {
    need(argc >= 5, "usage: mfx_eval <fsr4 root> <dump dir> <first,last> <out dir>");
    const std::string dump = argv[2], outDir = argv[4];
    int first = 0, last = 0; need(sscanf(argv[3], "%d,%d", &first, &last) == 2, "range first,last");
    setenv("FSR4_ROOT", argv[1], 1); setenv("FSR4_ANR_STATUS_DISABLED", "1", 1);
    setenv("FSR4_FG", "metalfx", 1); setenv("FSR4_FG_SETTINGS", "none", 1);
    fsr4_anr_refresh_settings();
    const unsigned UW = 2294, UH = 1290, RW = 1530, RH = 860, W = 3024, H = 1701, OY = 98, TH = H + 2 * OY;
    lby_upscale_out_w = UW; lby_upscale_out_h = UH; lby_upscale_depth_reversed = 1;
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice(); need(dev, "no device");
    char dir[] = "/tmp/mfx-eval-XXXXXX"; need(mkdtemp(dir), "mkdtemp");
    const std::string pref = std::string(dir) + "/fg-settings.conf";
    // MFX_EVAL_ANR=<runtime dir>: ANR 2x instead of MetalFX, set up as Lullaby runs it (game's size, dilated motion)
    const char *anr = getenv("MFX_EVAL_ANR");
    if (anr) {
        setenv("FSR4_ANR_RUNTIME", anr, 1); setenv("FSR4_FG", "anr", 1); setenv("FSR4_ANR_IGNORE_DISTORTION", "1", 1);
        if (!getenv("FSR4_ANR_SCALE")) setenv("FSR4_ANR_SCALE", "auto", 1); setenv("FSR4_ANR_COLOR", "linear", 1); setenv("FSR4_ANR_DEPTH", "auto", 1);
        if (!getenv("FSR4_ANR_DILATE")) setenv("FSR4_ANR_DILATE", "1", 1);
    }
    need(fsr4_fg::write_settings(pref, anr ? fsr4_fg::Mode::ANR : fsr4_fg::Mode::MetalFX), "preference");
    setenv("FSR4_FG_SETTINGS", pref.c_str(), 1);
    std::this_thread::sleep_for(std::chrono::milliseconds(700));
    need(fsr4_anr_selected_mode() == (anr ? 1 : 0), "FG mode not selected");
    MTLFXFrameInterpolatorDescriptor *d = [MTLFXFrameInterpolatorDescriptor new];
    d.inputWidth = RW; d.inputHeight = RH; d.outputWidth = W; d.outputHeight = H;
    d.colorTextureFormat = d.outputTextureFormat = d.uiTextureFormat = MTLPixelFormatRGBA16Float;
    d.depthTextureFormat = MTLPixelFormatR32Float; d.motionTextureFormat = MTLPixelFormatRG16Float;
    NSError *err = nil;
    id<MTL4Compiler> compiler = [dev newCompilerWithDescriptor:[MTL4CompilerDescriptor new] error:&err];
    id fg = [d newFrameInterpolatorWithDevice:dev compiler:compiler]; need(fg, "no frame interpolator");
    id<MTLFXFrameInterpolatorBase> b = fg;
    id<MTLTexture> c0 = tex(dev, W, TH, MTLPixelFormatRGBA16Float), c1 = tex(dev, W, TH, MTLPixelFormatRGBA16Float);
    id<MTLTexture> out = tex(dev, W, TH, MTLPixelFormatRGBA16Float);
    id<MTLTexture> z = tex(dev, RW, RH, MTLPixelFormatR32Float), mv = tex(dev, RW, RH, MTLPixelFormatRG16Float);
    id<MTL4CommandQueue> q4 = [dev newMTL4CommandQueue]; id<MTL4CommandAllocator> alloc = [dev newCommandAllocator];
    id<MTLSharedEvent> ev = [dev newSharedEvent]; uint64_t token = 0;
    id<MTLResidencySet> res = [dev newResidencySetWithDescriptor:[MTLResidencySetDescriptor new] error:&err];
    for (id<MTLTexture> t : @[c0, c1, out, z, mv]) [res addAllocation:t];
    [res commit];
    id<MTLFence> fence = [dev newFence]; b.fence = fence;
    b.depthTexture = z; b.motionTexture = mv; b.outputTexture = out;
    ((id<MTL4FXFrameInterpolator>)fg).outputOffsetY = OY;
    b.nearPlane = .1f; b.farPlane = 1000; b.fieldOfView = 60; b.aspectRatio = float(W) / H; b.deltaTime = 1.f / 25;
    b.depthReversed = YES;
    const float mvs = getenv("MFX_EVAL_MVMUL") ? (float)atof(getenv("MFX_EVAL_MVMUL")) : 2.f;   // two frames of motion
    b.motionVectorScaleX = RW * mvs; b.motionVectorScaleY = RH * mvs;

    // the game's upscaled frame (RGB9E5) stretched to the window, bilinear, as linear half floats
    std::vector<float> up(size_t(UW) * UH * 3);
    std::vector<_Float16> win(size_t(W) * TH * 4, (_Float16)0);
    for (size_t i = 0; i < size_t(W) * TH; ++i) win[i * 4 + 3] = (_Float16)1;
    auto stretch = [&](int n, std::vector<_Float16> &dst) {
        char p[64]; snprintf(p, sizeof p, "/%03d-shown.raw", n);
        auto raw = slurp(dump + p); need(raw.size() == size_t(UW) * UH * 4, "shown frame size");
        const uint32_t *u = (const uint32_t *)raw.data();
        for (size_t i = 0; i < size_t(UW) * UH; ++i) {
            const float s = ldexpf(1.f, int(u[i] >> 27) - 15 - 9);
            up[i * 3] = (u[i] & 511) * s; up[i * 3 + 1] = ((u[i] >> 9) & 511) * s; up[i * 3 + 2] = ((u[i] >> 18) & 511) * s;
        }
        for (unsigned y = 0; y < H; ++y) {
            const float fy = std::max(0.f, (y + .5f) * UH / H - .5f); const unsigned y0 = std::min((unsigned)fy, UH - 1), y1 = std::min(y0 + 1, UH - 1);
            const float ty = fy - y0;
            for (unsigned x = 0; x < W; ++x) {
                const float fx = std::max(0.f, (x + .5f) * UW / W - .5f); const unsigned x0 = std::min((unsigned)fx, UW - 1), x1 = std::min(x0 + 1, UW - 1);
                const float tx = fx - x0;
                for (int c = 0; c < 3; ++c) {
                    const float a = up[(size_t(y0) * UW + x0) * 3 + c] * (1 - tx) + up[(size_t(y0) * UW + x1) * 3 + c] * tx;
                    const float bb = up[(size_t(y1) * UW + x0) * 3 + c] * (1 - tx) + up[(size_t(y1) * UW + x1) * 3 + c] * tx;
                    dst[(size_t(y + OY) * W + x) * 4 + c] = (_Float16)(a * (1 - ty) + bb * ty);
                }
            }
        }
    };
    auto loadColor = [&](id<MTLTexture> t, int n) {
        stretch(n, win);
        [t replaceRegion:MTLRegionMake2D(0, 0, W, TH) mipmapLevel:0 withBytes:win.data() bytesPerRow:W * 8];
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
    // warm up: the hook makes its small interpolator and kernels off this thread
    loadColor(c0, first); loadDM(first); b.colorTexture = c0; b.prevColorTexture = c0;
    for (int i = 0; i < 4; ++i) { b.shouldResetHistory = i == 0; encode(); std::this_thread::sleep_for(std::chrono::milliseconds(400)); }
    std::vector<_Float16> rd(size_t(W) * TH * 4);
    auto save = [&](id<MTLTexture> t, const char *name, int n) {
        [t getBytes:rd.data() bytesPerRow:W * 8 fromRegion:MTLRegionMake2D(0, 0, W, TH) mipmapLevel:0];
        char p[64]; snprintf(p, sizeof p, "/%03d-%s.f16", n, name);
        FILE *f = fopen((outDir + p).c_str(), "wb"); need(f, "out file");
        fwrite(rd.data() + size_t(OY) * W * 4, 2, size_t(W) * H * 4, f); fclose(f);   // the picture only
    };
    int made = 0;
    // one stream as in a game: the even frames are the real ones, each makes the odd frame before it; MetalFX needs a
    // few frames of history before it interpolates, so the first two are not kept
    id<MTLTexture> prevT = c0, curT = c1;
    loadColor(prevT, first); loadDM(first); b.colorTexture = prevT; b.prevColorTexture = prevT; b.shouldResetHistory = YES; encode();
    b.shouldResetHistory = NO;
    for (int n = first; n + 2 <= last; n += 2) {
        loadColor(curT, n + 2); loadDM(n + 2); b.colorTexture = curT; b.prevColorTexture = prevT; encode();
        if (n - first >= 4) {
            save(out, "gen", n + 1);
            id<MTLTexture> t = tex(dev, W, TH, MTLPixelFormatRGBA16Float);
            loadColor(t, n + 1); save(t, "ref", n + 1);
            ++made;
        }
        std::swap(prevT, curT);
    }
    unlink(pref.c_str()); rmdir(dir);
    printf("mfx_eval: %d generated frames in %s (FSR4_MFX_SIZE=%s DILATE=%s EDGE=%s)\n", made, outDir.c_str(),
           getenv("FSR4_MFX_SIZE") ?: "-", getenv("FSR4_MFX_DILATE") ?: "-", getenv("FSR4_MFX_EDGE") ?: "-");
    return 0;
} catch (const std::exception &e) { fprintf(stderr, "mfx_eval: %s\n", e.what()); return 1; } } }
