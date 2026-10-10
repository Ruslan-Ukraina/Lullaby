// Steam Helper as a regular app (native-app): focus tracing and guard, in both
// steam_osx and Steam Helper.
#ifndef NOTPROTON_FEATS_STEAMFOCUS_H
#define NOTPROTON_FEATS_STEAMFOCUS_H

// Does nothing unless lullaby/steam-windows is "native-app". `who` names the
// process in the log; `make_regular` turns Steam Helper into a regular app.
void np_steamfocus_start(const char *who, int make_regular);

#endif
