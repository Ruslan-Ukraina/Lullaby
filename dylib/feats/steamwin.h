// Native macOS chrome for Steam's windows, in Steam Helper's browser process.
#ifndef NOTPROTON_FEATS_STEAMWIN_H
#define NOTPROTON_FEATS_STEAMWIN_H

// Steam Helper without --type=: the CEF browser process that owns Steam's windows.
int np_steamwin_is_browser_process(int argc, const char **argv);

// Reads notproton/steam-windows and, unless it is off, starts watching windows.
void np_steamwin_start(void);

#endif
