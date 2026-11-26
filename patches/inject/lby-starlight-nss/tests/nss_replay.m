// Replays a lullaby-nss dump (the game's colour, depth and motion of consecutive frames) through NSSUpscaler with a given
// temporal tuning, and writes the result as a new dump that nss-dump-analyze.py reads like one from the game: "shown" is
// this replay, the dump's MetalFX shadow is kept beside it for comparison.
//
//   nss_replay <dump dir> <out dir> [quality: fast|low|mid|high]
//   env: NSS_TUNE="alphaAdd,alphaMul,gammaMul,thetaMul" (default 0,1,1,1), NSS_EXPOSURE (default 0.125), NSS_RES (weights dir)
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "NSSMetal/NSSMetal.h"

static id<MTLTexture> tex(id<MTLDevice> d, MTLPixelFormat f, NSUInteger w, NSUInteger h, NSData *bytes, NSUInteger bpp, MTLTextureUsage u) {
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:f width:w height:h mipmapped:NO];
    td.usage = u, td.storageMode = MTLStorageModeShared;
    id<MTLTexture> t = [d newTextureWithDescriptor:td];
    if (bytes) [t replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0 withBytes:bytes.bytes bytesPerRow:w * bpp];
    return t;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: nss_replay <dump dir> <out dir> [quality]\n"); return 2; }
        NSString *in = @(argv[1]), *out = @(argv[2]);
        const char *q = argc > 3 ? argv[3] : "mid";
        [[NSFileManager defaultManager] createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nil];
        float tune[4] = {0, 1, 1, 1};
        if (getenv("NSS_TUNE")) sscanf(getenv("NSS_TUNE"), "%f,%f,%f,%f", &tune[0], &tune[1], &tune[2], &tune[3]);
        NSSSetTemporalTuning(tune[0], tune[1], tune[2], tune[3]);
        float trust[2] = {0, 0};   // NSS_TRUST="motionPx,dev"
        if (getenv("NSS_TRUST")) sscanf(getenv("NSS_TRUST"), "%f,%f", &trust[0], &trust[1]);
        NSSSetHistoryTrust(trust[0], trust[1]);
        NSSSetHistoryTrustStill(getenv("NSS_STILL") ? (float)atof(getenv("NSS_STILL")) : 0);
        float outl[2] = {0, 0};   // NSS_OUTLIER="k,strength"
        if (getenv("NSS_OUTLIER")) sscanf(getenv("NSS_OUTLIER"), "%f,%f", &outl[0], &outl[1]);
        NSSSetOutlierDamping(outl[0], outl[1]);
        NSSSetSparkHistory(getenv("NSS_SPARK") ? (float)atof(getenv("NSS_SPARK")) : 0);
        NSSSetStillFlatness(getenv("NSS_FLAT") ? (float)atof(getenv("NSS_FLAT")) : 0);
        const float exposure = getenv("NSS_EXPOSURE") ? (float)atof(getenv("NSS_EXPOSURE")) : 0.125f;
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        id<MTLCommandQueue> queue = [dev newCommandQueue];
        NSArray<NSString *> *lines = [[NSString stringWithContentsOfFile:[in stringByAppendingPathComponent:@"meta.txt"] encoding:NSUTF8StringEncoding error:nil]
                                      componentsSeparatedByString:@"\n"];
        lines = [[lines filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [@([[a substringFromIndex:6] intValue]) compare:@([[b substringFromIndex:6] intValue])];
        }];
        if (getenv("NSS_FRAMES")) {   // "first,last": only these frames of the dump (the first gets a reset)
            int f0 = 0, f1 = 1 << 30; sscanf(getenv("NSS_FRAMES"), "%d,%d", &f0, &f1);
            lines = [lines filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *l, NSDictionary *b) {
                const int n = [[l substringFromIndex:6] intValue]; return n >= f0 && n <= f1; }]];
        }
        NSSUpscaler *up = nil;
        id<MTLTexture> outT = nil, expT = tex(dev, MTLPixelFormatR32Float, 1, 1, [NSData dataWithBytes:&exposure length:4], 4, MTLTextureUsageShaderRead);
        NSMutableString *meta = [NSMutableString string];
        BOOL first = YES;
        for (NSString *line in lines) {
            NSMutableDictionary *kv = [NSMutableDictionary dictionary];
            for (NSString *tok in [line componentsSeparatedByString:@" "]) {
                NSRange r = [tok rangeOfString:@"="];
                if (r.location != NSNotFound) kv[[tok substringToIndex:r.location]] = [tok substringFromIndex:r.location + 1];
            }
            const int n = [kv[@"frame"] intValue];
            int cw, ch, ow, oh, cf, mf;
            sscanf([kv[@"tex.color"] UTF8String], "%dx%d:%d", &cw, &ch, &cf);
            sscanf([kv[@"tex.motion"] UTF8String], "%*dx%*d:%d", &mf);
            sscanf([kv[@"tex.shown"] UTF8String], "%dx%d", &ow, &oh);
            int rw, rh; sscanf([kv[@"content"] UTF8String], "%dx%d", &rw, &rh);
            float jx, jy, sx, sy; sscanf([kv[@"jitter"] UTF8String], "%f,%f", &jx, &jy); sscanf([kv[@"mvscale"] UTF8String], "%f,%f", &sx, &sy);
            NSString *(^path)(NSString *) = ^(NSString *name) { return [in stringByAppendingFormat:@"/%03d-%@.raw", n, name]; };
            id<MTLTexture> color = tex(dev, (MTLPixelFormat)cf, cw, ch, [NSData dataWithContentsOfFile:path(@"color")], 4, MTLTextureUsageShaderRead);
            id<MTLTexture> motion = tex(dev, (MTLPixelFormat)mf, cw, ch, [NSData dataWithContentsOfFile:path(@"motion")], 4, MTLTextureUsageShaderRead);
            id<MTLTexture> depth = tex(dev, MTLPixelFormatR32Float, cw, ch, [NSData dataWithContentsOfFile:path(@"depth")], 4, MTLTextureUsageShaderRead);
            if (!up) {
                NSSUpscalerDescriptor *d = [NSSUpscalerDescriptor new];
                d.inputWidth = rw, d.inputHeight = rh, d.outputWidth = ow, d.outputHeight = oh;
                d.quality = !strcmp(q, "low") ? NSSQualityLow : !strcmp(q, "high") ? NSSQualityHigh : !strcmp(q, "fast") ? 3 : NSSQualityMid;
                d.resourceDirectory = [NSURL fileURLWithPath:@(getenv("NSS_RES") ?: ".")];
                NSError *err = nil;
                up = [[NSSUpscaler alloc] initWithDevice:dev descriptor:d error:&err];
                if (!up) { fprintf(stderr, "NSS setup failed: %s\n", err.localizedDescription.UTF8String); return 1; }
                outT = tex(dev, MTLPixelFormatRGBA16Float, ow, oh, nil, 8, MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite);
            }
            up.colorTexture = color, up.depthTexture = depth, up.motionTexture = motion, up.exposureTexture = expT, up.outputTexture = outT;
            up.jitterOffsetX = jx, up.jitterOffsetY = jy, up.motionVectorScaleX = sx, up.motionVectorScaleY = sy;
            up.depthReversed = [kv[@"depthrev"] intValue] != 0, up.reset = first, up.preExposure = 1;
            first = NO;
            id<MTLCommandBuffer> cb = [queue commandBuffer];
            [up encodeToCommandBuffer:cb];
            [cb commit], [cb waitUntilCompleted];
            if (cb.error) { fprintf(stderr, "frame %d: %s\n", n, cb.error.localizedDescription.UTF8String); return 1; }
            NSMutableData *px = [NSMutableData dataWithLength:(NSUInteger)ow * oh * 8];
            [outT getBytes:px.mutableBytes bytesPerRow:ow * 8 fromRegion:MTLRegionMake2D(0, 0, ow, oh) mipmapLevel:0];
            [px writeToFile:[out stringByAppendingFormat:@"/%03d-shown.raw", n] atomically:NO];
            for (NSString *name in @[@"color", @"motion", @"depth", @"metalfx"]) {
                NSString *src = path(name), *dst = [out stringByAppendingFormat:@"/%03d-%@.raw", n, name];
                [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
                [[NSFileManager defaultManager] createSymbolicLinkAtPath:dst withDestinationPath:src error:nil];
            }
            NSString *l = [line stringByReplacingOccurrencesOfString:[@"tex.shown=" stringByAppendingString:kv[@"tex.shown"]]
                                                          withString:[NSString stringWithFormat:@"tex.shown=%dx%d:115", ow, oh]];
            [meta appendFormat:@"%@\n", l];
        }
        [meta writeToFile:[out stringByAppendingPathComponent:@"meta.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        printf("replayed %lu frames, tune %g,%g,%g,%g, exposure %g\n", (unsigned long)lines.count, tune[0], tune[1], tune[2], tune[3], exposure);
    }
    return 0;
}
