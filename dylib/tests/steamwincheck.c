// The switch word and the stylesheet rule for native Steam windows.
// Included rather than linked, like gatecheck.
#include "../feats/steamwin_css.c"

#include <stdio.h>
#include <stdlib.h>

const char *np_home_dir(void) { return NULL; }
void np_support_path(char *buf, size_t bufsz, const char *home, const char *rel) {
    (void)home; (void)rel;
    if (bufsz) buf[0] = 0;
}

static int g_fail;

#define CHECK(cond, what) do { if (!(cond)) { printf("WRONG: %s\n", what); g_fail = 1; } } while (0)

int main(void) {
    CHECK(np_steamwin_parse_mode("native\n") == NP_SW_NATIVE, "native");
    CHECK(np_steamwin_parse_mode("  native") == NP_SW_NATIVE, "leading space");
    CHECK(np_steamwin_parse_mode("log\n") == NP_SW_LOG, "log");
    CHECK(np_steamwin_parse_mode("off\n") == NP_SW_OFF, "off");
    CHECK(np_steamwin_parse_mode("nativeish") == NP_SW_OFF, "nativeish is off");
    CHECK(np_steamwin_parse_mode("native-app\n") == NP_SW_NATIVE_APP, "native-app");
    CHECK(np_steamwin_parse_mode("") == NP_SW_OFF, "empty");
    CHECK(np_steamwin_parse_mode(NULL) == NP_SW_OFF, "null");

    CHECK(np_steamwin_css_should_patch("/x/steamui/css/library.css"), "steamui css");
    CHECK(!np_steamwin_css_should_patch("/x/steamui/library.js"), "js is not css");
    CHECK(!np_steamwin_css_should_patch("/x/other/library.css"), "css outside steamui");

    const char *sheet = ".title-area .title-bar-actions{display:flex}";
    size_t out_len = 0;
    char *out = np_steamwin_css_transform((const uint8_t *)sheet, strlen(sheet), &out_len);
    CHECK(out != NULL, "title bar sheet gets the rule");
    CHECK(out && strstr(out, ".TitleBar.OSX .title-bar-actions.window-controls{visibility:hidden!important}"),
          "rule hides Valve's window controls");
    CHECK(out && strstr(out, ".friendListHeaderContainer.titleBarContainer.OSX{padding-top:12px!important}"),
          "friends header moves below the traffic lights");
    CHECK(out && strstr(out, ".ModalDialogPopup .DialogHeader{margin-top:20px!important}"),
          "dialog titles move below the traffic lights");
    CHECK(out && !strstr(out, ".DesktopUI .TitleBar"), "the main window's row is not moved");
    CHECK(out && out_len == strlen(sheet) + strlen(NP_STEAMWIN_CSS), "rule appended once");
    char *again = out ? np_steamwin_css_transform((const uint8_t *)out, out_len, &out_len) : NULL;
    CHECK(again == NULL, "never twice");
    free(out);
    free(again);

    const char *other = ".Library{color:red}";
    CHECK(np_steamwin_css_transform((const uint8_t *)other, strlen(other), &out_len) == NULL,
          "sheets without the title bar are left alone");

    if (!g_fail)
        printf("==> steamwin-check: switch word and stylesheet rule as expected\n");
    return g_fail;
}
