// Strips DYLD_INSERT_LIBRARIES and the SDL block list from child processes
#include "hooks.h"
#include "../util/log.h"

#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int   DobbyHook(void *address, void *replace_call, void **origin_call);
extern void *DobbySymbolResolver(const char *image_name, const char *symbol_name);

typedef int (*fn_execve)(const char *path, char *const argv[], char *const envp[]);
typedef int (*fn_posix_spawn)(pid_t *pid, const char *path,
                             const posix_spawn_file_actions_t *fa,
                             const posix_spawnattr_t *attr,
                             char *const argv[], char *const envp[]);

static fn_execve      orig_execve;
static fn_posix_spawn orig_posix_spawn;
static fn_posix_spawn orig_posix_spawnp;

// The SDL block list stops Steam from seeing a second, generic copy of the Steam Controller,
// which solves double input (upstream NotProton 1.1.x, "Fixes Steam Input issues"). It is
// Steam's alone, like the insert: SteamBundle puts both in Steam's LSEnvironment.
#define LB_INSERT_KEY "DYLD_INSERT_LIBRARIES="

static const char *const lb_steam_only_keys[] = {
    LB_INSERT_KEY,
    "SDL_JOYSTICK_BLACKLIST_DEVICES=",
};

static int lb_is_steam_only(const char *entry) {
    for (size_t k = 0; k < sizeof(lb_steam_only_keys) / sizeof(lb_steam_only_keys[0]); k++) {
        if (strncmp(entry, lb_steam_only_keys[k], strlen(lb_steam_only_keys[k])) == 0)
            return 1;
    }
    return 0;
}

// steam_osx re-execs itself and needs the insert for hooks. Steam Helper runs
// CEF and needs it for the webpatch fopen interpose, strips elsewhere
static int lb_target_keeps_insert(const char *path) {
    if (!path)
        return 1;
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    return strcmp(base, "steam_osx") == 0
        || strcmp(base, "Steam Helper") == 0;
}

// LaunchServices hands the caller's environment to every app it opens (and Steam Helper
// runs /usr/bin/profiles, which crashes on the insert with SIP off), so once the hooks are
// in, the insert lives here instead and goes back only into steam_osx and Steam Helper
// (upstream NotProton 1.1.4, "Prevent NotProton from being passed along to tools launched
// by Steam Helper").
static char *lb_insert_entry;

static int lb_is_insert(const char *entry) {
    return strncmp(entry, LB_INSERT_KEY, strlen(LB_INSERT_KEY)) == 0;
}

static char **lb_with_insert(char *const envp[]) {
    if (!lb_insert_entry)
        return NULL;

    int count = 0;
    if (envp) {
        for (; envp[count]; count++) {
            if (lb_is_insert(envp[count]))
                return NULL;
        }
    }

    char **full = malloc(sizeof(char *) * (size_t)(count + 2));
    if (!full) {
        LB_WARN("[spawn] cannot allocate an environment with the insert, child starts without it");
        return NULL;
    }
    for (int i = 0; i < count; i++)
        full[i] = envp[i];
    full[count] = lb_insert_entry;
    full[count + 1] = NULL;
    return full;
}

static void lb_take_insert(void) {
    const char *value = getenv("DYLD_INSERT_LIBRARIES");
    if (!value || lb_insert_entry)
        return;

    size_t len = strlen(LB_INSERT_KEY) + strlen(value) + 1;
    lb_insert_entry = malloc(len);
    if (!lb_insert_entry) {
        LB_WARN("[spawn] cannot hold the insert, apps opened from here inherit it");
        return;
    }
    snprintf(lb_insert_entry, len, "%s%s", LB_INSERT_KEY, value);
    unsetenv("DYLD_INSERT_LIBRARIES");
    LB_LOG("[spawn] insert taken out of the environment");
}

static char **lb_without_insert(char *const envp[]) {
    if (!envp)
        return NULL;

    int count = 0;
    int found = 0;
    for (int i = 0; envp[i]; i++) {
        if (lb_is_steam_only(envp[i]))
            found = 1;
        count++;
    }
    if (!found)
        return NULL;

    char **clean = malloc(sizeof(char *) * (size_t)(count + 1));
    if (!clean) {
        LB_WARN("[spawn] cannot allocate a stripped environment, insert passed through");
        return NULL;
    }

    int j = 0;
    for (int i = 0; envp[i]; i++) {
        if (!lb_is_steam_only(envp[i]))
            clean[j++] = envp[i];
    }
    clean[j] = NULL;
    return clean;
}

static int lb_hook_execve(const char *path, char *const argv[], char *const envp[]) {
    int keep = lb_target_keeps_insert(path);
    char **clean = keep ? lb_with_insert(envp) : lb_without_insert(envp);
    if (!clean)
        return orig_execve(path, argv, envp);

    LB_DBG("[spawn] execve '%s' %s the insert", path, keep ? "with" : "without");
    int rc = orig_execve(path, argv, (char *const *)clean);
    // Only reached when the exec failed, since a successful one replaced this image.
    free(clean);
    return rc;
}

static int lb_spawn_without_insert(fn_posix_spawn orig, const char *api,
                                   pid_t *pid, const char *path,
                                   const posix_spawn_file_actions_t *fa,
                                   const posix_spawnattr_t *attr,
                                   char *const argv[], char *const envp[]) {
    int keep = lb_target_keeps_insert(path);
    char **clean = keep ? lb_with_insert(envp) : lb_without_insert(envp);
    if (!clean)
        return orig(pid, path, fa, attr, argv, envp);

    LB_DBG("[spawn] %s '%s' %s the insert", api, path, keep ? "with" : "without");
    int rc = orig(pid, path, fa, attr, argv, (char *const *)clean);
    free(clean);
    return rc;
}

static int lb_hook_posix_spawn(pid_t *pid, const char *path,
                               const posix_spawn_file_actions_t *fa,
                               const posix_spawnattr_t *attr,
                               char *const argv[], char *const envp[]) {
    return lb_spawn_without_insert(orig_posix_spawn, "posix_spawn",
                                   pid, path, fa, attr, argv, envp);
}

static int lb_hook_posix_spawnp(pid_t *pid, const char *path,
                                const posix_spawn_file_actions_t *fa,
                                const posix_spawnattr_t *attr,
                                char *const argv[], char *const envp[]) {
    return lb_spawn_without_insert(orig_posix_spawnp, "posix_spawnp",
                                   pid, path, fa, attr, argv, envp);
}

static int lb_hook_symbol(const char *sym, void *repl, void **orig) {
    void *addr = DobbySymbolResolver("libsystem_kernel.dylib", sym);
    if (!addr)
        addr = DobbySymbolResolver(NULL, sym);
    if (!addr) {
        LB_WARN("[spawn] %s: unresolved, children keep the insert", sym);
        return 0;
    }

    int rc = DobbyHook(addr, repl, orig);
    if (rc == 0) {
        LB_LOG("[spawn] %s: hooked @ %p", sym, addr);
        return 1;
    }
    LB_WARN("[spawn] %s: DobbyHook failed rc=%d, children keep the insert", sym, rc);
    return 0;
}

void lb_hooks_spawn_install(void) {
    if (lb_hooks_env_lists_label("LULLABY_DISABLE", "spawn")) {
        LB_WARN("[spawn] DISABLED via LULLABY_DISABLE, children keep the insert");
        return;
    }

    int hooked = lb_hook_symbol("execve",       (void *)lb_hook_execve,       (void **)&orig_execve)
               + lb_hook_symbol("posix_spawn",  (void *)lb_hook_posix_spawn,  (void **)&orig_posix_spawn)
               + lb_hook_symbol("posix_spawnp", (void *)lb_hook_posix_spawnp, (void **)&orig_posix_spawnp);

    // Without every hook in place, a steam_osx re-exec could start without the dylib.
    if (hooked == 3)
        lb_take_insert();
}
