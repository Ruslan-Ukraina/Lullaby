// Makes Steam Play Launch Options function the way they do on Linux.
//
// From upstream NotProton 1.1.0 (e9f97f7, e7758ba; GPL-3.0, same project). NotProton's own
// addition: the shell first records the names of the variables it was handed in
// NOTPROTON_ENV_BASE, so compat_run.sh can tell the ones the player's launch options set
// (NAME=value ahead of %command%) and hand them to the game, which starts through
// LaunchServices with an environment of its own (Amendment 09.10, docs/ROADMAP.md §13).
#include "hooks.h"
#include "../core/macho.h"
#include "../feats/compat.h"
#include "../util/log.h"

#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define NP_PARSE_SYM_POSIX \
    "_Z28V_ParseShellCommandLinePOSIXPKcR10CUtlVectorI10CUtlString10CUtlMemoryIS2_EEiPS0_"

typedef int (*fn_parse_shell)(const char *cmd, void *argv, int max, const char **rest);

static fn_parse_shell orig_parse_shell;
static int            np_shell_wrapped;

static size_t np_quote(char *out, const char *s) {
    size_t n = 0;

    out[n++] = '\'';
    for (; *s; s++) {
        if (*s == '\'') {
            memcpy(out + n, "'\\''", 4);
            n += 4;
        } else {
            out[n++] = *s;
        }
    }
    out[n++] = '\'';
    return n;
}

// Ahead of the command line in /bin/sh: the names of the variables the shell was handed.
#define NP_ENV_BASE "export NOTPROTON_ENV_BASE=\" $(env | cut -d= -f1 | tr '\\n' ' ')\"; "

// Shell, followed by the command line as one argument. A shell of the player's own
// (STEAM_GAME_LAUNCH_SHELL) gets the command line alone, as upstream hands it.
static char *np_launch_shell(const char *cmd, const char *shell, int max, const char **rest) {
    // np_hook_parse_shell frees the wrapped copy before its caller reads *rest.
    if (!cmd || max != -1 || rest || !np_compat_runs_tool(cmd))
        return NULL;

    const char *lead = shell ? "" : "/bin/sh -c ";
    const char *base = shell ? "" : NP_ENV_BASE;
    size_t      cmd_len = strlen(base) + strlen(cmd);
    char       *line = malloc(cmd_len + 1);
    size_t      cap  = strlen(lead) + 4 * cmd_len + 3
                     + (shell ? 4 * strlen(shell) + 3 : 0) + 1;
    char       *out  = malloc(cap);
    size_t      n    = strlen(lead);

    if (!out || !line) {
        free(out);
        free(line);
        return NULL;
    }
    memcpy(line, base, strlen(base));
    memcpy(line + strlen(base), cmd, strlen(cmd) + 1);

    memcpy(out, lead, n);
    if (shell) {
        n += np_quote(out + n, shell);
        out[n++] = ' ';
    }
    n += np_quote(out + n, line);
    out[n] = 0;
    free(line);
    return out;
}

static int np_hook_parse_shell(const char *cmd, void *argv, int max, const char **rest) {
    const char *shell   = getenv("STEAM_GAME_LAUNCH_SHELL");
    char       *wrapped = np_launch_shell(cmd, shell, max, rest);

    if (wrapped)
        NP_LOG("[launch] handed to %s: %s", shell ? shell : "/bin/sh -c", cmd);

    int rc = orig_parse_shell(wrapped ? wrapped : cmd, argv, max, rest);
    free(wrapped);
    return rc;
}

// Doubles every backslash in place. Enlarge the buffer before calling this.
static void np_double_backslashes(char *s, size_t len, size_t extra) {
    char *out = s + len + extra;

    *out = 0;
    while (len) {
        char c = s[--len];
        *--out = c;
        if (c == '\\')
            *--out = c;
    }
}

static size_t np_count_backslashes(const char *s) {
    size_t n = 0;

    for (; *s; s++)
        n += *s == '\\';
    return n;
}

typedef void *(*fn_plat_realloc)(void *p, size_t size);
typedef uint64_t (*fn_vr_support)(void *self, uint32_t appid, char **arguments);

static void           *orig_vr_support;
static fn_plat_realloc plat_realloc;

// Hooked to fix games that have backslashes in their Steam launch config, not for VR.
// Linux Steam doubles backslashes in game arguments right after this VR check, and macOS
// Steam does not.
static uint64_t np_hook_vr_support(void *self, uint32_t appid, char **arguments) {
    fn_vr_support orig = (fn_vr_support)orig_vr_support;

    if (!orig) {
        NP_ERR("[launch] SteamVRSupport check: no original, app %u keeps its arguments", appid);
        return 0;
    }
    uint64_t ret = orig(self, appid, arguments);

    if (!np_shell_wrapped || !arguments || !*arguments || !np_compat_app_runs_tool(appid))
        return ret;
    size_t extra = np_count_backslashes(*arguments);
    if (!extra)
        return ret;

    size_t len = strlen(*arguments);
    char  *buf = plat_realloc ? plat_realloc(*arguments, len + extra + 1) : NULL;
    if (!buf)
        return ret;
    np_double_backslashes(buf, len, extra);
    *arguments = buf;
    NP_LOG("[launch] app %u arguments: %s", appid, buf);
    return ret;
}

static np_patch_entry_t g_hooks[] = {
    {
        .label      = "LaunchBuilder::SteamVRSupportCheck",
        .signature  = "LaunchBuilder::SteamVRSupportCheck",
        .entry      = (void *)np_hook_vr_support,
        .trampoline = &orig_vr_support,
    },
};

int np_hooks_launch_count(void) {
    return np_shell_wrapped ? (int)(sizeof(g_hooks) / sizeof(g_hooks[0])) : 0;
}

np_patch_entry_t *np_hooks_launch_defs(void) {
    return g_hooks;
}

void np_hooks_launch_install(const struct mach_header_64 *mh, intptr_t slide) {
    if (np_hooks_env_lists_label("NOTPROTON_DISABLE", "launch")) {
        NP_WARN("[launch] DISABLED via NOTPROTON_DISABLE, launches keep running "
                "without a shell");
        return;
    }

    // dlsym takes the name without the leading underscore the symbol table carries.
    orig_parse_shell = (fn_parse_shell)dlsym(RTLD_DEFAULT, NP_PARSE_SYM_POSIX);
    if (!orig_parse_shell) {
        NP_WARN("[launch] V_ParseShellCommandLinePOSIX: unresolved, launches keep "
                "running without a shell");
        return;
    }

    int rebound = np_rebind_import(mh, slide, "_" NP_PARSE_SYM_POSIX,
                                   (void *)np_hook_parse_shell);
    np_shell_wrapped = rebound > 0;
    if (rebound > 0)
        NP_LOG("[launch] V_ParseShellCommandLinePOSIX: %d import slot(s) rebound", rebound);
    else
        NP_WARN("[launch] V_ParseShellCommandLinePOSIX: no import slot in steamclient "
                "(rc=%d), launches keep running without a shell", rebound);

    // Steam frees this string itself, so it has to be grown with Steam's allocator as a
    // plain realloc would crash.
    plat_realloc = (fn_plat_realloc)dlsym(RTLD_DEFAULT, "Plat_Realloc");
    if (!plat_realloc)
        NP_WARN("[launch] Plat_Realloc: unresolved, unquoted backslashes in app "
                "arguments are lost");
}
