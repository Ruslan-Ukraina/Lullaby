// Dylib entry point into steamclient.dylib
#include "../version.h"
#include "../util/log.h"
#include "../util/file.h"
#include "../resolver/resolver.h"
#include "../resolver/sigdb.h"
#include "../core/macho.h"
#include "../hooks/hooks.h"
#include "../feats/compat.h"
#include "../feats/input_access.h"
#include "../feats/steamwin.h"
#include "../feats/steamfocus.h"
#include "../feats/updategate.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <stdint.h>
#include <dirent.h>
#include <mach-o/dyld.h>
#include <libgen.h>

#define STEAMCLIENT_DYLIB "steamclient.dylib"
#define STEAMUI_DYLIB     "steamui.dylib"

// The bootstrapper can take a while before the real client dylib appears...
#define WAIT_TIMEOUT_MS 60000

static void drop_marker_file(const char *dir, const char *name) {
    char path[1024];
    int len = snprintf(path, sizeof(path), "%s/%s", dir, name);
    if (len < 0 || len >= (int)sizeof(path))
        return;
    if (unlink(path) == 0)
        LB_LOG("removed marker %s", path);
}

// A leftover 'marker' makes the client redownload and rewrite Info.plist, which is bad.
static void clear_relaunch_markers(void) {
    char exe[1024];
    uint32_t cap = sizeof(exe);
    if (_NSGetExecutablePath(exe, &cap) != 0) {
        LB_WARN("could not read own executable path");
        return;
    }

    char scratch[1024];
    snprintf(scratch, sizeof(scratch), "%s", exe);
    const char *dir = dirname(scratch);

    drop_marker_file(dir, ".crash");
    drop_marker_file(dir, ".forceupdate");
}

// The databases to try, newest first: LULLABY_SIG alone when set.
static int sigdb_candidates(char (*paths)[LB_SIGDB_PATH_MAX], int max) {
    const char *env = getenv("LULLABY_SIG");
    if (env && env[0]) {
        snprintf(paths[0], LB_SIGDB_PATH_MAX, "%s", env);
        return 1;
    }

    const char *home = lb_home_dir();
    if (!home) return 0;

    char dir[512];
    lb_support_path(dir, sizeof(dir), home, "signatures/macos.arm64");
    int n = lb_sigdb_candidates(dir, paths, max);
    if (n <= 0) LB_ERR("install_thread: no signature database in %s", dir);
    return n < 0 ? 0 : n;
}

static pthread_t g_install;
static int       g_install_started;
static int       g_active;

static void install_steamui(lb_sigdb_t *sigdb) {
    int required = lb_required_for_module(sigdb, STEAMUI_DYLIB);
    if (required == 0) {
        LB_DBG("install_thread: no %s signatures in this database", STEAMUI_DYLIB);
        return;
    }

    const struct mach_header_64 *mh = NULL;
    intptr_t slide = 0;

    if (lb_await_image(STEAMUI_DYLIB, WAIT_TIMEOUT_MS, &mh, &slide, NULL, 0) != 0) {
        LB_WARN("install_thread: %s absent after %d ms, its hooks stay off",
                STEAMUI_DYLIB, WAIT_TIMEOUT_MS);
        return;
    }

    lb_resolve_result_t resolved = {0};
    int count = lb_resolve_signatures(mh, slide, sigdb, STEAMUI_DYLIB, &resolved);
    LB_LOG("install_thread: %s signatures %d/%d resolved", STEAMUI_DYLIB, count, required);

    if (count < required)
        LB_WARN("install_thread: %s %d/%d signatures resolved; the hooks that did "
                "resolve still install, the rest stay off", STEAMUI_DYLIB, count,
                required);

    int total = 0;
    int installed = lb_hooks_install_steamui(mh, slide, &resolved, &total);

    LB_LOG("install_thread: %s ready, %d/%d hooks installed",
           STEAMUI_DYLIB, installed, total);

    lb_free_resolution(&resolved);
}

static void *install_thread(void *unused) {
    (void)unused;

    LB_LOG("install_thread: waiting for %s", STEAMCLIENT_DYLIB);

    const struct mach_header_64 *mh = NULL;
    intptr_t slide = 0;

    if (lb_await_image(STEAMCLIENT_DYLIB, WAIT_TIMEOUT_MS, &mh, &slide,
                             NULL, 0) != 0) {
        // The Steam bootstraper does this
        LB_LOG("install_thread: %s absent after %d ms, hooks will install in the "
               "relaunched client", STEAMCLIENT_DYLIB, WAIT_TIMEOUT_MS);
        return NULL;
    }

    uintptr_t text_base = 0;
    size_t text_size = 0;

    if (lb_find_segment(mh, slide, "__TEXT", &text_base, &text_size) != 0) {
        LB_ERR("install_thread: no __TEXT segment in %s", STEAMCLIENT_DYLIB);
        return NULL;
    }

    LB_LOG("install_thread: %s __TEXT @ 0x%lx (%zu bytes) slide=0x%lx",
           STEAMCLIENT_DYLIB, (unsigned long)text_base, text_size,
           (unsigned long)slide);

    // The client is up, so the bootstrapper's update check is over: Steam's update
    // block goes back if Lullaby's gate is on (feats/updategate.c).
    lb_update_gate_rearm();
    lb_input_access_check();

    static char candidates[LB_SIGDB_MAX_CANDIDATES][LB_SIGDB_PATH_MAX];
    int candidate_count = sigdb_candidates(candidates, LB_SIGDB_MAX_CANDIDATES);

    lb_sigdb_t sigdb = {0};
    lb_resolve_result_t resolved = {0};
    int chosen = 0;

    // Newest first; a database for a newer Steam that does not fit this build is
    // passed over for the next one. Safety feature :) nothing installs unless
    // every signature of one database resolves.
    for (int i = 0; i < candidate_count && !chosen; i++) {
        if (lb_load_profile(candidates[i], &sigdb) != 0) {
            LB_ERR("install_thread: cannot load signature database from %s", candidates[i]);
            continue;
        }
        int resolved_count = lb_resolve_signatures(mh, slide, &sigdb, STEAMCLIENT_DYLIB,
                                                   &resolved);
        int required = lb_required_for_module(&sigdb, STEAMCLIENT_DYLIB);
        LB_LOG("install_thread: signatures %d/%d resolved with %s", resolved_count,
               required, candidates[i]);
        if (resolved_count >= required) {
            chosen = 1;
            break;
        }
        LB_WARN("install_thread: %s does not fit this Steam build (%d/%d), trying an older one",
                candidates[i], resolved_count, required);
        lb_free_resolution(&resolved);
        lb_free_profile(&sigdb);
    }

    if (!chosen) {
        LB_ERR("install_thread: none of %d signature database(s) resolves every signature, "
               "installing nothing; the signature database is out of date for this Steam build",
               candidate_count);
        return NULL;
    }

    // Registers compatibility tool.
    lb_compat_ensure_tool_manifest();

    // Launch options through a shell (hook_launch.c). Its one signature-backed hook, the
    // backslash fix, needs the database that just fitted, so it comes after the check.
    lb_hooks_launch_install(mh, slide);

    int total = 0;
    int installed = lb_hooks_install_all(mh, slide, &resolved, &total);

    LB_LOG("install_thread: ready, %d/%d hooks installed", installed, total);

    if (installed == 0)
        LB_WARN("install_thread: no hooks installed, check the signature database");
    else if (installed < total)
        LB_WARN("install_thread: only %d of %d hooks installed, compat support is "
                "incomplete for this client build", installed, total);

    lb_free_resolution(&resolved);

    install_steamui(&sigdb);

    lb_free_profile(&sigdb);

    return NULL;
}

static void lb_log_platform_overrides(void) {
    static const char *const vars[] = {
        "SteamOverridePlatform",
        "SteamPlatform",
        "STEAM_FORCE_OS",
        "STEAMOS",
        "SteamOS",
        "SteamOverrideOSType",
        "STEAM_COMPAT_FORCE_PLATFORM",
    };

    int found = 0;
    for (size_t i = 0; i < sizeof(vars) / sizeof(vars[0]); i++) {
        const char *val = getenv(vars[i]);
        if (val) {
            LB_LOG("lb_init: platform override present %s=%s", vars[i], val);
            found = 1;
        }
    }
    if (!found)
        LB_LOG("lb_init: no platform override env set, client reports as macOS");
}

__attribute__((constructor))
static void lb_init(int argc, const char **argv) {
    // Steam's windows live in Steam Helper's browser process, not in steam_osx.
    if (lb_steamwin_is_browser_process(argc, argv)) {
        // The main Steam Helper (no --type=) also runs tools such as /usr/bin/profiles and
        // opens apps: they start without the insert (hook_spawn.c).
        lb_log_attach();
        lb_hooks_spawn_install();
        lb_steamwin_start();
        lb_steamfocus_start("helper", 1);
        return;
    }

    const char *pn = getprogname();
    if (!pn || strcmp(pn, "steam_osx") != 0)
        return;

    lb_log_init();
    g_active = 1;

    clear_relaunch_markers();

    LB_LOG("lb_init: loaded into %s (pid %d) version %s",
           pn, getpid(), LULLABY_VERSION);

    lb_log_platform_overrides();
    lb_steamfocus_start("osx", 0);
    lb_compat_export_tools_path();
    lb_hooks_spawn_install();

    if (pthread_create(&g_install, NULL, install_thread, NULL) == 0)
        g_install_started = 1;
    else
        LB_ERR("lb_init: cannot create loader thread");
}

__attribute__((destructor))
static void lb_fini(void) {
    if (!g_active)
        return;

    if (g_install_started) {
        lb_await_stop();
        pthread_join(g_install, NULL);
    }

    LB_LOG("lb_fini: unloading, hooks left in place for the OS to reclaim");
}
