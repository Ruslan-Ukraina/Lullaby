// The switch for native Steam windows and the stylesheet half of it: with the
// macOS traffic lights in Steam's title row, Valve's own drawn ones are hidden.
// Pure C so steam_osx (which serves steamui) and the tests can use it.
#include "steamwin_css.h"
#include "../util/file.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static np_steamwin_mode_t g_mode = NP_SW_OFF;
static pthread_once_t g_mode_once = PTHREAD_ONCE_INIT;

// The first word only, whole: "native" or "log"; anything else is off, as
// NotProton.app's SteamWindows.mode reads it.
static int is_word(const char *text, const char *word) {
    size_t n = strlen(word);
    if (strncmp(text, word, n) != 0)
        return 0;
    char next = text[n];
    return next == '\0' || next == '\n' || next == '\r' || next == ' ' || next == '\t';
}

np_steamwin_mode_t np_steamwin_parse_mode(const char *text) {
    if (!text)
        return NP_SW_OFF;
    while (*text == ' ' || *text == '\t' || *text == '\n' || *text == '\r')
        text++;
    if (is_word(text, "native"))
        return NP_SW_NATIVE;
    if (is_word(text, "log"))
        return NP_SW_LOG;
    return NP_SW_OFF;
}

static void read_mode(void) {
    const char *home = np_home_dir();
    if (!home)
        return;
    char path[512];
    np_support_path(path, sizeof(path), home, NP_STEAMWIN_SWITCH_FILE);
    FILE *f = fopen(path, "r");
    if (!f)
        return;
    char word[32] = {0};
    if (fgets(word, sizeof(word), f))
        g_mode = np_steamwin_parse_mode(word);
    fclose(f);
}

np_steamwin_mode_t np_steamwin_mode(void) {
    pthread_once(&g_mode_once, read_mode);
    return g_mode;
}

static int has_suffix(const char *s, const char *suf) {
    size_t ls = strlen(s), lf = strlen(suf);
    return ls >= lf && memcmp(s + ls - lf, suf, lf) == 0;
}

int np_steamwin_css_should_patch(const char *path) {
    return path && has_suffix(path, ".css") && strstr(path, "/steamui/") != NULL;
}

// Valve draws its traffic lights as `.TitleBar.OSX .title-bar-actions.window-controls`
// (library.js, TitleBar). Hidden, not removed: the row keeps their width, and the
// real buttons sit in that place.
const char NP_STEAMWIN_CSS[] =
    "\n/* NotProton: native Steam windows */\n"
    ".TitleBar.OSX .title-bar-actions.window-controls{visibility:hidden!important}\n";

static const char ANCHOR[] = ".title-bar-actions";

char *np_steamwin_css_transform(const uint8_t *src, size_t src_len, size_t *out_len) {
    if (!src || !out_len)
        return NULL;
    // Only stylesheets that style the title bar, and never twice.
    if (!memmem(src, src_len, ANCHOR, sizeof(ANCHOR) - 1))
        return NULL;
    if (memmem(src, src_len, "NotProton: native Steam windows", 31))
        return NULL;
    size_t extra = sizeof(NP_STEAMWIN_CSS) - 1;
    char *out = malloc(src_len + extra + 1);
    if (!out)
        return NULL;
    memcpy(out, src, src_len);
    memcpy(out + src_len, NP_STEAMWIN_CSS, extra);
    out[src_len + extra] = '\0';
    *out_len = src_len + extra;
    return out;
}
