// Steam's update block, put back inside the client (Phase 5, docs/DECISIONS.md P5-4).
#ifndef LULLABY_FEATS_UPDATEGATE_H
#define LULLABY_FEATS_UPDATEGATE_H

#define NP_UPDATE_GATE_FILE "steam-update-gate"
#define NP_UPDATE_GATE_KEY  "BootStrapperInhibitUpdateOnLaunch"

// When lullaby/steam-update-gate says auto or manual, writes
// BootStrapperInhibitUpdateOnLaunch=enable into Steam's steam.cfg files, the way
// the app's UpdateBlock does. Called once the client is up (steamclient.dylib is
// loaded), after the bootstrapper's own update check, so a lift Lullaby.app made
// for a supported build lasts exactly one Steam start.
void np_update_gate_rearm(void);

// The same with explicit paths. cfgs[0] is written even when absent; the others
// only when their directory exists. Returns how many files were written, or -1
// when the gate file names no mode (nothing to do).
int np_update_gate_rearm_paths(const char *gate_file, const char *const *cfgs, int count);

#endif // LULLABY_FEATS_UPDATEGATE_H
