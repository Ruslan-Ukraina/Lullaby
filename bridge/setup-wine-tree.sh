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

DORMISON_REPO="${DORMISON_REPO:-$HOME/Projects/dormison}"
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

"$repo/lsteamclient/fetch.sh"
"$repo/steam-shim/fetch-headers.sh"

# Whole trees, not just the two Makefile.in files: makedep reads the SOURCES each one
# lists and fails the entire configure if any of those files is absent.
mkdir -p "$WINE_SRC/dlls/lsteamclient" "$WINE_SRC/programs/steam.exe"
rsync -a "$repo/build/lsteamclient/" "$WINE_SRC/dlls/lsteamclient/"
rsync -a --exclude build.sh --exclude gen-implib.sh --exclude fetch-headers.sh \
    "$repo/steam-shim/" "$WINE_SRC/programs/steam.exe/"
echo "==> placed sources for dlls/lsteamclient and programs/steam.exe"

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

echo "==> ready, now run: ../lsteamclient/build.sh --install"
echo "                    ../steam-shim/build.sh --install"
