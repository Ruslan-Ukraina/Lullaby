// Native macOS chrome for Steam's windows, in Steam Helper's browser process.
#ifndef LULLABY_FEATS_STEAMWIN_H
#define LULLABY_FEATS_STEAMWIN_H

// Steam Helper without --type=: the CEF browser process that owns Steam's windows.
int lb_steamwin_is_browser_process(int argc, const char **argv);

// Reads lullaby/steam-windows and, unless it is off, starts watching windows.
void lb_steamwin_start(void);

#endif
