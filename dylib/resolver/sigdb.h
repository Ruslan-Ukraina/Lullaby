// Signature database loader
#ifndef LULLABY_RESOLVER_SIGDB_H
#define LULLABY_RESOLVER_SIGDB_H

#include <stdint.h>
#include <stddef.h>
#include "anchor.h"

#define LB_MODULE_DEFAULT "steamclient.dylib"

typedef struct {
    char        name[128];
    char        module[64];
    char        aob_hex[4096];
    uintptr_t   func_addr_this_build;
    int         deprecated;
    int32_t     match_offset;   // site = hit - match_offset; the site is not always an entry
    lb_anchor_t anchor;
} lb_sig_entry_t;

// A loaded signature database targeting a specific Steam client build.
typedef struct {
    lb_sig_entry_t *signatures;
    int             sig_count;
    int             schema_version;
    int             sigdb_version;
    uint64_t        steam_build;
    char            steam_build_date[32];
} lb_sigdb_t;

#define LB_SIGDB_MAX_CANDIDATES 32
#define LB_SIGDB_PATH_MAX       512

// Database files in `dir` named <build>.json, newest build first. Returns how many
// went into `paths` (at most `max`), or -1 when `dir` cannot be read.
int  lb_sigdb_candidates(const char *dir, char (*paths)[LB_SIGDB_PATH_MAX], int max);

int  lb_load_profile(const char *path, lb_sigdb_t *out);
void lb_free_profile(lb_sigdb_t *p);

#endif // LULLABY_RESOLVER_SIGDB_H
