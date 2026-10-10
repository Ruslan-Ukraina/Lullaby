// The Steam panel's channel to Lullaby's settings (docs/ROADMAP.md section 5, DECISIONS P7A-2).
//
// Steam Helper serves https://steamloopback.host/<path> from its steamui folder through
// CefStreamReader::CreateForFile, which opens the file with fopen; the webpatch hook
// already answers that call for the compat chunk. A request of the panel is a path that
// does not exist on disk:
//
//   steamui/lullaby-settings/<token>/<nonce>/<base64url of a JSON request>.json
//
// and the answer is what `lullaby-settings panel <request>` prints, handed back as an
// anonymous file. The token is random per Steam Helper process and reaches the page only
// inside the patched chunk, so no other page or program can drive the CLI through it.
#ifndef LULLABY_FEATS_SETTINGSBRIDGE_H
#define LULLABY_FEATS_SETTINGSBRIDGE_H

#include <stddef.h>
#include <stdint.h>

// The text the patched chunk carries where the token goes.
#define NP_SETTINGS_TOKEN_PLACEHOLDER "__NP_SETTINGS_TOKEN__"
#define NP_SETTINGS_TOKEN_LEN 32

// How long the CLI may take to answer, in milliseconds.
extern int np_settings_timeout_ms;

// This process's token, 32 lowercase hex digits.
const char *np_settings_token(void);

// Whether `path` is a request of the panel (a steamui path under lullaby-settings/).
int np_settings_should_serve(const char *path);

// The answer to a request as a rewound anonymous fd, or -1 to fall through. A request
// with a wrong token or a malformed body is answered with an error object, not -1, so the
// page always gets JSON.
int np_settings_serve(const char *path);

// The JSON answer for the steamui-relative `rest` (lullaby-settings/...), running `cli`.
// Caller frees. Exposed for the hermetic test.
char *np_settings_answer(const char *rest, const char *token, const char *cli, size_t *out_len);

// `src` with every placeholder replaced by `token`; NULL when there is none. Caller frees.
char *np_settings_inject_token(const char *src, size_t len, const char *token, size_t *out_len);

// base64url (no padding) into bytes; NULL on a malformed input. Caller frees.
uint8_t *np_base64url_decode(const char *src, size_t len, size_t *out_len);

#endif // LULLABY_FEATS_SETTINGSBRIDGE_H
