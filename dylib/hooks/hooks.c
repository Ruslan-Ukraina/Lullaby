// Hook registration and Dobby installation.

#include "hooks.h"
#include "../core/macho.h"
#include "../feats/webui.h"
#include "../feats/compat.h"
#include "../util/log.h"
#include <stdlib.h>
#include <string.h>

extern int DobbyHook(void *address, void *replace_call, void **origin_call);
typedef void (*lb_prehook_fn)(void *address, void *ctx);
extern int DobbyInstrument(void *address, lb_prehook_fn pre_handler);

int lb_hooks_env_lists_label(const char *var, const char *label) {
    const char *list = getenv(var);
    if (!list || !list[0] || !label)
        return 0;

    size_t label_len = strlen(label);
    while (*list) {
        const char *comma = strchr(list, ',');
        size_t field_len = comma ? (size_t)(comma - list) : strlen(list);
        if (field_len == label_len && memcmp(list, label, label_len) == 0)
            return 1;
        if (!comma)
            break;
        list = comma + 1;
    }
    return 0;
}

typedef struct {
    const char        *group;
    int              (*count)(void);
    lb_patch_entry_t *(*entries)(void);
} lb_hook_group_t;

// webpatch reaches the client through a dyld interpose table, not a resolved
// address, so it has no row here.
static const lb_hook_group_t lb_groups[] = {
    { "compat", lb_hooks_compat_count, lb_hooks_compat_defs },
    { "webui",  lb_hooks_webui_count,  lb_hooks_webui_defs  },
    { "launch", lb_hooks_launch_count, lb_hooks_launch_defs },
};

static const lb_hook_group_t lb_steamui_groups[] = {
    { "shortcut", lb_hooks_shortcut_count, lb_hooks_shortcut_defs },
    { "icon",     lb_hooks_icon_count,     lb_hooks_icon_defs     },
};

// Installs one entry. Returns 1 when the patch lands, 0 when it is skipped or fails.
static int lb_apply_entry(lb_resolve_result_t *resolved, const char *group,
                          lb_patch_entry_t *e) {
    if (lb_hooks_env_lists_label("LULLABY_DISABLE", e->label)) {
        LB_WARN("[%s] %s: DISABLED via LULLABY_DISABLE", group, e->label);
        return 0;
    }

    uintptr_t addr = e->address ? e->address
                   : e->signature ? lb_lookup_address(resolved, e->signature) : 0;
    if (!addr) {
        if (e->tolerate_missing)
            LB_DBG("[%s] %s: unresolved (optional)", group, e->label);
        else
            LB_WARN("[%s] %s: unresolved, cannot install", group, e->label);
        return 0;
    }

    int prehook = (e->mode == LB_PATCH_PREHOOK);
    int rc = prehook ? DobbyInstrument((void *)addr, (lb_prehook_fn)e->entry)
                     : DobbyHook((void *)addr, e->entry, e->trampoline);
    if (rc == 0) {
        LB_LOG("[%s] %s: %s @ %p", group, e->label,
               prehook ? "instrumented" : "hooked", (void *)addr);
        return 1;
    }

    // Dobby patches the target before reporting the error and never registers the
    // entry, so the patch cannot be lifted.
    LB_ERR("[%s] %s: %s failed (ret=%d) @ %p, target may stay patched with no original; "
           "the hook degrades instead of calling it",
           group, e->label, prehook ? "DobbyInstrument" : "DobbyHook", rc, (void *)addr);
    return 0;
}

static int install_groups(const lb_hook_group_t *groups, size_t n_groups,
                          lb_resolve_result_t *resolved, int *total_out) {
    int total  = 0;
    int landed = 0;

    for (size_t g = 0; g < n_groups; g++) {
        const lb_hook_group_t *group = &groups[g];
        lb_patch_entry_t *entries = group->entries();
        int n = group->count();
        for (int i = 0; i < n; i++) {
            total++;
            landed += lb_apply_entry(resolved, group->group, &entries[i]);
        }
    }

    if (total_out)
        *total_out = total;
    return landed;
}

int lb_hooks_install_steamui(const struct mach_header_64 *mh, intptr_t slide,
                             lb_resolve_result_t *resolved, int *total_out) {
    (void)mh;
    (void)slide;

    int total  = 0;
    int landed = install_groups(lb_steamui_groups,
                                sizeof(lb_steamui_groups) / sizeof(lb_steamui_groups[0]),
                                resolved, &total);

    if (total_out)
        *total_out = total;
    LB_LOG("hooks: steamui %d/%d installed", landed, total);
    return landed;
}

int lb_hooks_install_all(const struct mach_header_64 *mh, intptr_t slide,
                         lb_resolve_result_t *resolved, int *total_out) {
    lb_hooks_compat_set_helpers(
        lb_lookup_address(resolved, "CCompatManager::YldRegisterTool"),
        lb_lookup_address(resolved, "CCompatManager::GetValidPlatforms"),
        lb_lookup_address(resolved, "CCompatManager::FindToolForTargetApp"),
        lb_lookup_address(resolved, "CCompatManager::SetCompatToolMapping"),
        lb_lookup_address(resolved, "CCompatManager::FindMapping"),
        lb_lookup_address(resolved, "CCompatManager::GetWildcardMapping"));

    lb_compat_probe_tool_layout(
        lb_lookup_address(resolved, "CCompatManager::ResolveCompatToolForApp.local_redirect"),
        lb_lookup_address(resolved, "CCompatManager::GetOSListOverrideForApp.oslist_gate"));
    lb_compat_probe_enabled_off(
        lb_lookup_address(resolved, "CCompatManager::BIsCompatibilityToolEnabled"));

    uintptr_t register_fn = lb_lookup_address(resolved,
                                             "CWebUIJobDispatcher::RegisterHandler");
    uintptr_t dispatch_fn = lb_lookup_address(resolved, "CWebUITransport::DispatchJob");

    lb_webui_init(mh, slide, register_fn, dispatch_fn,
                  lb_lookup_address(resolved, "CWebUIMsgJob::SendResponse"));
    lb_webui_dump_routes();
    lb_hooks_webui_bind(mh, slide, register_fn, dispatch_fn);

    int total  = 0;
    int landed = install_groups(lb_groups, sizeof(lb_groups) / sizeof(lb_groups[0]),
                                resolved, &total);

    lb_hooks_compat_publish_originals();

    if (total_out)
        *total_out = total;
    LB_LOG("hooks: %d/%d installed", landed, total);
    return landed;
}
