// Cuts a signature database for a new Steam client build (docs/BACKLOG.md 22).
//
//     out/sigslice <base sigdb.json> <steam build> <out.json>
//
// Loads the client under $HOME/Library/Application Support/Steam/... the way
// anchorcheck does, and resolves every signature of the base database through its
// anchor, by the same code the dylib runs. The new database is the base with, per
// signature:
//   func_addr_this_build  where the anchor landed in this build;
//   aob_hex               the base's pattern if it still finds exactly that site on
//                         its own, otherwise a new one read from this build, with
//                         every pc-relative instruction (and the page offset that
//                         follows an ADRP) wildcarded, as short as stays unique.
// Every pattern is then checked the way anchorcheck checks the fallback: anchors
// forced to miss, np_resolve_signatures must land on the anchor's site.
//
// Anchors are never rewritten: one that does not resolve, or a vtable_slot (a data
// address of one build), needs a person, and the database is not written.
// Exit 0 written, 1 a signature needs a person, 2 bad input, 3 the client will not load.

#include "../resolver/sigdb.h"
#include "../resolver/resolver.h"
#include "../resolver/anchor.h"
#include "../resolver/aob.h"
#include "../core/macho.h"
#include "../../vendor/cJSON.h"

#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STEAM_MACOS \
    "/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/"
#define MAX_IMAGES   4
#define PATTERN_MIN  32
#define PATTERN_MAX  128

typedef struct {
    char                          module[64];
    const struct mach_header_64  *mh;
    intptr_t                      slide;
    uintptr_t                     text;
    size_t                        text_sz;
} image_t;

static image_t g_images[MAX_IMAGES];
static int     g_image_count;

static const image_t *image_for(const char *module) {
    for (int i = 0; i < g_image_count; i++)
        if (strcmp(g_images[i].module, module) == 0) return &g_images[i];
    return NULL;
}

static int load_image(const char *module) {
    if (image_for(module)) return 0;
    if (g_image_count >= MAX_IMAGES) return -1;
    const char *home = getenv("HOME");
    char path[1024], suffix[128];
    snprintf(path, sizeof(path), "%s%s%s", home ? home : "", STEAM_MACOS, module);
    snprintf(suffix, sizeof(suffix), "/%s", module);
    if (!dlopen(path, RTLD_LAZY | RTLD_LOCAL)) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror());
        return -1;
    }
    image_t *im = &g_images[g_image_count];
    size_t want = strlen(suffix);
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        size_t len = name ? strlen(name) : 0;
        if (len < want || strcmp(name + len - want, suffix) != 0) continue;
        im->mh    = (const struct mach_header_64 *)_dyld_get_image_header(i);
        im->slide = _dyld_get_image_vmaddr_slide(i);
        break;
    }
    if (!im->mh || np_find_segment(im->mh, im->slide, "__TEXT", &im->text, &im->text_sz) != 0) {
        fprintf(stderr, "%s: not found after dlopen, or no __TEXT\n", module);
        return -1;
    }
    snprintf(im->module, sizeof(im->module), "%s", module);
    g_image_count++;
    printf("image  %-20s %s\n", module, path);
    return 0;
}

// Instructions whose bits depend on where code and data sit in this build.
static int pc_relative(uint32_t w) {
    return (w & 0x9F000000u) == 0x90000000u      // ADRP
        || (w & 0x9F000000u) == 0x10000000u      // ADR
        || (w & 0x7C000000u) == 0x14000000u      // B, BL
        || (w & 0xFF000010u) == 0x54000000u      // B.cond
        || (w & 0x7E000000u) == 0x34000000u      // CBZ, CBNZ
        || (w & 0x7E000000u) == 0x36000000u      // TBZ, TBNZ
        || (w & 0x3B000000u) == 0x18000000u;     // LDR (literal), LDRSW, PRFM
}

// ADD (immediate) or a load/store with an unsigned offset off a register that an
// ADRP just set: the low 12 bits of a page address, which move with the data.
static int page_offset(uint32_t w, uint32_t adrp_regs) {
    unsigned rn = (w >> 5) & 31u;
    int add_imm = (w & 0x7F800000u) == 0x11000000u;
    int ldst_uimm = (w & 0x3B000000u) == 0x39000000u;
    return (add_imm || ldst_uimm) && (adrp_regs & (1u << rn));
}

static void pattern_text(const uint8_t *code, int len, char *out, size_t cap) {
    uint32_t adrp_regs = 0;
    size_t at = 0;
    out[0] = '\0';
    for (int off = 0; off + 4 <= len; off += 4) {
        uint32_t w;
        memcpy(&w, code + off, 4);
        int wild = pc_relative(w) || page_offset(w, adrp_regs);
        if ((w & 0x9F000000u) == 0x90000000u) adrp_regs |= 1u << (w & 31u);
        else adrp_regs &= ~(1u << (w & 31u));    // Rd overwritten (close enough)
        for (int b = 0; b < 4; b++) {
            int n = wild ? snprintf(out + at, cap - at, "%s??", at ? " " : "")
                         : snprintf(out + at, cap - at, "%s%02X", at ? " " : "", code[off + b]);
            if (n < 0 || (size_t)n >= cap - at) return;
            at += (size_t)n;
        }
    }
}

// The fallback path alone: anchor forced to miss, pattern only, as the dylib would run it.
static uintptr_t fallback_site(const image_t *im, const np_sig_entry_t *sig, const char *aob) {
    np_sig_entry_t copy = *sig;
    snprintf(copy.aob_hex, sizeof(copy.aob_hex), "%s", aob);
    if (copy.anchor.kind != NP_MATCH_AOB) {
        copy.anchor.str[0] = '\001';
        copy.anchor.str[1] = '\0';
        copy.anchor.va = 0;
        copy.anchor.calls[0][0] = '\001';
    }
    np_sigdb_t one = { .signatures = &copy, .sig_count = 1 };
    np_resolve_result_t res = {0};
    np_resolve_signatures(im->mh, im->slide, &one, im->module, &res);
    uintptr_t got = np_lookup_address(&res, copy.name);
    np_free_resolution(&res);
    return got;
}

static cJSON *read_json(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc((size_t)n + 1);
    if (!buf || fread(buf, 1, (size_t)n, f) != (size_t)n) { fclose(f); free(buf); return NULL; }
    fclose(f);
    buf[n] = '\0';
    cJSON *j = cJSON_Parse(buf);
    free(buf);
    return j;
}

static void set_string(cJSON *obj, const char *key, const char *value) {
    if (cJSON_GetObjectItem(obj, key))
        cJSON_ReplaceItemInObject(obj, key, cJSON_CreateString(value));
    else
        cJSON_AddStringToObject(obj, key, value);
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s <base sigdb.json> <steam build> <out.json>\n", argv[0]);
        return 2;
    }
    const char *base = argv[1], *out_path = argv[3];
    char *end = NULL;
    unsigned long long build = strtoull(argv[2], &end, 10);
    if (!build || !end || *end) { fprintf(stderr, "bad steam build '%s'\n", argv[2]); return 2; }

    np_sigdb_t db = {0};
    cJSON *doc = read_json(base);
    cJSON *sigs = doc ? cJSON_GetObjectItem(doc, "signatures") : NULL;
    if (!doc || !cJSON_IsArray(sigs) || np_load_profile(base, &db) != 0) {
        fprintf(stderr, "cannot read sigdb '%s'\n", base);
        return 2;
    }
    if (cJSON_GetArraySize(sigs) != db.sig_count) {
        fprintf(stderr, "%s: %d signatures in the file, %d loaded\n", base,
                cJSON_GetArraySize(sigs), db.sig_count);
        return 2;
    }
    if (load_image(NP_MODULE_DEFAULT) != 0) return 3;
    printf("base   %s (build %llu) -> build %llu\n\n", base,
           (unsigned long long)db.steam_build, build);

    int failed = 0, regenerated = 0;
    for (int i = 0; i < db.sig_count; i++) {
        np_sig_entry_t *sig = &db.signatures[i];
        cJSON *obj = cJSON_GetArrayItem(sigs, i);
        cJSON *name = cJSON_GetObjectItem(obj, "name");
        if (!cJSON_IsString(name) || strcmp(name->valuestring, sig->name) != 0) {
            fprintf(stderr, "signature %d: file and loader disagree on its name\n", i);
            return 2;
        }
        if (sig->deprecated) { printf("  %-56s deprecated, left as is\n", sig->name); continue; }
        if (load_image(sig->module) != 0) return strcmp(sig->module, NP_MODULE_DEFAULT) ? 2 : 3;
        const image_t *im = image_for(sig->module);

        if (sig->anchor.kind == NP_MATCH_VTABLE_SLOT || sig->anchor.kind == NP_MATCH_NONE) {
            printf("  %-56s NEEDS A PERSON: anchor kind cannot move to another build\n", sig->name);
            failed++;
            continue;
        }
        uintptr_t site = sig->anchor.kind == NP_MATCH_AOB
            ? fallback_site(im, sig, sig->aob_hex)
            : np_locate_anchor(im->mh, im->slide, im->text, im->text_sz, &sig->anchor);
        if (!site) {
            printf("  %-56s NEEDS A PERSON: the anchor does not resolve in this build\n", sig->name);
            failed++;
            continue;
        }
        unsigned long unslid = (unsigned long)(site - (uintptr_t)im->slide);
        char addr[32];
        snprintf(addr, sizeof(addr), "0x%lx", unslid);
        set_string(obj, "func_addr_this_build", addr);

        const char *verdict = "pattern kept";
        if (sig->anchor.kind != NP_MATCH_AOB
            && (!sig->aob_hex[0] || fallback_site(im, sig, sig->aob_hex) != site)) {
            // A new pattern from this build's bytes at the site, as short as stays unique.
            uintptr_t fn_start = 0, fn_end = 0;
            size_t room = im->text + im->text_sz - site;
            if (np_function_bounds(im->mh, im->slide, site, &fn_start, &fn_end) == 0 && fn_end > site)
                room = fn_end - site;
            char text[PATTERN_MAX * 3 + 1];
            int found = 0;
            for (int len = PATTERN_MIN; len <= PATTERN_MAX && (size_t)len <= room; len += 8) {
                pattern_text((const uint8_t *)site, len, text, sizeof(text));
                np_sig_entry_t probe = *sig;
                probe.match_offset = 0;
                if (fallback_site(im, &probe, text) == site) { found = len; break; }
            }
            if (!found) {
                printf("  %-56s NEEDS A PERSON: no unique pattern of %d..%d bytes at 0x%lx\n",
                       sig->name, PATTERN_MIN, PATTERN_MAX, unslid);
                failed++;
                continue;
            }
            set_string(obj, "aob_hex", text);
            cJSON_DeleteItemFromObject(obj, "match_offset");
            regenerated++;
            verdict = "new pattern";
        }
        printf("  %-56s 0x%-9lx %s\n", sig->name, unslid, verdict);
    }

    printf("\n%d signatures, %d new patterns, %d need a person\n", db.sig_count, regenerated, failed);
    if (failed) {
        printf("not written: %s\n", out_path);
        return 1;
    }
    cJSON_ReplaceItemInObject(doc, "steam_build", cJSON_CreateNumber((double)build));
    set_string(doc, "steam_build_date", "");
    char *json = cJSON_Print(doc);
    FILE *f = json ? fopen(out_path, "w") : NULL;
    if (!f || fputs(json, f) < 0 || fputc('\n', f) == EOF || fclose(f) != 0) {
        fprintf(stderr, "%s: cannot write\n", out_path);
        return 2;
    }
    printf("written: %s\n", out_path);
    free(json);
    cJSON_Delete(doc);
    np_free_profile(&db);
    return 0;
}
