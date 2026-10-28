/* The window-state decisions. Pure C: cc -o core_test core_test.c && ./core_test */
#include <stdio.h>
#include "../windowstate_core.h"

static int fails;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL %s\n", what); fails++; } } while (0)

int main(void)
{
    lbws_rect screen = { 0, 0, 1512, 982 };
    lbws_rect small = { 100, 80, 1280, 720 };
    lbws_rect full = { 0, 0, 1512, 982 };
    lbws_rect nearly = { 0, 0, 1500, 975 };
    lbws_rect offset = { 600, 0, 1512, 982 };

    CHECK(lbws_classify(true, true, small, screen) == LBWS_NATIVE, "native fullscreen wins");
    CHECK(lbws_classify(true, false, full, screen) == LBWS_NATIVE, "native fullscreen wins over a covering frame");
    CHECK(lbws_classify(false, true, small, screen) == LBWS_WINDOW, "a titled small window is a Window");
    CHECK(lbws_classify(false, true, full, screen) == LBWS_WINDOW, "a titled window covering the screen is a Window");
    CHECK(lbws_classify(false, false, full, screen) == LBWS_BORDERLESS, "no title bar, covering: Window (full screen)");
    CHECK(lbws_classify(false, false, nearly, screen) == LBWS_BORDERLESS, "within 2 % covers");
    CHECK(lbws_classify(false, false, small, screen) == LBWS_WINDOW, "borderless but small is a Window");
    CHECK(lbws_classify(false, false, offset, screen) == LBWS_WINDOW, "covering size but not at the screen");

    lbws_rect deadlock = { 0, 0, 960, 600 };
    lbws_rect splash = { 0, 0, 480, 270 };
    CHECK(lbws_borderless_fullscreen_like(false, deadlock), "a big borderless window is a full screen the game meant");
    CHECK(!lbws_borderless_fullscreen_like(false, splash), "a small borderless window (splash) is left alone");
    CHECK(!lbws_borderless_fullscreen_like(true, deadlock), "a titled window is the player's");

    lbws_state s;
    CHECK(lbws_parse("native", &s) && s == LBWS_NATIVE, "parse native");
    CHECK(lbws_parse("borderless", &s) && s == LBWS_BORDERLESS, "parse borderless");
    CHECK(lbws_parse("window", &s) && s == LBWS_WINDOW, "parse window");
    CHECK(!lbws_parse("floating", &s) && !lbws_parse(NULL, &s), "parse refuses the rest");
    CHECK(!strcmp(lbws_name(LBWS_NATIVE), "native") && !strcmp(lbws_name(LBWS_BORDERLESS), "borderless") &&
          !strcmp(lbws_name(LBWS_WINDOW), "window"), "names");

    lbws_plan p = lbws_plan_restore(LBWS_NATIVE, 0, 0, false, true, true, 1280, 720);
    CHECK(p.action == LBWS_ENTER_NATIVE, "left in native: go there");
    p = lbws_plan_restore(LBWS_NATIVE, 0, 0, true, true, true, 1280, 720);
    CHECK(p.action == LBWS_NOTHING, "already native: nothing");
    p = lbws_plan_restore(LBWS_NATIVE, 0, 0, false, false, true, 1280, 720);
    CHECK(p.action == LBWS_NOTHING, "cannot go native: nothing");

    p = lbws_plan_restore(LBWS_WINDOW, 1600, 900, false, true, true, 1280, 720);
    CHECK(p.action == LBWS_SET_SIZE && p.w == 1600 && p.h == 900, "left in a window: its size back");
    p = lbws_plan_restore(LBWS_WINDOW, 1281, 721, false, true, true, 1280, 720);
    CHECK(p.action == LBWS_NOTHING, "within 2 points: nothing");
    p = lbws_plan_restore(LBWS_WINDOW, 1600, 900, false, true, false, 1280, 720);
    CHECK(p.action == LBWS_NOTHING, "no resize handle: nothing");
    p = lbws_plan_restore(LBWS_WINDOW, 100, 100, false, true, true, 1280, 720);
    CHECK(p.action == LBWS_NOTHING, "a size below the minimum is not put back");
    p = lbws_plan_restore(LBWS_WINDOW, 1600, 900, true, true, true, 1280, 720);
    CHECK(p.action == LBWS_NOTHING, "already in native fullscreen: the size is not touched");

    p = lbws_plan_restore(LBWS_BORDERLESS, 1600, 900, false, true, true, 1280, 720);
    CHECK(p.action == LBWS_NOTHING, "borderless is the game's own to put back");

    /* A game that covers the screen, shown by the engine in a window: the switch decides. */
    CHECK(lbws_plan_fullscreen(true, true, false, true) == LBWS_FS_ENTER, "covering game, switch on: native full screen");
    CHECK(lbws_plan_fullscreen(true, true, false, false) == LBWS_FS_WAIT, "cannot yet: wait for the window's behaviour");
    CHECK(lbws_plan_fullscreen(true, true, true, true) == LBWS_FS_NOTHING, "already native: nothing");
    CHECK(lbws_plan_fullscreen(true, false, false, true) == LBWS_FS_NOTHING, "switch off: stays a window");
    CHECK(lbws_plan_fullscreen(false, true, false, true) == LBWS_FS_NOTHING, "an ordinary window is not sent to full screen");
    CHECK(lbws_want_native(NULL) && lbws_want_native("1") && lbws_want_native("") && !lbws_want_native("0"),
          "the switch is on unless it says 0");

    if (fails) { printf("core_test: %d failed\n", fails); return 1; }
    printf("core_test: the window-state decisions hold\n");
    return 0;
}
