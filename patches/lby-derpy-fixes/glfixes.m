/* lby-derpy-fixes: faults of WineMetalGL (OpenGL on Metal) and DXMT (Direct3D 11 on Metal) worked around from outside, until the authors mend them.
 * Injected into the Wine loader's process (DYLD_INSERT_LIBRARIES, like lby-pinkiepie-windowstate); does nothing unless the
 * process runs WineMetalGL (WINEDLLOVERRIDES names winemetalgl). Uses names only (a symbol, a label), no offsets.
 *
 *   GLF-02  The colour texture of a window ("default framebuffer", private storage) is never cleared, at the start and when
 *           the window changes size. A game that swaps before it has drawn (a loading screen) showed the GPU's old memory,
 *           a flat magenta rectangle at the switch to native full screen. The texture is given its label the moment it is
 *           made: a texture given that label is cleared to black at once, before WineMetalGL copies the old picture into
 *           it. LULLABY_GL_CLEAR=0 turns it off.
 *
 *   MTL-01  A Metal mesh render pipeline that has a colour attachment but no fragment function aborts the process in Metal's own
 *           descriptor validation ("Mesh Render Pipeline Descriptor Validation, fragmentFunction must not be nil"). DXMT builds such
 *           a pipeline for a Direct3D 11 pass that has tessellation, a render target and no pixel shader (Modern Warfare Remastered,
 *           after a mission loads). Direct3D 11 means "no colour is written" there, so the pipeline gets an empty fragment function
 *           and a colour write mask of none, in the two calls that take a mesh descriptor (the device's pipeline creation and a
 *           binary archive's addMeshRenderPipelineFunctions). Not tied to one game. LULLABY_MESH_FS=0 turns it off.
 *
 *   MTL-02  DXMT picks the largest tessellation factor whose mesh fits Metal's 32768 bytes with dxmt::dxbc::estimate_mesh_size
 *           (winemetal.so), and that estimate is short: it rounds the vertex count of a strip down to a multiple of 4 (Metal rounds
 *           up) and leaves the position out of a vertex. The factor it picks then makes a mesh of 34560..36992 bytes, the pipeline
 *           is never made ("Failed to create tessellation raster PSO: Total mesh size ... exceeds", Modern Warfare Remastered after
 *           a mission loads, then a GPU reset). The function is replaced with the same sum, the factor one more (a fractional
 *           factor is rounded up to even or odd: 57 made 124 vertices, 33728 bytes), vertices rounded up, two float4 more a vertex. Found by its name and checked byte for byte (the field's offset is read out of its own instruction); another
 *           build of it is left alone and said in the log. x86_64 only (the engine's winemetal.so). LULLABY_TESS_FIT=0 turns it off.
 *
 *   MTL-03  An indirect Direct3D 11 draw with tessellation or a geometry shader becomes a mesh draw whose group count DXMT
 *           writes on the GPU: every such draw of a render pass adds a task, and at the end of the pass one vertex shader
 *           (ts_draw_arguments_marshal / gs_draw_arguments_marshal in DXMT's own library) is meant to go over all tasks. In
 *           v0.80 its loop has no increment (mended upstream after v0.80), and the shipped shader does the first task only, so
 *           the 2nd..nth draw of a pass takes its group count from a buffer that is never cleared: leftovers, up to a billion
 *           groups, and the GPU stays busy until macOS stops it (Modern Warfare Remastered in a mission: display stuck, GPU
 *           restart). Asked for by those two names, the library gives fixed functions built from source instead (every task,
 *           the loop bounded, no draw and an overflowing count get 0 groups), only when Metal's reflection shows DXMT v0.80's
 *           task layout; another layout is left alone and said in the log. Not tied to one game. LULLABY_INDIRECT_ARGS=0 turns it off.
 *
 * GLF-02 goes when WineMetalGL mends it; MTL-01, MTL-02 and MTL-03 go when DXMT does (agent report: winemetalgl-issue-draft-resize-uninitialised). */
#import <Metal/Metal.h>
#include <dlfcn.h>
#include <libkern/OSCacheControl.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void say(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fputs("glfixes: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}

static BOOL runsWineMetalGL(void)
{
    const char *over = getenv("WINEDLLOVERRIDES");
    return over && strstr(over, "winemetalgl");
}

static BOOL switchedOff(const char *name)
{
    const char *v = getenv(name);
    return v && !strcmp(v, "0");
}

/* ---- GLF-02 ---------------------------------------------------------------------------------------------------------- */

static IMP gOrigSetLabel;

static void clearToBlack(id<MTLTexture> texture)
{
    static id<MTLCommandQueue> queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = [[texture device] newCommandQueue]; });
    if (!queue || !(texture.usage & MTLTextureUsageRenderTarget)) return;
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLCommandBuffer> buffer = [queue commandBuffer];
    [[buffer renderCommandEncoderWithDescriptor:pass] endEncoding];
    [buffer commit];
    [buffer waitUntilCompleted];   /* before WineMetalGL's own commands touch the texture */
}

static void labelHook(id self, SEL _cmd, NSString *label)
{
    ((void (*)(id, SEL, NSString *))gOrigSetLabel)(self, _cmd, label);
    if ([label isEqualToString:@"default framebuffer"] && [self conformsToProtocol:@protocol(MTLTexture)])
        clearToBlack((id<MTLTexture>)self);
}

static void hookTextureLabel(id<MTLDevice> device)
{
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
    d.storageMode = MTLStorageModePrivate;
    d.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> probe = [device newTextureWithDescriptor:d];
    Method m = probe ? class_getInstanceMethod(object_getClass(probe), @selector(setLabel:)) : NULL;
    if (!m) return;
    gOrigSetLabel = method_getImplementation(m);
    method_setImplementation(m, (IMP)labelHook);
    say("new window textures are cleared to black");
}

/* ---- MTL-01 ---------------------------------------------------------------------------------------------------------- */

static IMP gOrigMeshNew, gOrigMeshArchive;
static int gMeshFixed;

static id<MTLFunction> emptyFragment(id<MTLDevice> device)
{
    static id<MTLFunction> fn;
    static id<MTLDevice> owner;
    @synchronized ([NSNull null]) {
        if (fn && owner == device) return fn;
        NSError *e = nil;
        id<MTLLibrary> lib = [device newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nfragment void lullaby_empty_fragment() {}\n"
                                                  options:nil error:&e];
        fn = lib ? [lib newFunctionWithName:@"lullaby_empty_fragment"] : nil;
        owner = device;
        if (!fn) say("MTL-01: the empty fragment function did not compile: %s", e ? [[e description] UTF8String] : "?");
        return fn;
    }
}

/* A mesh descriptor that would abort: rasterization on, a colour attachment, no fragment function. */
static void fixMeshDescriptor(MTLMeshRenderPipelineDescriptor *d, id<MTLDevice> device)
{
    if (!d || ![d isKindOfClass:[MTLMeshRenderPipelineDescriptor class]] || d.fragmentFunction || !d.rasterizationEnabled) return;
    BOOL color = NO;
    for (NSUInteger i = 0; i < 8; i++)
        if (d.colorAttachments[i].pixelFormat != MTLPixelFormatInvalid) { color = YES; break; }
    if (!color) return;
    id<MTLFunction> fn = emptyFragment(device);
    if (!fn) return;
    d.fragmentFunction = fn;
    for (NSUInteger i = 0; i < 8; i++)
        if (d.colorAttachments[i].pixelFormat != MTLPixelFormatInvalid) d.colorAttachments[i].writeMask = MTLColorWriteMaskNone;
    if (gMeshFixed++ == 0) say("MTL-01: a mesh pipeline without a fragment function got an empty one (no colour written, as in Direct3D 11)");
}

static id meshNewHook(id self, SEL _cmd, MTLMeshRenderPipelineDescriptor *d, MTLPipelineOption options, void *reflection, NSError **error)
{
    fixMeshDescriptor(d, (id<MTLDevice>)self);
    return ((id (*)(id, SEL, id, MTLPipelineOption, void *, NSError **))gOrigMeshNew)(self, _cmd, d, options, reflection, error);
}

static BOOL meshArchiveHook(id self, SEL _cmd, MTLMeshRenderPipelineDescriptor *d, NSError **error)
{
    if ([self respondsToSelector:@selector(device)]) fixMeshDescriptor(d, [(id<MTLBinaryArchive>)self device]);
    return ((BOOL (*)(id, SEL, id, NSError **))gOrigMeshArchive)(self, _cmd, d, error);
}

static void hookMeshPipelines(id<MTLDevice> device)
{
    SEL sel = @selector(newRenderPipelineStateWithMeshDescriptor:options:reflection:error:);
    Method m = class_getInstanceMethod(object_getClass(device), sel);
    if (m) {
        gOrigMeshNew = method_getImplementation(m);
        method_setImplementation(m, (IMP)meshNewHook);
    }
    NSError *e = nil;
    id<MTLBinaryArchive> archive = [device newBinaryArchiveWithDescriptor:[MTLBinaryArchiveDescriptor new] error:&e];
    SEL asel = @selector(addMeshRenderPipelineFunctionsWithDescriptor:error:);
    Method am = archive ? class_getInstanceMethod(object_getClass(archive), asel) : NULL;
    if (am) {
        gOrigMeshArchive = method_getImplementation(am);
        method_setImplementation(am, (IMP)meshArchiveHook);
    }
    if (m || am) say("MTL-01 armed (device call %s, archive call %s)", m ? "yes" : "no", am ? "yes" : "no");
}

/* ---- MTL-02 ---------------------------------------------------------------------------------------------------------- */

#if defined(__x86_64__)
#define MESH_SIZE_SYMBOL "__ZN4dxmt4dxbc18estimate_mesh_sizeEPNS0_18SM50ShaderInternalEj"
/* DXMT v0.80: size = outputs(shader) * 16 * (((2 * (factor + 1) + 4) & ~3) | 1); bytes 6..9 are the field's offset */
static const unsigned char kMeshSizeCode[37] = {
    0x55, 0x48, 0x89, 0xe5, 0x8b, 0x8f, 0, 0, 0, 0, 0xc1, 0xe1, 0x04, 0xff, 0xc6, 0x48, 0x8d, 0x04, 0x75, 0x04, 0x00, 0x00,
    0x00, 0x48, 0x83, 0xe0, 0xfc, 0x48, 0x83, 0xc8, 0x01, 0x48, 0x0f, 0xaf, 0xc1, 0x5d, 0xc3};
static uint32_t gOutputsOffset;
static int gTessFitDone;

static uint64_t fittedMeshSize(const void *shader, uint32_t factor)
{
    uint64_t outputs = *(const uint32_t *)((const char *)shader + gOutputsOffset);
    /* the shader rounds a fractional factor up to even or odd (one more), Metal rounds the vertices up to 4 */
    uint64_t vertices = (2ull * ((uint64_t)factor + 2) + 4 + 3) & ~3ull;
    return vertices * (outputs + 2) * 16;
}

/* the symbol out of the image's own symbol table (an image being added: no dlopen inside dyld's callback) */
static void *findSymbol(const struct mach_header_64 *mh, intptr_t slide, const char *want)
{
    const struct load_command *lc = (const void *)(mh + 1);
    const struct symtab_command *st = NULL;
    const struct segment_command_64 *linkedit = NULL;
    for (uint32_t i = 0; i < mh->ncmds; i++, lc = (const void *)((const char *)lc + lc->cmdsize)) {
        if (lc->cmd == LC_SYMTAB) st = (const void *)lc;
        else if (lc->cmd == LC_SEGMENT_64 && !strcmp(((const struct segment_command_64 *)lc)->segname, SEG_LINKEDIT))
            linkedit = (const void *)lc;
    }
    if (!st || !linkedit) return NULL;
    const char *base = (const char *)(linkedit->vmaddr + slide - linkedit->fileoff);
    const struct nlist_64 *syms = (const void *)(base + st->symoff);
    const char *strs = base + st->stroff;
    for (uint32_t i = 0; i < st->nsyms; i++)
        if ((syms[i].n_type & N_TYPE) == N_SECT && syms[i].n_un.n_strx && !strcmp(strs + syms[i].n_un.n_strx, want))
            return (void *)(syms[i].n_value + slide);
    return NULL;
}

static void fitMeshSize(const struct mach_header *header, intptr_t slide)
{
    Dl_info info;
    if (gTessFitDone || header->magic != MH_MAGIC_64 || !dladdr(header, &info) || !info.dli_fname) return;
    size_t len = strlen(info.dli_fname);
    if (len < 13 || strcmp(info.dli_fname + len - 13, "/winemetal.so")) return;
    gTessFitDone = 1;
    unsigned char *fn = findSymbol((const struct mach_header_64 *)header, slide, MESH_SIZE_SYMBOL);
    if (!fn) { say("MTL-02: winemetal.so has no estimate_mesh_size, left alone"); return; }
    for (int i = 0; i < 37; i++)
        if ((i < 6 || i > 9) && fn[i] != kMeshSizeCode[i]) { say("MTL-02: estimate_mesh_size is another build (byte %d), left alone", i); return; }
    memcpy(&gOutputsOffset, fn + 6, 4);
    unsigned char jump[12] = {0x48, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xe0};   /* movabs rax, target; jmp rax */
    uint64_t target = (uint64_t)fittedMeshSize;
    memcpy(jump + 2, &target, 8);
    mach_vm_address_t page = (mach_vm_address_t)fn & ~(mach_vm_address_t)(vm_page_size - 1);
    mach_vm_size_t span = ((mach_vm_address_t)fn + sizeof(jump) - page + vm_page_size - 1) & ~(mach_vm_size_t)(vm_page_size - 1);
    if (mach_vm_protect(mach_task_self(), page, span, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) {
        say("MTL-02: code page not writable, left alone");
        return;
    }
    memcpy(fn, jump, sizeof(jump));
    mach_vm_protect(mach_task_self(), page, span, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    sys_icache_invalidate(fn, sizeof(jump));
    say("MTL-02 armed: tessellation meshes sized as Metal sizes them (outputs field +0x%x)", gOutputsOffset);
}

#endif

/* ---- MTL-03 ---------------------------------------------------------------------------------------------------------- */

typedef id (*NewFunctionIMP)(id, SEL, NSString *) __attribute__((ns_returns_retained));
static NewFunctionIMP gOrigNewFunction;

typedef struct { const char *name; NSUInteger offset; MTLDataType type; } TaskField;
/* DXMT v0.80's tasks (dxmt_context.cpp TS_MARSHAL_TASK, GS_MARSHAL_TASK), 32 bytes each, at buffer 0 */
static const TaskField kTSFields[] = {
    {"draw_arguments", 0, MTLDataTypePointer}, {"dispatch_arguments_out", 8, MTLDataTypePointer},
    {"max_object_threadgroups", 16, MTLDataTypeULong}, {"control_point_count", 24, MTLDataTypeUShort},
    {"patch_per_group", 26, MTLDataTypeUShort}, {"end_of_command", 28, MTLDataTypeUInt}};
static const TaskField kGSFields[] = {
    {"draw_arguments", 0, MTLDataTypePointer}, {"dispatch_arguments_out", 8, MTLDataTypePointer},
    {"max_object_threadgroups", 16, MTLDataTypeULong}, {"vertex_count_per_warp", 24, MTLDataTypeUInt},
    {"end_of_command", 28, MTLDataTypeUInt}};
static const struct { const char *dxmt, *fixed; const TaskField *fields; NSUInteger count; } kMarshal[2] = {
    {"ts_draw_arguments_marshal", "lullaby_ts_draw_arguments_marshal", kTSFields, sizeof kTSFields / sizeof *kTSFields},
    {"gs_draw_arguments_marshal", "lullaby_gs_draw_arguments_marshal", kGSFields, sizeof kGSFields / sizeof *kGSFields}};

/* every task of the pass, the loop bounded; no draw (no vertices, an incomplete patch, no instances) and a count over the
 * limit get 0 groups, the product taken in 64 bits (DXMT's 32-bit product wraps: 2^31 groups x 2 passed as 0) */
static NSString *const kMarshalSource =
    @"#include <metal_stdlib>\nusing namespace metal;\n"
     "struct lby_groups { uint x; uint y; uint z; };\n"
     "struct lby_ts_task { constant uint2 *draw_arguments; device lby_groups *dispatch_arguments_out;\n"
     "  ulong max_object_threadgroups; ushort control_point_count; ushort patch_per_group; uint end_of_command; };\n"
     "struct lby_gs_task { constant uint2 *draw_arguments; device lby_groups *dispatch_arguments_out;\n"
     "  ulong max_object_threadgroups; uint vertex_count_per_warp; uint end_of_command; };\n"
     "static void lby_put(device lby_groups *out, ulong groups, uint instances, ulong limit) {\n"
     "  bool draw = groups && instances && groups * instances <= limit;\n"
     "  out->x = draw ? uint(groups) : 0; out->y = draw ? instances : 0; out->z = draw ? 1 : 0;\n"
     "}\n"
     "vertex void lullaby_ts_draw_arguments_marshal(constant lby_ts_task *tasks [[buffer(0)]]) {\n"
     "  for (uint i = 0; i < (1u << 20); i++) {\n"
     "    constant lby_ts_task &t = tasks[i];\n"
     "    uint2 a = *t.draw_arguments;\n"
     "    uint patches = t.control_point_count ? a.x / t.control_point_count : 0;\n"
     "    ulong groups = patches && t.patch_per_group ? ulong((patches - 1) / t.patch_per_group) + 1 : 0;\n"
     "    lby_put(t.dispatch_arguments_out, groups, a.y, t.max_object_threadgroups);\n"
     "    if (t.end_of_command) break;\n"
     "  }\n"
     "}\n"
     "vertex void lullaby_gs_draw_arguments_marshal(constant lby_gs_task *tasks [[buffer(0)]]) {\n"
     "  for (uint i = 0; i < (1u << 20); i++) {\n"
     "    constant lby_gs_task &t = tasks[i];\n"
     "    uint2 a = *t.draw_arguments;\n"
     "    ulong groups = a.x && t.vertex_count_per_warp ? ulong((a.x - 1) / t.vertex_count_per_warp) + 1 : 0;\n"
     "    lby_put(t.dispatch_arguments_out, groups, a.y, t.max_object_threadgroups);\n"
     "    if (t.end_of_command) break;\n"
     "  }\n"
     "}\n";

/* the function's one buffer, at index 0, holds tasks laid out field by field as `want` (Metal's own reflection) */
static BOOL sameTaskLayout(id<MTLDevice> device, id<MTLFunction> fn, const TaskField *want, NSUInteger count)
{
    @autoreleasepool {   /* the reflection is autoreleased; a Wine thread may have no pool */
    if (fn.functionType != MTLFunctionTypeVertex) return NO;
    MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
    d.vertexFunction = fn;
    d.rasterizationEnabled = NO;
    MTLAutoreleasedRenderPipelineReflection refl = nil;
    NSError *e = nil;
    if (![device newRenderPipelineStateWithDescriptor:d options:MTLPipelineOptionBindingInfo | MTLPipelineOptionBufferTypeInfo
                                           reflection:&refl error:&e]) return NO;
    id<MTLBufferBinding> tasks = nil;
    NSUInteger buffers = 0;
    for (id<MTLBinding> b in refl.vertexBindings)
        if (b.type == MTLBindingTypeBuffer && ++buffers && b.index == 0) tasks = (id<MTLBufferBinding>)b;
    if (buffers != 1 || !tasks || tasks.bufferDataSize != 32) return NO;
    MTLStructType *st = tasks.bufferPointerType.elementStructType ?: tasks.bufferStructType;
    if (st.members.count != count) return NO;
    for (NSUInteger i = 0; i < count; i++) {
        MTLStructMember *m = st.members[i];
        if (strcmp(m.name.UTF8String ?: "", want[i].name) || m.offset != want[i].offset || m.dataType != want[i].type) return NO;
    }
    return YES;
    }
}

static id<MTLLibrary> marshalLibrary(id<MTLDevice> device)
{
    static id<MTLLibrary> lib;
    static id<MTLDevice> owner;
    @synchronized ([NSNull null]) {
        if (lib && owner == device) return lib;
        NSError *e = nil;
        lib = [device newLibraryWithSource:kMarshalSource options:nil error:&e];
        owner = device;
        if (!lib) say("MTL-03: the fixed marshal functions did not compile: %s", e ? [[e description] UTF8String] : "?");
        return lib;
    }
}

static __attribute__((ns_returns_retained)) id fixedMarshal(id<MTLLibrary> library, id<MTLFunction> original, int kind)
{
    id<MTLDevice> device = library.device;
    if (!device || !sameTaskLayout(device, original, kMarshal[kind].fields, kMarshal[kind].count)) {
        say("MTL-03: %s has another task layout, left alone", kMarshal[kind].dxmt);
        return nil;
    }
    id<MTLFunction> fixed = [marshalLibrary(device) newFunctionWithName:@(kMarshal[kind].fixed)];
    if (!fixed || !sameTaskLayout(device, fixed, kMarshal[kind].fields, kMarshal[kind].count)) {
        say("MTL-03: the fixed %s is not laid out as DXMT's, left alone", kMarshal[kind].dxmt);
        return nil;
    }
    say("MTL-03: DXMT's %s replaced: every indirect draw of a pass gets its own mesh groups (v0.80 wrote the first only)",
        kMarshal[kind].dxmt);
    return fixed;
}

static __attribute__((ns_returns_retained)) id newFunctionHook(id self, SEL _cmd, NSString *name)
{
    id fn = gOrigNewFunction(self, _cmd, name);
    if (!fn || name.length != 25 || ![name hasSuffix:@"_draw_arguments_marshal"]) return fn;   /* every other shader */
    int kind = [name isEqualToString:@(kMarshal[0].dxmt)] ? 0 : [name isEqualToString:@(kMarshal[1].dxmt)] ? 1 : -1;
    id fixed = kind < 0 ? nil : fixedMarshal((id<MTLLibrary>)self, fn, kind);
    return fixed ?: fn;
}

static void hookMarshalFunctions(void)
{
    /* Metal's one library class, the same for a library from data (winemetal.so) and from source */
    Class cls = objc_getClass("_MTLLibrary");
    Method m = cls && class_conformsToProtocol(cls, @protocol(MTLLibrary)) ? class_getInstanceMethod(cls, @selector(newFunctionWithName:)) : NULL;
    if (!m) { say("MTL-03: no Metal library class, left alone"); return; }
    gOrigNewFunction = (NewFunctionIMP)method_getImplementation(m);
    method_setImplementation(m, (IMP)newFunctionHook);
    say("MTL-03 armed: DXMT's indirect draw marshal functions are checked when asked for");
}

/* ---- arming on the renderer's first Metal device ------------------------------------------------------------------- */

/* GLF-02 and MTL-01 hook methods of the device's own classes, so they need a device. Making one in the constructor
 * (as before) ran before the engine applies .sevo/apps/<exe>.env, and Metal decides Apple's Metal HUD from
 * MTL_HUD_ENABLED when the process's first device is made: a game whose HUD was on in its own settings only (off for
 * the bottle) never showed it. So the library waits for the renderer (DXMT, WineMetalGL, D3DMetal) to make the first
 * device, through these two calls, and arms on that one. */
static BOOL gIsWineProcess;

static void armOnDevice(id<MTLDevice> device)
{
    static dispatch_once_t once;
    if (!device || !gIsWineProcess) return;
    dispatch_once(&once, ^{
        if (runsWineMetalGL() && !switchedOff("LULLABY_GL_CLEAR")) hookTextureLabel(device);
        if (!switchedOff("LULLABY_MESH_FS")) hookMeshPipelines(device);
    });
}

static id<MTLDevice> glfCreateSystemDefaultDevice(void) NS_RETURNS_RETAINED;   /* like the originals: the caller owns the result */
static NSArray<id<MTLDevice>> *glfCopyAllDevices(void) NS_RETURNS_RETAINED;

static id<MTLDevice> glfCreateSystemDefaultDevice(void)
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();   /* the real one: an image's own calls are not interposed */
    armOnDevice(device);
    return device;
}

static NSArray<id<MTLDevice>> *glfCopyAllDevices(void)
{
    NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();
    armOnDevice(devices.firstObject);
    return devices;
}

__attribute__((used, section("__DATA,__interpose"))) static const struct { const void *replacement, *original; } glfInterpose[] = {
    { (const void *)glfCreateSystemDefaultDevice, (const void *)MTLCreateSystemDefaultDevice },
    { (const void *)glfCopyAllDevices, (const void *)MTLCopyAllDevices },
};

__attribute__((constructor)) static void glf_init(void)
{
    const char *name = getprogname();
    if (!name || strncmp(name, "wine", 4) || !strcmp(name, "wineserver")) return;   /* the Wine loader's processes only */
    gIsWineProcess = YES;
    if (!switchedOff("LULLABY_INDIRECT_ARGS")) hookMarshalFunctions();
#if defined(__x86_64__)
    if (!switchedOff("LULLABY_TESS_FIT")) {
        _dyld_register_func_for_add_image(fitMeshSize);
    }
#endif
}
