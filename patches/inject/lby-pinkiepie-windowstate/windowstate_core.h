/* lby-pinkiepie-windowstate: the decisions, with no AppKit in them so a test can run them.
 *
 * A game's window is in one of three states: a Window, macOS Native Fullscreen, or a Window
 * (full screen): borderless and covering the screen, which is what a game's own "borderless" mode
 * makes. The state the game was left in is saved, and put back at the next launch. */
#ifndef LBWS_CORE_H
#define LBWS_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <string.h>

typedef enum { LBWS_WINDOW = 0, LBWS_NATIVE = 1, LBWS_BORDERLESS = 2 } lbws_state;

typedef struct { double x, y, w, h; } lbws_rect;

static inline const char *lbws_name(lbws_state s)
{
    switch (s) {
    case LBWS_NATIVE: return "native";
    case LBWS_BORDERLESS: return "borderless";
    default: return "window";
    }
}

static inline bool lbws_parse(const char *name, lbws_state *out)
{
    if (!name) return false;
    if (!strcmp(name, "window")) *out = LBWS_WINDOW;
    else if (!strcmp(name, "native")) *out = LBWS_NATIVE;
    else if (!strcmp(name, "borderless")) *out = LBWS_BORDERLESS;
    else return false;
    return true;
}

/* A frame covers a screen when it is within 2 % of its size in both directions and starts at it. */
/* A game's big window with no title bar that does not cover the screen (a borderless "full screen" at a smaller resolution,
 * Deadlock at 1920x1200): the game means it as its full screen, so it is treated like a covering one and goes to native full
 * screen, where the engine scales it (ENG-15). Small borderless windows (a splash, a launcher) are left alone. */
#define LBWS_BORDERLESS_MIN_W 800.0
#define LBWS_BORDERLESS_MIN_H 500.0
static inline bool lbws_borderless_fullscreen_like(bool has_title_bar, lbws_rect frame)
{
    return !has_title_bar && frame.w >= LBWS_BORDERLESS_MIN_W && frame.h >= LBWS_BORDERLESS_MIN_H;
}

static inline bool lbws_covers(lbws_rect frame, lbws_rect screen)
{
    double tw = screen.w * 0.02, th = screen.h * 0.02;
    return frame.w >= screen.w - tw && frame.h >= screen.h - th &&
           frame.x <= screen.x + tw && frame.y <= screen.y + th;
}

/* What state a window is in now. Native fullscreen wins; a window without a title bar that covers
 * its screen is a Window (full screen); everything else is a Window. */
static inline lbws_state lbws_classify(bool native_fullscreen, bool has_title_bar, lbws_rect frame, lbws_rect screen)
{
    if (native_fullscreen) return LBWS_NATIVE;
    if (!has_title_bar && lbws_covers(frame, screen)) return LBWS_BORDERLESS;
    return LBWS_WINDOW;
}

typedef enum { LBWS_NOTHING = 0, LBWS_SET_SIZE = 1, LBWS_ENTER_NATIVE = 2 } lbws_action;

typedef struct { lbws_action action; double w, h; } lbws_plan;

/* The smallest window worth putting back; anything below is a splash or a dialog's size. */
#define LBWS_MIN_W 320.0
#define LBWS_MIN_H 200.0

/* What to do when the game's window first appears.
 *  saved:      the state the game was left in, and the Window size it last had (0 when unknown);
 *  now_native: the window is in native fullscreen already (the game or the engine put it there);
 *  can_native: the window can go to native fullscreen (AppKit's full-screen-primary behaviour);
 *  resizable:  the window has a resize handle;
 *  cur:        the window's content size now. */
static inline lbws_plan lbws_plan_restore(lbws_state saved, double saved_w, double saved_h, bool now_native,
                                          bool can_native, bool resizable, double cur_w, double cur_h)
{
    lbws_plan none = { LBWS_NOTHING, 0, 0 };
    if (saved == LBWS_NATIVE) {
        if (now_native || !can_native) return none;
        lbws_plan p = { LBWS_ENTER_NATIVE, 0, 0 };
        return p;
    }
    if (saved == LBWS_WINDOW) {
        if (now_native || !resizable) return none;
        if (saved_w < LBWS_MIN_W || saved_h < LBWS_MIN_H) return none;
        double dw = saved_w - cur_w, dh = saved_h - cur_h;
        if (dw > -2 && dw < 2 && dh > -2 && dh < 2) return none;
        lbws_plan p = { LBWS_SET_SIZE, saved_w, saved_h };
        return p;
    }
    return none; /* the game's own borderless mode is the game's to put back */
}

typedef enum { LBWS_FS_NOTHING = 0, LBWS_FS_ENTER = 1, LBWS_FS_WAIT = 2 } lbws_fs_action;

/* A game whose window covers the screen is shown by the engine as an ordinary window (WineWindow's
 * presentationWindowed). With the native full screen switch on, it goes on to macOS's native full screen:
 * its own desktop, at the game's resolution. The saved state does not decide this, the switch does.
 *  windowed_presentation: the engine shows a screen-covering window of the game in a window;
 *  want_native:           the switch (LULLABY_NATIVE_FULLSCREEN, on unless it says 0);
 *  now_native, can_native: as above; the full-screen behaviour is set a moment after the window shows,
 *                          so a window that cannot yet is waited for. */
static inline lbws_fs_action lbws_plan_fullscreen(bool windowed_presentation, bool want_native, bool now_native,
                                                  bool can_native)
{
    if (!windowed_presentation || !want_native || now_native) return LBWS_FS_NOTHING;
    return can_native ? LBWS_FS_ENTER : LBWS_FS_WAIT;
}

/* The want_native switch from its text: on unless it is "0". */
static inline bool lbws_want_native(const char *text) { return !(text && !strcmp(text, "0")); }

#endif
