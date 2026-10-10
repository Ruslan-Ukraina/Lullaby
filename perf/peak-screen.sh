#!/bin/sh
# Sets PEAK's Unity screen settings in its prefix (the game must not run).
#   perf/peak-screen.sh MODE WIDTH HEIGHT    MODE: 0 exclusive, 1 fullscreen window, 3 windowed
set -eu
P="$HOME/Library/Application Support/Steam/steamapps/compatdata/3527290/pfx"
E="$HOME/Library/Application Support/lullaby/runners/current/wine/bin"
k='HKCU\Software\LandCrab\PEAK'
hex() { printf '0x%x' "$1"; }
WINEPREFIX="$P" WINEDEBUG=-all
export WINEPREFIX WINEDEBUG
f="$P/drive_c/np-screen.reg"
printf '%s\r\n' 'Windows Registry Editor Version 5.00' '' '[HKEY_CURRENT_USER\Software\LandCrab\PEAK]' \
  "\"Screenmanager Fullscreen mode_h3630240806\"=dword:$(printf '%08x' "$1")" \
  "\"Screenmanager Resolution Width_h182942802\"=dword:$(printf '%08x' "$2")" \
  "\"Screenmanager Resolution Height_h2627697771\"=dword:$(printf '%08x' "$3")" \
  '"Screenmanager Resolution Use Native_h1405027254"=dword:00000000' '' > "$f"
"$E/wine" reg import 'C:\np-screen.reg' > /dev/null 2>&1
rm -f "$f"
"$E/wineserver" -w
echo "PEAK screen: mode $1, $2x$3 ($k)"
