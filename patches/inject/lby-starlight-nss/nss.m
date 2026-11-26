// lby-starlight-nss (T9, test build): Arm's Neural Super Sampling in place of MetalFX's temporal upscaler.
//
// D3DMetal turns a game's DLSS calls into MetalFX temporal upscaling. Loaded into the Wine loader's process
// (DYLD_INSERT_LIBRARIES, like lby-ponthree-pacer), this library catches -[<MetalFX temporal scaler>
// encodeToCommandBuffer:] and, when LULLABY_UPSCALER=nss, encodes NSSMetal's upscaler into the same command
// buffer with the inputs the game handed MetalFX. Without it, MetalFX runs untouched.
//
// Based on Lightscale's hook/unix/lsfg_nss_hook.m (MaximKotliar/lightscale, MIT); NSSMetal is
// MaximKotliar/nss-metal (Apache-2.0); NSS weights are Arm's (Arm AI Model Community License).
//
//   LULLABY_UPSCALER=nss            NSS instead of MetalFX (anything else: MetalFX)
//   LULLABY_NSS_QUALITY=fast|low|mid|high   (default mid)
//   LULLABY_NSS_DIR=<dir>           kernels (nss.metallib) and weights (default: lullaby/components/nss)
//   LULLABY_NSS_LOG=<path>          log file (default: stderr, i.e. the game's log)
//   LULLABY_CAS=<0..1>              AMD FidelityFX CAS sharpening after the upscaler (NSS or MetalFX), off when unset or 0
//
// CAS (T10): the upscaler writes into a texture of ours, one CAS compute pass writes the game's output in the same
// command buffer. The pass waits for the scaler's fence and updates it again, so the game reads the sharpened frame.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <stdatomic.h>
#import <sys/stat.h>
#import <ctype.h>
#import "NSSMetal/NSSMetal.h"

static FILE *gLog;
static BOOL gOn;
static int gQuality = 1;   // NSSQuality: 0 low, 1 mid, 2 high, 3 fast
static float gCas;         // CAS sharpness, 0 = off
static void nlog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
// conventions (LULLABY_NSS_* at start, then live.conf): sign of jitter and motion, a motion multiplier, depth direction
// (-1: the game's), whether the game's exposure texture is used
static float gJSign = 1, gMvSign = 1, gMvMul = 1;
static int gDepthRev = -1, gUseExposure = 1;
static atomic_int gGen;    // bumped when quality changes: upscalers are made again
// measuring (live.conf): shadow=1 runs the other upscaler too, on the same inputs, into a texture of ours; dump=N copies
// N frames (shown output, the shadow, the game's colour, motion and depth) out of the GPU into components/nss/dumps/
static atomic_bool gShadow;
// stage=1 (default): the upscaler writes a texture of ours and the frame reaches the game's output by a copy. In some RE9
// runs anything a shader wrote straight into D3DMetal's output texture came out black (MetalFX's own pass too), while the
// same pass into our texture was right.
static atomic_bool gStage = true;
static atomic_int gDumpLeft;
static char gDumpDir[1024];
static void startDump(int n);

// live.conf (LULLABY_NSS_LIVE, default beside the library's resources): key=value lines read again whenever the file
// changes, checked about once a second, so a setting can be compared while the game runs. Keys: upscaler (nss|metalfx),
// quality, cas, jsign, mvsign, mvmul, depthrev (-1|0|1), exposure (0|1).
static BOOL gFsr4;   // LULLABY_UPSCALER=fsr4: FSR 4's hook does the upscale; NSS only as the shadow, never shown
static void applySetting(const char *k, const char *v) {
    if (!strcmp(k, "upscaler")) { if (!gFsr4) gOn = !strcmp(v, "nss"); }
    else if (!strcmp(k, "quality")) { int q = !strcmp(v, "low") ? 0 : !strcmp(v, "high") ? 2 : !strcmp(v, "fast") ? 3 : 1; if (q != gQuality) gQuality = q, atomic_fetch_add(&gGen, 1); }
    else if (!strcmp(k, "cas")) gCas = fmaxf(0.0f, fminf(1.0f, (float)atof(v)));
    else if (!strcmp(k, "jsign")) gJSign = (float)atof(v);
    else if (!strcmp(k, "mvsign")) gMvSign = (float)atof(v);
    else if (!strcmp(k, "mvmul")) gMvMul = (float)atof(v);
    else if (!strcmp(k, "depthrev")) gDepthRev = atoi(v);
    else if (!strcmp(k, "exposure")) gUseExposure = atoi(v) != 0;
    else if (!strcmp(k, "shadow")) atomic_store(&gShadow, atoi(v) != 0);
    else if (!strcmp(k, "stage")) atomic_store(&gStage, atoi(v) != 0);
    else if (!strcmp(k, "trust")) {   // history bypasses the clamp only below this motion (px) and deviation (clamp widths); 0,0 = as shipped
        float m = 0, d = 0;
        if (sscanf(v, "%f,%f", &m, &d) == 2) NSSSetHistoryTrust(m, d);
    }
    else if (!strcmp(k, "still")) NSSSetHistoryTrustStill((float)atof(v));   // rain/sparks: agreement where nothing moves, 0 = off
    else if (!strcmp(k, "outlier")) {   // dithered hair: k spreads, strength (0,0 = off)
        float kk = 0, ss = 0;
        if (sscanf(v, "%f,%f", &kk, &ss) == 2) NSSSetOutlierDamping(kk, ss);
    }
    else if (!strcmp(k, "spark")) NSSSetSparkHistory((float)atof(v));   // old raindrops/sparks in history: clamp widths, 0 = off
    else if (!strcmp(k, "flat")) NSSSetStillFlatness((float)atof(v));   // still-area check only on flat ground, 0 = everywhere
    else if (!strcmp(k, "tune")) {   // NSS's temporal step: alpha add, alpha multiplier, clamp width, clamp bypass (0,1,1,1 = as shipped)
        float t[4] = {0, 1, 1, 1};
        if (sscanf(v, "%f,%f,%f,%f", &t[0], &t[1], &t[2], &t[3]) == 4) NSSSetTemporalTuning(t[0], t[1], t[2], t[3]);
    }
    else if (!strcmp(k, "dump")) startDump(atoi(v));
}

static char gLivePath[1024];
static void liveCheck(void) {
    static atomic_long calls;
    static struct timespec seen;
    if (!gLivePath[0] || atomic_fetch_add(&calls, 1) % 60) return;
    struct stat sb;
    if (stat(gLivePath, &sb) || (sb.st_mtimespec.tv_sec == seen.tv_sec && sb.st_mtimespec.tv_nsec == seen.tv_nsec)) return;
    seen = sb.st_mtimespec;
    FILE *f = fopen(gLivePath, "r");
    if (!f) return;
    char line[256], applied[512] = "";
    while (fgets(line, sizeof line, f)) {
        char *eq = strchr(line, '='), *end = line + strlen(line);
        while (end > line && (end[-1] == '\n' || end[-1] == ' ')) *--end = 0;
        if (line[0] == '#' || !eq) continue;
        *eq = 0;
        applySetting(line, eq + 1);
        strlcat(applied, line, sizeof applied), strlcat(applied, "=", sizeof applied), strlcat(applied, eq + 1, sizeof applied), strlcat(applied, " ", sizeof applied);
    }
    fclose(f);
    nlog(@"live.conf: %s", applied);
}

static void nlog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void nlog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    fprintf(gLog ?: stderr, "lullaby-nss: %s\n", s.UTF8String);
    fflush(gLog ?: stderr);
}

static const char *qname(int q) { return q == 0 ? "low" : q == 2 ? "high" : q == 3 ? "fast" : "mid"; }

static const void *kKey = &kKey;
@interface LbyNssState : NSObject {
@public
    NSSUpscaler *up;
    BOOL failed, loggedFallback;
    int lastW, lastH, rebuilds;
    long frames;
    int gen;
    CFTimeInterval firstRebuild;
    // CAS
    BOOL casFailed;
    id<MTLComputePipelineState> casPS;
    id<MTLBuffer> casConst;
    id<MTLTexture> casTmp, casOut;
    id casTable, casRes;   // id<MTL4ArgumentTable>, id<MTLResidencySet> (Metal 4): every allocation of ours, and the game's output
    id<MTLTexture> shadow, stage;
    NSMutableArray *dumpOld;   // dump buffers to take out of the residency set once written
    long dumpFrame;
}
@end
@implementation LbyNssState
@end

static atomic_long gNssFrames, gFxFrames, gCasFrames;

static LbyNssState *stateOf(id s) {
    LbyNssState *st = objc_getAssociatedObject(s, kKey);
    if (!st) { st = [LbyNssState new]; objc_setAssociatedObject(s, kKey, st, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return st;
}

#pragma mark - CAS

// AMD FidelityFX CAS, sharpen only (no scaling), from ffx_cas.h (MIT): 3x3 min/max, adaptive negative lobe.
static NSString *const kCasSrc = @
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"kernel void lby_cas(texture2d<half, access::read> src [[texture(0)]], texture2d<half, access::write> dst [[texture(1)]],\n"
"                    constant float &peakIn [[buffer(0)]], uint2 p [[thread_position_in_grid]]) {\n"
"  if (p.x >= dst.get_width() || p.y >= dst.get_height()) return;\n"
"  int2 q = int2(p), m = int2(src.get_width() - 1, src.get_height() - 1);\n"
"  /* HDR: sharpen in a reversibly compressed range c / (1 + max c), so bright pixels are sharpened too */\n"
"  #define C(x) half3((x) / (1.0f + max(max((x).r, (x).g), max((x).b, 0.0f))))\n"
"  #define T(dx,dy) C(float3(src.read(uint2(clamp(q + int2(dx,dy), int2(0), m))).rgb))\n"
"  float4 e4 = float4(src.read(p));\n"
"  half3 b = T(0,-1), d = T(-1,0), e = C(e4.rgb), f = T(1,0), h = T(0,1);\n"
"  half3 a = T(-1,-1), c = T(1,-1), g = T(-1,1), i = T(1,1);\n"
"  half3 mn = min(min(min(d, e), min(f, b)), h); mn += min(mn, min(min(a, c), min(g, i)));\n"
"  half3 mx = max(max(max(d, e), max(f, b)), h); mx += max(mx, max(max(a, c), max(g, i)));\n"
"  half3 amp = sqrt(saturate(min(mn, 2.0h - mx) / max(mx, half3(1e-4h))));\n"
"  half3 w = amp * half(peakIn);\n"
"  float3 o = clamp(float3((b * w + d * w + f * w + h * w + e) / (1.0h + 4.0h * w)), 0.0f, 0.999f);\n"
"  o = o / (1.0f - max(max(o.r, o.g), o.b));   /* back to HDR */\n"
"  dst.write(half4(half3(min(o, float3(65000.0f))), half(e4.a)), p);\n"
"}\n";

static BOOL casFormatOK(MTLPixelFormat f) {
    switch (f) {
        case MTLPixelFormatRGBA16Float: case MTLPixelFormatRGBA8Unorm: case MTLPixelFormatBGRA8Unorm:
        case MTLPixelFormatRGB10A2Unorm: case MTLPixelFormatBGR10A2Unorm: case MTLPixelFormatRG11B10Float:
        case MTLPixelFormatRGBA32Float: case MTLPixelFormatRGB9E5Float: return YES;   // RE9: written into our staging texture
        default: return NO;
    }
}

static id ensureRes(LbyNssState *st, id<MTLDevice> dev) {
    if (!st->casRes) if (@available(macOS 26.0, *)) {
        MTLResidencySetDescriptor *rd = [MTLResidencySetDescriptor new];
        rd.initialCapacity = 16;
        st->casRes = [dev newResidencySetWithDescriptor:rd error:nil];
    }
    return st->casRes;
}

// our texture for the upscaler to write, or nil (CAS off or not possible for this output)
static id<MTLTexture> casTarget(LbyNssState *st, id<MTLFXTemporalScalerBase> s, BOOL metal4) {
    if (gCas <= 0 || st->casFailed) return nil;
    id<MTLTexture> out = s.outputTexture;
    if (!out) return nil;
    if (!casFormatOK(out.pixelFormat) || !(out.usage & MTLTextureUsageShaderWrite) || out.textureType != MTLTextureType2D) {
        st->casFailed = YES;
        nlog(@"CAS off for this scaler: output format %lu, usage 0x%lx", (unsigned long)out.pixelFormat, (unsigned long)out.usage);
        return nil;
    }
    id<MTLDevice> dev = out.device;
    if (!st->casPS) {
        NSError *err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithSource:kCasSrc options:nil error:&err];
        id<MTLFunction> fn = [lib newFunctionWithName:@"lby_cas"];
        st->casPS = fn ? [dev newComputePipelineStateWithFunction:fn error:&err] : nil;
        if (!st->casPS) { st->casFailed = YES; nlog(@"CAS off: %@", err.localizedDescription); return nil; }
        const float peak = -1.0f / (8.0f - 3.0f * fminf(gCas, 1.0f));   // ffx: lerp(8, 5, sharpness)
        st->casConst = [dev newBufferWithBytes:&peak length:sizeof peak options:MTLResourceStorageModeShared];
        if (metal4) if (@available(macOS 26.0, *)) {
            MTL4ArgumentTableDescriptor *ad = [MTL4ArgumentTableDescriptor new];
            ad.maxBufferBindCount = 1, ad.maxTextureBindCount = 2;
            st->casTable = [dev newArgumentTableWithDescriptor:ad error:nil];
            if (!st->casTable || !ensureRes(st, dev)) { st->casFailed = YES; nlog(@"CAS off: no Metal 4 argument table"); return nil; }
            [st->casRes addAllocation:st->casConst];
            [st->casRes commit];
        }
    }
    if (!st->casTmp || st->casTmp.width != out.width || st->casTmp.height != out.height || st->casTmp.pixelFormat != out.pixelFormat) {
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:out.pixelFormat
                                       width:out.width height:out.height mipmapped:NO];
        td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget | s.outputTextureUsage;
        td.storageMode = MTLStorageModePrivate;
        id<MTLTexture> old = st->casTmp;
        st->casTmp = [dev newTextureWithDescriptor:td];
        if (!st->casTmp) { st->casFailed = YES; nlog(@"CAS off: no texture"); return nil; }
        if (st->casRes) {
            if (old) [st->casRes removeAllocation:old];
            [st->casRes addAllocation:st->casTmp];
            [st->casRes commit];
        }
        nlog(@"CAS %.2f on %lux%lu (format %lu)", gCas, (unsigned long)out.width, (unsigned long)out.height, (unsigned long)out.pixelFormat);
    }
    if (st->casRes && st->casOut != out) {   // the game's output, resident for our pass
        if (st->casOut) [st->casRes removeAllocation:st->casOut];
        [st->casRes addAllocation:out];
        [st->casRes commit];
    }
    st->casOut = out;
    const float peak = -1.0f / (8.0f - 3.0f * fminf(gCas, 1.0f));   // live: cas= in live.conf
    if (*(float *)st->casConst.contents != peak) *(float *)st->casConst.contents = peak;
    return st->casTmp;
}

static void casEncode(LbyNssState *st, id cbObj, BOOL metal4, id<MTLFence> fence, id<MTLTexture> src, id<MTLTexture> dst) {
    const MTLSize tg = MTLSizeMake(16, 16, 1), grid = MTLSizeMake(dst.width, dst.height, 1);
    if (metal4) {
        if (@available(macOS 26.0, *)) {
            id<MTL4CommandBuffer> cb = cbObj;
            id<MTL4ArgumentTable> t = st->casTable;
            [cb useResidencySet:st->casRes];
            id<MTL4ComputeCommandEncoder> ce = [cb computeCommandEncoder];
            ce.label = @"Lullaby CAS";
            // after the upscaler's writes (its fence, and a barrier for an upscaler that did not use one)
            [ce barrierAfterQueueStages:MTLStageAll beforeStages:MTLStageDispatch visibilityOptions:MTL4VisibilityOptionDevice];
            if (fence) [ce waitForFence:fence beforeEncoderStages:MTLStageDispatch];
            [ce setComputePipelineState:st->casPS];
            [t setTexture:src.gpuResourceID atIndex:0], [t setTexture:dst.gpuResourceID atIndex:1];
            [t setAddress:st->casConst.gpuAddress atIndex:0];
            [ce setArgumentTable:t];
            [ce dispatchThreads:grid threadsPerThreadgroup:tg];
            if (fence) [ce updateFence:fence afterEncoderStages:MTLStageDispatch];
            [ce endEncoding];
        }
    } else {
        id<MTLCommandBuffer> cb = cbObj;
        id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
        ce.label = @"Lullaby CAS";
        if (fence) [ce waitForFence:fence];
        [ce setComputePipelineState:st->casPS];
        [ce setTexture:src atIndex:0], [ce setTexture:dst atIndex:1];
        [ce setBuffer:st->casConst offset:0 atIndex:0];
        [ce dispatchThreads:grid threadsPerThreadgroup:tg];
        if (fence) [ce updateFence:fence];
        [ce endEncoding];
    }
    atomic_fetch_add(&gCasFrames, 1);
}

#pragma mark - NSS

static BOOL isMetal4(id cbObj) {
    if (@available(macOS 26.0, *)) return [cbObj conformsToProtocol:@protocol(MTL4CommandBuffer)];
    return NO;
}

static BOOL nssTry(id<MTLFXTemporalScalerBase> s, id cbObj, id<MTLTexture> out, BOOL force) {
    if (!gOn && !force) return NO;
    LbyNssState *st = stateOf(s);
    if (st->failed) return NO;
    BOOL metal4 = NO;
    if (@available(macOS 26.0, *)) metal4 = [cbObj conformsToProtocol:@protocol(MTL4CommandBuffer)];
    if (!metal4 && ![cbObj conformsToProtocol:@protocol(MTLCommandBuffer)]) {
        if (!st->loggedFallback) nlog(@"%s is not a command buffer we know; MetalFX runs", class_getName(object_getClass(cbObj)));
        st->loggedFallback = YES;
        return NO;
    }
    const int wr = (int)(s.inputContentWidth ?: s.inputWidth), hr = (int)(s.inputContentHeight ?: s.inputHeight);
    const int wo = (int)s.outputWidth, ho = (int)s.outputHeight;
    if (!s.colorTexture || !s.depthTexture || !s.motionTexture || !s.outputTexture || wo <= wr || ho <= hr ||
        !(s.outputTexture.usage & MTLTextureUsageShaderWrite) || s.motionTexture.width != s.colorTexture.width) {
        if (!st->loggedFallback) nlog(@"unsupported inputs (render %dx%d -> %dx%d); MetalFX runs", wr, hr, wo, ho);
        st->loggedFallback = YES;
        return NO;
    }
    if (st->gen != atomic_load(&gGen)) st->up = nil, st->gen = atomic_load(&gGen), st->rebuilds = 0;
    NSSUpscaler *up = st->up;
    if (!up || (int)up.inputWidth != wr || (int)up.inputHeight != hr || (int)up.outputWidth != wo || (int)up.outputHeight != ho) {
        // dynamic resolution would rebuild every few frames: give such a scaler back to MetalFX
        const CFTimeInterval now = CACurrentMediaTime();
        if (now - st->firstRebuild > 10) st->firstRebuild = now, st->rebuilds = 0;
        if (++st->rebuilds > 4) { st->failed = YES; nlog(@"render size keeps changing; MetalFX runs for this scaler"); return NO; }
        const CFTimeInterval t0 = CACurrentMediaTime();
        NSSUpscalerDescriptor *d = [NSSUpscalerDescriptor new];
        d.inputWidth = wr, d.inputHeight = hr, d.outputWidth = wo, d.outputHeight = ho, d.quality = (NSSQuality)gQuality;
        const char *dir = getenv("LULLABY_NSS_DIR");
        d.resourceDirectory = [NSURL fileURLWithPath:dir ? @(dir)
            : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/lullaby/components/nss"]];
        NSError *err = nil;
        up = st->up = [[NSSUpscaler alloc] initWithDevice:[(id<MTLCommandBuffer>)cbObj device] descriptor:d error:&err];
        if (!up) { st->failed = YES; nlog(@"setup failed (%@); MetalFX runs", err.localizedDescription); return NO; }
        nlog(@"NSS %s %dx%d -> %dx%d (%.2fx), set up in %.0f ms%s", qname(gQuality), wr, hr, wo, ho, (double)ho / hr,
             (CACurrentMediaTime() - t0) * 1e3, metal4 ? ", Metal 4" : "");
    }
    up.colorTexture = s.colorTexture, up.depthTexture = s.depthTexture, up.motionTexture = s.motionTexture;
    up.exposureTexture = s.exposureTexture, up.outputTexture = out ?: s.outputTexture;
    // same conventions as MetalFX; LULLABY_NSS_JSIGN / LULLABY_NSS_MVSIGN = -1 flip them for a game that differs
    // LULLABY_NSS_MVMUL scales the motion (a game whose scale is for another size), LULLABY_NSS_DEPTHREV=0|1 overrides the
    // depth direction, LULLABY_NSS_EXPOSURE=0 ignores the game's exposure texture: switches to find a game's conventions.
    // a change of conventions starts the history again
    static float lastKey = NAN;
    const float key = gJSign * 1000 + gMvSign * 100 + gMvMul * 10 + gDepthRev + gUseExposure * 0.5f;
    const BOOL changed = !isnan(lastKey) && key != lastKey;
    lastKey = key;
    up.jitterOffsetX = gJSign * s.jitterOffsetX, up.jitterOffsetY = gJSign * s.jitterOffsetY;
    up.motionVectorScaleX = gMvSign * gMvMul * s.motionVectorScaleX, up.motionVectorScaleY = gMvSign * gMvMul * s.motionVectorScaleY;
    up.depthReversed = gDepthRev >= 0 ? gDepthRev : s.isDepthReversed, up.reset = s.reset || changed, up.preExposure = s.preExposure;
    if (!gUseExposure) up.exposureTexture = nil;
    // what the game hands over: once per scaler in full, then the jitter of a few frames and every 600th frame
    st->frames++;
    if (st->frames == 1)
        nlog(@"inputs: color %lux%lu fmt %lu, depth %lux%lu fmt %lu, motion %lux%lu fmt %lu, output %lux%lu fmt %lu, exposure %s, "
             "content %dx%d; motion scale %.3f %.3f, depth reversed %d, pre-exposure %.3f; sent: motion scale %.3f %.3f, depth reversed %d",
             (unsigned long)s.colorTexture.width, (unsigned long)s.colorTexture.height, (unsigned long)s.colorTexture.pixelFormat,
             (unsigned long)s.depthTexture.width, (unsigned long)s.depthTexture.height, (unsigned long)s.depthTexture.pixelFormat,
             (unsigned long)s.motionTexture.width, (unsigned long)s.motionTexture.height, (unsigned long)s.motionTexture.pixelFormat,
             (unsigned long)s.outputTexture.width, (unsigned long)s.outputTexture.height, (unsigned long)s.outputTexture.pixelFormat,
             s.exposureTexture ? "yes" : "no", wr, hr, s.motionVectorScaleX, s.motionVectorScaleY, s.isDepthReversed, s.preExposure,
             up.motionVectorScaleX, up.motionVectorScaleY, up.depthReversed);
    if ((st->frames == 30 || st->frames % 300 == 0) && s.exposureTexture) {   // the game's exposure value, read on our own queue
        id<MTLTexture> ex = s.exposureTexture;
        static id<MTLCommandQueue> q;
        static id<MTLBuffer> buf;
        if (!q) q = [ex.device newCommandQueue], buf = [ex.device newBufferWithLength:16 options:MTLResourceStorageModeShared];
        const MTLPixelFormat pf = ex.pixelFormat;
        const NSUInteger bpp = pf == MTLPixelFormatR16Float ? 2 : pf == MTLPixelFormatRG16Float ? 4 : pf == MTLPixelFormatR32Float ? 4 : 0;
        if (bpp && ex.storageMode != MTLStorageModeMemoryless) {
            id<MTLCommandBuffer> c = [q commandBuffer];
            id<MTLBlitCommandEncoder> b = [c blitCommandEncoder];
            [b copyFromTexture:ex sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(1, 1, 1)
                      toBuffer:buf destinationOffset:0 destinationBytesPerRow:bpp destinationBytesPerImage:bpp];
            [b endEncoding];
            const long fno = st->frames;
            const float pre = s.preExposure;
            [c addCompletedHandler:^(id<MTLCommandBuffer> done) {
                float v = pf == MTLPixelFormatR32Float ? *(float *)buf.contents : (float)*(__fp16 *)buf.contents;
                nlog(@"frame %ld: game exposure %g (format %lu), pre-exposure %g", fno, v, (unsigned long)pf, pre);
            }];
            [c commit];
        } else if (st->frames == 30) nlog(@"exposure texture format %lu not read", (unsigned long)pf);
    }
    if (st->frames <= 8 || st->frames % 600 == 0)
        nlog(@"frame %ld: jitter %.3f %.3f, reset %d, motion scale %.3f %.3f", st->frames, s.jitterOffsetX, s.jitterOffsetY, s.reset,
             s.motionVectorScaleX, s.motionVectorScaleY);
    if (metal4) {
        if (@available(macOS 26.0, *)) [up encodeToMTL4CommandBuffer:cbObj fence:s.fence];
    } else {
        [up encodeToCommandBuffer:cbObj];
    }
    up.colorTexture = up.depthTexture = up.motionTexture = up.exposureTexture = up.outputTexture = nil;   // don't keep the game's textures
    return YES;
}

#pragma mark - Measuring

static void startDump(int n) {
    if (n <= 0) return;
    const char *base = getenv("LULLABY_NSS_DIR");
    NSString *root = base ? @(base) : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/lullaby/components/nss"];
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *dir = [root stringByAppendingFormat:@"/dumps/%@", [f stringFromDate:[NSDate date]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    strlcpy(gDumpDir, dir.fileSystemRepresentation, sizeof gDumpDir);
    atomic_store(&gDumpLeft, n);
    nlog(@"dumping %d frames into %s", n, gDumpDir);
}

static NSUInteger bytesPerPixel(MTLPixelFormat f) {
    switch (f) {
        case MTLPixelFormatRGBA16Float: return 8;
        case MTLPixelFormatRGB9E5Float: case MTLPixelFormatRG11B10Float: case MTLPixelFormatRG16Float: case MTLPixelFormatR32Float:
        case MTLPixelFormatRGBA8Unorm: case MTLPixelFormatBGRA8Unorm: case MTLPixelFormatRGB10A2Unorm: case MTLPixelFormatBGR10A2Unorm:
        case MTLPixelFormatDepth32Float: case MTLPixelFormatDepth32Float_Stencil8: return 4;
        default: return 0;
    }
}

// copies of the frame's textures into shared buffers, in the game's command buffer after the upscaler (and CAS), written to
// files a second later; names[i] gives each file its name
static void dumpTextures(LbyNssState *st, id cbObj, BOOL metal4, id<MTLFence> fence, NSArray<id<MTLTexture>> *texs,
                         NSArray<NSString *> *names, NSString *meta) {
    id<MTLDevice> dev = texs.firstObject.device;
    NSMutableArray *bufs = [NSMutableArray array], *used = [NSMutableArray array];
    for (NSUInteger i = 0; i < texs.count; i++) {
        id<MTLTexture> t = texs[i];
        const NSUInteger bpp = bytesPerPixel(t.pixelFormat);
        if (!bpp || t.textureType != MTLTextureType2D) { [bufs addObject:NSNull.null]; continue; }
        id<MTLBuffer> b = [dev newBufferWithLength:bpp * t.width * t.height options:MTLResourceStorageModeShared];
        [bufs addObject:b ?: (id)NSNull.null];
        if (b) [used addObject:b];
    }
    if (metal4) {
        if (@available(macOS 26.0, *)) {
            if (!ensureRes(st, dev)) return;
            for (id<MTLBuffer> b in used) [st->casRes addAllocation:b];
            for (id<MTLTexture> t in texs) if (![st->casRes containsAllocation:t]) [st->casRes addAllocation:t];
            [st->casRes commit];
            id<MTL4CommandBuffer> cb = cbObj;
            [cb useResidencySet:st->casRes];
            id<MTL4ComputeCommandEncoder> ce = [cb computeCommandEncoder];
            ce.label = @"Lullaby dump";
            [ce barrierAfterQueueStages:MTLStageAll beforeStages:MTLStageBlit visibilityOptions:MTL4VisibilityOptionDevice];
            if (fence) [ce waitForFence:fence beforeEncoderStages:MTLStageBlit];
            for (NSUInteger i = 0; i < texs.count; i++) {
                if (bufs[i] == NSNull.null) continue;
                id<MTLTexture> t = texs[i];
                const NSUInteger bpp = bytesPerPixel(t.pixelFormat);
                [ce copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(t.width, t.height, 1)
                           toBuffer:bufs[i] destinationOffset:0 destinationBytesPerRow:bpp * t.width destinationBytesPerImage:bpp * t.width * t.height
                            options:t.pixelFormat == MTLPixelFormatDepth32Float_Stencil8 ? MTLBlitOptionDepthFromDepthStencil : MTLBlitOptionNone];
            }
            if (fence) [ce updateFence:fence afterEncoderStages:MTLStageBlit];
            [ce endEncoding];
        }
    } else {
        id<MTLCommandBuffer> cb = cbObj;
        id<MTLBlitCommandEncoder> be = [cb blitCommandEncoder];
        if (fence) [be waitForFence:fence];
        for (NSUInteger i = 0; i < texs.count; i++) {
            if (bufs[i] == NSNull.null) continue;
            id<MTLTexture> t = texs[i];
            const NSUInteger bpp = bytesPerPixel(t.pixelFormat);
            [be copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(t.width, t.height, 1)
                       toBuffer:bufs[i] destinationOffset:0 destinationBytesPerRow:bpp * t.width destinationBytesPerImage:bpp * t.width * t.height
                        options:t.pixelFormat == MTLPixelFormatDepth32Float_Stencil8 ? MTLBlitOptionDepthFromDepthStencil : MTLBlitOptionNone];
        }
        if (fence) [be updateFence:fence];
        [be endEncoding];
    }
    NSString *dir = @(gDumpDir);
    const long fno = st->dumpFrame++;
    NSMutableString *line = [NSMutableString stringWithFormat:@"frame=%ld %@", fno, meta];
    for (NSUInteger i = 0; i < texs.count; i++)
        [line appendFormat:@" tex.%@=%lux%lu:%lu", names[i], (unsigned long)texs[i].width, (unsigned long)texs[i].height, (unsigned long)texs[i].pixelFormat];
    [line appendString:@"\n"];
    static dispatch_queue_t writer;   // one at a time: meta.txt lines in order
    static dispatch_once_t once;
    dispatch_once(&once, ^{ writer = dispatch_queue_create("lullaby-nss.dump", DISPATCH_QUEUE_SERIAL); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), writer, ^{
        for (NSUInteger i = 0; i < names.count; i++) {
            if (bufs[i] == NSNull.null) continue;
            id<MTLBuffer> b = bufs[i];
            [[NSData dataWithBytesNoCopy:b.contents length:b.length freeWhenDone:NO]
                writeToFile:[dir stringByAppendingFormat:@"/%03ld-%@.raw", fno, names[i]] atomically:NO];
        }
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:[dir stringByAppendingPathComponent:@"meta.txt"]];
        if (!h) { [[NSFileManager defaultManager] createFileAtPath:[dir stringByAppendingPathComponent:@"meta.txt"] contents:nil attributes:nil];
                  h = [NSFileHandle fileHandleForWritingAtPath:[dir stringByAppendingPathComponent:@"meta.txt"]]; }
        [h seekToEndOfFile], [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]], [h closeFile];
    });
    if (!st->dumpOld) st->dumpOld = [NSMutableArray array];
    [st->dumpOld addObject:@[@(CACurrentMediaTime()), used]];
}

// buffers of earlier dumps leave the residency set on the game's thread, once their files are written
static void dumpTidy(LbyNssState *st) {
    if (!st->dumpOld.count || !st->casRes) return;
    BOOL changed = NO;
    while (st->dumpOld.count && CACurrentMediaTime() - [st->dumpOld[0][0] doubleValue] > 3) {
        for (id<MTLBuffer> b in st->dumpOld[0][1]) [st->casRes removeAllocation:b];
        [st->dumpOld removeObjectAtIndex:0];
        changed = YES;
    }
    if (changed) [st->casRes commit];
}

// a private texture like the game's output (format, size, the scaler's usage), kept resident for Metal 4
static id<MTLTexture> twinOf(LbyNssState *st, id<MTLTexture> old, id<MTLFXTemporalScalerBase> s, BOOL metal4, const char *what) {
    id<MTLTexture> out = s.outputTexture;
    if (!out) return nil;
    if (old && old.width == out.width && old.height == out.height && old.pixelFormat == out.pixelFormat) return old;
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:out.pixelFormat width:out.width height:out.height mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget | s.outputTextureUsage;
    td.storageMode = MTLStorageModePrivate;
    id<MTLTexture> t = [out.device newTextureWithDescriptor:td];
    if (metal4 && ensureRes(st, out.device)) {
        if (old) [st->casRes removeAllocation:old];
        if (t) [st->casRes addAllocation:t];
        [st->casRes commit];
    }
    nlog(@"%s texture: %lux%lu format %lu", what, (unsigned long)out.width, (unsigned long)out.height, (unsigned long)out.pixelFormat);
    return t;
}

// our texture into the game's output: a copy, in the same command buffer, after the passes before it (fence and barrier)
static void copyToOutput(LbyNssState *st, id cbObj, BOOL metal4, id<MTLFence> fence, id<MTLTexture> src, id<MTLTexture> dst) {
    if (metal4) {
        if (@available(macOS 26.0, *)) {
            id<MTL4CommandBuffer> cb = cbObj;
            if (st->casRes && ![st->casRes containsAllocation:dst]) [st->casRes addAllocation:dst], [st->casRes commit];
            if (st->casRes) [cb useResidencySet:st->casRes];
            id<MTL4ComputeCommandEncoder> ce = [cb computeCommandEncoder];
            ce.label = @"Lullaby output copy";
            [ce barrierAfterQueueStages:MTLStageAll beforeStages:MTLStageBlit visibilityOptions:MTL4VisibilityOptionDevice];
            if (fence) [ce waitForFence:fence beforeEncoderStages:MTLStageBlit];
            [ce copyFromTexture:src toTexture:dst];
            if (fence) [ce updateFence:fence afterEncoderStages:MTLStageBlit];
            [ce endEncoding];
        }
    } else {
        id<MTLBlitCommandEncoder> be = [(id<MTLCommandBuffer>)cbObj blitCommandEncoder];
        be.label = @"Lullaby output copy";
        if (fence) [be waitForFence:fence];
        [be copyFromTexture:src toTexture:dst];
        if (fence) [be updateFence:fence];
        [be endEncoding];
    }
}

static id<MTLTexture> shadowTarget(LbyNssState *st, id<MTLFXTemporalScalerBase> s, BOOL metal4) {
    id<MTLTexture> out = s.outputTexture;
    if (!out) return nil;
    if (!st->shadow || st->shadow.width != out.width || st->shadow.height != out.height || st->shadow.pixelFormat != out.pixelFormat) {
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:out.pixelFormat width:out.width height:out.height mipmapped:NO];
        td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget | s.outputTextureUsage;
        td.storageMode = MTLStorageModePrivate;
        id<MTLTexture> old = st->shadow;
        st->shadow = [out.device newTextureWithDescriptor:td];
        if (metal4 && ensureRes(st, out.device)) {
            if (old) [st->casRes removeAllocation:old];
            if (st->shadow) [st->casRes addAllocation:st->shadow];
            [st->casRes commit];
        }
        nlog(@"shadow upscaler on: %lux%lu", (unsigned long)out.width, (unsigned long)out.height);
    }
    return st->shadow;
}

static __unsafe_unretained dispatch_queue_t gHookQueue;   // a global queue (never freed), taken in the constructor: no retain later
static void wrapScaler(Class cls, int round);
static void hookScalerClass(Class cls) {
    static NSMutableSet *done;
    @synchronized(NSNull.null) {
        if (!done) done = [NSMutableSet set];
        NSString *n = @(class_getName(cls));
        if ([done containsObject:n]) return;
        [done addObject:n];
    }
    wrapScaler(cls, 0);
}

// Our wrapper stays the outermost one: FSR 4's hook swizzles the same method once the game makes its scaler, after
// ours, which left our dumps and shadow blind to FSR 4's frames. A few seconds later the method is checked again and,
// if someone else's code now sits on top, ours is put above it (the inner copy of ours then only passes the call on).
// With FSR 4 upscaling and nothing to measure or sharpen, the wrapper passes the call straight on: no staging copy.
static __thread int gInScaler;
static void wrapScaler(Class cls, int round) {
    SEL sel = @selector(encodeToCommandBuffer:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { nlog(@"%s has no encodeToCommandBuffer:", class_getName(cls)); return; }
    IMP orig = method_getImplementation(m);
    IMP mine = imp_implementationWithBlock(^(id<MTLFXTemporalScalerBase> self, id cb) {
        if (gInScaler || (gFsr4 && !atomic_load(&gShadow) && atomic_load(&gDumpLeft) <= 0 && gCas <= 0)) {
            if (!gInScaler) liveCheck();
            ((void (*)(id, SEL, id))orig)(self, sel, cb);
            return;
        }
        gInScaler = 1;
        @autoreleasepool {
            liveCheck();
            const BOOL m4 = isMetal4(cb);
            if (!m4 && ![cb conformsToProtocol:@protocol(MTLCommandBuffer)]) { ((void (*)(id, SEL, id))orig)(self, sel, cb); gInScaler = 0; return; }
            LbyNssState *st = stateOf(self);
            dumpTidy(st);
            id<MTLTexture> out = self.outputTexture, tmp = casTarget(st, self, m4);
            // stage: the upscaler (and CAS) write our textures; the game's output gets a copy at the end
            id<MTLTexture> stage = atomic_load(&gStage) && out ? (st->stage = twinOf(st, st->stage, self, m4, "stage")) : nil;
            id<MTLTexture> final = stage ?: out;   // what the upscaler or CAS leaves the frame in
            // MetalFX into `target` (our texture or the game's): the scaler's output swapped for the call
            void (^metalFX)(id<MTLTexture>) = ^(id<MTLTexture> target) {
                const BOOL swap = target && target != out;
                if (swap) {
                    if (m4) if (@available(macOS 26.0, *)) [(id<MTL4CommandBuffer>)cb useResidencySet:st->casRes];
                    self.outputTexture = target;
                }
                ((void (*)(id, SEL, id))orig)(self, sel, cb);
                if (swap) self.outputTexture = out;
            };
            id<MTLTexture> target = tmp ?: stage;   // nil: the game's output itself
            const BOOL usedNSS = nssTry(self, cb, target, NO);
            if (usedNSS) atomic_fetch_add(&gNssFrames, 1);
            else atomic_fetch_add(&gFxFrames, 1), metalFX(target);
            if (tmp) casEncode(st, cb, m4, self.fence, tmp, final);
            if (stage) copyToOutput(st, cb, m4, self.fence, stage, out);
            id<MTLTexture> shadow = atomic_load(&gShadow) ? shadowTarget(st, self, m4) : nil;
            if (shadow) {   // the other upscaler, same inputs: NSS's state is kept apart from what it shows
                if (usedNSS) metalFX(shadow);
                else nssTry(self, cb, shadow, YES);
            }
            if (atomic_load(&gDumpLeft) > 0 && out && self.colorTexture) {
                atomic_fetch_sub(&gDumpLeft, 1);
                NSMutableArray *t = [NSMutableArray arrayWithObjects:out, self.colorTexture, nil], *n = [NSMutableArray arrayWithObjects:@"shown", @"color", nil];
                if (self.motionTexture) [t addObject:self.motionTexture], [n addObject:@"motion"];
                if (self.depthTexture) [t addObject:self.depthTexture], [n addObject:@"depth"];
                if (shadow) [t addObject:shadow], [n addObject:usedNSS ? @"metalfx" : @"nss"];
                NSString *meta = [NSString stringWithFormat:@"shown=%@ quality=%s cas=%.2f jitter=%.4f,%.4f mvscale=%.3f,%.3f depthrev=%d reset=%d content=%lux%lu",
                    usedNSS ? @"nss" : gFsr4 ? @"fsr4" : @"metalfx", qname(gQuality), tmp ? gCas : 0.0f, self.jitterOffsetX, self.jitterOffsetY,
                    self.motionVectorScaleX, self.motionVectorScaleY, self.isDepthReversed, self.reset,
                    (unsigned long)(self.inputContentWidth ?: self.inputWidth), (unsigned long)(self.inputContentHeight ?: self.inputHeight)];
                dumpTextures(st, cb, m4, self.fence, t, n, meta);
            }
        }
        gInScaler = 0;
    });
    method_setImplementation(m, mine);
    nlog(@"hooked -[%s encodeToCommandBuffer:]%s", class_getName(cls), round ? " again, above a later hook" : "");
    if (round >= 3) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (round == 0 ? 3 : round == 1 ? 8 : 20) * (int64_t)NSEC_PER_SEC), gHookQueue, ^{
        if (method_getImplementation(class_getInstanceMethod(cls, sel)) != mine) wrapScaler(cls, round + 1);
        else if (round < 2) {   // still ours: look once more later (FSR 4 hooks when its first frame comes)
            const int next = round + 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (next == 1 ? 8 : 20) * (int64_t)NSEC_PER_SEC), gHookQueue, ^{
                if (method_getImplementation(class_getInstanceMethod(cls, sel)) != mine) wrapScaler(cls, next + 1);
            });
        }
    });
}

static void hookDescriptor(SEL sel, int args) {
    Class d = objc_getClass("MTLFXTemporalScalerDescriptor");
    Method m = d ? class_getInstanceMethod(d, sel) : NULL;
    if (!m) return;
    IMP o = method_getImplementation(m);
    if (args == 1) {
        method_setImplementation(m, imp_implementationWithBlock(^id(MTLFXTemporalScalerDescriptor *self, id dev) {
            id sc = ((id (*)(id, SEL, id))o)(self, sel, dev);
            nlog(@"game made a MetalFX temporal scaler (Metal 3) %lux%lu -> %lux%lu, content properties %d",
                 (unsigned long)self.inputWidth, (unsigned long)self.inputHeight, (unsigned long)self.outputWidth,
                 (unsigned long)self.outputHeight, self.isInputContentPropertiesEnabled);
            if (sc) hookScalerClass(object_getClass(sc));
            return sc;
        }));
    } else {
        method_setImplementation(m, imp_implementationWithBlock(^id(MTLFXTemporalScalerDescriptor *self, id dev, id compiler) {
            id sc = ((id (*)(id, SEL, id, id))o)(self, sel, dev, compiler);
            nlog(@"game made a MetalFX temporal scaler (Metal 4) %lux%lu -> %lux%lu, content properties %d",
                 (unsigned long)self.inputWidth, (unsigned long)self.inputHeight, (unsigned long)self.outputWidth,
                 (unsigned long)self.outputHeight, self.isInputContentPropertiesEnabled);
            if (sc) hookScalerClass(object_getClass(sc));
            return sc;
        }));
    }
}

static void lbyHookMetalFX(void) {
    static atomic_bool done;
    if (!objc_getClass("MTLFXTemporalScalerDescriptor") || atomic_exchange(&done, true)) return;
    hookDescriptor(@selector(newTemporalScalerWithDevice:), 1);
    hookDescriptor(NSSelectorFromString(@"newTemporalScalerWithDevice:compiler:"), 2);
    nlog(@"MetalFX loaded: watching for its temporal scalers");
}


static void lbyHookMetalFXAsync(void *unused) { (void)unused; @autoreleasepool { lbyHookMetalFX(); } }

// Called with the runtime's lock held (no method changes here): the hooks go in right after, off this thread. D3DMetal
// brings MetalFX in at its start and makes temporal scalers much later, when the game turns DLSS on.
static void lbyImageAdded(const struct mach_header *mh) {
    Dl_info di;
    if (!dladdr(mh, &di) || !di.dli_fname || !strstr(di.dli_fname, "/MetalFX.framework/")) return;
    // plain C only here: even a block copy sends a message, which takes the lock the runtime holds
    dispatch_async_f(gHookQueue, NULL, lbyHookMetalFXAsync);
}

// Texture LOD bias under upscaling (LULLABY_LOD_BIAS). A game rendering below the output size should sample textures
// log2(render/output) mips sharper (about -0.58 at 1530 -> 2294), as DLSS asks of it; D3DMetal passes a sampler's bias
// on as -[MTLSamplerDescriptor setLodBias:] (Metal, macOS 26). Always counted (what the game asks, in the log); with
// LULLABY_LOD_BIAS=<number> that much more bias goes to every mipmapped, filtered, non-comparison sampler (not shadows,
// not point-sampled data), read when the device builds the sampler from the descriptor.
static float gLodAdd;
static atomic_long gLodSet, gLodGet, gLodApplied, gLodNeg, gLodZero;
static void lbyLodSummary(void) {
    if (atomic_load(&gLodSet) || atomic_load(&gLodGet))
        nlog(@"samplers: lodBias set %ld times (%ld negative, %ld zero), read %ld times, %ld given %+.2f more",
             atomic_load(&gLodSet), atomic_load(&gLodNeg), atomic_load(&gLodZero), atomic_load(&gLodGet),
             atomic_load(&gLodApplied), gLodAdd);
}
static void lbyHookSamplers(void *unused) {
    (void)unused;
    @autoreleasepool {
        Class c = objc_getClass("MTLSamplerDescriptorInternal") ?: objc_getClass("MTLSamplerDescriptor");   // what +new hands out
        Method set = c ? class_getInstanceMethod(c, sel_registerName("setLodBias:")) : NULL;
        Method get = c ? class_getInstanceMethod(c, sel_registerName("lodBias")) : NULL;
        if (!set || !get) { nlog(@"samplers: no lodBias on MTLSamplerDescriptor"); return; }
        IMP os = method_getImplementation(set), og = method_getImplementation(get);
        SEL ss = method_getName(set), sg = method_getName(get);
        method_setImplementation(set, imp_implementationWithBlock(^(id self, float v) {
            long n = atomic_fetch_add(&gLodSet, 1);
            if (v < -0.01f) atomic_fetch_add(&gLodNeg, 1); else if (v <= 0.01f) atomic_fetch_add(&gLodZero, 1);
            if (n < 8 || (v < -0.01f && atomic_load(&gLodNeg) <= 4)) nlog(@"samplers: the game sets lodBias %.3f", v);
            if ((n + 1) % 20000 == 0) lbyLodSummary();
            ((void (*)(id, SEL, float))os)(self, ss, v);
        }));
        method_setImplementation(get, imp_implementationWithBlock(^float(MTLSamplerDescriptor *self) {
            float v = ((float (*)(id, SEL))og)(self, sg);
            atomic_fetch_add(&gLodGet, 1);
            if (gLodAdd != 0 && self.mipFilter != MTLSamplerMipFilterNotMipmapped && self.minFilter == MTLSamplerMinMagFilterLinear
                && self.compareFunction == MTLCompareFunctionNever) {
                atomic_fetch_add(&gLodApplied, 1);
                return v + gLodAdd;
            }
            return v;
        }));
        nlog(@"samplers: watching lodBias (extra %+.2f)", gLodAdd);
    }
}

__attribute__((constructor)) static void lbyNssInit(void) {
    const char *u = getenv("LULLABY_UPSCALER");
    gOn = u && !strcmp(u, "nss");
    gFsr4 = u && !strcmp(u, "fsr4");
    const char *q = getenv("LULLABY_NSS_QUALITY");
    if (q) gQuality = !strcmp(q, "low") ? 0 : !strcmp(q, "high") ? 2 : !strcmp(q, "fast") ? 3 : 1;
    const char *c = getenv("LULLABY_CAS");
    if (c && *c) gCas = fmaxf(0.0f, fminf(1.0f, (float)atof(c)));
    for (const char *const *k = (const char *const[]){"JSIGN", "MVSIGN", "MVMUL", "DEPTHREV", "EXPOSURE", NULL}; *k; k++) {
        char name[64], low[16]; snprintf(name, sizeof name, "LULLABY_NSS_%s", *k);
        const char *v = getenv(name);
        if (!v) continue;
        size_t i = 0; for (; (*k)[i] && i < sizeof low - 1; i++) low[i] = (char)tolower((*k)[i]); low[i] = 0;
        applySetting(low, v);
    }
    // history bypasses NSS's clamp freely below 4 px of motion, above it only where it agrees with this frame (8 clamp widths)
    // (measured on RE9's frames, agent/nss-set; trust=0,0 in live.conf gives NSS as shipped)
    NSSSetHistoryTrust(4, 8);
    // smooth step (new frame weight x0.7): less shimmer in motion; still areas drop history that disagrees with this frame
    // only on flat ground (old raindrops), fine detail keeps it (agent/logs/2026-11-25/nss-tune.txt)
    NSSSetTemporalTuning(0, 0.7f, 1, 1);
    NSSSetHistoryTrustStill(4);
    NSSSetStillFlatness(0.1f);
    const char *live = getenv("LULLABY_NSS_LIVE"), *dir = getenv("LULLABY_NSS_DIR");
    if (live) strlcpy(gLivePath, live, sizeof gLivePath);
    else snprintf(gLivePath, sizeof gLivePath, "%s/live.conf", dir ? dir : [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/lullaby/components/nss"] UTF8String]);
    const char *lp = getenv("LULLABY_NSS_LOG");
    if (lp && *lp) gLog = fopen(lp, "a");
    // MetalFX is not linked and never loaded from here: loading it at process start (before the engine applies
    // .sevo/apps/<exe>.env) turned Apple's Metal HUD off, and Wine's helper processes have no use for it. The hooks
    // go in when something else (D3DMetal) brings MetalFX in.
    [NSSUpscaler setLogHandler:^(NSString *m) { nlog(@"%@", m); }];
    gHookQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    objc_addLoadImageFunc(lbyImageAdded);   // dyld's add-image callback comes before MetalFX's classes exist
    const char *lod = getenv("LULLABY_LOD_BIAS");
    if (lod && *lod) gLodAdd = fmaxf(-2.0f, fminf(0.0f, (float)atof(lod)));
    dispatch_async_f(gHookQueue, NULL, lbyHookSamplers);
    nlog(@"waiting for MetalFX (upscaler %s, quality %s, CAS %.2f)", gOn ? "NSS" : "MetalFX", qname(gQuality), gCas);
}

__attribute__((destructor)) static void lbyNssFini(void) {
    lbyLodSummary();
    const long n = atomic_load(&gNssFrames), f = atomic_load(&gFxFrames), k = atomic_load(&gCasFrames);
    if (n || f) nlog(@"frames: NSS %ld, MetalFX %ld, CAS %ld", n, f, k);
}
