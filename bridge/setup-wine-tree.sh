#!/bin/sh
# Create and configure the wine tree that the component builds need.
#
#   ./setup-wine-tree.sh   create and configure, skipping whatever is already done
#
# The engine is Dormison, and its release ships a runtime-only Wine with no winegcc
# or winebuild, so lsteamclient and the steam.exe shim are built in a wine source
# tree and staged into the bridge unsigned.
#
# The base is Dormison's own source at the commit its release was built from
# (engine-info.json -> commit; dormison-b1 is 52c2a4b918d6). ntdll from a different
# vintage speaks a different server protocol, and lsteamclient.so links against the
# ntdll.so built here, so the tree has to be that commit and nothing else.
#
# The source is a detached git worktree of DORMISON_REPO, so the checkout there is
# never touched. A missing commit is fetched from DORMISON_URL first.
#
# A unix half loads into the wine loader's own process and has to match its arch.
# Dormison's loader is x86_64 (Rosetta), which on an Apple Silicon host needs the
# cross configure that HOST and the two compilers below provide. Dormison builds
# with -std=gnu23 (build-macos/configure.sh), so the compilers here do too. The PE
# halves come from mingw.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"

DORMISON_REPO="${DORMISON_REPO:-$repo/scratch/dormison}"
DORMISON_URL="${DORMISON_URL:-https://github.com/kageroumado/dormison.git}"
# The commit dormison-b1 was built from. A worktree records what it resolved to,
# so a moved branch can never change what gets built here without a signal.
WINE_COMMIT="${WINE_COMMIT:-52c2a4b918d6ec5f469ed4e5f58777598c9378ff}"
WINE_SRC="${WINE_SRC:-$repo/scratch/dormison-src}"
WINE_BUILD="${WINE_BUILD:-$repo/scratch/dormison-build}"
# i386 is built because a 32 bit game needs the i386 PE halves. freetype and X are
# off because nothing built here uses either.
CONFIGURE_OPTS="${CONFIGURE_OPTS:---enable-archs=i386,x86_64 --without-freetype --without-x}"
HOST="${HOST:-x86_64-apple-darwin}"
# Taken from HOST rather than spelled out twice, since configure normalises it.
HOST_CPU="${HOST%%-*}"
HOST_CC="${HOST_CC:-clang -arch x86_64 -std=gnu23}"
HOST_CXX="${HOST_CXX:-clang++ -arch x86_64}"

# The bison and autoconf macOS ships are too old for wine's configure.
PATH="/opt/homebrew/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/autoconf/bin:$PATH"
export PATH

missing=""
for tool in git make bison flex i686-w64-mingw32-gcc x86_64-w64-mingw32-gcc; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
    echo "==> missing tools:$missing" >&2
    echo "    brew install mingw-w64 bison flex" >&2
    exit 1
fi

if [ ! -e "$WINE_SRC/.git" ]; then
    [ -d "$DORMISON_REPO/.git" ] || {
        echo "==> no Dormison checkout at $DORMISON_REPO" >&2
        echo "    git clone --filter=blob:none $DORMISON_URL $DORMISON_REPO" >&2
        exit 1
    }
    if ! git -C "$DORMISON_REPO" cat-file -e "$WINE_COMMIT^{commit}" 2>/dev/null; then
        echo "==> fetching $WINE_COMMIT into $DORMISON_REPO"
        git -C "$DORMISON_REPO" fetch "$DORMISON_URL" "$WINE_COMMIT"
    fi
    echo "==> adding a worktree of $DORMISON_REPO at $WINE_COMMIT: $WINE_SRC"
    git -C "$DORMISON_REPO" worktree add --detach "$WINE_SRC" "$WINE_COMMIT"
else
    echo "==> source tree present, leaving it alone: $WINE_SRC"
fi

head="$(git -C "$WINE_SRC" rev-parse HEAD)"
if [ "$head" != "$WINE_COMMIT" ]; then
    echo "==> $WINE_SRC is at $head, not the pinned $WINE_COMMIT" >&2
    echo "    It is not the commit the engine release was built from." >&2
    echo "    Set WINE_COMMIT to the engine's engine-info.json commit." >&2
    exit 1
fi
echo "==> source tree at pinned $WINE_COMMIT"

if grep -q 'WINE_CONFIG_MAKEFILE(dlls/lsteamclient)' "$WINE_SRC/configure.ac"; then
    echo "==> components already registered with configure"
else
    echo "==> registering dlls/lsteamclient and programs/steam.exe with configure"
    ( cd "$WINE_SRC" && git apply "$here/register-components.diff" )
fi

"$repo/bridge/lsteamclient/fetch.sh"
"$repo/bridge/steam-shim/fetch-headers.sh"

# Whole trees, not just the two Makefile.in files: makedep reads the SOURCES each one
# lists and fails the entire configure if any of those files is absent.
mkdir -p "$WINE_SRC/dlls/lsteamclient" "$WINE_SRC/programs/steam.exe"
rsync -a "$repo/build/lsteamclient/" "$WINE_SRC/dlls/lsteamclient/"
rsync -a --exclude build.sh --exclude gen-implib.sh --exclude fetch-headers.sh \
    "$repo/bridge/steam-shim/" "$WINE_SRC/programs/steam.exe/"
echo "==> placed sources for dlls/lsteamclient and programs/steam.exe"

# The release's install prefix is compiled into ntdll.so (BINDIR, DLLDIR, DATADIR), and
# a different one moves every later byte of its data: dormison-r6 was configured with
# --prefix=/Users/kirie/Developer/build/dormison/stage, r5 with the default, and the
# unpatched rebuild only matches the release's code with the release's prefix. Read off
# the engine's ntdll.so (ENGINE, the unpacked release) unless CONFIGURE_OPTS names one.
if [ -n "${ENGINE:-}" ] && [ -f "$ENGINE/wine/lib/wine/x86_64-unix/ntdll.so" ]; then
    case " $CONFIGURE_OPTS " in
    *" --prefix="*) ;;
    *)
        release_prefix=$(strings -a "$ENGINE/wine/lib/wine/x86_64-unix/ntdll.so" \
            | sed -n 's|^\(/.*\)/lib/wine$|\1|p' | head -1)
        if [ -n "$release_prefix" ]; then
            CONFIGURE_OPTS="$CONFIGURE_OPTS --prefix=$release_prefix"
            echo "==> the release was built with --prefix=$release_prefix"
        fi
        ;;
    esac
fi

# A release that ships libfreetype (dormison-r6 does) has win32u.so built with it, and
# win32u is only rebuilt equal to the release with freetype on too: the headers come
# from the host (pkg-config or Homebrew), the library from the engine itself, which is
# the x86_64 build the unix half has to link against.
if [ -n "${ENGINE:-}" ] && [ -f "$ENGINE/wine/lib/libfreetype.dylib" ]; then
    case " $CONFIGURE_OPTS " in
    *" --without-freetype "*)
        ft_cflags=$(pkg-config --cflags freetype2 2>/dev/null || true)
        [ -n "$ft_cflags" ] || ft_cflags="-I$(brew --prefix freetype 2>/dev/null || echo /opt/homebrew)/include/freetype2"
        CONFIGURE_OPTS=$(echo " $CONFIGURE_OPTS " | sed 's/ --without-freetype / --with-freetype /')
        export FREETYPE_CFLAGS="$ft_cflags" FREETYPE_LIBS="-L$ENGINE/wine/lib -lfreetype"
        echo "==> the release ships freetype: configuring with it ($FREETYPE_CFLAGS)"
        ;;
    esac
fi

# The names win32u.so dlopens (libfreetype, libvulkan) are compiled in from configure's
# SONAME probe, and against the release's libraries that probe stores a whole line of
# `otool -L` ("<tab>libfreetype.dylib (compatibility version 27.0.0, ...)") instead of a
# file name: the rebuilt win32u.so then finds neither FreeType (no fonts) nor Vulkan. The
# release's own win32u.so says what the names are, so they are taken from it, both for a
# fresh configure and for a tree that was configured before.
release_soname() {
    strings -a "$ENGINE/wine/lib/wine/x86_64-unix/win32u.so" | sed -n "s|^\\(lib$1[^ ]*\\.dylib\\)\$|\\1|p" | head -1
}
if [ -n "${ENGINE:-}" ] && [ -f "$ENGINE/wine/lib/wine/x86_64-unix/win32u.so" ]; then
    ft_soname=$(release_soname freetype)
    vk_soname=$(release_soname vulkan)
    [ -z "$ft_soname" ] || export ac_cv_lib_soname_freetype="$ft_soname"
    [ -z "$vk_soname" ] || export ac_cv_lib_soname_vulkan="$vk_soname"
fi

# The release's own libraries (libvulkan, libMoltenVK, libfreetype, x86_64 builds the
# engine ships in wine/lib) decide what configure turns on, as on the machine the
# release was built on: without libvulkan the rebuilt win32u.so lacks its Vulkan code
# and no longer equals the release. Configure looks there first.
if [ -n "${ENGINE:-}" ] && [ -d "$ENGINE/wine/lib" ]; then
    export LDFLAGS="-L$ENGINE/wine/lib ${LDFLAGS:-}"
    echo "==> configure links against the release's libraries in $ENGINE/wine/lib"
fi

# A configure that dies in config.status still leaves config.status behind, so that
# is not the thing to test for. The Makefile is what has to exist.
if [ -f "$WINE_BUILD/Makefile" ]; then
    echo "==> build tree already configured, leaving it alone: $WINE_BUILD"
else
    echo "==> configuring $WINE_BUILD"
    mkdir -p "$WINE_BUILD"
    # Unquoted on purpose so the options split. CC and CXX are each a command plus flag.
    # shellcheck disable=SC2086
    ( cd "$WINE_BUILD" && "$WINE_SRC/configure" $CONFIGURE_OPTS \
        --host="$HOST" CC="$HOST_CC" CXX="$HOST_CXX" )
fi

# A tree configured before the names were taken from the release carries the garbled ones in
# config.h. config.h keeps its time (everything would be rebuilt otherwise); only the two
# objects that use the names are rebuilt.
fix_soname() {
    cfg="$WINE_BUILD/include/config.h"
    [ -n "$2" ] && [ -f "$cfg" ] || return 0
    grep -q "^#define $1 \"$2\"\$" "$cfg" && return 0
    stamp=$(mktemp)
    touch -r "$cfg" "$stamp"
    sed -i '' "s|^#define $1 .*|#define $1 \"$2\"|" "$cfg"
    touch -r "$stamp" "$cfg"
    rm -f "$stamp" "$WINE_BUILD/dlls/win32u/freetype.o" "$WINE_BUILD/dlls/win32u/vulkan.o"
    echo "==> $1 in config.h set to $2"
}
fix_soname SONAME_LIBFREETYPE "${ft_soname:-}"
fix_soname SONAME_LIBVULKAN "${vk_soname:-}"

# A cross configure that quietly falls back to the host compiler produces arm64 unix
# objects that only fail much later, at the link, so check it here instead.
if ! grep -q "^host_cpu = $HOST_CPU" "$WINE_BUILD/config.status"; then
    echo "==> configure did not take the $HOST_CPU host, unix halves would be the wrong arch" >&2
    exit 1
fi

# lsteamclient's unix half links against wine's ntdll.so. It is wine's artifact rather
# than a component's, so it is built here and before the component scripts run.
if [ -f "$WINE_BUILD/dlls/ntdll/ntdll.so" ]; then
    echo "==> dlls/ntdll/ntdll.so already built"
else
    echo "==> building dlls/ntdll/ntdll.so"
    ( cd "$WINE_BUILD" && make dlls/ntdll/ntdll.so )
fi

echo "==> ready, now run: bridge/lsteamclient/build.sh --install"
echo "                    bridge/steam-shim/build.sh --install"
