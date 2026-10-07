// Applies the webpatch to a real Steam chunk and writes the result, for a syntax check
// of the page as Steam Helper would get it (make webpatch-syntax). The token is put in
// as the dylib does.
#include "feats/webpatch.h"
#include "feats/settingsbridge.h"
#include "util/file.h"

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 3) { fputs("usage: webpatch-apply <chunk.js> <out.js>\n", stderr); return 2; }
    size_t len = 0;
    uint8_t *raw = np_read_whole_file(argv[1], &len);
    if (!raw) { fprintf(stderr, "cannot read %s\n", argv[1]); return 1; }
    size_t out_len = 0;
    const char *shape = NULL;
    char *patched = np_webpatch_transform(raw, len, &out_len, &shape);
    if (!patched) { fprintf(stderr, "%s: the webpatch did not apply\n", argv[1]); return 1; }
    size_t keyed_len = 0;
    char *keyed = np_settings_inject_token(patched, out_len, np_settings_token(), &keyed_len);
    FILE *f = fopen(argv[2], "wb");
    if (!f) return 1;
    fwrite(keyed ? keyed : patched, 1, keyed ? keyed_len : out_len, f);
    fclose(f);
    printf("%s: [%s] patched, %s token\n", argv[1], shape ? shape : "fixes only", keyed ? "with" : "without");
    return 0;
}
