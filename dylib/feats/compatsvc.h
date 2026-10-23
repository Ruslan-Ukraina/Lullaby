// CompatManager WebUI service.
#ifndef LULLABY_FEATS_COMPATSVC_H
#define LULLABY_FEATS_COMPATSVC_H

#include <stdint.h>
#include <stddef.h>
#include <mach-o/loader.h>

// Registers on first route lookup rather than at install time
void lb_compatsvc_register(const struct mach_header_64 *mh, intptr_t slide,
                           uintptr_t text_base, size_t text_size);

// Whether the CompatManager routes are answering. UNTRIED is a route lookup that has
// not happened yet, which is not the same as a client that cannot serve them: the
// compat chunk can be served before anything asks the transport for a route.
enum {
    LB_COMPATSVC_UNTRIED = 0,
    LB_COMPATSVC_READY,
    LB_COMPATSVC_ABSENT,
};
int lb_compatsvc_routes(void);

// Sentinel name for "no tool".
#define LB_COMPAT_TOOL_NONE "lullaby.none"

// Tells the page the mapping changed.
void lb_compatsvc_state_changed(void);

#endif // LULLABY_FEATS_COMPATSVC_H
