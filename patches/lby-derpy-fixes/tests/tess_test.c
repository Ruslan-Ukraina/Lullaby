/* MTL-02: DXMT's mesh size estimate and the fitted one. A stand-in winemetal.so carries the very bytes of DXMT v0.80's
 * dxmt::dxbc::estimate_mesh_size under its name; the program (named "wine..." like the loader) loads it, as the engine does.
 *
 *   wine-glfixes-tess-test fitted   the sizes Metal reported in Modern Warfare Remastered's log come out (hook on)
 *   wine-glfixes-tess-test dxmt     DXMT's own short estimate comes out (LULLABY_TESS_FIT=0)
 *
 * The stand-in (x86_64): cc -arch x86_64 -dynamiclib -DSTANDIN tess_test.c -o <dir>/winemetal.so */
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef STANDIN
__asm__(".globl __ZN4dxmt4dxbc18estimate_mesh_sizeEPNS0_18SM50ShaderInternalEj\n"
        ".p2align 4\n"
        "__ZN4dxmt4dxbc18estimate_mesh_sizeEPNS0_18SM50ShaderInternalEj:\n"
        ".byte 0x55,0x48,0x89,0xe5,0x8b,0x8f,0x18,0x02,0x00,0x00,0xc1,0xe1,0x04,0xff,0xc6,0x48,0x8d,0x04,0x75,0x04,0x00,0x00\n"
        ".byte 0x00,0x48,0x83,0xe0,0xfc,0x48,0x83,0xc8,0x01,0x48,0x0f,0xaf,0xc1,0x5d,0xc3\n");
#else
typedef uint64_t (*estimate_fn)(void *, uint32_t);

/* DXMT v0.80's pick (dxbc_converter.cpp, domain shader reflection): count up from 1, stop at the first size above 32768 */
static uint32_t pick(estimate_fn f, void *shader)
{
    uint32_t best = 1;
    for (uint32_t k = 1; k <= 64; k++) {
        if (f(shader, k) > 32768) break;
        best = k;
    }
    return best;
}

int main(int argc, char **argv)
{
    if (argc < 3) { fprintf(stderr, "usage: %s fitted|dxmt <dir with winemetal.so>\n", argv[0]); return 2; }
    char path[1024];
    snprintf(path, sizeof path, "%s/winemetal.so", argv[2]);
    void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!h) { printf("FAIL: %s\n", dlerror()); return 2; }
    estimate_fn f = (estimate_fn)dlsym(h, "_ZN4dxmt4dxbc18estimate_mesh_sizeEPNS0_18SM50ShaderInternalEj");
    if (!f) { printf("FAIL: no symbol\n"); return 2; }
    unsigned char shader[0x400];
    int bad = 0;
    /* outputs in the log's failing pipelines: 16 (factor 60, Metal 34816), 17 (56, 34560), 18 (54, 35264); 15 made 33728 at 57
     * under the first MTL-02 (124 vertices: the factor rounded up to 58) */
    static const struct { uint32_t outputs, dxmt_pick, dxmt_size_at_pick; } cases[] = {{15, 64, 31920}, {16, 60, 32000}, {17, 56, 31824}, {18, 54, 32544}};
    for (unsigned i = 0; i < 4; i++) {
        memset(shader, 0, sizeof shader);
        memcpy(shader + 0x218, &cases[i].outputs, 4);
        uint32_t k = pick(f, shader);
        /* what Metal counts at worst: a fractional factor rounded up by one, vertices up to 4, position + outputs + one */
        uint64_t metal = ((2ull * (k + 2) + 4 + 3) & ~3ull) * (cases[i].outputs + 2) * 16;
        if (!strcmp(argv[1], "dxmt")) {
            if (k != cases[i].dxmt_pick || f(shader, k) != cases[i].dxmt_size_at_pick) bad = 1;
            printf("outputs %u: DXMT picks factor %u, estimate %llu, Metal %llu\n", cases[i].outputs, k,
                   (unsigned long long)f(shader, k), (unsigned long long)metal);
        } else {
            if (!k || metal > 0x8000) bad = 1;
            printf("outputs %u: fitted factor %u, Metal %llu (limit 32768)\n", cases[i].outputs, k, (unsigned long long)metal);
        }
    }
    printf(bad ? "FAIL\n" : "ok\n");
    return bad;
}
#endif
