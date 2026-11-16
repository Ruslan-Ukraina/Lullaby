/* MTL-01: a Metal mesh render pipeline with a colour attachment and no fragment function. Metal aborts the process on that unless
 * the library puts an empty fragment function in. The program's name starts with "wine" like the loader's, and the library comes
 * in with DYLD_INSERT_LIBRARIES.
 *
 *   wine-glfixes-mesh-test plain|raster-off|color|color-raster-off   a pipeline Metal accepts as it is, or the one it aborts on (color)
 *   wine-glfixes-mesh-test color-emptyfs                             the workaround written by hand */
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>
/* mesh pipeline, depth only, no fragment function (what a Direct3D 11 depth-only pass with tessellation becomes) */
int main(int argc, char **argv)
{
    @autoreleasepool {
        id<MTLDevice> d = MTLCreateSystemDefaultDevice();
        NSString *src = @"#include <metal_stdlib>\nusing namespace metal;\n"
            "struct V { float4 position [[position]]; };\n"
            "using M = mesh<V, void, 3, 1, topology::triangle>;\n"
            "[[mesh]] void m(M out) { out.set_primitive_count(1); out.set_index(0,0); out.set_index(1,1); out.set_index(2,2);\n"
            " V v; v.position = float4(0,0,0,1); out.set_vertex(0,v); out.set_vertex(1,v); out.set_vertex(2,v); }\n";
        NSError *e = nil;
        id<MTLLibrary> lib = [d newLibraryWithSource:src options:nil error:&e];
        if (!lib) { printf("FAIL: library: %s\n", [[e description] UTF8String]); return 2; }
        MTLMeshRenderPipelineDescriptor *pd = [MTLMeshRenderPipelineDescriptor new];
        pd.meshFunction = [lib newFunctionWithName:@"m"];
        pd.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        if (argc > 1 && !strcmp(argv[1], "raster-off")) pd.rasterizationEnabled = NO;
        if (argc > 1 && !strcmp(argv[1], "color")) pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        if (argc > 1 && !strcmp(argv[1], "color-raster-off")) { pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm; pd.rasterizationEnabled = NO; }
        if (argc > 1 && (!strcmp(argv[1], "color-emptyfs") || !strcmp(argv[1], "color-emptyfs-nomask"))) {
            pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
            id<MTLLibrary> fl = [d newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nfragment void lby_empty_fs() {}\n" options:nil error:&e];
            if (!fl) { printf("FAIL: fragment library: %s\n", [[e description] UTF8String]); return 2; }
            pd.fragmentFunction = [fl newFunctionWithName:@"lby_empty_fs"];
            if (!strcmp(argv[1], "color-emptyfs")) pd.colorAttachments[0].writeMask = MTLColorWriteMaskNone;
        }
        id<MTLRenderPipelineState> ps = [d newRenderPipelineStateWithMeshDescriptor:pd options:MTLPipelineOptionNone reflection:nil error:&e];
        printf(ps ? "ok: the mesh pipeline without a fragment function was created\n" : "FAIL: %s\n", ps ? "" : [[e description] UTF8String]);
        return ps ? 0 : 1;
    }
}
