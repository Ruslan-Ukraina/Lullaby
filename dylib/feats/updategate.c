// Steam's update block, put back inside the client. Lullaby.app lifts the block
// only while Valve offers a Steam build it has signatures for (SteamUpdateGate);
// the bootstrapper reads steam.cfg when Steam starts, updates, and starts the
// client, where this runs and writes the block back. The next build then waits
// for NotProton's signatures even when the app is not open.

#include "updategate.h"
#include "../util/file.h"
#include "../util/log.h"

#include <errno.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int gate_mode_on(const char *gate_file) {
    size_t n = 0;
    uint8_t *raw = np_read_whole_file(gate_file, &n);
    if (!raw) return 0;
    size_t a = 0, b = n;
    while (a < b && (raw[a] == ' ' || raw[a] == '\t' || raw[a] == '\n' || raw[a] == '\r')) a++;
    while (b > a && (raw[b - 1] == ' ' || raw[b - 1] == '\t' || raw[b - 1] == '\n' || raw[b - 1] == '\r')) b--;
    int on = (b - a == 4 && memcmp(raw + a, "auto", 4) == 0) ||
             (b - a == 6 && memcmp(raw + a, "manual", 6) == 0);
    free(raw);
    return on;
}

static void trim(const char **s, const char **e) {
    while (*s < *e && (**s == ' ' || **s == '\t')) (*s)++;
    while (*e > *s && ((*e)[-1] == ' ' || (*e)[-1] == '\t' || (*e)[-1] == '\r')) (*e)--;
}

// The value of a `key=value` line for our key, or NULL.
static int key_value(const char *line, const char *end, const char **vs, const char **ve) {
    const char *eq = memchr(line, '=', (size_t)(end - line));
    if (!eq) return 0;
    const char *ks = line, *ke = eq;
    trim(&ks, &ke);
    size_t klen = strlen(NP_UPDATE_GATE_KEY);
    if ((size_t)(ke - ks) != klen || memcmp(ks, NP_UPDATE_GATE_KEY, klen) != 0) return 0;
    *vs = eq + 1;
    *ve = end;
    trim(vs, ve);
    return 1;
}

static int write_atomically(const char *path, const char *data, size_t len) {
    char tmp[1100];
    int n = snprintf(tmp, sizeof(tmp), "%s.lullaby-new", path);
    if (n < 0 || n >= (int)sizeof(tmp)) return -1;
    FILE *f = fopen(tmp, "wb");
    if (!f) return -1;
    int ok = fwrite(data, 1, len, f) == len;
    ok = (fclose(f) == 0) && ok;
    if (!ok || rename(tmp, path) != 0) {
        unlink(tmp);
        return -1;
    }
    return 0;
}

// 1 written, 0 already blocked (or skipped), -1 failed.
static int ensure_block(const char *path, int create) {
    size_t n = 0;
    uint8_t *raw = np_read_whole_file(path, &n);
    if (!raw) {
        if (!create) {
            char copy[1024];
            snprintf(copy, sizeof(copy), "%s", path);
            struct stat st;
            if (stat(dirname(copy), &st) != 0 || !S_ISDIR(st.st_mode)) return 0;
        }
        n = 0;
    }
    const char *text = raw ? (const char *)raw : "";
    size_t cap = n + strlen(NP_UPDATE_GATE_KEY) + 16;
    char *out = malloc(cap);
    if (!out) { free(raw); return -1; }
    size_t used = 0;
    int seen = 0, blocked = 0;

    const char *p = text, *end = text + n;
    while (p <= end) {
        const char *nl = memchr(p, '\n', (size_t)(end - p));
        const char *le = nl ? nl : end;
        const char *vs, *ve;
        if (key_value(p, le, &vs, &ve)) {
            blocked = (ve - vs == 6 && memcmp(vs, "enable", 6) == 0);
            if (!seen) {
                used += (size_t)sprintf(out + used, "%s=enable", NP_UPDATE_GATE_KEY);
                seen = 1;
                if (nl) out[used++] = '\n';
            }
        } else {
            memcpy(out + used, p, (size_t)(le - p));
            used += (size_t)(le - p);
            if (nl) out[used++] = '\n';
        }
        if (!nl) break;
        p = nl + 1;
    }
    if (blocked) {
        free(out);
        free(raw);
        return 0;
    }
    if (!seen) {
        if (used > 0 && out[used - 1] != '\n') out[used++] = '\n';
        used += (size_t)sprintf(out + used, "%s=enable\n", NP_UPDATE_GATE_KEY);
    }
    int rc = write_atomically(path, out, used);
    free(out);
    free(raw);
    return rc == 0 ? 1 : -1;
}

int np_update_gate_rearm_paths(const char *gate_file, const char *const *cfgs, int count) {
    if (!gate_mode_on(gate_file)) return -1;
    int written = 0;
    for (int i = 0; i < count; i++) {
        int rc = ensure_block(cfgs[i], i == 0);
        if (rc == 1) {
            written++;
            NP_LOG("update gate: Steam's update block is back in %s", cfgs[i]);
        } else if (rc < 0) {
            NP_WARN("update gate: could not write %s (%s)", cfgs[i], strerror(errno));
        }
    }
    return written;
}

void np_update_gate_rearm(void) {
    const char *home = np_home_dir();
    if (!home) return;
    char gate[1024], outer[1024], inner[1024];
    np_support_path(gate, sizeof(gate), home, NP_UPDATE_GATE_FILE);
    snprintf(outer, sizeof(outer), "%s/Library/Application Support/Steam/steam.cfg", home);
    snprintf(inner, sizeof(inner),
             "%s/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam.cfg", home);
    const char *cfgs[] = {outer, inner};
    int written = np_update_gate_rearm_paths(gate, cfgs, 2);
    if (written == 0) NP_DBG("update gate: Steam's update block already in place");
}
