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

// The first word only, whole: "native", "native-app" or "log"; anything else is off, as
// Lullaby.app's SteamWindows.mode reads it.
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
    if (is_word(text, "native-app"))
        return NP_SW_NATIVE_APP;
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

// All rules apply only under `.TitleBar.NPDesktop`, a class np_steamwin_js_transform
// adds to Steam's TitleBar outside the in-game overlay: overlay windows have no
// macOS frame and keep Valve's buttons and spacing.
//
// Valve draws its traffic lights as `.TitleBar.OSX .title-bar-actions.window-controls`
// (library.js, TitleBar). Hidden, not removed: the row keeps their width, and the
// real buttons sit in that place.
//
// The real buttons sit 13-27 pt from the top. In the compact windows Steam starts
// its content higher than that, under the buttons, so that content moves down; the
// main window, where the row lines up, is not touched:
//   friends list   its header (avatar, name) is `.friendListHeaderContainer
//                  .titleBarContainer.OSX`, which has no padding of its own;
//   every dialog   popups Steam opens as `html.ModalDialogPopup` (servers, players,
//                  About, the launch option chooser…): their outermost
//                  `.DialogContent`, the box that paints the dialog's background,
//                  gets a transparent top border. The background shows through it
//                  (background-clip is the border box) and starts at the border
//                  (background-origin), so the freed strip continues the dialog's
//                  own gradient: no black, no band; border-box keeps the height.
//                  Popups without a DialogContent are not moved.
const char NP_STEAMWIN_CSS[] =
    "\n/* Lullaby: native Steam windows */\n"
    ".TitleBar.OSX.NPDesktop .title-bar-actions.window-controls{visibility:hidden!important}\n"
    ".friendListHeaderContainer.titleBarContainer.OSX:has(> .TitleBar.NPDesktop){padding-top:12px!important}\n"
    "html.ModalDialogPopup:has(.TitleBar.NPDesktop) .DialogContent:not(.DialogContent .DialogContent)"
    "{border-top:14px solid transparent!important;box-sizing:border-box!important;"
    "background-origin:border-box!important}\n";

static const char ANCHOR[] = ".title-bar-actions";

char *np_steamwin_css_transform(const uint8_t *src, size_t src_len, size_t *out_len) {
    if (!src || !out_len)
        return NULL;
    // Only stylesheets that style the title bar, and never twice.
    if (!memmem(src, src_len, ANCHOR, sizeof(ANCHOR) - 1))
        return NULL;
    if (memmem(src, src_len, "Lullaby: native Steam windows", 31))
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

// MARK: TitleBar class

// TitleBar in library.js: `…popup:M,children:C}=e,…("TitleBar","title-area",p&&"OSX",…`.
// After `p&&"OSX",` goes `p&&!<overlay?>(M)&&"NPDesktop",`. The overlay test uses
// names Steam does not minify: window.g_PopupManager.GetPopups(), each popup's
// window and BIsInOverlay() (a popup of a game's overlay has its PID in
// browser_info). Anything unexpected counts as not the overlay.
static const char TB_ANCHOR[] = "\"TitleBar\",\"title-area\",";
static const char TB_OVERLAY[] =
    "&&!function(w){try{var m=window.g_PopupManager;return!!(w&&m&&m.GetPopups&&"
    "Array.from(m.GetPopups()).some(function(e){return e&&e.window===w&&"
    "(e.BIsInOverlay?e.BIsInOverlay():!!(e.browser_info&&e.browser_info.m_unPID))}))}"
    "catch(n){return!1}}(";
static const char TB_TAIL[] = ")&&\"NPDesktop\",";

static int ident_char(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '$';
}

char *np_steamwin_js_transform(const uint8_t *src, size_t src_len, size_t *out_len) {
    const char *s = (const char *)src;
    if (!s || !out_len)
        return NULL;
    const char *at = memmem(s, src_len, TB_ANCHOR, sizeof(TB_ANCHOR) - 1);
    if (!at)
        return NULL;
    size_t rest = src_len - (size_t)(at - s) - (sizeof(TB_ANCHOR) - 1);
    if (memmem(at + 1, rest, TB_ANCHOR, sizeof(TB_ANCHOR) - 1))
        return NULL;                        // more than one TitleBar: not the shape we know
    if (memmem(s, src_len, "NPDesktop", 9))
        return NULL;                        // already patched

    // `p&&"OSX",` right after the anchor.
    const char *id = at + sizeof(TB_ANCHOR) - 1, *e = id;
    while ((size_t)(e - s) < src_len && ident_char(*e))
        e++;
    static const char OSX[] = "&&\"OSX\",";
    if (e == id || (size_t)(e - s) + sizeof(OSX) - 1 > src_len || memcmp(e, OSX, sizeof(OSX) - 1) != 0)
        return NULL;
    const char *insert = e + sizeof(OSX) - 1;

    // `popup:M` in the destructuring just before.
    const char *p = at, *popup = NULL;
    for (const char *q = at; q > s && at - q < 600; q--)
        if (memcmp(q, "popup:", 6) == 0) { popup = q + 6; break; }
    if (!popup)
        return NULL;
    const char *pe = popup;
    while (pe < at && ident_char(*pe))
        pe++;
    if (pe == popup)
        return NULL;
    (void)p;

    size_t id_len = (size_t)(e - id), pop_len = (size_t)(pe - popup);
    size_t extra = id_len + (sizeof(TB_OVERLAY) - 1) + pop_len + (sizeof(TB_TAIL) - 1);
    char *out = malloc(src_len + extra + 1);
    if (!out)
        return NULL;
    size_t head = (size_t)(insert - s), o = 0;
    memcpy(out, s, head); o += head;
    memcpy(out + o, id, id_len); o += id_len;
    memcpy(out + o, TB_OVERLAY, sizeof(TB_OVERLAY) - 1); o += sizeof(TB_OVERLAY) - 1;
    memcpy(out + o, popup, pop_len); o += pop_len;
    memcpy(out + o, TB_TAIL, sizeof(TB_TAIL) - 1); o += sizeof(TB_TAIL) - 1;
    memcpy(out + o, insert, src_len - head); o += src_len - head;
    out[o] = '\0';
    *out_len = o;
    return out;
}
