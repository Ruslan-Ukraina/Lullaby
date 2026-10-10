// Native Steam windows: the switch file and the stylesheet that hides Valve's
// drawn window buttons. The windows themselves are steamwin.m.
#ifndef LULLABY_FEATS_STEAMWIN_CSS_H
#define LULLABY_FEATS_STEAMWIN_CSS_H

#include <stddef.h>
#include <stdint.h>

// lullaby/steam-windows: absent or "off", "log" (describe windows, change
// nothing), "native", "native-app" (native, and Steam Helper runs as a regular
// app: experiment, DECISIONS W10 option B). Lullaby.app writes it; it is read
// once per process. Everything native applies to native-app too.
#define NP_STEAMWIN_SWITCH_FILE "steam-windows"

typedef enum { NP_SW_OFF = 0, NP_SW_LOG = 1, NP_SW_NATIVE = 2, NP_SW_NATIVE_APP = 3 } np_steamwin_mode_t;

np_steamwin_mode_t np_steamwin_parse_mode(const char *word);
np_steamwin_mode_t np_steamwin_mode(void);

extern const char NP_STEAMWIN_CSS[];

// A steamui stylesheet.
int np_steamwin_css_should_patch(const char *path);

// The sheet with the rule appended, or NULL when it does not style the title
// bar (or already carries the rule). Caller frees.
char *np_steamwin_css_transform(const uint8_t *src, size_t src_len, size_t *out_len);

// library.js with the TitleBar tagged `NPDesktop` outside the in-game overlay,
// or NULL when the TitleBar is not there in the known shape. Caller frees.
char *np_steamwin_js_transform(const uint8_t *src, size_t src_len, size_t *out_len);

#endif
