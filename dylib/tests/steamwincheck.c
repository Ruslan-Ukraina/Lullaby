// The switch word and the stylesheet rule for native Steam windows.
// Included rather than linked, like gatecheck.
#include "../feats/steamwin_css.c"

#include <stdio.h>
#include <stdlib.h>

const char *lb_home_dir(void) { return NULL; }
void lb_support_path(char *buf, size_t bufsz, const char *home, const char *rel) {
    (void)home; (void)rel;
    if (bufsz) buf[0] = 0;
}

static int g_fail;

#define CHECK(cond, what) do { if (!(cond)) { printf("WRONG: %s\n", what); g_fail = 1; } } while (0)

int main(void) {
    CHECK(lb_steamwin_parse_mode("native\n") == LB_SW_NATIVE, "native");
    CHECK(lb_steamwin_parse_mode("  native") == LB_SW_NATIVE, "leading space");
    CHECK(lb_steamwin_parse_mode("log\n") == LB_SW_LOG, "log");
    CHECK(lb_steamwin_parse_mode("off\n") == LB_SW_OFF, "off");
    CHECK(lb_steamwin_parse_mode("nativeish") == LB_SW_OFF, "nativeish is off");
    CHECK(lb_steamwin_parse_mode("native-app\n") == LB_SW_NATIVE_APP, "native-app");
    CHECK(lb_steamwin_parse_mode("") == LB_SW_OFF, "empty");
    CHECK(lb_steamwin_parse_mode(NULL) == LB_SW_OFF, "null");

    CHECK(lb_steamwin_css_should_patch("/x/steamui/css/library.css"), "steamui css");
    CHECK(!lb_steamwin_css_should_patch("/x/steamui/library.js"), "js is not css");
    CHECK(!lb_steamwin_css_should_patch("/x/other/library.css"), "css outside steamui");

    const char *sheet = ".title-area .title-bar-actions{display:flex}";
    size_t out_len = 0;
    char *out = lb_steamwin_css_transform((const uint8_t *)sheet, strlen(sheet), &out_len);
    CHECK(out != NULL, "title bar sheet gets the rule");
    CHECK(out && strstr(out, ".TitleBar.OSX.LBDesktop .title-bar-actions.window-controls{visibility:hidden!important}"),
          "Valve's buttons hidden only where the TitleBar is tagged LBDesktop");
    CHECK(out && strstr(out, ":has(> .TitleBar.LBDesktop){padding-top:12px!important}"),
          "friends header moves below the traffic lights, outside the overlay");
    CHECK(out && strstr(out, "html.ModalDialogPopup:has(.TitleBar.LBDesktop) .DialogContent:not(.DialogContent .DialogContent)"
                             "{border-top:14px solid transparent!important"),
          "one rule for every dialog popup, inside the box that paints its background");
    CHECK(out && !strstr(out, "body.ModalDialogBody:has"), "the body is not moved (that showed the window's black)");
    CHECK(out && !strstr(out, ".DialogHeader"), "no per-header rule left");
    CHECK(out && out_len == strlen(sheet) + strlen(LB_STEAMWIN_CSS), "rule appended once");
    char *again = out ? lb_steamwin_css_transform((const uint8_t *)out, out_len, &out_len) : NULL;
    CHECK(again == NULL, "never twice");
    free(out);
    free(again);

    const char *other = ".Library{color:red}";
    CHECK(lb_steamwin_css_transform((const uint8_t *)other, strlen(other), &out_len) == NULL,
          "sheets without the title bar are left alone");

    // TitleBar, as library.js ships it (Steam 1788652215).
    const char *js = "x=1;function p(e){const{className:t,hideActions:i,bOSX:p=(0,l.Pr)(),"
        "onClose:b,extraActions:w,popup:M,children:C}=e,v=(0,c.jt)(M);return(0,n.jsxs)(\"div\","
        "{className:(0,a.A)(\"TitleBar\",\"title-area\",p&&\"OSX\",(v||g)&&\"WindowFocus\",t)})}";
    size_t js_len = 0;
    char *tagged = lb_steamwin_js_transform((const uint8_t *)js, strlen(js), &js_len);
    CHECK(tagged != NULL, "TitleBar found");
    CHECK(tagged && strstr(tagged, "p&&\"OSX\",p&&!function(w){"), "class added after OSX, same flag");
    CHECK(tagged && strstr(tagged, "}(M)&&\"LBDesktop\",(v||g)&&\"WindowFocus\""), "overlay test gets the popup");
    CHECK(tagged && strstr(tagged, "window.g_PopupManager") && strstr(tagged, "BIsInOverlay"),
          "overlay test uses Steam's popup manager");
    CHECK(tagged && js_len == strlen(tagged), "length reported");
    char *twice = tagged ? lb_steamwin_js_transform((const uint8_t *)tagged, js_len, &js_len) : NULL;
    CHECK(twice == NULL, "never twice");
    free(tagged);
    free(twice);
    const char *plain = "function q(){return 1}";
    CHECK(lb_steamwin_js_transform((const uint8_t *)plain, strlen(plain), &js_len) == NULL,
          "scripts without the TitleBar are left alone");
    const char *drift = "(\"TitleBar\",\"title-area\",p&&\"MAC\",t)";
    CHECK(lb_steamwin_js_transform((const uint8_t *)drift, strlen(drift), &js_len) == NULL,
          "a changed shape is refused");

    if (!g_fail)
        printf("==> steamwin-check: switch word and stylesheet rule as expected\n");
    return g_fail;
}
