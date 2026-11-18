/* MTL-03: DXMT v0.80 writes the mesh dispatch size of an indirect tessellation / geometry-shader draw with one vertex shader
 * per render pass, ts_draw_arguments_marshal / gs_draw_arguments_marshal, meant to loop over the pass's tasks. The loop has
 * no increment, and the compiled shader in the engine does tasks[0] only, so draws 2..n keep whatever the never-cleared
 * buffer held. The stand-in below is that compiled shader (the same task layout, one task done, nothing else), so running it
 * without the fix cannot loop on the GPU. The program's name starts with "wine" like the loader's, and the library comes in
 * with DYLD_INSERT_LIBRARIES.
 *
 *   wine-glfixes-marshal-test bug [metallib]     only the first task of each pass written (as the engine does)
 *   wine-glfixes-marshal-test fixed [metallib]   every task written; empty, incomplete and overflowing draws get 0 groups
 *   wine-glfixes-marshal-test other              a function with another task layout is left as it is
 * With a metallib path (the engine's library cut out of DXMT's d3d11.dll) its own two functions are run instead. */
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>

static NSString *const kStandIn =
    @"#include <metal_stdlib>\nusing namespace metal;\n"
     "struct DXMTDispatchArguments { uint x; uint y; uint z; };\n"
     "struct DXMTTSDispatchMarshal { constant uint2& draw_arguments; device DXMTDispatchArguments& dispatch_arguments_out;\n"
     "  ulong max_object_threadgroups; ushort control_point_count; ushort patch_per_group; uint end_of_command; };\n"
     "struct DXMTGSDispatchMarshal { constant uint2& draw_arguments; device DXMTDispatchArguments& dispatch_arguments_out;\n"
     "  ulong max_object_threadgroups; uint vertex_count_per_warp; uint end_of_command; };\n"
     "[[vertex]] void ts_draw_arguments_marshal(constant DXMTTSDispatchMarshal* tasks [[buffer(0)]]) {\n"
     "  constant DXMTTSDispatchMarshal& task = tasks[0];\n"
     "  device DXMTDispatchArguments& output = task.dispatch_arguments_out;\n"
     "  uint patch_count_per_instance = task.draw_arguments.x / (uint)task.control_point_count;\n"
     "  uint x = (patch_count_per_instance - 1) / task.patch_per_group + 1;\n"
     "  if (x * task.draw_arguments.y > task.max_object_threadgroups) { output.x = 0; output.y = 0; output.z = 0; }\n"
     "  else { output.x = x; output.y = task.draw_arguments.y; output.z = 1; }\n"
     "}\n"
     "[[vertex]] void gs_draw_arguments_marshal(constant DXMTGSDispatchMarshal* tasks [[buffer(0)]]) {\n"
     "  constant DXMTGSDispatchMarshal& task = tasks[0];\n"
     "  device DXMTDispatchArguments& output = task.dispatch_arguments_out;\n"
     "  uint x = (task.draw_arguments.x - 1) / task.vertex_count_per_warp + 1;\n"
     "  if (x * task.draw_arguments.y > task.max_object_threadgroups) { output.x = 0; output.y = 0; output.z = 0; }\n"
     "  else { output.x = x; output.y = task.draw_arguments.y; output.z = 1; }\n"
     "}\n";

/* the same names, the tasks at buffer 1: not DXMT v0.80's layout, so the fix must leave them alone */
static NSString *const kOther =
    @"#include <metal_stdlib>\nusing namespace metal;\n"
     "struct T { device uint *out; uint end_of_command; };\n"
     "[[vertex]] void ts_draw_arguments_marshal(constant T* tasks [[buffer(1)]]) { *tasks[0].out = 7; }\n"
     "[[vertex]] void gs_draw_arguments_marshal(constant T* tasks [[buffer(1)]]) { *tasks[0].out = 7; }\n";

typedef struct { uint64_t draw_args, dispatch_args_out, max_object_threadgroups; uint16_t control_point_count, patch_per_group; uint32_t end_of_command; } TSTask;
typedef struct { uint64_t draw_args, dispatch_args_out, max_object_threadgroups; uint32_t vertex_count_per_warp, end_of_command; } GSTask;
typedef struct { uint32_t x, y, z; } Groups;

#define UNTOUCHED 0xA5A5A5A5u
enum { NTS = 6, NGS = 4 };
/* draw arguments (vertex or index count, instance count) and what a correct marshal writes */
static const uint32_t kTSArgs[NTS][2] = {{12, 2}, {300, 1}, {0, 2}, {2, 1}, {96, 5}, {9, 3}};
static const uint16_t kTSShape[NTS][2] = {{3, 4}, {3, 8}, {3, 2}, {3, 4}, {3, 1}, {3, 32}};   /* control points, patches a group */
static const Groups kTSWant[NTS] = {{1, 2, 1}, {13, 1, 1}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {1, 3, 1}};
/* 2: no vertices, the old sum wraps to 2^31 groups x 2; 3: an incomplete patch; 4: 32 x 5 groups over the limit of 100 */
static const uint32_t kGSArgs[NGS][2] = {{10, 3}, {0, 2}, {64, 1}, {5, 0}};
static const uint32_t kGSWarp[NGS] = {4, 2, 32, 4};
static const Groups kGSWant[NGS] = {{3, 3, 1}, {0, 0, 0}, {2, 1, 1}, {0, 0, 0}};

static id<MTLRenderPipelineState> marshalPipeline(id<MTLDevice> d, id<MTLFunction> f)
{
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = f;
    pd.rasterizationEnabled = NO;
    NSError *e = nil;
    id<MTLRenderPipelineState> ps = [d newRenderPipelineStateWithDescriptor:pd error:&e];
    if (!ps) printf("FAIL: pipeline for %s: %s\n", [f.name UTF8String], [[e description] UTF8String]);
    return ps;
}

/* one pass, as DXMT ends one: every task in one buffer, the last one marked, one point drawn */
static BOOL runPass(id<MTLCommandQueue> q, id<MTLRenderPipelineState> ps, id<MTLBuffer> tasks,
                    id<MTLBuffer> args, id<MTLBuffer> out)
{
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor new];
    rp.renderTargetWidth = 1;
    rp.renderTargetHeight = 1;
    rp.defaultRasterSampleCount = 1;
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:ps];
    [enc useResource:args usage:MTLResourceUsageRead stages:MTLRenderStageVertex];
    [enc useResource:out usage:MTLResourceUsageWrite stages:MTLRenderStageVertex];
    [enc setVertexBuffer:tasks offset:0 atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypePoint vertexStart:0 vertexCount:1];
    [enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    if (cb.status != MTLCommandBufferStatusCompleted) { printf("FAIL: command buffer: %s\n", [[cb.error description] UTF8String]); return NO; }
    return YES;
}

static int check(const char *what, const Groups *got, const Groups *want, int n, BOOL onlyFirst)
{
    int bad = 0;
    for (int i = 0; i < n; i++) {
        BOOL untouched = got[i].x == UNTOUCHED && got[i].y == UNTOUCHED && got[i].z == UNTOUCHED;
        BOOL ok = (onlyFirst && i > 0) ? untouched : !memcmp(&got[i], &want[i], sizeof(Groups));
        if (!ok) {
            printf("FAIL: %s task %d: %u %u %u, want %s\n", what, i, got[i].x, got[i].y, got[i].z,
                   (onlyFirst && i > 0) ? "untouched" : "the right groups");
            bad++;
        }
    }
    return bad;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        const char *mode = argc > 1 ? argv[1] : "fixed";
        BOOL bug = !strcmp(mode, "bug"), other = !strcmp(mode, "other");
        id<MTLDevice> d = MTLCreateSystemDefaultDevice();
        id<MTLCommandQueue> q = [d newCommandQueue];
        NSError *e = nil;
        id<MTLLibrary> lib;
        if (argc > 2) {
            NSData *data = [NSData dataWithContentsOfFile:@(argv[2])];
            if (!data) { printf("FAIL: cannot read %s\n", argv[2]); return 2; }
            dispatch_data_t dd = dispatch_data_create(data.bytes, data.length, nil, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            lib = [d newLibraryWithData:dd error:&e];   /* the way winemetal.so loads DXMT's own library */
        } else {
            lib = [d newLibraryWithSource:other ? kOther : kStandIn options:nil error:&e];
        }
        if (!lib) { printf("FAIL: library: %s\n", [[e description] UTF8String]); return 2; }
        id<MTLFunction> ts = [lib newFunctionWithName:@"ts_draw_arguments_marshal"];
        id<MTLFunction> gs = [lib newFunctionWithName:@"gs_draw_arguments_marshal"];
        if (!ts || !gs) { printf("FAIL: the library has no marshal functions\n"); return 2; }
        BOOL replaced = [ts.name hasPrefix:@"lullaby_"] && [gs.name hasPrefix:@"lullaby_"];
        if (other) {
            BOOL leftAlone = !replaced && [ts.name isEqualToString:@"ts_draw_arguments_marshal"];
            printf(leftAlone ? "ok: another task layout is left alone\n" : "FAIL: another task layout was replaced (%s)\n", [ts.name UTF8String]);
            return leftAlone ? 0 : 1;
        }
        if (replaced == bug) { printf("FAIL: functions are %s, mode %s\n", [ts.name UTF8String], mode); return 1; }

        id<MTLBuffer> args = [d newBufferWithLength:4096 options:MTLResourceStorageModeShared];
        id<MTLBuffer> out = [d newBufferWithLength:4096 options:MTLResourceStorageModeShared];
        id<MTLBuffer> tsTasks = [d newBufferWithLength:sizeof(TSTask) * NTS options:MTLResourceStorageModeShared];
        id<MTLBuffer> gsTasks = [d newBufferWithLength:sizeof(GSTask) * NGS options:MTLResourceStorageModeShared];
        uint32_t *a = args.contents;
        memset(out.contents, 0xA5, out.length);
        TSTask *tt = tsTasks.contents;
        for (int i = 0; i < NTS; i++) {
            a[2 * i] = kTSArgs[i][0], a[2 * i + 1] = kTSArgs[i][1];
            tt[i] = (TSTask){args.gpuAddress + 8 * i, out.gpuAddress + sizeof(Groups) * i, 100, kTSShape[i][0], kTSShape[i][1], i == NTS - 1};
        }
        GSTask *gt = gsTasks.contents;
        for (int i = 0; i < NGS; i++) {
            a[256 + 2 * i] = kGSArgs[i][0], a[256 + 2 * i + 1] = kGSArgs[i][1];
            gt[i] = (GSTask){args.gpuAddress + 1024 + 8 * i, out.gpuAddress + 2048 + sizeof(Groups) * i, 100, kGSWarp[i], i == NGS - 1};
        }
        id<MTLRenderPipelineState> tps = marshalPipeline(d, ts), gps = marshalPipeline(d, gs);
        if (!tps || !gps || !runPass(q, tps, tsTasks, args, out) || !runPass(q, gps, gsTasks, args, out)) return 2;
        int bad = check("ts", out.contents, kTSWant, NTS, bug) + check("gs", (Groups *)((char *)out.contents + 2048), kGSWant, NGS, bug);
        if (bad) return 1;
        printf(bug ? "ok: only the first task of a pass is written, the rest keep what the buffer held (%s, DXMT v0.80)\n"
                   : "ok: every task of a pass gets its groups, empty and overflowing draws none (%s, MTL-03)\n",
               argc > 2 ? "engine library" : "stand-in");
        return 0;
    }
}
