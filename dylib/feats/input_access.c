// Whether Steam may post input events, which Steam Input needs to turn a controller into
// keys and a mouse. NotProton signs Steam anew (ad hoc), and macOS keeps an approval given
// to Valve's signature listed but no longer honours it (upstream NotProton 1.1.x, "Fixes
// Steam Input issues"). This only reports it: asking macOS again or clearing the approval
// changes the Mac's privacy settings, which is the player's to decide (docs/DECISIONS.md).
#include "input_access.h"
#include "../util/log.h"

#include <CoreGraphics/CoreGraphics.h>

void np_input_access_check(void) {
    NP_LOG("input access: %s", CGPreflightPostEventAccess() ? "granted" : "missing");
}
