// Phase 5 pieces of the dylib, without Steam:
//   - np_update_gate_rearm_paths writes Steam's update block back the way the app's
//     UpdateBlock does, only when lullaby/steam-update-gate says auto or manual;
//   - np_sigdb_candidates lists <build>.json databases newest first, so the loader
//     falls back to an older one when the newest does not fit the installed Steam.
// Usage: out/updategate-check

#include "feats/updategate.h"
#include "resolver/sigdb.h"
#include "util/log.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int   np_log_level = NP_LVL_WARN;
FILE *np_log_file;

static int g_failed;
static char g_dir[512];

static void fail(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fputs("FAIL: ", stdout);
    vprintf(fmt, ap);
    fputc('\n', stdout);
    va_end(ap);
    g_failed = 1;
}

static void put(const char *name, const char *text) {
    char path[600];
    snprintf(path, sizeof(path), "%s/%s", g_dir, name);
    FILE *f = fopen(path, "wb");
    if (!f) { fail("cannot write %s", path); return; }
    fputs(text, f);
    fclose(f);
}

static char *get(const char *name) {
    char path[600];
    snprintf(path, sizeof(path), "%s/%s", g_dir, name);
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    static char buf[4096];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    buf[n] = '\0';
    fclose(f);
    return buf;
}

static void expect_file(const char *name, const char *want, const char *what) {
    const char *got = get(name);
    if (!got && !want) return;
    if (!got || !want || strcmp(got, want) != 0)
        fail("%s: %s is \"%s\", expected \"%s\"", what, name, got ? got : "(missing)", want ? want : "(missing)");
}

static int rearm(void) {
    char gate[600], outer[600], inner[600];
    snprintf(gate, sizeof(gate), "%s/steam-update-gate", g_dir);
    snprintf(outer, sizeof(outer), "%s/steam.cfg", g_dir);
    snprintf(inner, sizeof(inner), "%s/inner/steam.cfg", g_dir);
    const char *cfgs[] = {outer, inner};
    return np_update_gate_rearm_paths(gate, cfgs, 2);
}

#define BLOCK "BootStrapperInhibitUpdateOnLaunch=enable"

static void gate_cases(void) {
    // No gate file: an install from before Phase 5 is left alone.
    unlink(strcat(strcpy((char[600]){0}, g_dir), "/steam-update-gate"));
    if (rearm() != -1) fail("no gate file: expected nothing to do");
    expect_file("steam.cfg", NULL, "no gate file");

    put("steam-update-gate", "nonsense\n");
    if (rearm() != -1) fail("unknown mode: expected nothing to do");

    // auto: the required file is created; the inner one only where its folder exists.
    put("steam-update-gate", "auto\n");
    if (rearm() != 1) fail("auto, nothing there: expected one file written");
    expect_file("steam.cfg", BLOCK "\n", "auto, nothing there");
    expect_file("inner/steam.cfg", NULL, "inner folder missing");

    char inner[600];
    snprintf(inner, sizeof(inner), "%s/inner", g_dir);
    mkdir(inner, 0755);
    if (rearm() != 1) fail("auto, inner folder now there: expected one more file");
    expect_file("inner/steam.cfg", BLOCK "\n", "inner folder present");

    // Already blocked: nothing rewritten.
    if (rearm() != 0) fail("already blocked: expected no writes");

    // Other lines stay; a lifted block (line removed by the app) comes back at the end.
    put("steam.cfg", "Foo=1\nBar=2");
    if (rearm() != 1) fail("lifted block: expected one write");
    expect_file("steam.cfg", "Foo=1\nBar=2\n" BLOCK "\n", "lifted block");

    // A disabled value and duplicates collapse into one enable at the first one's place.
    put("steam.cfg", "A=1\n BootStrapperInhibitUpdateOnLaunch = disable \nB=2\n"
                     "BootStrapperInhibitUpdateOnLaunch=enable\n");
    // The last value wins, as in UpdateBlock.isPresent: enable here, so no write.
    if (rearm() != 0) fail("last value enable: expected no write");
    put("steam.cfg", "A=1\nBootStrapperInhibitUpdateOnLaunch=enable\nB=2\n"
                     "BootStrapperInhibitUpdateOnLaunch=disable\n");
    if (rearm() != 1) fail("last value disable: expected a write");
    expect_file("steam.cfg", "A=1\n" BLOCK "\nB=2\n", "last value disable");

    // manual counts as on as well.
    put("steam-update-gate", "manual");
    put("steam.cfg", "");
    if (rearm() != 1) fail("manual, empty file: expected a write");
    expect_file("steam.cfg", BLOCK "\n", "manual, empty file");
}

static void candidate_cases(void) {
    char dir[600];
    snprintf(dir, sizeof(dir), "%s/sigs", g_dir);
    mkdir(dir, 0755);
    const char *names[] = {"1788400362.json", "1790904859.json", "1789086785.json", "notes.json",
                           "0123.json", "1790904859.json.sig", "17x.json"};
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        char path[700];
        snprintf(path, sizeof(path), "%s/%s", dir, names[i]);
        FILE *f = fopen(path, "w");
        if (f) { fputs("{}", f); fclose(f); }
    }
    char paths[NP_SIGDB_MAX_CANDIDATES][NP_SIGDB_PATH_MAX];
    int n = np_sigdb_candidates(dir, paths, NP_SIGDB_MAX_CANDIDATES);
    const char *want[] = {"1790904859.json", "1789086785.json", "1788400362.json"};
    if (n != 3) fail("candidates: %d, expected 3", n);
    for (int i = 0; i < n && i < 3; i++) {
        const char *base = strrchr(paths[i], '/');
        if (!base || strcmp(base + 1, want[i]) != 0) fail("candidate %d is %s, expected %s", i, paths[i], want[i]);
    }
    // A short list keeps the newest.
    n = np_sigdb_candidates(dir, paths, 2);
    if (n != 2 || !strstr(paths[0], "1790904859") || !strstr(paths[1], "1789086785"))
        fail("candidates capped at 2: got %d (%s, %s)", n, n > 0 ? paths[0] : "-", n > 1 ? paths[1] : "-");
    if (np_sigdb_candidates("/nonexistent/lullaby", paths, 4) != -1) fail("missing folder: expected -1");
}

int main(void) {
    snprintf(g_dir, sizeof(g_dir), "/tmp/np-updategate-%d", (int)getpid());
    if (mkdir(g_dir, 0755) != 0) { perror(g_dir); return 1; }
    gate_cases();
    candidate_cases();
    char cmd[700];
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", g_dir);
    if (strncmp(g_dir, "/tmp/np-updategate-", 19) == 0) system(cmd);
    if (g_failed) return 1;
    puts("==> updategate-check: Steam's update block comes back only with the gate on; "
         "databases are tried newest first");
    return 0;
}
