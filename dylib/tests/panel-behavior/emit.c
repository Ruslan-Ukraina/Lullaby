// The payloads are macros, so the unit under test is included rather than linked:
// "statement" is the beta UI's renderer panel, "panel" the catalog panel (feats/panel.js)
// exactly as the gates splice it in.
#include "../../feats/webpatch.c"

#include <stdio.h>
#include <string.h>

int np_log_level = 0;
FILE *np_log_file = NULL;

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "panel") == 0) {
        fputs(NP_PANEL_JS, stdout);
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "statement") == 0) {
        fputs(NP_CX_OPTIONS_STATEMENT, stdout);
        return 0;
    }
    fputs("usage: emit statement|panel\n", stderr);
    return 2;
}
