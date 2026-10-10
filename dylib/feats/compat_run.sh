#!/bin/sh
# notproton compatibility tool shim: runs Windows games from Steam on the
# Dormison engine NotProton unpacked into runners/current
set -e

verb="$1"
shift || true

# Steam's launch options. hook_launch.c (from upstream NotProton 1.1.0) runs the launch
# through /bin/sh as Linux Steam does: NAME=value ahead of %command% is a variable, what
# follows %command% an argument of the game. The shell first notes the names it was handed
# in NOTPROTON_ENV_BASE, so the variables the options set are the rest; they go on to the
# game below, which LaunchServices starts with an environment of its own.
launch_env=""
launch_shell=0
if [ -n "${NOTPROTON_ENV_BASE+x}" ]; then
  launch_shell=1
  for name in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p'); do
    case " $NOTPROTON_ENV_BASE " in *" $name "*) continue ;; esac
    case "$name" in NOTPROTON_ENV_BASE|DYLD_*) continue ;; esac
    launch_env="$launch_env $name"
  done
  unset NOTPROTON_ENV_BASE
fi
# Only NotProton's renderer list on Steam's newer Compatibility page (webpatch.c) still
# writes its choice after the command; without the shell (an older dylib, or the hook
# off) every option arrives after it, and the known prefixes are taken as before.
argc=$#
argi=0
while [ "$argi" -lt "$argc" ]; do
  arg="$1"
  shift
  case "$arg" in
    NOTPROTON_RENDERER=*|CX_GRAPHICS_BACKEND=*) take=1 ;;
    CX_GRAPHICS*=*|D3DM_*=*|DXMT_*=*|DXVK_*=*|MTL_*=*|NOTPROTON_*=*|ROSETTA_*=*|SEVO_*=*|WINE*=*)
      [ "$launch_shell" = 1 ] && take=0 || take=1 ;;
    *) take=0 ;;
  esac
  if [ "$take" = 1 ]; then
    # shellcheck disable=SC2163 # arg is a NAME=VALUE pair, which export takes as an assignment
    export "$arg"
    launch_env="$launch_env ${arg%%=*}"
  else
    set -- "$@" "$arg"
  fi
  argi=$((argi+1))
done
# The player's own DLL overrides follow NotProton's (the bridge's and the renderer's).
launch_dll_overrides=""
case " $launch_env " in *" WINEDLLOVERRIDES "*) launch_dll_overrides="$WINEDLLOVERRIDES" ;; esac

case "$verb" in
  getcompatpath)
    printf '%s\n' "$STEAM_COMPAT_DATA_PATH"
    exit 0
    ;;
esac

support="$HOME/Library/Application Support/notproton"
# The Dormison engine. wine/bin/wine is its front door; x86_64-unix/wine is the
# loader proper, the one Dormison re-executes every Windows program through and
# the one a game's bundle carries a copy of. The server is native arm64.
engine_root="$support/runners/current"
wine_unix="$engine_root/wine/lib/wine/x86_64-unix"
WINELOADER="$engine_root/wine/bin/wine"
WINESERVER="$engine_root/wine/bin/wineserver"
# The app writes the engine's paths to notproton-engine.env (DormisonEngine). It
# is read as data, never sourced: one NP_ENGINE_NAME='value' per line.
engine_env_get() {
  sed -n "s/^$1='\(.*\)'\$/\1/p" "$engine_root/notproton-engine.env" 2>/dev/null | head -1 \
    | sed "s/'\\\\''/'/g"
}
if [ -f "$engine_root/notproton-engine.env" ]; then
  env_unix=$(engine_env_get NP_ENGINE_UNIX_DIR)
  env_loader=$(engine_env_get NP_ENGINE_WINELOADER)
  env_server=$(engine_env_get NP_ENGINE_WINESERVER)
  [ -n "$env_unix" ] && wine_unix=$env_unix
  [ -n "$env_loader" ] && WINELOADER=$env_loader
  [ -n "$env_server" ] && WINESERVER=$env_server
fi
export WINELOADER WINESERVER
bridge_src="$support/bridge"
# Dormison searches WINEDLLPATH after its own tree (set_dll_path), so this adds
# lsteamclient, which the engine does not ship, and never shadows an engine DLL.
export WINEDLLPATH="$bridge_src"
export PATH="$engine_root/wine/bin:$PATH"
# Dormison's View menu saves a setting through $SEVO_CLI and falls back to
# Sevoflurane's /usr/local/bin/sevo when that is unset. NotProton never calls
# Sevoflurane (docs/DECISIONS.md S1), so it always names this stand-in.
sevo_cli="$support/notproton-sevo"
export SEVO_CLI="$sevo_cli"

if [ -n "$STEAM_COMPAT_DATA_PATH" ]; then
  log="$STEAM_COMPAT_DATA_PATH/notproton-run.log"
else
  log=/dev/null
fi
[ "$(stat -f %z "$log" 2>/dev/null || echo 0)" -gt 262144 ] \
  && : > "$log" || true
run_started=$(date +%s)
{
  echo "=== notproton run $(date) ==="
  echo "verb=$verb"
  echo "args:"; for a in "$@"; do echo "  [$a]"; done
  echo "cwd=$(pwd)"
  echo "STEAM_COMPAT_DATA_PATH=$STEAM_COMPAT_DATA_PATH"
  echo "STEAM_COMPAT_INSTALL_PATH=$STEAM_COMPAT_INSTALL_PATH"
  echo "STEAM_COMPAT_APP_ID=$STEAM_COMPAT_APP_ID"
  echo "-- steam env passed through --"
  env | grep -iE '^(Steam|SDL_)' | sort
} >> "$log" 2>&1 || true

stage_step="startup"
[ -x "$WINELOADER" ] && [ -x "$WINESERVER" ] || {
  echo "=== no Dormison engine at $engine_root, set it up in NotProton ===" >> "$log" 2>&1 || true
  exit 1; }
echo "engine: $(readlink "$engine_root" 2>/dev/null || echo "$engine_root")" \
  >> "$log" 2>&1 || true

# The stand-in SEVO_CLI names. Dormison runs it as
# "app config <appid> <key> <value>" when a View menu setting changes. It logs the
# call and hands it to lullaby-settings, which stores the choice in the game's
# settings and rewrites its env files, so the choice holds on the next launch.
sevo_stub=$(cat <<'STUB'
#!/bin/sh
# NotProton's stand-in for Sevoflurane's sevo CLI (docs/DECISIONS.md S1, P7A-5).
log="$HOME/Library/Application Support/notproton/notproton-sevo.log"
printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$log" 2>/dev/null
cli="$HOME/Library/Application Support/notproton/lullaby-settings"
[ "$1" = app ] && [ "$2" = config ] && [ -x "$cli" ] || exit 0
"$cli" "$@" >> "$log" 2>&1
exit 0
STUB
)
if [ "$(cat "$sevo_cli" 2>/dev/null)" != "$sevo_stub" ]; then
  printf '%s\n' "$sevo_stub" > "$sevo_cli.new" && chmod 755 "$sevo_cli.new" \
    && mv -f "$sevo_cli.new" "$sevo_cli" \
    || echo "=== could not write $sevo_cli ===" >> "$log" 2>&1 || true
fi
# shellcheck disable=SC2329 # the trap below invokes this
report_early_exit() {
  status=$?
  [ "$status" = 0 ] && return 0
  echo "=== aborted during $stage_step (exit $status) before launch ===" \
    >> "$log" 2>&1 || true
}
trap report_early_exit EXIT

while :; do
  case "$STEAM_COMPAT_INSTALL_PATH" in
    ?*/) STEAM_COMPAT_INSTALL_PATH="${STEAM_COMPAT_INSTALL_PATH%/}" ;;
    *) break ;;
  esac
done
export STEAM_COMPAT_INSTALL_PATH

app_id="$STEAM_COMPAT_APP_ID"
case "$app_id" in ''|0) app_id="$SteamAppId" ;; esac
case "$app_id" in ''|0) app_id=$(basename "$STEAM_COMPAT_DATA_PATH" 2>/dev/null) ;; esac
case "$app_id" in ''|*[!0-9]*) app_id=0 ;; esac
echo "app_id=$app_id (STEAM_COMPAT_APP_ID=$STEAM_COMPAT_APP_ID)" >> "$log" 2>&1 || true

# Steam does not set SteamAppId or SteamGameId for helpers like the install-script
# evaluator. If they are set, SteamAPI_Init registers the helper as the running game so the
# real launch fails with AppError_16 (upstream NotProton 1.1.0). Non-Steam shortcuts come in
# as waitforexitandrun.
case "$verb" in
  waitforexitandrun)
    [ -n "$SteamAppId" ] || export SteamAppId="$app_id"
    [ -n "$SteamGameId" ] || export SteamGameId="$app_id"
    ;;
esac

prefix_machine() {
  dll="$WINEPREFIX/drive_c/windows/system32/ntdll.dll"
  [ -f "$dll" ] || return 1
  off=$(od -A n -t u4 -j 60 -N 4 "$dll" 2>/dev/null | tr -d ' ')
  case "$off" in ''|*[!0-9]*) return 1 ;; esac
  sig=$(od -A n -t x1 -j "$off" -N 4 "$dll" 2>/dev/null | tr -d ' \n')
  [ "$sig" = 50450000 ] || return 1
  od -A n -t x2 -j "$((off + 4))" -N 2 "$dll" 2>/dev/null | tr -d ' \n'
}

tool_name() {
  case "$1" in
    aa64) printf 'an ARM64 compatibility tool' ;;
    8664) printf 'Dormison' ;;
    *) printf 'an older 32-bit setup' ;;
  esac
}

refuse_foreign_prefix() {
  # Dormison runs Windows programs through Rosetta only: x86_64 prefixes.
  want=8664
  have=$(prefix_machine) || return 0
  [ "$have" = "$want" ] && return 0
  echo "=== prefix ntdll is $have and this compatibility tool wants $want, rebuild the prefix in NotProton ===" >> "$log" 2>&1 || true

  if [ "$verb" != run ]; then
    osascript >/dev/null 2>&1 <<APPLESCRIPT || true
display alert "This game needs its prefix rebuilt" message "This game originally ran under $(tool_name "$have"), but $(tool_name "$want") is present now. The prefix needs to be rebuilt in NotProton in order to run the game. You will not lose game saves by rebuilding the prefix." as critical
APPLESCRIPT
  fi
  exit 1
}
# Steam cloud related
merge_user_dir() {
  src=$1
  dst=$2
  failed=
  set -- ""
  while [ "$#" -gt 0 ]; do
    rest=$1
    shift
    src_dir="$src$rest"
    dst_dir="$dst$rest"
    if [ ! -r "$src_dir" ] || [ ! -x "$src_dir" ]; then failed=1; continue; fi
    if [ -L "$dst_dir" ] && [ ! -e "$dst_dir" ]; then
      rm -f "${dst_dir:?}" 2>/dev/null || true
    fi
    probe=$dst_dir
    through=
    while [ -n "$probe" ] && [ "$probe" != "$dst" ]; do
      if [ -L "$probe" ]; then through=1; break; fi
      probe=${probe%/*}
    done
    if [ -n "$through" ]; then
      echo "=== $rest is held by a link, merge refused ===" >> "$log" 2>&1 || true
      failed=1
      continue
    fi
    if [ -n "$rest" ] && [ -e "$dst_dir" ]; then continue; fi
    if ! mkdir -p "$dst_dir" 2>/dev/null; then failed=1; continue; fi
    for entry in "$src_dir"/* "$src_dir"/.[!.]* "$src_dir"/..?*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      name=${entry##*/}
      if [ -d "$entry" ] && [ ! -L "$entry" ]; then
        set -- "$@" "$rest/$name"
        continue
      fi
      landing="$dst_dir/$name"
      if [ -e "$landing" ]; then continue; fi
      if [ -L "$landing" ]; then rm -f "${landing:?}" 2>/dev/null || true; fi
      if [ -L "$entry" ]; then
        if ! cp -Pp "$entry" "$landing" 2>/dev/null; then
          rm -f "${landing:?}" 2>/dev/null || true
          failed=1
        fi
      else
        if ! cp -p "$entry" "$landing" 2>/dev/null; then
          rm -f "${landing:?}" 2>/dev/null || true
          failed=1
        fi
        chmod u+w "$landing" 2>/dev/null || true
      fi
    done
  done
  [ -z "$failed" ]
}

# Steam Cloud stuff
migrate_user_paths() {
  profile=$1
  for pair in \
    "Local Settings/Application Data|AppData/Local|../AppData/Local" \
    "Application Data|AppData/Roaming|./AppData/Roaming" \
    "My Documents|Documents|./Documents"; do
    old_rel=${pair%%|*}
    rest=${pair#*|}
    new_rel=${rest%%|*}
    link=${rest#*|}
    old="$profile/$old_rel"
    new="$profile/$new_rel"
    case "$(readlink "$new" 2>/dev/null || true)" in
      *"drive_c/users/steamuser/$old_rel") rm -f "${new:?}" 2>/dev/null || true ;;
    esac
    if [ -L "$new" ]; then
      echo "=== $new_rel is a link, rebuild the prefix for cloud saves ===" \
        >> "$log" 2>&1 || true
      continue
    fi
    held=
    for rel in "$old_rel" "$new_rel"; do
      probe=$rel
      while [ "$probe" != "${probe%/*}" ]; do
        probe=${probe%/*}
        if [ -L "$profile/$probe" ]; then held=$probe; break; fi
      done
      if [ -n "$held" ]; then break; fi
    done
    if [ -n "$held" ]; then
      echo "=== $held is a link, rebuild the prefix for cloud saves ===" \
        >> "$log" 2>&1 || true
      continue
    fi
    if [ -e "$old" ] && [ ! -L "$old" ]; then
      if ! merge_user_dir "$old" "$new"; then
        echo "=== $old_rel did not merge into $new_rel, left in place ===" \
          >> "$log" 2>&1 || true
        continue
      fi
      rmdir "$old BACKUP" 2>/dev/null || true
      if [ -e "$old BACKUP" ] || [ -L "$old BACKUP" ] \
        || ! mv "$old" "$old BACKUP" 2>> "$log"; then
        echo "=== $old_rel could not be moved aside, cloud saves stay split ===" \
          >> "$log" 2>&1 || true
        continue
      fi
    fi
    if [ ! -e "$old" ] && [ ! -L "$old" ]; then
      mkdir -p "${old%/*}" 2>/dev/null || true
      ln -s "$link" "$old" 2>/dev/null \
        || echo "=== $old_rel could not be aliased onto $new_rel ===" >> "$log" 2>&1 \
        || true
    elif [ -L "$old" ] && [ "$(readlink "$old")" != "$link" ]; then
      rm -f "${old:?}" 2>/dev/null || true
      ln -s "$link" "$old" 2>/dev/null \
        || echo "=== $old_rel could not be aliased onto $new_rel ===" >> "$log" 2>&1 \
        || true
    fi
  done
}

lay_out_proton_profile() {
  users="$WINEPREFIX/drive_c/users"
  if [ -d "$users/crossover" ] && [ ! -L "$users/crossover" ]; then
    echo "=== prefix predates the steamuser layout, rebuild it for cloud saves ===" \
      >> "$log" 2>&1 || true
    return 0
  fi
  profile="$users/steamuser"
  if [ -L "$profile" ]; then
    echo "=== the profile is a link, rebuild the prefix for cloud saves ===" \
      >> "$log" 2>&1 || true
    return 0
  fi
  mkdir -p "$profile" 2>/dev/null || return 0
  for folder in Documents Desktop Downloads Music Pictures Videos Templates \
      AppData/Local AppData/Roaming; do
    mkdir -p "$profile/$folder" 2>/dev/null || true
  done
  migrate_user_paths "$profile"
  if [ -L "$users/crossover" ] && [ ! -e "$users/crossover" ]; then
    rm -f "${users:?}/crossover" 2>/dev/null || true
  fi
  if [ ! -e "$users/crossover" ] \
    && ln -s steamuser "$users/crossover" 2>/dev/null; then
    echo "=== pointed crossover at steamuser ===" >> "$log" 2>&1 || true
  fi
  # Dormison names the profile after the macOS account (USER, else the password
  # entry; set_home_dir in dlls/ntdll/unix/loader.c), so that name leads to
  # steamuser as well, where Steam Cloud looks for saves.
  mac_user=${USER:-$(id -un 2>/dev/null || true)}
  case "$mac_user" in
    ''|steamuser|crossover|*/*|*\\*) return 0 ;;
  esac
  if [ -L "$users/$mac_user" ] && [ ! -e "$users/$mac_user" ]; then
    rm -f "${users:?}/${mac_user:?}" 2>/dev/null || true
  fi
  if [ ! -e "$users/$mac_user" ]; then
    ln -s steamuser "$users/$mac_user" 2>/dev/null \
      && echo "=== pointed $mac_user at steamuser ===" >> "$log" 2>&1 || true
  elif [ ! -L "$users/$mac_user" ]; then
    echo "=== $mac_user is a profile of its own, not steamuser ===" >> "$log" 2>&1 || true
  fi
}

# Sets KEY=VALUE in an env file in Dormison's format (dlls/ntdll/unix/env.c:
# one KEY=VALUE per line, no quoting), replacing the first KEY line, dropping
# any later ones, or appending it.
env_file_set() {
  file=$1
  key=$2
  value=$3
  if [ -f "$file" ]; then
    awk -v k="$key" -v v="$value" '
      { line = $0; sub(/^[ \t]+/, "", line) }
      index(line, k "=") == 1 { if (!done) print k "=" v; done = 1; next }
      { print }
      END { if (!done) print k "=" v }' "$file" > "$file.np-new" \
      && mv -f "$file.np-new" "$file"
  else
    printf '%s=%s\n' "$key" "$value" > "$file"
  fi
}

# Dormison applies <prefix>/.sevo/bottle.env at the start of every process in
# the prefix, then .sevo/apps/<program>.env (load_sevo_env). A new prefix gets
# NotProton's defaults; after that the keys are the user's and stay, except the
# two this script owns: WINEMSYNC, which only the bottle file may set and the
# server has to share, and SEVO_CLI (S1).
write_bottle_env() {
  sevo="$WINEPREFIX/.sevo"
  bottle="$sevo/bottle.env"
  mkdir -p "$sevo/apps" || return 0
  if [ ! -f "$bottle" ]; then
    cat > "$bottle" <<'BOTTLE'
# Dormison settings for every program in this prefix, first written by NotProton.
# One KEY=VALUE per line; .sevo/apps/<program>.env overrides them per program.
SEVO_RESIZABLE_WINDOWS=1
SEVO_UPSCALER=off
SEVO_FINAL_FILTER=lanczos
SEVO_FPS=0
SEVO_FPS_GRAPH=0
SEVO_LINEAR_MOUSE=0
SEVO_CURSOR_CONFINE=0
BOTTLE
  fi
  env_file_set "$bottle" WINEMSYNC "$WINEMSYNC"
  env_file_set "$bottle" SEVO_CLI "$sevo_cli"
  echo "bottle.env: $(grep -v '^#' "$bottle" | tr '\n' ' ')" >> "$log" 2>&1 || true
}

# A value the game's own env file (then the prefix's) sets, for the keys that are
# NotProton's rather than the engine's: the engine reads those files itself.
exe_lc=$(basename "$1" | tr '[:upper:]' '[:lower:]')
env_value() {
  for f in "$WINEPREFIX/.sevo/apps/$exe_lc.env" "$WINEPREFIX/.sevo/bottle.env"; do
    v=$(sed -n "s/^$1=//p" "$f" 2>/dev/null | head -1)
    if [ -n "$v" ]; then printf '%s' "$v"; return 0; fi
  done
  return 0
}
# A Wine registry switch a setting asks for, as y or nothing (deleted), in .reg form.
reg_switch_line() {
  if [ "$2" = 1 ]; then printf '"%s"="y"' "$1"; else printf '"%s"=-' "$1"; fi
}

controller_ids() {
  printf '%s\n' "$1" | tr ',' '\n' | tr 'A-F' 'a-f' \
    | sed -n 's/^[[:space:]]*0x\([0-9a-f]\{4\}\)\/0x\([0-9a-f]\{4\}\)[[:space:]]*$/\1\/\2/p' \
    | sort -u
}

ids_without() {
  printf '%s\n' "$2" -- "$1" \
    | awk '$0 == "--" { s = 1; next } !s { b[$0]; next } $0 != "" && !($0 in b)'
}

hidraw_lines() {
  printf '%s\n' "$2" | while read -r id; do
    [ -n "$id" ] || continue
    if [ "$1" = add ]; then
      printf '%s\r\n' "[HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\WineBus\\Devices\\$id]" \
        '"Hidraw"=dword:00000000' ''
    else
      printf '%s\r\n' "[-HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\WineBus\\Devices\\$id]" ''
    fi
  done
}

write_owned_controllers() {
  if printf '%s\n' "$1" | sed '/^$/d' | sort -u > "$controllers_file.new" \
    && mv -f "$controllers_file.new" "$controllers_file"; then
    return 0
  fi
  rm -f "$controllers_file.new"
  return 1
}

# Steam Input (upstream NotProton 1.1.x, "Fixes Steam Input issues", GPL-3.0). Proton hides
# the controllers that Steam Input handles from the Wine process. winebus still reads a few
# directly (DualSense, DualShock 4, Switch 1 Pro Controller and Joy-Cons: is_hidraw_enabled in
# dlls/winebus.sys/main.c, the same in Dormison), so Hidraw=0 hides those too. The Switch
# controllers get Hidraw=0 even when Steam Input is off, to avoid silently breaking
# controller support in most games. NOTPROTON_RAW_CONTROLLERS=1 in the launch options
# hands every controller back to the game.
plan_hidden_controllers() {
  controllers_file="$STEAM_COMPAT_DATA_PATH/notproton-hidden-controllers"
  controllers_add=""
  controllers_remove=""
  controllers_wanted=""
  [ -n "$STEAM_COMPAT_DATA_PATH" ] && [ ! -L "$controllers_file" ] || return 1
  owned=""
  [ ! -f "$controllers_file" ] || owned=$(sed -n '/^[0-9a-f]\{4\}\/[0-9a-f]\{4\}$/p' "$controllers_file")
  in_registry=""
  [ ! -f "$WINEPREFIX/system.reg" ] || in_registry=$(tr '[:upper:]' '[:lower:]' < "$WINEPREFIX/system.reg" \
    | sed -n 's/^\[system\\\\controlset001\\\\services\\\\winebus\\\\devices\\\\\([0-9a-f]\{4\}\/[0-9a-f]\{4\}\)\].*/\1/p' \
    | sort -u)
  if [ "$NOTPROTON_RAW_CONTROLLERS" != "1" ]; then
    controllers_wanted=$(ids_without "$(controller_ids "$SDL_GAMECONTROLLER_IGNORE_DEVICES")" \
      "$(controller_ids "$SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT")")
    controllers_wanted=$(printf '%s\n' "$controllers_wanted" 057e/2006 057e/2007 057e/2009 | sed '/^$/d' | sort -u)
    # Steam sends install scripts no ignore list. Keep the game's hidden controllers instead of clearing them.
    if [ "$verb" = run ]; then
      controllers_wanted=$(printf '%s\n' "$controllers_wanted" "$owned" | sed '/^$/d' | sort -u)
    fi
    controllers_wanted=$(ids_without "$controllers_wanted" "$(ids_without "$in_registry" "$owned")")
  fi
  controllers_add=$(ids_without "$controllers_wanted" "$in_registry")
  controllers_remove=$(ids_without "$owned" "$controllers_wanted")
  write_owned_controllers "$owned
$controllers_wanted"
}

# The prefix's registry for this launch, in one Wine process: under Rosetta every Wine
# process costs about a second, and a reg add per key ran a dozen of them before each game
# (measured 09.10; upstream NotProton 1.1.0, "Make games start about two seconds faster").
# Each prefix is one game's, so the prefix-wide keys are the game's own. RetinaMode is read
# with no program key at all (winemac.drv), EmulateModeset by win32u for every program,
# explorer.exe included. Command reaches every game as Control and Option as Alt (DECISIONS
# P7A-20); winemac.drv's own default is the other way round.
import_prefix_settings() {
  # A new prefix has no C: drive to hand the file over through yet: wineboot builds it.
  if [ ! -d "$WINEPREFIX/drive_c" ]; then
    "$WINELOADER" wineboot --init >> "$log" 2>&1 || true
  fi
  echo "video: RetinaMode=${NOTPROTON_RETINA:-0} EmulateModeset=${NOTPROTON_EMULATE_MODESET:-0}" >> "$log" 2>&1 || true
  echo "keyboard: Command is Control, Option is Alt" >> "$log" 2>&1 || true
  controllers_planned=0
  if plan_hidden_controllers 2>/dev/null; then
    controllers_planned=1
  else
    controllers_add=""
    controllers_remove=""
    echo "=== could not track the hidden controllers, leaving them as they are ===" >> "$log" 2>&1 || true
  fi
  settings_file=$(mktemp "$WINEPREFIX/drive_c/lullaby-settings.XXXXXX" 2>/dev/null) \
    || settings_file=""
  if [ -z "$settings_file" ] || ! { printf '%s\r\n' \
      'Windows Registry Editor Version 5.00' '' \
      '[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug]' '"Auto"="0"' '' \
      '[HKEY_LOCAL_MACHINE\Software\Wow6432Node\Microsoft\Windows NT\CurrentVersion\AeDebug]' '"Auto"="0"' '' \
      '[HKEY_CURRENT_USER\Software\Wine\WineDbg]' '"ShowCrashDialog"=dword:00000000' '' \
      '[HKEY_CURRENT_USER\Software\Wine\Mac Driver]' "$(reg_switch_line RetinaMode "$NOTPROTON_RETINA")" \
      '"LeftCommandIsCtrl"="y"' '"RightCommandIsCtrl"="y"' '"LeftOptionIsAlt"="y"' '"RightOptionIsAlt"="y"' '' \
      '[HKEY_CURRENT_USER\Software\Wine\X11 Driver]' \
      "$(reg_switch_line EmulateModeset "$NOTPROTON_EMULATE_MODESET")" '' \
      '[HKEY_LOCAL_MACHINE\Software\Classes\steam]' '"URL Protocol"=""' '' \
      '[HKEY_LOCAL_MACHINE\Software\Classes\steam\shell\open\command]' \
      '@="\"C:\\Program Files (x86)\\Steam\\steam.exe\" \"%1\""' '' \
      && hidraw_lines add "$controllers_add" && hidraw_lines remove "$controllers_remove"; } \
      > "$settings_file" 2>/dev/null; then
    [ -z "$settings_file" ] || rm -f "$settings_file"
    echo "=== could not write the prefix settings, launching without them ===" >> "$log" 2>&1 || true
    # the bridge staging still needs a built prefix
    "$WINELOADER" wineboot --init >> "$log" 2>&1 || true
    return 0
  fi
  "$WINELOADER" reg import "C:\\${settings_file##*/}" >> "$log" 2>&1 \
    && import_status=0 || import_status=$?
  rm -f "$settings_file"
  if [ "$import_status" -eq 0 ] && [ "$controllers_planned" -eq 1 ]; then
    write_owned_controllers "$controllers_wanted" 2>/dev/null || true
    if [ -n "$controllers_add$controllers_remove" ]; then
      # Wine only reads these keys when it starts, so restart Wine to apply them.
      "$WINESERVER" -k >> "$log" 2>&1 || true
      "$WINESERVER" -w >> "$log" 2>&1 || true
    fi
    if [ "$NOTPROTON_RAW_CONTROLLERS" = "1" ]; then
      echo "controllers: games read them directly (NOTPROTON_RAW_CONTROLLERS=1)" >> "$log" 2>&1 || true
    elif [ -n "$controllers_wanted" ]; then
      echo "controllers: $(printf '%s\n' "$controllers_wanted" | grep -c .) kept off hidraw" \
        >> "$log" 2>&1 || true
    fi
  fi
  [ "$import_status" -eq 0 ] \
    || echo "=== prefix settings import exited status=$import_status ===" >> "$log" 2>&1 || true
}
if [ -n "$STEAM_COMPAT_DATA_PATH" ]; then
  export WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx"
  mkdir -p "$WINEPREFIX"
  stage_step="prefix arch check"
  refuse_foreign_prefix
  # The settings catalog (lullaby-settings, docs/ROADMAP.md, section 4): it records this
  # game's programs, brings a prefix from before the catalog into it, and writes
  # .sevo/bottle.env and every program's file before anything starts.
  stage_step="game settings"
  settings_cli="$support/lullaby-settings"
  if [ -x "$settings_cli" ] && [ "$app_id" != 0 ]; then
    if "$settings_cli" launch --app "$app_id" --exe "$1" --prefix "$WINEPREFIX" \
      ${STEAM_COMPAT_INSTALL_PATH:+--install} ${STEAM_COMPAT_INSTALL_PATH:+"$STEAM_COMPAT_INSTALL_PATH"} \
      >> "$log" 2>&1; then
      echo "settings: .sevo written by lullaby-settings" >> "$log" 2>&1 || true
    else
      echo "=== lullaby-settings failed, the prefix keeps its files ===" >> "$log" 2>&1 || true
    fi
  fi
  # NotProton's own keys: a launch option first, then the program's file, then
  # bottle.env (the engine reads its SEVO_* keys from those files itself).
  [ -n "$NOTPROTON_RETINA" ] || NOTPROTON_RETINA=$(env_value NOTPROTON_RETINA)
  [ -n "$NOTPROTON_EMULATE_MODESET" ] || NOTPROTON_EMULATE_MODESET=$(env_value NOTPROTON_EMULATE_MODESET)
  [ -n "$NOTPROTON_DLSS" ] || NOTPROTON_DLSS=$(env_value NOTPROTON_DLSS)
  msync_from=launch-options
  # msync+ is Dormison's sync and stays on; the catalog's per-game debugging switch
  # (NOTPROTON_MSYNC in bottle.env) can turn it off. A prefix from before the
  # catalog carries the old marker instead.
  if [ -z "$WINEMSYNC" ]; then
    WINEMSYNC=$(sed -n 's/^NOTPROTON_MSYNC=//p' "$WINEPREFIX/.sevo/bottle.env" 2>/dev/null | head -1)
    [ -n "$WINEMSYNC" ] && msync_from=settings
  fi
  if [ -z "$WINEMSYNC" ] && [ -r "$STEAM_COMPAT_DATA_PATH/notproton-msync" ] \
    && [ -f "$WINEPREFIX/.sevo/bottle.env" ]; then
    WINEMSYNC=$(tr -d ' \t\n' \
      < "$STEAM_COMPAT_DATA_PATH/notproton-msync" 2>/dev/null || true)
    msync_from=carried-over
  fi
  [ -n "$WINEMSYNC" ] || msync_from=default
  export WINEMSYNC="${WINEMSYNC:-1}"
  echo "sync: WINEMSYNC=$WINEMSYNC from $msync_from" >> "$log" 2>&1 || true
  stage_step="bottle settings"
  write_bottle_env
  "$WINESERVER" -k >> "$log" 2>&1 || true
  stage_step="profile layout"
  lay_out_proton_profile
  stage_step="prefix settings"
  import_prefix_settings
fi

prefix_steam="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
# The engine's ntdll.dll, x86_64 and i386, has to carry the steamclient ->
# lsteamclient hook for a game to reach lsteamclient (B1, docs/DECISIONS.md P3-1:
# ntdll-patch/b1/install-b1.sh puts the pair in the engine and the bridge).
verify_runner() {
  for arch in x86_64 i386; do
    staged="$bridge_src/wine/$arch-windows/ntdll.dll"
    live="$engine_root/wine/lib/wine/$arch-windows/ntdll.dll"
    if [ ! -f "$staged" ]; then
      echo "=== no patched $arch ntdll in the bridge, $arch games will not reach lsteamclient ===" >> "$log" 2>&1 || true
    elif ! cmp -s "$staged" "$live"; then
      echo "=== the engine's $arch ntdll is not the patched copy, run ntdll-patch/b1/install-b1.sh ===" >> "$log" 2>&1 || true
    elif grep -a -q "lead to lsteamclient" "$live" 2>/dev/null; then
      echo "runner: $arch ntdll is the patched copy (B1)" >> "$log" 2>&1 || true
    else
      echo "runner: $arch ntdll is the patched copy" >> "$log" 2>&1 || true
    fi
  done
  for f in x86_64-windows/lsteamclient.dll i386-windows/lsteamclient.dll x86_64-unix/lsteamclient.so; do
    [ -f "$bridge_src/$f" ] && continue
    echo "=== bridge is missing $f ===" >> "$log" 2>&1 || true
  done
}
install_lsteamclient_trigger() {
  src="$bridge_src/i386-windows/lsteamclient.dll"
  dst="$WINEPREFIX/drive_c/windows/syswow64/lsteamclient.dll"
  [ -f "$src" ] && [ -d "$WINEPREFIX/drive_c/windows/syswow64" ] || return 0
  cmp -s "$src" "$dst" && return 0
  if cp -f "$src" "$dst"; then
    echo "=== installed syswow64 lsteamclient trigger ===" >> "$log" 2>&1 || true
  else
    echo "=== could not install the syswow64 lsteamclient trigger ===" >> "$log" 2>&1 || true
  fi
}

# A fix to match Proton
install_legacy_steam_dll() {
  src="$bridge_src/legacycompat/Steam.dll"
  dst="$WINEPREFIX/drive_c/windows/syswow64/Steam.dll"
  [ -f "$src" ] && [ -d "$WINEPREFIX/drive_c/windows/syswow64" ] || return 0
  cmp -s "$src" "$dst" && return 0
  if cp -f "$src" "$dst"; then
    echo "=== installed legacy Steam.dll ===" >> "$log" 2>&1 || true
  else
    echo "=== could not install the legacy Steam.dll ===" >> "$log" 2>&1 || true
  fi
}

# Steam runs a Windows game's installscript.vdf by invoking the standalone
# evaluator through the compat tool, the same way the linux client does, but
# the binaries are missing on macOS, so...
install_legacycompat() {
  src="$bridge_src/legacycompat"
  dst="$STEAM_COMPAT_CLIENT_INSTALL_PATH/legacycompat"
  [ -d "$src" ] && [ -n "$STEAM_COMPAT_CLIENT_INSTALL_PATH" ] || return 0
  mkdir -p "$dst" || return 0
  for f in "$src"/*; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    cmp -s "$f" "$dst/$b" && continue
    cp -f "$f" "$dst/$b" && \
      echo "=== installed legacycompat/$b ===" >> "$log" 2>&1
  done
}

bridge_files="steamclient64.dll steamclient.dll tier0_s64.dll vstdlib_s64.dll"
bridge_files="$bridge_files lsteamclient.dll lsteamclient.so steam.exe"
if [ -d "$bridge_src" ] && [ -n "$WINEPREFIX" ]; then
  stage_step="bridge staging"
  mkdir -p "$prefix_steam"
  for f in $bridge_files; do
    src="$bridge_src/$f"
    if [ "$f" = lsteamclient.so ]; then
      src="$bridge_src/${wine_unix##*/}/$f"
    fi
    if [ ! -f "$src" ]; then
      echo "=== bridge missing $f ===" >> "$log" 2>&1 || true
      continue
    fi
    # A clone (APFS) costs no space and a fifth of the time; a copy where cloning cannot work.
    cp -c -f "$src" "$prefix_steam/$f" 2>/dev/null || cp -f "$src" "$prefix_steam/$f" || \
      echo "=== failed to stage $f ===" >> "$log" 2>&1
  done
  for f in "$prefix_steam"/*.dll "$prefix_steam"/*.so "$prefix_steam"/*.exe; do
    [ -f "$f" ] || continue
    case " $bridge_files " in
      *" $(basename "$f") "*) ;;
      *) rm -f "${f:?}" && echo "=== pruned stale $(basename "$f") ===" >> "$log" 2>&1 ;;
    esac
  done
  verify_runner
  install_lsteamclient_trigger
  install_legacy_steam_dll
  export WINEDLLPATH="$prefix_steam:$WINEDLLPATH"
  export WINEDLLOVERRIDES="steamclient=n;steamclient64=n;lsteamclient=b"
  native_client="$STEAM_COMPAT_CLIENT_INSTALL_PATH"
  if [ -z "$native_client" ]; then
    native_client="$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$native_client"
  fi
  install_legacycompat
  echo "=== bridge staged into $prefix_steam ===" >> "$log" 2>&1 || true
  echo "WINEDLLPATH=$WINEDLLPATH" >> "$log" 2>&1 || true
  echo "STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_COMPAT_CLIENT_INSTALL_PATH" >> "$log" 2>&1 || true
fi

# The renderer reaches every program of this launch through WINEDLLPATH_PREPEND,
# which Dormison searches ahead of its own tree (set_dll_path), so the engine's
# files stay as shipped. Each renderer directory links into runners/current, so
# it follows an engine switch. DXMT is the default for D3D10 and D3D11.
renderers="$support/renderers"
stage_renderer() {
  dir="$renderers/$1"
  case "$1" in
    dxmt|dxmt-nvext)
      mkdir -p "$dir/x86_64-windows" "$dir/i386-windows" "$dir/x86_64-unix" || return 1
      for f in d3d11 d3d10core dxgi winemetal; do
        ln -sfn "$engine_root/dxmt/$f.dll" "$dir/x86_64-windows/$f.dll"
        ln -sfn "$engine_root/dxmt/i386-windows/$f.dll" "$dir/i386-windows/$f.dll"
      done
      # DLSS -> MetalFX (the catalog's experimental switch): DXMT's own NVAPI and NGX
      # answer the game, from a directory of their own so that no other game loads
      # them. The prefix holds files of both names (Wine's), as the loader requires.
      if [ "$1" = dxmt-nvext ]; then
        for f in nvapi64 nvngx; do
          ln -sfn "$engine_root/dxmt/$f.dll" "$dir/x86_64-windows/$f.dll"
        done
      fi
      # Wine looks for a builtin's unix half beside the directory it found the
      # PE in, and winemetal's is the engine's (32 bit games reach it via wow64).
      ln -sfn "$wine_unix/winemetal.so" "$dir/x86_64-unix/winemetal.so"
      # Wine takes a builtin off the dll path only for a name the prefix holds a
      # file for (find_builtin_without_file in dlls/ntdll/loader.c skips the dll
      # path otherwise), and winemetal is not one of Wine's own, so its builtin
      # copy goes into the prefix as that file. The loader then takes the image
      # from the dll path, where the renderer directory comes first.
      if [ -n "$WINEPREFIX" ]; then
        for pair in "system32:dxmt" "syswow64:dxmt/i386-windows"; do
          sysdir="$WINEPREFIX/drive_c/windows/${pair%%:*}"
          src="$engine_root/${pair#*:}/winemetal.dll"
          [ -d "$sysdir" ] || continue
          cmp -s "$src" "$sysdir/winemetal.dll" && continue
          cp -f "$src" "$sysdir/winemetal.dll" || return 1
        done
      fi
      # In this order: Dormison names the renderer in its sevo:gfx log line by
      # finding "d3d10core,d3d11" in WINEDLLOVERRIDES (sevo_provenance.c).
      renderer_overrides="d3d10core,d3d11,dxgi,winemetal=b"
      [ "$1" = dxmt-nvext ] && renderer_overrides="$renderer_overrides;nvapi64,nvngx=n,b"
      ;;
    dxvk)
      mkdir -p "$dir/x86_64-windows" || return 1
      for f in d3d11 d3d10core; do
        ln -sfn "$engine_root/dxvk/$f.dll" "$dir/x86_64-windows/$f.dll"
      done
      renderer_overrides="d3d11,d3d10core=b"
      ;;
    d3dmetal)
      # Apple's D3DMetal from the player's Game Porting Toolkit (notproton/d3dmetal/<version>,
      # named by NOTPROTON_D3DMETAL in bottle.env). Its macOS half goes into the running
      # engine's wine/lib/external, where the engine's x86_64-unix/{d3d11,d3d12,dxgi,...}.so
      # links lead (Apple's layout); doing it at every D3DMetal launch is what carries it into
      # a new engine after an update or a roll-back. The Windows DLLs reach this game alone
      # from the renderer directory, their unix halves beside them.
      tk="$NOTPROTON_D3DMETAL"
      [ -n "$tk" ] && [ -f "$tk/lib/external/libd3dshared.dylib" ] || {
        echo "=== D3DMetal is not installed: add Apple's Game Porting Toolkit in Steam ===" >> "$log" 2>&1 || true
        return 1; }
      ext="$engine_root/wine/lib/external"
      if ! cmp -s "$tk/lib/external/libd3dshared.dylib" "$ext/libd3dshared.dylib" \
        || ! cmp -s "$tk/lib/external/D3DMetal.framework/Versions/A/D3DMetal" \
          "$ext/D3DMetal.framework/Versions/A/D3DMetal"; then
        mkdir -p "$ext" && ditto "$tk/lib/external" "$ext" || return 1
        echo "d3dmetal: $(basename "$tk") delivered into $(readlink "$engine_root" 2>/dev/null || echo "$engine_root")" >> "$log" 2>&1 || true
      fi
      rm -rf "${dir:?}" && mkdir -p "$dir/x86_64-windows" "$dir/x86_64-unix" || return 1
      names=""
      for f in "$tk/lib/wine/x86_64-windows"/*.dll; do
        [ -f "$f" ] || continue
        b=$(basename "$f" .dll)
        ln -sfn "$f" "$dir/x86_64-windows/$b.dll"
        ln -sfn "$wine_unix/$b.so" "$dir/x86_64-unix/$b.so"
        names="${names:+$names,}$b"
      done
      [ -n "$names" ] || return 1
      renderer_overrides="$names=b"
      export SEVO_LIBD3DSHARED_PATH="$ext/libd3dshared.dylib" D3DM_WINE_UNIX_CALL=1
      ;;
    *) return 1 ;;
  esac
  for f in "$dir"/*/*; do
    [ -e "$f" ] && continue
    echo "=== renderer $1: $f leads nowhere in this engine ===" >> "$log" 2>&1 || true
    return 1
  done
}
# Launch option first (the Steam page's renderer list, or the old CX_GRAPHICS_BACKEND
# some games still carry), then the game's Game Settings.
renderer="${NOTPROTON_RENDERER:-${CX_GRAPHICS_BACKEND:-$(env_value NOTPROTON_RENDERER)}}"
renderer="${renderer:-dxmt}"
[ -n "$NOTPROTON_D3DMETAL" ] || NOTPROTON_D3DMETAL=$(env_value NOTPROTON_D3DMETAL)
case "$renderer" in
  dxmt|dxvk|wined3d|d3dmetal) ;;
  *)
    echo "=== unknown renderer $renderer, using DXMT ===" >> "$log" 2>&1 || true
    renderer=dxmt ;;
esac
unset WINEDLLPATH_PREPEND
renderer_dir="$renderer"
if [ "$renderer" = dxmt ] && [ "$NOTPROTON_DLSS" = 1 ]; then
  renderer_dir=dxmt-nvext
  echo "renderer: DLSS -> MetalFX through DXMT (experimental)" >> "$log" 2>&1 || true
fi
if [ "$renderer" != wined3d ]; then
  if stage_renderer "$renderer_dir"; then
    export WINEDLLPATH_PREPEND="$renderers/$renderer_dir"
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}$renderer_overrides"
  elif [ "$renderer" = d3dmetal ] && stage_renderer dxmt; then
    echo "=== $renderer unavailable, using DXMT ===" >> "$log" 2>&1 || true
    renderer=dxmt
    export WINEDLLPATH_PREPEND="$renderers/dxmt"
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}$renderer_overrides"
  else
    renderer=wined3d
  fi
fi
echo "renderer: $renderer${WINEDLLPATH_PREPEND:+ from $WINEDLLPATH_PREPEND}" >> "$log" 2>&1 || true
if [ -n "$launch_dll_overrides" ]; then
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}$launch_dll_overrides"
fi
echo "WINEDLLOVERRIDES=$WINEDLLOVERRIDES" >> "$log" 2>&1 || true

# Vulkan (DXVK, and every game that probes it) goes to the engine's own MoltenVK. The loader
# finds the engine's ICD manifest beside the main executable only, and a game runs from its
# bundle's copy of the loader, so without this it takes whatever /usr/local offers
# (KosmicKrisp, another MoltenVK) and DXVK fails on VK_KHR_surface (DECISIONS P7A-18).
vk_icd="$wine_unix/vulkan/icd.d/MoltenVK_icd.json"
if [ -f "$vk_icd" ]; then
  export VK_DRIVER_FILES="$vk_icd" VK_ICD_FILENAMES="$vk_icd"
  echo "vulkan: $vk_icd" >> "$log" 2>&1 || true
fi

# loaddll is a line per module, cheap, and shows lsteamclient coming in.
export WINEDEBUG="${WINEDEBUG:-err+all,fixme-all,+loaddll}"
trap - EXIT
printf 'launch_env=%s\n' "$launch_env" >> "$log" 2>&1 || true
echo "prelaunch: $(( $(date +%s) - run_started )) s" >> "$log" 2>&1 || true
echo "=== launching ($verb): $WINELOADER $* ===" >> "$log" 2>&1 || true

target="$1"
# The verb decides the route, as in Linux Steam (upstream NotProton 1.1.0, "Fix EA launcher"):
# a game can arrive as a URL (steam2ea://, uplay://) with no install path to match.
case "$verb" in
  waitforexitandrun) foreground=1 ;;
  *) foreground=0 ;;
esac

shim_exe="C:\\Program Files (x86)\\Steam\\steam.exe"

if [ "$foreground" = 0 ]; then
  status=0  # set -e would exit before the status is read
  case "$verb" in
    # runinprefix is the one verb the Linux client keeps on the raw loader.
    runinprefix)
      echo "=== running helper on raw loader: $* ===" >> "$log" 2>&1 || true
      "$WINELOADER" "$@" >> "$log" 2>&1 || status=$?
      ;;
    *)
      # An install script, or a URL that steam.exe resolves.
      echo "=== running helper through the shim: $* ===" >> "$log" 2>&1 || true
      "$WINELOADER" "$shim_exe" "$@" >> "$log" 2>&1 || status=$?
      ;;
  esac
  echo "=== helper exited status=$status ===" >> "$log" 2>&1 || true
  exit $status
fi

# Window focus: the game is started through its own bundle (name and icon in the Dock)
steam_root="$(dirname "$(dirname "$(dirname "$STEAM_COMPAT_DATA_PATH")")")"
manifest="$steam_root/steamapps/appmanifest_$app_id.acf"
client_root="$STEAM_COMPAT_CLIENT_INSTALL_PATH"
while [ -n "$client_root" ] && [ "$client_root" != "/" ] && [ ! -d "$client_root/appcache" ]; do
  client_root=$(dirname "$client_root")
done
# Icon stuff
appinfo_tool="$HOME/Library/Application Support/notproton/appinfo"
appinfo_vdf="$client_root/appcache/appinfo.vdf"
meta_name=""
meta_icon=""
meta_clienticon=""
if [ -x "$appinfo_tool" ] && [ -f "$appinfo_vdf" ]; then
  meta=$("$appinfo_tool" "$appinfo_vdf" "$app_id" 2>> "$log") || meta=""
  meta_name=$(printf '%s\n' "$meta" | sed -n 's/^name=//p')
  meta_icon=$(printf '%s\n' "$meta" | sed -n 's/^icon=//p')
  meta_clienticon=$(printf '%s\n' "$meta" | sed -n 's/^clienticon=//p')
fi
game_name="$meta_name"
if [ -z "$game_name" ] && [ -f "$manifest" ]; then
  game_name=$(sed -n 's/.*"name"[[:space:]]*"\(.*\)".*/\1/p' "$manifest" | head -1)
fi
[ -z "$game_name" ] && game_name=$(basename "$STEAM_COMPAT_INSTALL_PATH")
[ -z "$game_name" ] && game_name="Steam Game"
# shellcheck disable=SC1003 # the pair deletes a literal backslash, not a quote
bundle_name=$(printf '%s' "$game_name" | tr -d '/:"`$\\')
game_name_xml=$(printf '%s' "$game_name" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
# Dormison's loader, started with no program from a bundle under a directory
# named only with digits, opens sevoflurane://play/<digits> (open_in_sevoflurane
# in loader/main.c). The prefix keeps this directory out of that pattern (S1).
loader_root="$support/launchers/app-$app_id"
mkdir -p "$loader_root"
loader_app="$loader_root/$bundle_name.app"
rm -rf "${loader_root:?}"/*.app
loader_contents="$loader_app/Contents"
loader_macos="$loader_contents/MacOS"
loader_res="$loader_contents/Resources"
mkdir -p "$loader_macos" "$loader_res"

icon_arg=""
resolve_icon() {
  set +e
  iconmaker="$HOME/Library/Application Support/notproton/iconmaker"
  art_dir="$client_root/appcache/librarycache/$app_id"
  art=""
  if [ -n "$meta_clienticon" ]; then
    ico="$loader_root/clienticon-$meta_clienticon.ico"
    absent="$loader_root/clienticon-$meta_clienticon.absent"
    find "${loader_root:?}" -maxdepth 1 -name 'clienticon-*'   ! -name "clienticon-$meta_clienticon.*" -delete 2>/dev/null || true
    find "${absent:?}" -mtime +14 -delete 2>/dev/null || true
    if [ ! -s "$ico" ] && [ ! -f "$absent" ]; then
      url="https://shared.fastly.steamstatic.com/community_assets/images/apps/$app_id/$meta_clienticon.ico"
      code=$(curl -fsL --connect-timeout 5 --max-time 20 -w '%{http_code}' -o "$ico.new" "$url" 2>>"$log")
      magic=$(od -An -tx1 -N4 "$ico.new" 2>/dev/null | tr -d ' \n')
      if [ "$magic" = "00000100" ]; then
        mv -f "$ico.new" "$ico"
        echo "fetched client icon $meta_clienticon" >> "$log" 2>&1 || true
      else
        rm -f "${ico:?}.new"
        if [ "$code" = "404" ]; then
          : > "$absent"
          echo "no client icon published for $meta_clienticon" >> "$log" 2>&1 || true
        else
          echo "client icon fetch for $meta_clienticon failed (http ${code:-none}), will retry" >> "$log" 2>&1 || true
        fi
      fi
    fi
    [ -s "$ico" ] && art="$ico"
  fi
  if [ -z "$art" ] && [ -n "$meta_icon" ] && [ -f "$art_dir/$meta_icon.jpg" ]; then
    art="$art_dir/$meta_icon.jpg"
  fi
  if [ -z "$art" ]; then
    art=$(find "$art_dir" -maxdepth 1 -type f -name '*.jpg' 2>/dev/null |   grep -E '/[0-9a-f]{40}\.jpg$' | head -1)
  fi
  # Capsule art (horrible) fallback if no icon at all exists...
  if [ -z "$art" ]; then
    for name in library_600x900.jpg header.jpg; do
      found=$(find "$art_dir" -name "$name" 2>/dev/null | head -1)
      [ -n "$found" ] && { art="$found"; break; }
    done
  fi
  # non-Steam shortcuts have no art, so (as a temporary measure while I think of
  # better ways to solve for this) let's use the icon in the EXE itself instead.
  if [ -z "$art" ] && [ -f "$target" ]; then
    case "$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')" in
      *.exe) art="$target" ;;
    esac
  fi
  icon_source=""
  if [ -n "$art" ]; then
    icon_source="$art $(stat -f %m "$art" 2>/dev/null || echo 0)"
  fi
  icon_cache="$loader_root/game.icns"
  if [ -n "$art" ] && [ -s "$icon_cache" ] &&   [ "$(cat "$loader_root/notproton-icon.source" 2>/dev/null)" =   "$icon_source" ] && cp -f "$icon_cache" "$loader_res/game.icns"; then
    icon_arg="  <key>CFBundleIconFile</key><string>game</string>"
    echo "icon reused from $art" >> "$log" 2>&1 || true
  elif [ -n "$art" ] && [ -x "$iconmaker" ]; then
    if "$iconmaker" "$art" "$icon_cache" >> "$log" 2>&1 &&   cp -f "$icon_cache" "$loader_res/game.icns"; then
      icon_arg="  <key>CFBundleIconFile</key><string>game</string>"
      printf '%s\n' "$icon_source" > "$loader_root/notproton-icon.source"
      echo "icon built from $art" >> "$log" 2>&1 || true
    elif [ "$art" = "$ico" ]; then
      # A cached .ico that iconmaker rejects is corrupt and passes the size
      # guard on every launch, so drop it to force a clean fetch next time.
      rm -f "${ico:?}"
      echo "discarded unreadable client icon $meta_clienticon" >> "$log" 2>&1 || true
    fi
  fi
  set -e
  return 0
}
resolve_icon || true
[ -n "$icon_arg" ] || echo "no icon resolved, launching without one" >> "$log" 2>&1 || true

uielement_arg=""
if [ "${NOTPROTON_HIDE_LAUNCHER_TILE:-0}" = "1" ]; then
  uielement_arg="  <key>LSUIElement</key><true/>"
  echo "launcher tile hidden by NOTPROTON_HIDE_LAUNCHER_TILE" >> "$log" 2>&1 || true
fi
cat > "$loader_contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$game_name_xml</string>
  <key>CFBundleDisplayName</key><string>$game_name_xml</string>
  <key>CFBundleIdentifier</key><string>com.ruslanukraina.lullaby.launcher.$app_id</string>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
$uielement_arg
$icon_arg
</dict>
</plist>
PLIST

# Invokes macOS Game Mode
for f in "$wine_unix"/*; do
  [ -e "$f" ] || continue
  base=${f##*/}
  case "$base" in
    wine|wine.app) continue ;;
  esac
  ln -sfn "$f" "$loader_macos/$base"
done
ln "$wine_unix/wine" "$loader_macos/wine" 2>/dev/null || cp "$wine_unix/wine" "$loader_macos/wine"
if [ -x "$loader_macos/wine" ]; then
  WINELOADER="$loader_macos/wine"
  echo "loader staged in bundle for game mode" >> "$log" 2>&1 || true
  # Dormison re-executes every Windows program through the loader its
  # .sevo/apps/<program>.env names in SEVO_LOADER, otherwise through the
  # engine's own (loader_exec in dlls/ntdll/unix/loader.c). Naming this copy
  # for the shim and the game keeps both in the bundle, which is where the Dock
  # name, the icon and Game Mode come from.
  if [ -n "$WINEPREFIX" ] && mkdir -p "$WINEPREFIX/.sevo/apps"; then
    printf '%s\n' "$(basename "$target" | tr '[:upper:]' '[:lower:]')" > "$WINEPREFIX/.sevo/game-exe"
    for program in steam.exe "$(basename "$target")"; do
      program=$(printf '%s' "$program" | tr '[:upper:]' '[:lower:]')
      [ -n "$program" ] || continue
      env_file_set "$WINEPREFIX/.sevo/apps/$program.env" SEVO_LOADER "$WINELOADER"
      echo "loader: .sevo/apps/$program.env SEVO_LOADER=$WINELOADER" >> "$log" 2>&1 || true
    done
  fi
else
  echo "loader staging failed, game mode unavailable" >> "$log" 2>&1 || true
fi

cat > "$loader_macos/launcher" <<LAUNCHER
#!/bin/sh
# Opened from the Dock or Finder there is nothing to run, and the loader
# started without a program would hand the game to Sevoflurane (S1).
case "\$#:\${1:-}" in 0:|1:-psn_*) exit 0 ;; esac
export WINELOADER="$WINELOADER"
# Where the bundle's loader finds ntdll.so. Its presence also keeps the loader
# from ever opening sevoflurane:// (S1).
export SEVO_LOADER_TREE="$wine_unix"
export SEVO_CLI="$sevo_cli"
wine_log="$loader_root/notproton-wine.log"
exec > "\$wine_log" 2>&1
shim="$HOME/Library/Application Support/notproton/overlay-shim.dylib"
if [ -n "\$STEAM_DYLD_INSERT_LIBRARIES" ]; then
  if [ -f "\$shim" ]; then
    export DYLD_INSERT_LIBRARIES="\$shim:\$STEAM_DYLD_INSERT_LIBRARIES"
    export NOTPROTON_OVERLAY_SHIM="\$shim"
  else
    export DYLD_INSERT_LIBRARIES="\$STEAM_DYLD_INSERT_LIBRARIES"
  fi
fi
[ -n "\$NOTPROTON_GAME_CWD" ] && cd "\$NOTPROTON_GAME_CWD"
"$WINELOADER" "\$@"
exit \$?
LAUNCHER
chmod +x "$loader_macos/launcher"

wine_helpers='winedevice\.exe|services\.exe|plugplay\.exe|svchost\.exe'
wine_helpers="$wine_helpers|rpcss\.exe|explorer\.exe|steam\.exe"
wine_helpers="$wine_helpers|winemenubuilder\.exe|conhost\.exe|start\.exe"
wine_helpers="$wine_helpers|wineboot\.exe|rundll32\.exe|tabtip\.exe"
wine_helpers="$wine_helpers|vc_redist|vcredist|dxsetup\.exe|msiexec\.exe"
wine_helpers="$wine_helpers|installinf|iscriptevaluator\.exe|regsvr32\.exe"
wine_helpers="$wine_helpers|winedbg\.exe|unitycrashhandler"
prefix_server_dir() {
  [ -n "$WINEPREFIX" ] || return 1
  ids=$(stat -f '%d-%i' "$WINEPREFIX" 2>/dev/null) || return 1
  [ -n "$ids" ] || return 1
  printf '/tmp/.wine-%s/server-%s' "$(id -u)" \
    "$(printf '%s' "$ids" | awk -F- '{printf "%x-%x", $1, $2}')"
}

prefix_game_running() {
  command -v lsof >/dev/null 2>&1 || return 1
  dir=$(prefix_server_dir) || return 1
  [ -d "$dir" ] || return 1
  pids=$(lsof -t +D "$dir" 2>/dev/null | sort -u | tr '\n' ',')
  pids=${pids%,}
  [ -n "$pids" ] || return 1
  # shellcheck disable=SC1003 # the pair matches the backslash in a drive path
  ps -p "$pids" -o args= 2>/dev/null | grep -E '^[A-Za-z]:\\' | grep -viE "$wine_helpers" | grep -q .
}

wait_prefix_idle() {
  idle=0
  tick=0
  while [ "$idle" -lt 10 ] && [ "$tick" -lt 300 ]; do
    tick=$((tick + 1))
    if prefix_game_running; then idle=0; else idle=$((idle + 1)); fi
    sleep 1
  done
  echo "wait_prefix_idle done after tick=$tick idle=$idle" >> "$log" 2>&1 || true
}

kill_wine_prefix() {
  "$WINESERVER" -k >> "$log" 2>&1 || true
  "$WINESERVER" -w >> "$log" 2>&1 || true
  if command -v lsof >/dev/null 2>&1 && server_dir=$(prefix_server_dir); then
    if [ -d "$server_dir" ]; then
      survivors=$(lsof -t +D "$server_dir" 2>/dev/null | sort -u)
      if [ -n "$survivors" ]; then
        echo "=== sweeping prefix stragglers: $survivors ===" >> "$log" 2>&1 || true
        # shellcheck disable=SC2086 # survivors is a list of pids and has to split
        kill -9 $survivors 2>/dev/null || true
      fi
    fi
  fi
}

# Test runs only: NOTPROTON_WATCHDOG=<seconds> in the launch options ends a game
# that has drawn no frame by then, which is how a modal error box or a hang looks
# from outside. A player's run never sets it, so a dialog stays on screen for them.
start_watchdog() {
  limit=${NOTPROTON_WATCHDOG:-0}
  case "$limit" in ''|*[!0-9]*|0) return 0 ;; esac
  parent=$$
  (
    waited=0
    while [ "$waited" -lt "$limit" ]; do
      sleep 1
      waited=$((waited + 1))
      kill -0 "$parent" 2>/dev/null || exit 0
      grep -a -q "first present" "$loader_root/notproton-wine.log" 2>/dev/null && exit 0
    done
    shot="$STEAM_COMPAT_DATA_PATH/notproton-watchdog.png"
    screencapture -x "$shot" >/dev/null 2>&1 || true
    echo "=== watchdog: no first frame in ${limit}s, screenshot $shot, killing wine prefix ===" >> "$log" 2>&1 || true
    kill_wine_prefix
  ) &
  watchdog_pid=$!
}

# Steam's "Exit Game" and the client shutting the game down both send a
# termination signal to this run script, this handles it
# shellcheck disable=SC2329 # the trap below invokes this
terminate() {
  # Steam repeats the signal and then kills the script, so a second delivery
  # must not start over and the script must end here, not in wait_prefix_idle
  trap '' TERM INT HUP
  [ -n "$watchdog_pid" ] && kill "$watchdog_pid" 2>/dev/null || true
  echo "=== termination signal received, killing wine prefix ===" >> "$log" 2>&1 || true
  kill_wine_prefix
  [ -n "$open_pid" ] && kill "$open_pid" 2>/dev/null || true
  echo "=== termination signal, session ending ===" >> "$log" 2>&1 || true
  exit 143
}
trap terminate TERM INT HUP

game_cwd="$(pwd)"
if [ -n "$STEAM_DYLD_INSERT_LIBRARIES" ]; then
  echo "=== overlay injected from $STEAM_DYLD_INSERT_LIBRARIES ===" >> "$log" 2>&1 || true
else
  echo "=== client staged no overlay renderer, overlay disabled ===" >> "$log" 2>&1 || true
fi
set -- --args "$shim_exe" "$@"
for name in $(env | sed -nE 's/^(Steam[A-Za-z0-9]*|(D3DM_|DXMT_|DXVK_|MTL_|ROSETTA_|SEVO_)[A-Z0-9_]*)=.*/\1/p'); do
  eval "value=\$$name"
  # shellcheck disable=SC2154 # eval assigns value on the line above
  set -- --env "$name=$value" "$@"
done
if [ -n "$WINEDLLPATH_PREPEND" ]; then
  set -- --env WINEDLLPATH_PREPEND="$WINEDLLPATH_PREPEND" "$@"
fi
# What the launch options set and the list above leaves out. The ones NotProton builds
# itself (below) carry the player's part already.
for name in $launch_env; do
  case "$name" in
    # CX_GRAPHICS*: launch options left from CrossOver days; Dormison reads none of them.
    Steam*|CX_GRAPHICS*|D3DM_*|DXMT_*|DXVK_*|MTL_*|ROSETTA_*|SEVO_*) continue ;;
    WINESERVER|WINEDLLPATH|WINEDLLPATH_PREPEND|WINEDLLOVERRIDES|WINEMSYNC|WINEPREFIX|WINEDEBUG) continue ;;
    PATH|STEAM_COMPAT_*|STEAM_DYLD_INSERT_LIBRARIES|NOTPROTON_GAME_CWD) continue ;;
  esac
  eval "value=\${$name-}"
  set -- --env "$name=$value" "$@"
done
set -- \
  --env SEVO_CLI="$sevo_cli" \
  --env WINESERVER="$WINESERVER" \
  --env WINEDLLPATH="$WINEDLLPATH" \
  --env WINEDLLOVERRIDES="$WINEDLLOVERRIDES" \
  --env WINEMSYNC="$WINEMSYNC" \
  --env WINEPREFIX="$WINEPREFIX" \
  --env WINEDEBUG="$WINEDEBUG" \
  --env PATH="$PATH" \
  --env STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH" \
  --env STEAM_COMPAT_INSTALL_PATH="$STEAM_COMPAT_INSTALL_PATH" \
  --env STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_COMPAT_CLIENT_INSTALL_PATH" \
  --env STEAM_COMPAT_APP_ID="$STEAM_COMPAT_APP_ID" \
  --env STEAM_DYLD_INSERT_LIBRARIES="$STEAM_DYLD_INSERT_LIBRARIES" \
  --env NOTPROTON_GAME_CWD="$game_cwd" "$@"
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A"
lsregister="$lsregister/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$lsregister" ] && "$lsregister" -f "$loader_app" >> "$log" 2>&1 || true
open -n -W -a "$loader_app" "$@" >> "$log" 2>&1 &
open_pid=$!
start_watchdog
status=0
seen=0
idle=0
while :; do
  if prefix_game_running; then
    seen=1
    idle=0
  else
    idle=$((idle + 1))
  fi
  if ! kill -0 "$open_pid" 2>/dev/null; then
    wait "$open_pid" || status=$?
    echo "=== bundle exited status=$status ===" >> "$log" 2>&1 || true
    if [ "$status" -le 128 ]; then
      wait_prefix_idle
    fi
    break
  fi
  if [ "$seen" -eq 1 ] && [ "$idle" -ge 10 ]; then
    echo "=== game tree gone, ending session ===" >> "$log" 2>&1 || true
    break
  fi
  sleep 1
done
[ -n "$watchdog_pid" ] && kill "$watchdog_pid" 2>/dev/null || true
echo "=== game exited status=$status, killing wine prefix ===" >> "$log" 2>&1 || true
kill_wine_prefix
echo "=== wine prefix killed, session ending ===" >> "$log" 2>&1 || true
exit $status
