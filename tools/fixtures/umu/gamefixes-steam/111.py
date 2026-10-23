"""Sample Game"""
import os
from protonfixes import util

os.system("touch /tmp/umu-importer-must-not-run")


def main() -> None:
    os.system("touch /tmp/umu-importer-must-not-run")
    util.set_environment('WINE_FOO', '1')
    util.set_environment('PROTON_USE_WINED3D', '1')
    util.set_environment('DYLD_INSERT_LIBRARIES', 'x')
    util.winedll_override('xaudio2_9', util.OverrideOrder.NATIVE_BUILTIN)
    util.regedit_add('HKCU\\Software\\Wine\\Mac Driver', 'X', 'REG_DWORD', '1')
    util.regedit_add('HKCU\\Software\\Studio\\Game', 'X', 'REG_SZ', '1')
    util.protontricks('arial')
    if True:
        util.set_environment('WINE_IF', '1')
    util.set_cpu_topology_limit(8)
    util.set_environment('SDL_JOYSTICK_HIDAPI', '0')
