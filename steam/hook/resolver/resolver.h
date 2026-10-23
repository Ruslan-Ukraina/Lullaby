// Signature resolver
#ifndef LULLABY_RESOLVER_RESOLVER_H
#define LULLABY_RESOLVER_RESOLVER_H

#include <stdint.h>
#include <stddef.h>
#include <mach-o/loader.h>
#include "sigdb.h"

typedef struct {
    const char *name;
    uintptr_t   site;
} lb_resolved_t;

typedef struct {
    lb_resolved_t *items;
    int            used;
    int            cap;
} lb_resolve_result_t;

// True when the 32-bit value at `addr` looks like a common AArch64 prologue.
int lb_looks_like_prologue(uintptr_t addr);

uintptr_t lb_aob_site(const lb_sig_entry_t *sig, uintptr_t text, size_t text_sz);

// Resolve the signatures in `sigdb` that name `module` against the live image at
// `mh`+`slide`. Entries belonging to another image are left out of `out`.
int lb_resolve_signatures(const struct mach_header_64 *mh, intptr_t slide,
                      lb_sigdb_t *sigdb, const char *module,
                      lb_resolve_result_t *out);

int lb_required_for_module(const lb_sigdb_t *sigdb, const char *module);

uintptr_t lb_lookup_address(const lb_resolve_result_t *result, const char *name);
void      lb_free_resolution(lb_resolve_result_t *result);

#endif // LULLABY_RESOLVER_RESOLVER_H
