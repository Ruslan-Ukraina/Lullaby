#!/bin/sh
# lullaby compatibility tool shim: runs Windows games from Steam on the
# Dormison engine Lullaby unpacked into runners/current
set -e

verb="$1"
shift || true

# Steam's launch options. hook_launch.c (from upstream NotProton 1.1.0) runs the launch
# through /bin/sh as Linux Steam does: NAME=value ahead of %command% is a variable, what
# follows %command% an argument of the game. The shell first notes the names it was handed
# in LULLABY_ENV_BASE, so the variables the options set are the rest; they go on to the
# game below, which LaunchServices starts with an environment of its own.
launch_env=""
launch_shell=0
if [ -n "${LULLABY_ENV_BASE+x}" ]; then
  launch_shell=1
  for name in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p'); do
    case " $LULLABY_ENV_BASE " in *" $name "*) continue ;; esac
    case "$name" in LULLABY_ENV_BASE|DYLD_*) continue ;; esac
    launch_env="$launch_env $name"
  done
  unset LULLABY_ENV_BASE
fi
# Only Lullaby's renderer list on Steam's newer Compatibility page (webpatch.c) still
# writes its choice after the command; without the shell (an older dylib, or the hook
# off) every option arrives after it, and the known prefixes are taken as before.
argc=$#
argi=0
while [ "$argi" -lt "$argc" ]; do
  arg="$1"
  shift
  case "$arg" in
    LULLABY_RENDERER=*|CX_GRAPHICS_BACKEND=*) take=1 ;;
    CX_GRAPHICS*=*|D3DM_*=*|DXMT_*=*|DXVK_*=*|MTL_*=*|LULLABY_*=*|ROSETTA_*=*|SEVO_*=*|WINE*=*)
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
# The player's own DLL overrides follow Lullaby's (the bridge's and the renderer's).
launch_dll_overrides=""
case " $launch_env " in *" WINEDLLOVERRIDES "*) launch_dll_overrides="$WINEDLLOVERRIDES" ;; esac

case "$verb" in
  getcompatpath)
    printf '%s\n' "$STEAM_COMPAT_DATA_PATH"
    exit 0
    ;;
esac

support="$HOME/Library/Application Support/lullaby"
# The Dormison engine. wine/bin/wine is its front door; x86_64-unix/wine is the
# loader proper, the one Dormison re-executes every Windows program through and
# the one a game's bundle carries a copy of. The server is native arm64.
engine_root="$support/runners/current"
wine_unix="$engine_root/wine/lib/wine/x86_64-unix"
WINELOADER="$engine_root/wine/bin/wine"
WINESERVER="$engine_root/wine/bin/wineserver"
# The app writes the engine's paths to lullaby-engine.env (DormisonEngine). It
# is read as data, never sourced: one LB_ENGINE_NAME='value' per line.
engine_env_get() {
  sed -n "s/^$1='\(.*\)'\$/\1/p" "$engine_root/lullaby-engine.env" 2>/dev/null | head -1 \
    | sed "s/'\\\\''/'/g"
}
if [ -f "$engine_root/lullaby-engine.env" ]; then
  env_unix=$(engine_env_get LB_ENGINE_UNIX_DIR)
  env_loader=$(engine_env_get LB_ENGINE_WINELOADER)
  env_server=$(engine_env_get LB_ENGINE_WINESERVER)
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
# Sevoflurane's /usr/local/bin/sevo when that is unset. Lullaby never calls
# Sevoflurane (docs/DECISIONS.md S1), so it always names this stand-in.
sevo_cli="$support/lullaby-sevo"
export SEVO_CLI="$sevo_cli"

if [ -n "$STEAM_COMPAT_DATA_PATH" ]; then
  log="$STEAM_COMPAT_DATA_PATH/lullaby-run.log"
else
  log=/dev/null
fi
[ "$(stat -f %z "$log" 2>/dev/null || echo 0)" -gt 262144 ] \
  && : > "$log" || true
run_started=$(date +%s)
{
  echo "=== lullaby run $(date) ==="
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
  echo "=== no Dormison engine at $engine_root, set it up in Lullaby ===" >> "$log" 2>&1 || true
  exit 1; }
echo "engine: $(readlink "$engine_root" 2>/dev/null || echo "$engine_root")" \
  >> "$log" 2>&1 || true

# The stand-in SEVO_CLI names. Dormison runs it as
# "app config <appid> <key> <value>" when a View menu setting changes. It logs the
# call and hands it to lullaby-settings, which stores the choice in the game's
# settings and rewrites its env files, so the choice holds on the next launch.
sevo_stub=$(cat <<'STUB'
#!/bin/sh
# Lullaby's stand-in for Sevoflurane's sevo CLI (docs/DECISIONS.md S1, P7A-5).
log="$HOME/Library/Application Support/lullaby/lullaby-sevo.log"
printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$log" 2>/dev/null
cli="$HOME/Library/Application Support/lullaby/lullaby-settings"
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

# The machine type of a PE file (014c: 32-bit x86, 8664: x86-64), nothing when it is not one.
exe_machine() {
  [ -f "$1" ] || return 1
  pe_off=$(od -A n -t u4 -j 60 -N 4 "$1" 2>/dev/null | tr -d ' ')
  case "$pe_off" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(od -A n -t x1 -j "$pe_off" -N 4 "$1" 2>/dev/null | tr -d ' \n')" = 50450000 ] || return 1
  od -A n -t x2 -j "$((pe_off + 4))" -N 2 "$1" 2>/dev/null | tr -d ' \n'
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
  echo "=== prefix ntdll is $have and this compatibility tool wants $want, rebuild the prefix in Lullaby ===" >> "$log" 2>&1 || true

  if [ "$verb" != run ]; then
    osascript >/dev/null 2>&1 <<APPLESCRIPT || true
display alert "This game needs its prefix rebuilt" message "This game originally ran under $(tool_name "$have"), but $(tool_name "$want") is present now. The prefix needs to be rebuilt in Lullaby in order to run the game. You will not lose game saves by rebuilding the prefix." as critical
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
# Lullaby's defaults; after that the keys are the user's and stay, except the
# two this script owns: WINEMSYNC, which only the bottle file may set and the
# server has to share, and SEVO_CLI (S1).
# One-run switches from the launch options (VAR=value %command%). The engine applies bottle.env
# over the process environment, so a launch option is written into the file; lullaby-settings
# writes the file again at the next launch, which drops it. WINEMSYNC=0 is handled with the
# sync above (the server's own variable).
#   LULLABY_AVX=0    do not advertise AVX to the game
#   LULLABY_LOW_LATENCY=0   Lullaby's own NVIDIA Reflex answer off for this run (D3DMetal's stubs stay); =1 turns it on
#   LULLABY_GCMOUSE_SCALE=0.2   the mouse speed of GCMouse for this run (a number, 0.01 .. 100)
#   LULLABY_DLSS=0   DLSS through MetalFX off (DXMT's and D3DMetal's switches; the card stays NVIDIA)
launch_overrides() {
  if [ "${LULLABY_AVX:-}" = 0 ]; then
    env_file_set "$1" ROSETTA_ADVERTISE_AVX 0
  fi
  if [ "${LULLABY_DLSS:-}" = 0 ]; then
    env_file_set "$1" DXMT_ENABLE_NVEXT ''
    env_file_set "$1" D3DM_ENABLE_METALFX ''
  fi
  case "${LULLABY_LOW_LATENCY:-}" in
    0|1) env_file_set "$1" LULLABY_LOW_LATENCY "$LULLABY_LOW_LATENCY" ;;
  esac
  case "${LULLABY_GCMOUSE_SCALE:-}" in
    ''|*[!0-9.]*|*.*.*) ;;
    *) env_file_set "$1" LULLABY_GCMOUSE_SCALE "$LULLABY_GCMOUSE_SCALE" ;;
  esac
}

write_bottle_env() {
  sevo="$WINEPREFIX/.sevo"
  bottle="$sevo/bottle.env"
  mkdir -p "$sevo/apps" || return 0
  if [ ! -f "$bottle" ]; then
    cat > "$bottle" <<'BOTTLE'
# Dormison settings for every program in this prefix, first written by Lullaby.
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
  launch_overrides "$bottle"
  echo "bottle.env: $(grep -v '^#' "$bottle" | tr '\n' ' ')" >> "$log" 2>&1 || true
}

# A value the game's own env file (then the prefix's) sets, for the keys that are
# Lullaby's rather than the engine's: the engine reads those files itself.
exe_name=$(basename "$1")
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
# controller support in most games. LULLABY_RAW_CONTROLLERS=1 in the launch options
# hands every controller back to the game.
plan_hidden_controllers() {
  controllers_file="$STEAM_COMPAT_DATA_PATH/lullaby-hidden-controllers"
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
  if [ "$LULLABY_RAW_CONTROLLERS" != "1" ]; then
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
  echo "video: RetinaMode=${LULLABY_RETINA:-0} EmulateModeset=${LULLABY_EMULATE_MODESET:-0}" >> "$log" 2>&1 || true
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
      '[HKEY_CURRENT_USER\Software\Wine\Mac Driver]' "$(reg_switch_line RetinaMode "$LULLABY_RETINA")" \
      '"LeftCommandIsCtrl"="y"' '"RightCommandIsCtrl"="y"' '"LeftOptionIsAlt"="y"' '"RightOptionIsAlt"="y"' '' \
      '[HKEY_CURRENT_USER\Software\Wine\X11 Driver]' \
      "$(reg_switch_line EmulateModeset "$LULLABY_EMULATE_MODESET")" '' \
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
    if [ "$LULLABY_RAW_CONTROLLERS" = "1" ]; then
      echo "controllers: games read them directly (LULLABY_RAW_CONTROLLERS=1)" >> "$log" 2>&1 || true
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
  # Lullaby's own keys: a launch option first, then the program's file, then
  # bottle.env (the engine reads its SEVO_* keys from those files itself).
  [ -n "$LULLABY_RETINA" ] || LULLABY_RETINA=$(env_value LULLABY_RETINA)
  [ -n "$LULLABY_EMULATE_MODESET" ] || LULLABY_EMULATE_MODESET=$(env_value LULLABY_EMULATE_MODESET)
  # Display mode emulation is for old games, which are 32-bit: the program decides, no setting.
  if [ -z "$LULLABY_EMULATE_MODESET" ] && [ "$(exe_machine "$1")" = 014c ]; then
    LULLABY_EMULATE_MODESET=1
    echo "32-bit program: display mode emulation on" >> "$log" 2>&1 || true
  fi
  [ -n "$LULLABY_DLSS" ] || LULLABY_DLSS=$(env_value LULLABY_DLSS)
  msync_from=launch-options
  # msync+ is Dormison's sync and stays on; the catalog's per-game debugging switch
  # (LULLABY_MSYNC in bottle.env) can turn it off. A prefix from before the
  # catalog carries the old marker instead.
  if [ -z "$WINEMSYNC" ]; then
    WINEMSYNC=$(sed -n 's/^LULLABY_MSYNC=//p' "$WINEPREFIX/.sevo/bottle.env" 2>/dev/null | head -1)
    [ -n "$WINEMSYNC" ] && msync_from=settings
  fi
  if [ -z "$WINEMSYNC" ] && [ -r "$STEAM_COMPAT_DATA_PATH/lullaby-msync" ] \
    && [ -f "$WINEPREFIX/.sevo/bottle.env" ]; then
    WINEMSYNC=$(tr -d ' \t\n' \
      < "$STEAM_COMPAT_DATA_PATH/lullaby-msync" 2>/dev/null || true)
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
# patches/engine/lby-discord-ntdllhook/install-b1.sh puts the pair in the engine and the bridge).
verify_runner() {
  for arch in x86_64 i386; do
    staged="$bridge_src/wine/$arch-windows/ntdll.dll"
    live="$engine_root/wine/lib/wine/$arch-windows/ntdll.dll"
    if [ ! -f "$staged" ]; then
      echo "=== no patched $arch ntdll in the bridge, $arch games will not reach lsteamclient ===" >> "$log" 2>&1 || true
    elif ! cmp -s "$staged" "$live"; then
      echo "=== the engine's $arch ntdll is not the patched copy, run patches/engine/lby-discord-ntdllhook/install-b1.sh ===" >> "$log" 2>&1 || true
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
# Steam on Linux symlinks this for every compat tool launch; some legacy games (Prey 2006) look for it
# beside the steamapps/common folders (upstream NotProton 1.2.0). The app's Remove takes the link away.
link_legacy_steam_dll() {
  src="$STEAM_COMPAT_CLIENT_INSTALL_PATH/legacycompat/Steam.dll"
  [ -n "$STEAM_COMPAT_INSTALL_PATH" ] && [ -f "$src" ] || return 0
  dst="$(dirname "$STEAM_COMPAT_INSTALL_PATH")/Steam.dll"
  [ -L "$dst" ] || [ ! -e "$dst" ] || return 0
  [ "$(readlink "$dst" 2>/dev/null)" = "$src" ] && return 0
  if ln -sfn "$src" "$dst" 2>> "$log"; then
    echo "=== linked legacy Steam.dll at $dst ===" >> "$log" 2>&1 || true
  else
    echo "=== could not link legacy Steam.dll at $dst ===" >> "$log" 2>&1 || true
  fi
}

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

bridge_files="steamclient64.dll steamclient.dll tier0_s64.dll vstdlib_s64.dll tier0_s.dll vstdlib_s.dll"
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
  # A 32-bit game looks for lsteamclient.dll in i386-windows first; the plain file above is x86_64 and
  # is refused by a 32-bit process (0xc000007b).
  if [ -f "$bridge_src/i386-windows/lsteamclient.dll" ]; then
    mkdir -p "$prefix_steam/i386-windows"
    cp -c -f "$bridge_src/i386-windows/lsteamclient.dll" "$prefix_steam/i386-windows/lsteamclient.dll" 2>/dev/null || \
      cp -f "$bridge_src/i386-windows/lsteamclient.dll" "$prefix_steam/i386-windows/lsteamclient.dll" || \
      echo "=== failed to stage i386-windows/lsteamclient.dll ===" >> "$log" 2>&1
  fi
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
  link_legacy_steam_dll
  echo "=== bridge staged into $prefix_steam ===" >> "$log" 2>&1 || true
  echo "WINEDLLPATH=$WINEDLLPATH" >> "$log" 2>&1 || true
  echo "STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_COMPAT_CLIENT_INSTALL_PATH" >> "$log" 2>&1 || true
fi

# The renderer reaches every program of this launch through WINEDLLPATH_PREPEND,
# which Dormison searches ahead of its own tree (set_dll_path), so the engine's
# files stay as shipped. Each renderer directory links into runners/current, so
# it follows an engine switch. DXMT is the default for D3D10 and D3D11.
renderers="$support/renderers"
# NVIDIA's secure loader (nvapi64.lib, in Streamline and in games that call NVAPI
# directly) loads nvapi64.dll only through the copy in system32, and refuses a copy
# that is not the one the renderer provides: Dormison's engine places GPTK 4.0 beta 2's
# there at wineboot, and with another toolkit active NvAPI_Initialize answered
# NVAPI_LIBRARY_NOT_FOUND, so Streamline saw no NVIDIA GPU and games hid DLSS. Apple's
# Read Me says the same: nvapi64.dll and nvngx.dll go into the prefix's system32.
# $1: directory holding nvapi64.dll; $2: the file that becomes nvngx.dll.
place_nvidia_dlls() {
  [ -n "$WINEPREFIX" ] && [ -d "$WINEPREFIX/drive_c/windows/system32" ] || return 0
  for pair in "nvapi64.dll:$1/nvapi64.dll" "nvngx.dll:$2"; do
    dst="$WINEPREFIX/drive_c/windows/system32/${pair%%:*}"
    src="${pair#*:}"
    [ -f "$src" ] || continue
    cmp -s "$src" "$dst" && continue
    cp -f "$src" "$dst" || return 1
    echo "dlss: $(basename "$dst") in system32 <- $src" >> "$log" 2>&1 || true
  done
}

# A component from its author's release, pinned by sha256 and fetched the first time a game needs it
# into components/<name> (nothing else is trusted: a wrong hash installs nothing, no network leaves
# the game on Wine's own renderer). Pins are the same as release/components.json.
mtld3d_url="https://github.com/athei/mtld3d/releases/download/v0.15.1/mtld3d.tar.xz"
mtld3d_sha256="115d9089323b20010738d2b4835e79e6652d41690c4b360141e8b0433faff972"
winemetalgl_url="https://github.com/metalsharp/WineMetalGL/releases/download/winemetalgl-3.7.0/winemetalgl-3.7.0-x86_64.tar.gz"
winemetalgl_sha256="7eaaf6d5525494a855ff368d6ce15b753fd213b7d16254f0eddd45b166eac2af"
fetch_component() { # NAME URL SHA256 SUBDIR_OF_ARCHIVE_TO_KEEP ("" for the whole archive)
  fc_name=$1; fc_url=$2; fc_want=$3; fc_keep=$4
  fc_dest="$support/components/$fc_name"
  [ "$(cat "$fc_dest/.sha256" 2>/dev/null)" = "$fc_want" ] && return 0
  fc_tmp=$(mktemp -d "${TMPDIR:-/tmp}/lullaby-$fc_name.XXXXXX") || return 1
  echo "component $fc_name: fetching $fc_url" >> "$log" 2>&1 || true
  if curl -fsSL --connect-timeout 8 --max-time 120 -o "$fc_tmp/archive" "$fc_url" 2>>"$log"; then
    fc_got=$(shasum -a 256 "$fc_tmp/archive" | cut -d' ' -f1)
    if [ "$fc_got" = "$fc_want" ]; then
      mkdir -p "$fc_tmp/x"
      if ! tar -xf "$fc_tmp/archive" -C "$fc_tmp/x" 2>>"$log"; then rm -rf "${fc_tmp:?}"; return 1; fi
      fc_src="$fc_tmp/x"
      if [ -n "$fc_keep" ]; then
        for fc_top in "$fc_tmp/x"/*; do fc_src="$fc_top/$fc_keep"; break; done
      fi
      if [ -d "$fc_src" ]; then
        mkdir -p "$support/components"
        rm -rf "${fc_dest:?}"
        if ! mkdir -p "$fc_dest"; then rm -rf "${fc_tmp:?}"; return 1; fi
        if [ -n "$fc_keep" ]; then mv "$fc_src" "$fc_dest/$fc_keep"; else mv "$fc_src"/* "$fc_dest/"; fi
        printf '%s' "$fc_want" > "$fc_dest/.sha256"
        rm -rf "${fc_tmp:?}"
        echo "component $fc_name: installed" >> "$log" 2>&1 || true
        return 0
      fi
    else
      echo "component $fc_name: sha256 $fc_got is not the pinned $fc_want, not installed" >> "$log" 2>&1 || true
    fi
  else
    echo "component $fc_name: download failed" >> "$log" 2>&1 || true
  fi
  rm -rf "${fc_tmp:?}"
  return 1
}
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
        place_nvidia_dlls "$engine_root/dxmt" "$engine_root/dxmt/nvngx.dll" || return 1
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
    d3dmetal|d3dmetal-reflex)
      # Apple's D3DMetal from the player's Game Porting Toolkit (lullaby/d3dmetal/<version>,
      # named by LULLABY_D3DMETAL in bottle.env). Its macOS half goes into the running
      # engine's wine/lib/external, where the engine's x86_64-unix/{d3d11,d3d12,dxgi,...}.so
      # links lead (Apple's layout); doing it at every D3DMetal launch is what carries it into
      # a new engine after an update or a roll-back. The Windows DLLs reach this game alone
      # from the renderer directory, their unix halves beside them.
      tk="$LULLABY_D3DMETAL"
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
        # Apple's Read Me (4.0 beta 3): DLSS reaches MetalFX through nvngx-on-metalfx
        # under the name nvngx, the one games load (D3DM_ENABLE_METALFX switches it).
        n=$b
        [ "$b" = nvngx-on-metalfx ] && n=nvngx
        ln -sfn "$f" "$dir/x86_64-windows/$n.dll"
        # The engine carries links for the DLLs of the toolkit it was built beside
        # (d3d11, d3d12, dxgi); a newer toolkit brings more (4.0 beta 3: d3d12core,
        # d3d10, nvapi64, nvngx-on-metalfx). Those get the target the toolkit's own
        # link names, in the same lib/external, so one libd3dshared serves them all.
        u="$wine_unix/$b.so"
        if [ ! -e "$u" ] && t=$(readlink "$tk/lib/wine/x86_64-unix/$b.so" 2>/dev/null); then
          u="$ext/${t##*/}"
        fi
        ln -sfn "$u" "$dir/x86_64-unix/$n.so"
        names="${names:+$names,}$n"
      done
      [ -n "$names" ] || return 1
      renderer_overrides="$names=b"
      place_nvidia_dlls "$tk/lib/wine/x86_64-windows" "$tk/lib/wine/x86_64-windows/nvngx-on-metalfx.dll" || return 1
      export SEVO_LIBD3DSHARED_PATH="$ext/libd3dshared.dylib" D3DM_WINE_UNIX_CALL=1
      # NVIDIA Reflex by Lullaby (Low latency, Diagnostics): Lullaby's nvapi64.dll answers
      # the game in front of D3DMetal's, which keeps its unix half as nvapimt. The D3DMetal
      # layer feeds it when each frame reaches the screen (winemac.so fix 0003).
      # Wine finds a builtin by the name inside its file, and Apple's says nvapi64.dll, which
      # would hand Lullaby's back to itself: the copy here says nvapimt.dll, same length.
      # The prefix holds a file of each name, as the loader requires for a builtin.
      if [ "$1" = d3dmetal-reflex ]; then
        apple="$tk/lib/wine/x86_64-windows/nvapi64.dll"
        [ -f "$apple" ] && [ -L "$dir/x86_64-unix/nvapi64.so" ] || return 1
        at=$(LC_ALL=C grep -a -b -o 'nvapi64\.dll' "$apple" | cut -d: -f1)
        case "$at" in ''|*[!0-9]*) echo "reflex: D3DMetal's nvapi64.dll names itself $(printf '%s' "$at" | wc -l) times, not once" >> "$log" 2>&1; return 1 ;; esac
        cp -f "$apple" "$dir/x86_64-windows/nvapimt.dll" || return 1
        printf 'nvapimt.dll' | dd of="$dir/x86_64-windows/nvapimt.dll" bs=1 seek="$at" conv=notrunc 2>/dev/null || return 1
        mv -f "$dir/x86_64-unix/nvapi64.so" "$dir/x86_64-unix/nvapimt.so" || return 1
        ln -sfn "$nvapi_shim" "$dir/x86_64-windows/nvapi64.dll"
        renderer_overrides="$names,nvapimt=b"
        if [ -n "$WINEPREFIX" ] && [ -d "$WINEPREFIX/drive_c/windows/system32" ]; then
          rm -f "$WINEPREFIX/drive_c/windows/system32/nvapi64_d3dm.dll"
          for pair in "nvapi64.dll:$nvapi_shim" "nvapimt.dll:$dir/x86_64-windows/nvapimt.dll"; do
            dst="$WINEPREFIX/drive_c/windows/system32/${pair%%:*}"
            cmp -s "${pair#*:}" "$dst" || cp -f "${pair#*:}" "$dst" || return 1
          done
        fi
        export LULLABY_PRESENT_FEED=1
        echo "reflex: Lullaby's nvapi64 in front of D3DMetal's" >> "$log" 2>&1 || true
      fi
      ;;
    mtld3d)
      # mtld3d (Direct3D 9 on Metal, zlib): the release bundle unpacked in components/mtld3d.
      # Its builtin-marked d3d9.dll is found on the dll path like DXMT's; mtld3d.dll is not one of
      # Wine's names, so its copy goes into the prefix too (as winemetal's does above).
      src="$support/components/mtld3d/wine"
      fetch_component mtld3d "$mtld3d_url" "$mtld3d_sha256" "" || true
      [ -f "$src/x86_64-windows/d3d9.dll" ] && [ -f "$src/x86_64-unix/mtld3d.so" ] || {
        echo "=== mtld3d is not installed in $support/components/mtld3d ===" >> "$log" 2>&1 || true
        return 1; }
      mkdir -p "$dir/x86_64-windows" "$dir/i386-windows" "$dir/x86_64-unix" || return 1
      for f in d3d9 mtld3d; do
        ln -sfn "$src/x86_64-windows/$f.dll" "$dir/x86_64-windows/$f.dll"
        ln -sfn "$src/i386-windows/$f.dll" "$dir/i386-windows/$f.dll"
      done
      ln -sfn "$src/x86_64-unix/mtld3d.so" "$dir/x86_64-unix/mtld3d.so"
      if [ -n "$WINEPREFIX" ]; then
        for pair in "system32:x86_64-windows" "syswow64:i386-windows"; do
          sysdir="$WINEPREFIX/drive_c/windows/${pair%%:*}"
          [ -d "$sysdir" ] || continue
          cmp -s "$src/${pair#*:}/mtld3d.dll" "$sysdir/mtld3d.dll" && continue
          cp -f "$src/${pair#*:}/mtld3d.dll" "$sysdir/mtld3d.dll" || return 1
        done
      fi
      renderer_overrides="d3d9,mtld3d=b;nvapi64,nvapi=d"   # D3DMetal's nvapi64.dll answers NULL for what it does not know
      ;;
    winemetalgl)
      # WineMetalGL (OpenGL on Metal, LGPL-3.0+): the x86_64 package's module/ unpacked in
      # components/winemetalgl (fetched, pinned). As its installer does for a prefix: opengl32.dll forwards to
      # winemetalgl.dll, both in system32 and syswow64, and opengl32 is a native override.
      src="$support/components/winemetalgl/module"
      fetch_component winemetalgl "$winemetalgl_url" "$winemetalgl_sha256" module || true
      [ -f "$src/x86_64-windows/winemetalgl.dll" ] && [ -f "$src/x86_64-unix/winemetalgl.so" ] || {
        echo "=== WineMetalGL is not installed in $support/components/winemetalgl ===" >> "$log" 2>&1 || true
        return 1; }
      mkdir -p "$dir/x86_64-windows" "$dir/i386-windows" "$dir/x86_64-unix" || return 1
      ln -sfn "$src/x86_64-windows/winemetalgl.dll" "$dir/x86_64-windows/winemetalgl.dll"
      ln -sfn "$src/i386-windows/winemetalgl.dll" "$dir/i386-windows/winemetalgl.dll"
      for f in winemetalgl.so libwinemetalgl.dylib; do
        ln -sfn "$src/x86_64-unix/$f" "$dir/x86_64-unix/$f"
      done
      if [ -n "$WINEPREFIX" ]; then
        for pair in "system32:x86_64-windows" "syswow64:i386-windows"; do
          sysdir="$WINEPREFIX/drive_c/windows/${pair%%:*}"
          [ -d "$sysdir" ] || continue
          for f in opengl32 winemetalgl; do
            cmp -s "$src/${pair#*:}/$f.dll" "$sysdir/$f.dll" && continue
            cp -f "$src/${pair#*:}/$f.dll" "$sysdir/$f.dll" || return 1
          done
        done
      fi
      # The prefix keeps D3DMetal's nvapi64.dll, which answers NvAPI_QueryInterface with NULL for what it does not know;
      # a game that finds NVAPI (Euro Truck Simulator 2 on OpenGL) calls that NULL and crashes. Without it the game sees
      # no NVIDIA API, as on any other GPU.
      renderer_overrides="opengl32=n;winemetalgl=b;nvapi64,nvapi=d"
      ;;
    *) return 1 ;;
  esac
  for f in "$dir"/*/*; do
    [ -e "$f" ] && continue
    echo "=== renderer $1: $f leads nowhere in this engine ===" >> "$log" 2>&1 || true
    return 1
  done
}
# --- apiscout begin: the API scout, patches/inject/lby-spitfire-apiscout (tests extract this block) ---
# GNU and BSD stat differ; the run script runs on macOS, the tests may not.
apiscout_stat() {
  stat -f '%m %z' "$1" 2>/dev/null || stat -c '%Y %s' "$1" 2>/dev/null || echo "0 0"
}

apiscout_backend() {
  case "$1" in
    dx12) echo d3dmetal ;;
    dx11) echo dxmt ;;
    dx9) echo mtld3d ;;
    vk) echo kosmickrisp ;;
    gl) echo winemetalgl ;;
    *) echo dxmt ;;
  esac
}

# Flags of the engines seen so far (Unity, Source 2, Unreal, SCS). The first match wins.
apiscout_from_args() {
  prev=""
  for a in "$@"; do
    case "$a" in
      -force-d3d12|-force-dx12|-dx12|-d3d12) echo "dx12 $a"; return 0 ;;
      -force-d3d11|-force-d3d11-singlethreaded|-force-dx11|-dx11|-d3d11) echo "dx11 $a"; return 0 ;;
      -force-d3d9|-dx9|-d3d9) echo "dx9 $a"; return 0 ;;
      -force-vulkan|-vulkan) echo "vk $a"; return 0 ;;
      -force-glcore|-force-opengl|-opengl|-gl) echo "gl $a"; return 0 ;;
    esac
    if [ "$prev" = "-rdevice" ]; then
      case "$a" in
        dx9|d3d9) echo "dx9 -rdevice $a"; return 0 ;;
        dx11|d3d11) echo "dx11 -rdevice $a"; return 0 ;;
        opengl|gl) echo "gl -rdevice $a"; return 0 ;;
      esac
    fi
    # Source 1: -dxlevel 80..98 is Direct3D 9 and older, 100 and 110 Direct3D 10/11
    if [ "$prev" = "-dxlevel" ]; then
      case "$a" in
        80|81|90|95|98) echo "dx9 -dxlevel $a"; return 0 ;;
        100|110) echo "dx11 -dxlevel $a"; return 0 ;;
      esac
    fi
    # Godot 4: --rendering-driver vulkan|d3d12|opengl3[_angle|_es], --rendering-method gl_compatibility
    if [ "$prev" = "--rendering-driver" ]; then
      case "$a" in
        d3d12) echo "dx12 --rendering-driver $a"; return 0 ;;
        vulkan) echo "vk --rendering-driver $a"; return 0 ;;
        opengl3|opengl3_angle|opengl3_es) echo "gl --rendering-driver $a"; return 0 ;;
      esac
    fi
    if [ "$prev" = "--rendering-method" ] && [ "$a" = gl_compatibility ]; then
      echo "gl --rendering-method $a"; return 0
    fi
    prev="$a"
  done
  return 1
}

# Source 2: boot.vcfg "DefaultRenderSystemOption" "-vulkan"; SCS: config.cfg `uset r_device "<value>"`;
apiscout_from_settings() {
  gamedir=$1; userdir=$2
  f=$(find "$gamedir/game" -maxdepth 3 -name boot.vcfg 2>/dev/null | head -n 1)
  if [ -n "$f" ]; then
    v=$(sed -n 's/.*"DefaultRenderSystemOption"[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n 1)
    case "$v" in
      -vulkan) echo "vk $f"; return 0 ;;
      -dx11) echo "dx11 $f"; return 0 ;;
      "") echo "dx11 $f (no option: Source 2 default)"; return 0 ;;
    esac
  fi
  # RE Engine: config.ini in the game folder, [Render] Capability=DirectX12 (or DirectX11)
  if [ -f "$gamedir/config.ini" ]; then
    v=$(sed -n 's/^Capability=\(.*\)/\1/p' "$gamedir/config.ini" | head -n 1 | tr -d '\r')
    case "$v" in
      DirectX12) echo "dx12 $gamedir/config.ini"; return 0 ;;
      DirectX11) echo "dx11 $gamedir/config.ini"; return 0 ;;
    esac
  fi
  # Source 1: <mod>/cfg/videoconfig.txt, "setting.dxlevel" "90"
  for v in "$gamedir"/*/cfg/videoconfig.txt; do
    [ -f "$v" ] || continue
    lvl=$(sed -n 's/.*"setting.dxlevel"[[:space:]]*"\([0-9]*\)".*/\1/p' "$v" | head -n 1)
    case "$lvl" in
      80|81|90|95|98) echo "dx9 $v"; return 0 ;;
      100|110) echo "dx11 $v"; return 0 ;;
    esac
  done
  # CryEngine: system.cfg or user.cfg in the game folder, r_Driver = DX11 | DX12 | Vk
  for c in "$gamedir/system.cfg" "$gamedir/user.cfg"; do
    [ -f "$c" ] || continue
    v=$(sed -n 's/^[[:space:]]*[rR]_[dD]river[[:space:]]*=[[:space:]]*"\{0,1\}\([A-Za-z0-9]*\).*/\1/p' "$c" | tail -n 1 | tr -d '\r')
    case "$v" in
      DX12) echo "dx12 $c"; return 0 ;;
      DX11) echo "dx11 $c"; return 0 ;;
      Vk|VK|Vulkan) echo "vk $c"; return 0 ;;
    esac
  done
  for c in "$userdir"/Documents/*/config.cfg; do
    [ -f "$c" ] || continue
    v=$(sed -n 's/^uset r_device "\(.*\)"/\1/p' "$c" | head -n 1)
    case "$v" in
      "") ;;
      *[dD][xX]9*|*d3d9*) echo "dx9 $c"; return 0 ;;
      *[dD][xX]11*|*d3d11*) echo "dx11 $c"; return 0 ;;
      *[oO]pen[gG][lL]*) echo "gl $c"; return 0 ;;
    esac
  done
  return 1
}

# Unity: the first Direct3D/Vulkan/OpenGL line of Player.log. It is the previous run's log, not a
# setting, so it is reported as source=lastrun.
apiscout_from_lastrun() {
  gamedir=$1; userdir=$2
  for l in "$userdir"/AppData/LocalLow/*/*/Player.log; do
    [ -f "$l" ] || continue
    v=$(grep -E 'Direct3D 1[12]\.0|^ *Vulkan|Renderer: .*OpenGL|Direct3D 9' "$l" 2>/dev/null | head -n 1)
    case "$v" in
      *"Direct3D 12"*) echo "dx12 $l"; return 0 ;;
      *"Direct3D 11"*) echo "dx11 $l"; return 0 ;;
      *Vulkan*) echo "vk $l"; return 0 ;;
      *OpenGL*) echo "gl $l"; return 0 ;;
    esac
  done
  return 1
}

# Names beside the exe that only suggest, never decide: a D3D12 folder or *_dx12.dll is a
# candidate, so it is reported as "files" and used only when nothing else spoke.
apiscout_from_files() {
  gamedir=$1
  # A Unity game carries its D3D12 files (Agility SDK) whatever API it starts with, so there they say nothing.
  if [ ! -f "$gamedir/UnityPlayer.dll" ] && { [ -d "$gamedir/D3D12" ] || ls "$gamedir"/*_dx12.dll >/dev/null 2>&1; }; then
    echo "dx12 $gamedir (D3D12 folder or *_dx12.dll)"; return 0
  fi
  # MonoGame: the DesktopGL build draws with OpenGL, the WindowsDX build (SharpDX) with D3D11
  mg="$gamedir/MonoGame.Framework.dll"
  if [ -f "$mg" ]; then
    if grep -qa 'SharpDX' "$mg" 2>/dev/null; then echo "dx11 $mg (MonoGame WindowsDX)"; return 0; fi
    if grep -qa 'DesktopGL' "$mg" 2>/dev/null; then echo "gl $mg (MonoGame DesktopGL)"; return 0; fi
  fi
  return 1
}

apiscout_detect() {
  gamedir=$1; userdir=$2; shift 2
  if r=$(apiscout_from_args "$@"); then
    echo "api=${r%% *} source=arg evidence=${r#* }"; return 0
  fi
  if r=$(apiscout_from_settings "$gamedir" "$userdir"); then
    echo "api=${r%% *} source=settings evidence=${r#* }"; return 0
  fi
  if r=$(apiscout_from_lastrun "$gamedir" "$userdir"); then
    echo "api=${r%% *} source=lastrun evidence=${r#* }"; return 0
  fi
  if r=$(apiscout_from_files "$gamedir"); then
    echo "api=${r%% *} source=files evidence=${r#* }"; return 0
  fi
  echo "api=none source=none evidence=nothing known, DXMT"
}

# The places of a verdict, so that a launch looks at those only.
apiscout_remember() {
  state=$1; shift
  : > "$state"
  for p in "$@"; do
    [ -e "$p" ] && printf '%s|%s\n' "$p" "$(apiscout_stat "$p")" >> "$state"
  done
}

# Prints the paths whose mtime or size changed since apiscout_remember; returns 0 if any did.
apiscout_changed() {
  state=$1; any=1
  [ -f "$state" ] || return 0
  while IFS='|' read -r p rest; do
    now=$(apiscout_stat "$p")
    if [ "$now" != "$rest" ]; then echo "$p"; any=0; fi
  done < "$state"
  return $any
}

# A game that ends with an error status (not a plain exit 0, not Steam's stop signal 143) within two
# minutes did not start on the backend chosen for it. The notice says where to change the backend.
apiscout_notice_needed() { # STATUS ELAPSED_SECONDS
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "$1" -ne 0 ] && [ "$1" -ne 143 ] && [ "$2" -lt 120 ]
}
apiscout_notice_text() { # GAME BACKEND API: the English text, used when lullaby-settings is not there
  echo "$1 did not start with the $2 renderer ($3). In Steam open the game's Properties, Compatibility, and choose another renderer for this game."
}
# --- apiscout end ---
# Launch option first (the Steam page's renderer list, or the old CX_GRAPHICS_BACKEND
# some games still carry), then the game's Game Settings.
renderer="${LULLABY_RENDERER:-${CX_GRAPHICS_BACKEND:-$(env_value LULLABY_RENDERER)}}"
# "auto" is the base choice of the list: nothing chosen, the scout below names the renderer.
case "$renderer" in auto) renderer="" ;; esac
# The API scout (patches/inject/lby-spitfire-apiscout) names the API the game will draw with and
# so the renderer, unless the player chose one (launch option or Game Settings): that choice wins.
# Its places are remembered in the game's compatdata (lullaby-apiscout), nowhere in Steam.
# KosmicKrisp is not chosen by it (MoltenVK stays the Vulkan driver, LULLABY_VULKAN opts in).
scout_user="${WINEPREFIX:-$STEAM_COMPAT_DATA_PATH/pfx}/drive_c/users/steamuser"
scout_state="$STEAM_COMPAT_DATA_PATH/lullaby-apiscout"
scout_line=""
# Only the game's own run: Steam also runs helpers (the install-script evaluator) through this script.
if [ "$verb" = waitforexitandrun ]; then
  scout_line=$(apiscout_detect "$STEAM_COMPAT_INSTALL_PATH" "$scout_user" "$@" 2>/dev/null) || scout_line=""
fi
scout_renderer=""
if [ -n "$scout_line" ]; then
  scout_api=${scout_line#api=}; scout_api=${scout_api%% *}
  scout_src=${scout_line#*source=}; scout_src=${scout_src%% *}
  scout_ev=${scout_line#*evidence=}; scout_ev=${scout_ev%% (*}
  scout_backend=$(apiscout_backend "$scout_api")
  case "$scout_backend" in
    d3dmetal|dxmt) scout_renderer=$scout_backend ;;
    # fetched on first use; a game that cannot have them goes on Wine's own (stage_renderer failing)
    mtld3d|winemetalgl) scout_renderer=$scout_backend ;;
    *) scout_renderer=wined3d ;;
  esac
  apiscout_changed "$scout_state" 2>/dev/null | while read -r p; do echo "apiscout: changed since the last launch: $p" >> "$log" 2>&1 || true; done
  case "$scout_src" in settings|lastrun|files) apiscout_remember "$scout_state" "$scout_ev" 2>/dev/null || true ;; esac
fi
if [ -z "$renderer" ]; then
  renderer="${scout_renderer:-dxmt}"
  [ -n "$scout_line" ] && echo "apiscout: $scout_line backend=$scout_backend, renderer $renderer" >> "$log" 2>&1 || true
else
  [ -n "$scout_line" ] && echo "apiscout: $scout_line backend=$scout_backend; the player's renderer $renderer is used" >> "$log" 2>&1 || true
fi
[ -n "$LULLABY_D3DMETAL" ] || LULLABY_D3DMETAL=$(env_value LULLABY_D3DMETAL)
case "$renderer" in
  dxmt|dxvk|wined3d|d3dmetal|mtld3d|winemetalgl) ;;
  moltenvk) ;;
  *)
    echo "=== unknown renderer $renderer, using DXMT ===" >> "$log" 2>&1 || true
    renderer=dxmt ;;
esac
# MoltenVK in the list: Vulkan games on the engine's own MoltenVK, no Direct3D layer (nothing is put on the dll path).
renderer_moltenvk=0
if [ "$renderer" = moltenvk ]; then
  renderer_moltenvk=1
  renderer=wined3d
  echo "renderer: MoltenVK chosen, Vulkan games use the engine's MoltenVK" >> "$log" 2>&1 || true
fi
unset WINEDLLPATH_PREPEND
renderer_dir="$renderer"
if [ "$renderer" = dxmt ] && [ "$LULLABY_DLSS" = 1 ]; then
  renderer_dir=dxmt-nvext
  echo "renderer: DLSS -> MetalFX through DXMT (experimental)" >> "$log" 2>&1 || true
fi
# Lullaby's NVIDIA Reflex (the game's Low latency switch): D3DMetal from a directory of
# its own, so a game without it never loads Lullaby's nvapi64.
nvapi_shim="$support/lullaby-nvapi64.dll"
if [ "$renderer" = d3dmetal ] && [ "$(env_value LULLABY_LOW_LATENCY)" = 1 ]; then
  if [ -f "$nvapi_shim" ]; then
    renderer_dir=d3dmetal-reflex
    mkdir -p "$support/launchers/app-$app_id" 2>/dev/null || true
    LULLABY_NVAPI_LOG="Z:$(printf '%s' "$support/launchers/app-$app_id/lullaby-nvapi.log" | tr / '\134')"
    export LULLABY_NVAPI_LOG
  else
    echo "reflex: no $nvapi_shim, Reflex stays D3DMetal's" >> "$log" 2>&1 || true
  fi
fi
if [ "$renderer" != wined3d ]; then
  if stage_renderer "$renderer_dir"; then
    export WINEDLLPATH_PREPEND="$renderers/$renderer_dir"
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}$renderer_overrides"
  else
    # A backend of another API is never put in silently (DXMT cannot run a D3D12 game):
    # the game starts on Wine's own and the log says why.
    [ "$renderer" = d3dmetal ] && echo "=== d3dmetal is not set up (add the Game Porting Toolkit in Lullaby), no other renderer is substituted ===" >> "$log" 2>&1 || true
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
# LULLABY_VULKAN=kosmickrisp (launch option or Game Settings file) takes Lullaby's own x86_64 build of
# Mesa's KosmicKrisp from components/kosmickrisp instead; without it, MoltenVK stays.
vk_driver="${LULLABY_VULKAN:-$(env_value LULLABY_VULKAN)}"
[ "$renderer_moltenvk" = 1 ] && vk_driver=moltenvk
if [ "$vk_driver" = kosmickrisp ]; then
  if [ -f "$support/components/kosmickrisp/kosmickrisp_icd.json" ]; then
    vk_icd="$support/components/kosmickrisp/kosmickrisp_icd.json"
  else
    echo "=== KosmicKrisp is not installed in $support/components/kosmickrisp, MoltenVK stays ===" >> "$log" 2>&1 || true
  fi
fi
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
appinfo_tool="$HOME/Library/Application Support/lullaby/appinfo"
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
  iconmaker="$HOME/Library/Application Support/lullaby/iconmaker"
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
  # The program's own icon is read too when there is one: iconmaker takes the biggest of the two, and
  # Steam's published icon is often 48 px where the exe carries 256.
  alt_arg=""
  case "$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')" in
    *.exe) [ -f "$target" ] && alt_arg="$target" ;;
  esac
  # icon_style: iconmaker's look (its styleVersion); a cached icon of another look is made again.
  icon_style=3
  icon_source=""
  if [ -n "$art" ]; then
    icon_source="$art $(stat -f %m "$art" 2>/dev/null || echo 0) ${alt_arg:+$(stat -f %m "$alt_arg" 2>/dev/null || echo 0)} style$icon_style"
  fi
  icon_cache="$loader_root/game.icns"
  if [ -n "$art" ] && [ -s "$icon_cache" ] &&   [ "$(cat "$loader_root/lullaby-icon.source" 2>/dev/null)" =   "$icon_source" ] && cp -f "$icon_cache" "$loader_res/game.icns"; then
    icon_arg="  <key>CFBundleIconFile</key><string>game</string>"
    echo "icon reused from $art" >> "$log" 2>&1 || true
  elif [ -n "$art" ] && [ -x "$iconmaker" ]; then
    if "$iconmaker" "$art" "$icon_cache" ${alt_arg:+--alt "$alt_arg"} >> "$log" 2>&1 &&   cp -f "$icon_cache" "$loader_res/game.icns"; then
      icon_arg="  <key>CFBundleIconFile</key><string>game</string>"
      printf '%s\n' "$icon_source" > "$loader_root/lullaby-icon.source"
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
if [ "${LULLABY_HIDE_LAUNCHER_TILE:-0}" = "1" ]; then
  uielement_arg="  <key>LSUIElement</key><true/>"
  echo "launcher tile hidden by LULLABY_HIDE_LAUNCHER_TILE" >> "$log" 2>&1 || true
fi
# macOS Game Mode (Performance > macOS Game Mode): off, the bundle opts out, so apps in
# the background (OBS, a VTuber model) keep their share of the CPU and GPU while streaming.
gamemode_arg=""
if [ "$(env_value LULLABY_GAME_MODE)" = "0" ]; then
  gamemode_arg="  <key>LSSupportsGameMode</key><false/>"
  echo "game mode off (LULLABY_GAME_MODE=0)" >> "$log" 2>&1 || true
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
  <key>NSMicrophoneUsageDescription</key><string>This game would like to access your microphone.</string>
  <key>NSCameraUsageDescription</key><string>This game would like to access your camera.</string>
  <key>NSLocalNetworkUsageDescription</key><string>This game would like to access devices on your local network.</string>
$uielement_arg
$gamemode_arg
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
wine_log="$loader_root/lullaby-wine.log"
exec > "\$wine_log" 2>&1
shim="$HOME/Library/Application Support/lullaby/overlay-shim.dylib"
if [ -n "\$STEAM_DYLD_INSERT_LIBRARIES" ]; then
  if [ -f "\$shim" ]; then
    export DYLD_INSERT_LIBRARIES="\$shim:\$STEAM_DYLD_INSERT_LIBRARIES"
    export LULLABY_OVERLAY_SHIM="\$shim"
    # Bridges built before the rename (r5-1 and older) read the old name.
    export NOTPROTON_OVERLAY_SHIM="\$shim"
  else
    export DYLD_INSERT_LIBRARIES="\$STEAM_DYLD_INSERT_LIBRARIES"
  fi
fi
# The state the game's window was left in is kept in the prefix and put back (lby-pinkiepie-windowstate);
# LULLABY_WINDOW_STATE=0 as a launch option turns that off for a run (the library reads it itself).
# The bundle's icon stays in the Dock: the engine would put the program's own window icon over it once the
# window is up (a lower-resolution, unstyled picture).
${icon_arg:+export LULLABY_KEEP_BUNDLE_ICON=1}
window_state="$HOME/Library/Application Support/lullaby/lullaby-windowstate.dylib"
if [ -f "\$window_state" ]; then
  export DYLD_INSERT_LIBRARIES="\$window_state\${DYLD_INSERT_LIBRARIES:+:\$DYLD_INSERT_LIBRARIES}"
  export LULLABY_WINDOW_STATE_FILE="$WINEPREFIX/.sevo/lullaby-window.json"
fi
# Frame pacing of the game's presentation (lby-ponthree-pacer): the library does nothing unless PACER_MODE asks for it.
pacer="$HOME/Library/Application Support/lullaby/lullaby-pacer.dylib"
if [ -f "\$pacer" ]; then
  export DYLD_INSERT_LIBRARIES="\$pacer\${DYLD_INSERT_LIBRARIES:+:\$DYLD_INSERT_LIBRARIES}"
fi
[ -n "\$LULLABY_GAME_CWD" ] && cd "\$LULLABY_GAME_CWD"
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

# Test runs only: LULLABY_WATCHDOG=<seconds> in the launch options ends a game
# that has drawn no frame by then, which is how a modal error box or a hang looks
# from outside. A player's run never sets it, so a dialog stays on screen for them.
start_watchdog() {
  limit=${LULLABY_WATCHDOG:-0}
  case "$limit" in ''|*[!0-9]*|0) return 0 ;; esac
  parent=$$
  (
    waited=0
    while [ "$waited" -lt "$limit" ]; do
      sleep 1
      waited=$((waited + 1))
      kill -0 "$parent" 2>/dev/null || exit 0
      grep -a -q "first present" "$loader_root/lullaby-wine.log" 2>/dev/null && exit 0
    done
    shot="$STEAM_COMPAT_DATA_PATH/lullaby-watchdog.png"
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
# Lullaby's Reflex: the D3DMetal layer's present feed and the nvapi64 log.
for name in LULLABY_PRESENT_FEED LULLABY_NVAPI_LOG; do
  eval "value=\${$name-}"
  [ -n "$value" ] && set -- --env "$name=$value" "$@"
done
# What the launch options set and the list above leaves out. The ones Lullaby builds
# itself (below) carry the player's part already.
for name in $launch_env; do
  case "$name" in
    # CX_GRAPHICS*: launch options left from CrossOver days; Dormison reads none of them.
    Steam*|CX_GRAPHICS*|D3DM_*|DXMT_*|DXVK_*|MTL_*|ROSETTA_*|SEVO_*) continue ;;
    WINESERVER|WINEDLLPATH|WINEDLLPATH_PREPEND|WINEDLLOVERRIDES|WINEMSYNC|WINEPREFIX|WINEDEBUG) continue ;;
    PATH|STEAM_COMPAT_*|STEAM_DYLD_INSERT_LIBRARIES|LULLABY_GAME_CWD) continue ;;
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
  --env LULLABY_GAME_CWD="$game_cwd" "$@"
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A"
lsregister="$lsregister/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$lsregister" ] && "$lsregister" -f "$loader_app" >> "$log" 2>&1 || true
open -n -W -a "$loader_app" "$@" >> "$log" 2>&1 &
open_pid=$!
# A game pad does not count as activity: keep the Mac and its display awake while the game runs (upstream
# NotProton 1.2.0).
[ -x /usr/bin/caffeinate ] && { /usr/bin/caffeinate -d -i -w "$open_pid" >> "$log" 2>&1 & }
# The one thing the API scout ever shows: the game did not start, and where to change the backend.
# Steam ends this script as soon as the game is gone, so the notice is started the moment the
# game's launcher has returned, before the waits and the prefix clean-up.
scout_notice() { # STATUS
  [ "$verb" = waitforexitandrun ] || return 0
  apiscout_notice_needed "$1" "$(( $(date +%s) - run_started ))" || [ "$LULLABY_SCOUT_NOTICE_TEST" = 1 ] || return 0
  notice_game=${bundle_name:-${exe_name%.exe}}
  echo "=== notice: $notice_game did not start with $renderer (${scout_api:-?}) ===" >> "$log" 2>&1 || true
  notice_cli="$support/lullaby-settings"
  if [ -x "$notice_cli" ]; then
    ( nohup "$notice_cli" notice game-not-started --game "$notice_game" --renderer "$renderer" --api "${scout_api:-?}" --center-on Steam --icon-of "$loader_app" >/dev/null 2>&1 & ) || true
  else
    notice=$(apiscout_notice_text "$notice_game" "$renderer" "${scout_api:-?}")
    ( nohup osascript -e "display dialog \"$notice\" with title \"Lullaby\" buttons {\"OK\"} default button 1 with icon caution giving up after 120" >/dev/null 2>&1 & ) || true
  fi
}
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
    scout_notice "$status"
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
