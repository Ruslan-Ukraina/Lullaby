// Hook definitions, Dobby installation, and shared hook infrastructure.
#ifndef LULLABY_HOOKS_HOOKS_H
#define LULLABY_HOOKS_HOOKS_H

#include <stdint.h>
#include <stddef.h>
#include "../resolver/resolver.h"

typedef enum {
    LB_PATCH_REPLACE = 0,   // swap in a replacement, keep the original callable
    LB_PATCH_PREHOOK = 1,   // run before the target, may rewrite registers
} lb_patch_mode_t;

// Register state a prehook is handed, in Dobby's layout.
typedef struct { uint64_t _d0, sp, _d1; struct { uint64_t x[29]; } general; } lb_arm64_ctx_t;

typedef struct {
    const char      *label;
    const char      *signature;
    // Target for a hook that lands somewhere a signature cannot name, such as an
    // instruction inside a function.
    uintptr_t        address;
    void            *entry;
    void           **trampoline;
    lb_patch_mode_t  mode;
    int              tolerate_missing;   // when set, an unresolved signature only logs at debug
} lb_patch_entry_t;

int               lb_hooks_compat_count(void);
lb_patch_entry_t *lb_hooks_compat_defs(void);

void lb_hooks_compat_publish_originals(void);

void lb_hooks_compat_set_helpers(uintptr_t yld_register_tool,
                                 uintptr_t get_valid_platforms,
                                 uintptr_t find_tool_for_target_app,
                                 uintptr_t set_compat_tool_mapping,
                                 uintptr_t find_mapping,
                                 uintptr_t get_wildcard_mapping);

int               lb_hooks_webui_count(void);
lb_patch_entry_t *lb_hooks_webui_defs(void);

void lb_hooks_webui_bind(const struct mach_header_64 *mh, intptr_t slide,
                         uintptr_t register_fn, uintptr_t dispatch_fn);

int               lb_hooks_launch_count(void);
lb_patch_entry_t *lb_hooks_launch_defs(void);

int               lb_hooks_shortcut_count(void);
lb_patch_entry_t *lb_hooks_shortcut_defs(void);

int               lb_hooks_icon_count(void);
lb_patch_entry_t *lb_hooks_icon_defs(void);

int lb_hooks_install_all(const struct mach_header_64 *mh, intptr_t slide,
                         lb_resolve_result_t *resolved, int *total_out);

int lb_hooks_install_steamui(const struct mach_header_64 *mh, intptr_t slide,
                             lb_resolve_result_t *resolved, int *total_out);

// True when `label` is one entry of the comma-separated value of env var `var`.
// LULLABY_DISABLE uses this to skip named hooks.
int lb_hooks_env_lists_label(const char *var, const char *label);

// Resolved from libc rather than the signature database, and installed before the client
// can spawn anything, so this one does not wait for steamclient the way the rest do.
void lb_hooks_spawn_install(void);

// Launch options through a shell, as on Linux (hook_launch.c). Rebinds an import rather
// than an address, so it does not wait on the signature database.
void lb_hooks_launch_install(const struct mach_header_64 *mh, intptr_t slide);

#endif // LULLABY_HOOKS_HOOKS_H
