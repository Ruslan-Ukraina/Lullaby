CC       := clang
ARCH     := arm64
MIN_VER  := 15.0

CFLAGS   := -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) \
            -std=c17 -O2 -Wall -Wextra -Wno-unused-parameter \
            -fPIC -MMD -MP \
            -Isteam/hook -Ivendor -Ivendor/dobby/include
LDFLAGS  := -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) \
            -dynamiclib -install_name @rpath/lullaby.dylib

# AppKit is weak: steam_osx and Steam Helper have it, nothing else needs it.
FRAMEWORKS := -framework CoreFoundation -framework Foundation -framework CoreGraphics -weak_framework AppKit -lobjc

DOBBY_DIR  := build/dobby
DOBBY_LIBS := $(DOBBY_DIR)/libdobby.a \
              $(DOBBY_DIR)/builtin-plugin/SymbolResolver/libdobby_symbol_resolver.a \
              $(DOBBY_DIR)/builtin-plugin/SymbolResolver/libmacho_ctx_kit.a \
              $(DOBBY_DIR)/builtin-plugin/SymbolResolver/libshared_cache_ctx_kit.a \
              $(DOBBY_DIR)/external/osbase/libosbase.a \
              $(DOBBY_DIR)/external/logging/liblogging.a

SRCS := \
	steam/hook/core/loader.c \
	steam/hook/core/macho.c \
	steam/hook/resolver/anchor.c \
	steam/hook/resolver/aob.c \
	steam/hook/resolver/resolver.c \
	steam/hook/resolver/sigdb.c \
	steam/hook/util/log.c \
	steam/hook/util/file.c \
	steam/hook/util/peicon.c \
	steam/hook/hooks/hooks.c \
	steam/hook/hooks/hook_compat.c \
	steam/hook/hooks/hook_shortcut.c \
	steam/hook/hooks/hook_icon.c \
	steam/hook/hooks/hook_webui.c \
	steam/hook/hooks/hook_webpatch.c \
	steam/hook/hooks/hook_spawn.c \
	steam/hook/hooks/hook_launch.c \
	steam/hook/feats/compat.c \
	steam/hook/feats/webui.c \
	steam/hook/feats/compatsvc.c \
	steam/hook/feats/webpatch.c \
	steam/hook/feats/settingsbridge.c \
	steam/hook/feats/steamwin_css.c \
	steam/hook/feats/updategate.c \
	steam/hook/feats/input_access.c \
	vendor/cJSON.c

# Objective-C: AppKit through the runtime, for Steam Helper's windows.
OBJC_SRCS := steam/hook/feats/steamwin.m steam/hook/feats/steamfocus.m

OUT_DIR     := out

GENERATED_DIR := $(OUT_DIR)/generated
RUN_SCRIPT_H  := $(GENERATED_DIR)/compat_run.h
PANEL_JS_H    := $(GENERATED_DIR)/panel_js.h
CFLAGS += -I$(GENERATED_DIR)

ARM64_DYLIB := $(OUT_DIR)/lullaby.arm64.dylib
X86_STUB    := $(OUT_DIR)/lullaby.x86_64.dylib
TARGET      := $(OUT_DIR)/lullaby.dylib

OBJS := $(patsubst %.c,$(OUT_DIR)/%.o,$(SRCS)) $(patsubst %.m,$(OUT_DIR)/%.o,$(OBJC_SRCS))
DEPS := $(OBJS:.o=.d)

.PHONY: all iconmaker-tests windowstate windowstate-tests nvapi-shim reflex-sim patchcheck clean rebuild dobby deploy dylib-install sigcheck app-payload app app-zip app-config \
        anchorcheck callscheck sigdb-fixtures webpatch-fixtures peicon-fixtures panel-behavior app-tests launch-shell \
        tests-list overlay-shim overlay-shim-install overlay-shim-tests \
        overlay-shim-bench iconmaker icon \
        appinfo helpers-install bridge runcheck compatcheck \
        compatsvc-check scriptcheck steamwin-check updategate-check settingsbridge-check webpatch-syntax sigslice

APP_PAYLOAD := app/Sources/LullabyApp/Resources/payload

all: $(TARGET) $(APP_PAYLOAD)

# SwiftPM's `.copy("Resources/payload")` in Package.swift needs this directory
# to exist
$(APP_PAYLOAD):
	@mkdir -p $(APP_PAYLOAD)

TEST_PATHS := steam/hook/tests steam/overlay/tests app/Tests

tests-list:
	@for p in $(TEST_PATHS); do echo $$p; done

# A check with no inputs left is reported
SKIP = echo "==> $(1): $(2) not present, skipped"

runcheck:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		$(call SKIP,runcheck,shellcheck); exit 0; fi; \
	shellcheck steam/hook/feats/compat_run.sh && sh -n steam/hook/feats/compat_run.sh && \
	shellcheck steam/hook/tests/termcheck.sh steam/hook/tests/stubcheck.sh steam/hook/tests/watchdogcheck.sh steam/hook/tests/routecheck.sh steam/hook/tests/settingscheck.sh steam/hook/tests/bitnesscheck.sh steam/hook/tests/overridecheck.sh && sh steam/hook/tests/termcheck.sh && sh steam/hook/tests/stubcheck.sh && sh steam/hook/tests/watchdogcheck.sh && sh steam/hook/tests/routecheck.sh steam/hook/feats/compat_run.sh && sh steam/hook/tests/settingscheck.sh steam/hook/feats/compat_run.sh && sh steam/hook/tests/bitnesscheck.sh && sh steam/hook/tests/overridecheck.sh && \
	echo "==> runcheck: the run script lints and parses clean"

# runcheck owns compat_run.sh, whose warnings wait for a change that can move
# the embedded __text baseline
SCRIPTS := $(shell git ls-files '*.sh' 2>/dev/null | grep -v '^steam/hook/feats/compat_run\.sh$$')

scriptcheck:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		$(call SKIP,scriptcheck,shellcheck); exit 0; fi; \
	if [ -z "$(strip $(SCRIPTS))" ]; then $(call SKIP,scriptcheck,a git checkout); exit 0; fi; \
	for s in $(SCRIPTS); do \
		shellcheck -x "$$s" || exit 1; \
		sh -n "$$s" || exit 1; \
	done; \
	echo "==> scriptcheck: $(words $(SCRIPTS)) scripts lint and parse clean"

# Every engine patch is in patches/REGISTRY.md and has a header, and the registry names no missing one.
patchcheck:
	patches/engine/check-registry.sh

COMPATCHECK := $(OUT_DIR)/compatcheck

compatcheck: $(RUN_SCRIPT_H)
	@if [ ! -f steam/hook/tests/compatcheck.c ]; then $(call SKIP,compatcheck,steam/hook/tests/compatcheck.c); exit 0; fi; \
	mkdir -p $(OUT_DIR) && \
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook -I$(GENERATED_DIR) \
	  -o $(COMPATCHECK) steam/hook/tests/compatcheck.c && \
	$(COMPATCHECK)

COMPATSVC_CHECK := $(OUT_DIR)/compatsvc-check

compatsvc-check:
	@if [ ! -f steam/hook/tests/compatsvc-check.c ]; then $(call SKIP,compatsvc-check,steam/hook/tests/compatsvc-check.c); exit 0; fi; \
	mkdir -p $(OUT_DIR) && \
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook \
	  -o $(COMPATSVC_CHECK) steam/hook/tests/compatsvc-check.c && \
	$(COMPATSVC_CHECK)

sigcheck:
	@if [ ! -f steam/hook/tests/sigcheck.py ]; then $(call SKIP,sigcheck,steam/hook/tests/sigcheck.py); exit 0; fi; \
	python3 steam/hook/tests/sigcheck.py

# Validates anchors against a real dlopen'd steamclient.dylib
ANCHORCHECK := $(OUT_DIR)/anchorcheck
ANCHORCHECK_SRCS := steam/hook/tests/anchorcheck.c \
	steam/hook/core/macho.c steam/hook/resolver/aob.c steam/hook/resolver/anchor.c \
	steam/hook/resolver/resolver.c steam/hook/resolver/sigdb.c \
	steam/hook/util/log.c steam/hook/util/file.c vendor/cJSON.c

$(ANCHORCHECK): $(ANCHORCHECK_SRCS)
	@mkdir -p $(dir $@)
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g -O1 \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook -Ivendor \
	  -o $@ $(ANCHORCHECK_SRCS)

anchorcheck:
	@if [ ! -f steam/hook/tests/anchorcheck.c ]; then $(call SKIP,anchorcheck,steam/hook/tests/anchorcheck.c); exit 0; fi; \
	$(MAKE) -s $(ANCHORCHECK) && $(ANCHORCHECK)

# Cuts a database for a new client build from an older one (docs/BACKLOG.md 22):
# out/sigslice <base.json> <build> <out.json>, with HOME as for anchorcheck.
SIGSLICE := $(OUT_DIR)/sigslice

$(SIGSLICE): steam/hook/tests/sigslice.c $(filter-out steam/hook/tests/anchorcheck.c,$(ANCHORCHECK_SRCS))
	@mkdir -p $(dir $@)
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g -O1 \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook -Ivendor \
	  -o $@ $^

sigslice: $(SIGSLICE)

CALLSCHECK := $(OUT_DIR)/callscheck
CALLSCHECK_SRCS := steam/hook/tests/callscheck.c $(filter-out steam/hook/tests/anchorcheck.c,$(ANCHORCHECK_SRCS))

$(CALLSCHECK): $(CALLSCHECK_SRCS)
	@mkdir -p $(dir $@)
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g -O1 \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook -Ivendor \
	  -fsanitize=address,undefined -fno-sanitize-recover=all \
	  -o $@ $(CALLSCHECK_SRCS)

callscheck:
	@if [ ! -f steam/hook/tests/callscheck.c ]; then $(call SKIP,callscheck,steam/hook/tests/callscheck.c); exit 0; fi; \
	$(MAKE) -s $(CALLSCHECK) && $(CALLSCHECK)

SIGDB_FIXTURES := steam/hook/tests/sigdb-fixtures

sigdb-fixtures:
	@if [ ! -d $(SIGDB_FIXTURES) ] || [ ! -f steam/hook/tests/anchorcheck.c ]; then \
		$(call SKIP,sigdb-fixtures,$(SIGDB_FIXTURES)); exit 0; fi; \
	$(MAKE) -s $(ANCHORCHECK) || exit 1; \
	fail=0; n=0; \
	for f in $(SIGDB_FIXTURES)/*.json; do \
		n=$$((n+1)); \
		want=$$(awk -v name="$${f##*/}" '$$2 == name { print $$1 }' $(SIGDB_FIXTURES)/EXPECTED); \
		out=$$($(ANCHORCHECK) "$$f" 2>&1); rc=$$?; \
		if [ $$rc -ge 128 ]; then echo "crashed (rc=$$rc): $$f"; fail=1; continue; fi; \
		if [ $$rc -eq 3 ]; then \
			echo "anchorcheck cannot run here, so none of these fixtures were checked:"; \
			echo "$$out" | tail -1; fail=1; break; fi; \
		if [ -z "$$want" ]; then \
			echo "no expected status in $(SIGDB_FIXTURES)/EXPECTED: $$f"; fail=1; continue; fi; \
		if [ "$$rc" != "$$want" ]; then \
			echo "expected $$want, got $$rc: $$f"; fail=1; fi; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi; \
	echo "==> $$n sigdb fixtures: none crashed, each exited as $(SIGDB_FIXTURES)/EXPECTED records"

PEICON_CHECK := $(OUT_DIR)/peicon-check

$(PEICON_CHECK): steam/hook/tests/peicon-check.c steam/hook/util/peicon.c steam/hook/util/peicon.h
	@mkdir -p $(dir $@)
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g -O1 \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook \
	  -o $@ steam/hook/tests/peicon-check.c steam/hook/util/peicon.c

peicon-fixtures:
	@if [ ! -f steam/hook/tests/peicon-check.c ]; then \
		$(call SKIP,peicon-fixtures,steam/hook/tests/peicon-check.c); exit 0; fi; \
	$(MAKE) -s $(PEICON_CHECK) || exit 1; \
	tmp=$$(mktemp -d); \
	$(PEICON_CHECK) "$$tmp"; rc=$$?; \
	rm -rf "$${tmp:?}"; \
	if [ $$rc -eq 9 ]; then \
		echo "peicon-check ran out of time, so a hostile resource tree is unbounded"; fi; \
	exit $$rc

GATECHECK         := $(OUT_DIR)/gatecheck
WEBPATCH_FIXTURES := steam/hook/tests/webpatch-fixtures

$(GATECHECK): steam/hook/tests/gatecheck.c steam/hook/feats/webpatch.c steam/hook/feats/webpatch.h $(PANEL_JS_H)
	@mkdir -p $(dir $@)
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g -O1 \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook -I$(GENERATED_DIR) -o $@ steam/hook/tests/gatecheck.c

webpatch-fixtures:
	@if [ ! -d $(WEBPATCH_FIXTURES) ] || [ ! -f steam/hook/tests/gatecheck.c ]; then \
		$(call SKIP,webpatch-fixtures,$(WEBPATCH_FIXTURES)); exit 0; fi; \
	$(MAKE) -s $(GATECHECK) || exit 1; \
	$(GATECHECK) || exit 1; \
	fail=0; tmp=$$(mktemp -d); n=0; \
	for good in $(WEBPATCH_FIXTURES)/gates.*.js; do \
		n=$$(( $$n + 1 )); base=$$(basename $$good .js); \
		cat $$good $$good > $$tmp/$$base.doubled.js; \
		head -c $$(( $$(stat -f %z $$good) / 2 )) $$good > $$tmp/$$base.truncated.js; \
		for spec in "$$good:APPLIED" "$$tmp/$$base.doubled.js:REJECTED" \
		            "$$tmp/$$base.truncated.js:REJECTED"; do \
			f=$${spec%:*}; want=$${spec##*:}; \
			out=$$($(GATECHECK) "$$f" 2>&1); rc=$$?; \
			case "$$out" in *WRONG*) echo "$$out"; fail=1 ;; esac; \
			case "$$out" in *$$want*) ;; *) echo "expected $$want: $$out"; fail=1 ;; esac; \
			if [ $$rc -ne 0 ]; then fail=1; fi; \
		done; \
	done; \
	rm -rf "$${tmp:?}"; \
	if [ $$fail -ne 0 ]; then exit 1; fi; \
	echo "==> gate table and $$n webpatch fixtures: anchors intact, drift refused"

STEAMWINCHECK := $(OUT_DIR)/steamwincheck

$(STEAMWINCHECK): steam/hook/tests/steamwincheck.c steam/hook/feats/steamwin_css.c steam/hook/feats/steamwin_css.h
	@mkdir -p $(dir $@)
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g -O1 \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook -o $@ steam/hook/tests/steamwincheck.c

steamwin-check:
	@$(MAKE) -s $(STEAMWINCHECK) && $(STEAMWINCHECK)

# Steam's update block written back inside the client, and the newest-first list of
# signature databases the loader tries (Phase 5).
UPDATEGATE_CHECK := $(OUT_DIR)/updategate-check

updategate-check:
	@mkdir -p $(OUT_DIR) && \
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g -O1 \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook -Ivendor -o $(UPDATEGATE_CHECK) \
	  steam/hook/tests/updategate-check.c steam/hook/feats/updategate.c steam/hook/resolver/sigdb.c \
	  steam/hook/util/file.c vendor/cJSON.c && \
	$(UPDATEGATE_CHECK)

SETTINGSBRIDGE_CHECK := $(OUT_DIR)/settingsbridge-check

settingsbridge-check:
	@mkdir -p $(OUT_DIR) && \
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g -O1 \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook -o $(SETTINGSBRIDGE_CHECK) \
	  steam/hook/tests/settingsbridge-check.c steam/hook/feats/settingsbridge.c steam/hook/util/file.c steam/hook/util/log.c && \
	$(SETTINGSBRIDGE_CHECK)

# The webpatch on the Steam chunks of this Mac, checked by node as JavaScript: the
# panel spliced into Steam's own code must parse. Skipped without Steam or node.
STEAMUI_DIR ?= $(HOME)/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steamui

webpatch-syntax: $(PANEL_JS_H)
	@if ! command -v node >/dev/null 2>&1 || [ ! -d "$(STEAMUI_DIR)" ]; then \
		echo "==> webpatch-syntax: no node or no Steam, skipped"; exit 0; fi; \
	mkdir -p $(OUT_DIR) && \
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g -O1 \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook -I$(GENERATED_DIR) -o $(OUT_DIR)/webpatch-apply \
	  steam/hook/tests/webpatch-apply.c steam/hook/feats/webpatch.c steam/hook/feats/settingsbridge.c \
	  steam/hook/util/file.c steam/hook/util/log.c && \
	tmp=$$(mktemp -d) && n=0 && \
	for f in "$(STEAMUI_DIR)"/chunk~*.js "$(STEAMUI_DIR)"/library.js "$(STEAMUI_DIR)"/sp.js; do \
		[ -f "$$f" ] && grep -q 'AppProperties_Compat' "$$f" || continue; \
		$(OUT_DIR)/webpatch-apply "$$f" "$$tmp/patched.js" || { rm -rf "$${tmp:?}"; exit 1; }; \
		node --check "$$tmp/patched.js" || { echo "webpatch-syntax: $$f does not parse after the webpatch"; rm -rf "$${tmp:?}"; exit 1; }; \
		node steam/hook/tests/lbselp-check.js "$$tmp/patched.js" || { rm -rf "$${tmp:?}"; exit 1; }; \
		n=$$((n + 1)); \
	done; \
	rm -rf "$${tmp:?}"; \
	echo "==> webpatch-syntax: $$n patched Steam chunk(s) parse"

LAUNCH_SHELL := $(OUT_DIR)/launch-shell

# Launch options through a shell, as on Linux (steam/hook/hooks/hook_launch.c, upstream 1.1.0).
launch-shell:
	@if [ ! -f steam/hook/tests/launch-shell.c ]; then $(call SKIP,launch-shell,steam/hook/tests/launch-shell.c); exit 0; fi; \
	mkdir -p $(OUT_DIR) && \
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g -O1 \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook -o $(LAUNCH_SHELL) steam/hook/tests/launch-shell.c && \
	$(LAUNCH_SHELL)

SPAWN_ENV := $(OUT_DIR)/spawn-env

spawn-env:
	@if [ ! -f steam/hook/tests/spawn-env.c ]; then $(call SKIP,spawn-env,steam/hook/tests/spawn-env.c); exit 0; fi; \
	mkdir -p $(OUT_DIR) && \
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g -O1 \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook -o $(SPAWN_ENV) steam/hook/tests/spawn-env.c && \
	$(SPAWN_ENV)

SPAWN_LIVE := steam/hook/tests/spawn-live

# HOME points into the scratch folder: the dylib logs to <HOME>/Library/Application
# Support/lullaby, and a run here must not create that folder on the developer's Mac.
spawn-live: $(TARGET)
	@if [ ! -d $(SPAWN_LIVE) ]; then $(call SKIP,spawn-live,$(SPAWN_LIVE)); exit 0; fi; \
	tmp=$$(mktemp -d); trap 'rm -rf "$${tmp:?}"' EXIT; mkdir -p $$tmp/sub $$tmp/home; \
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -O1 -Wall -Wextra \
	  -o $$tmp/child $(SPAWN_LIVE)/child.c || exit 1; \
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -O1 -Wall -Wextra \
	  -o $$tmp/steam_osx $(SPAWN_LIVE)/driver.c || exit 1; \
	cp $$tmp/steam_osx $$tmp/inert; cp $$tmp/child $$tmp/steam_osx_child; \
	cp $$tmp/child $$tmp/sub/steam_osx; \
	cp $$tmp/steam_osx "$$tmp/Steam Helper"; cp $$tmp/child "$$tmp/sub/Steam Helper"; \
	fail=0; \
	for spec in "inert:child:1" "steam_osx:child:0" \
	            "steam_osx:steam_osx_child:0" "steam_osx:sub/steam_osx:1" \
	            "steam_osx:sub/Steam Helper:1" "Steam Helper:child:0" \
	            "Steam Helper:sub/Steam Helper:1" "Steam Helper:child:1:--type=renderer"; do \
		drv=$${spec%%:*}; rest=$${spec#*:}; kid=$${rest%%:*}; rest=$${rest#*:}; \
		want=$${rest%%:*}; arg=$${rest#*:}; [ "$$arg" = "$$rest" ] && arg=""; \
		got=$$(HOME=$$tmp/home DYLD_INSERT_LIBRARIES=$$PWD/$(TARGET) "$$tmp/$$drv" "$$tmp/$$kid" $$arg 2>/dev/null \
		       | grep -c "/lullaby.dylib$$") || true; \
		if [ "$$got" != "$$want" ]; then \
			echo "$$drv $$arg -> $$kid: dylib loaded $$got, wanted $$want"; fail=1; fi; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi; \
	echo "==> spawn live: the hook lands, steam_osx and Steam Helper keep the dylib, other children do not"

APP_TESTS := app/Tests

app-tests:
	@if [ ! -d $(APP_TESTS) ]; then $(call SKIP,app-tests,$(APP_TESTS)); exit 0; fi; \
	touch app/Package.swift; cd app && swift test --no-parallel

PANEL_TESTS := steam/hook/tests/panel-behavior

panel-behavior:
	@if [ ! -d $(PANEL_TESTS) ]; then $(call SKIP,panel-behavior,$(PANEL_TESTS)); exit 0; fi; \
	if ! command -v node >/dev/null 2>&1; then \
		echo "==> panel-behavior: node not found, skipped"; exit 0; fi; \
	mkdir -p $(OUT_DIR) && \
	$(MAKE) -s $(PANEL_JS_H) && \
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -g -O1 \
	  -Wall -Wextra -Wno-unused-parameter -Isteam/hook -I$(GENERATED_DIR) -o $(OUT_DIR)/panel-emit \
	  $(PANEL_TESTS)/emit.c && \
	node $(PANEL_TESTS)/catalog.js $(OUT_DIR)/panel-emit $(PANEL_TESTS)/fixtures && \
	node $(PANEL_TESTS)/behavior.js $(OUT_DIR)/panel-emit && \
	node $(PANEL_TESTS)/switching.js $(OUT_DIR)/panel-emit && \
	node $(PANEL_TESTS)/cleanup.js $(OUT_DIR)/panel-emit && \
	echo "==> panel behavior: renders as expected, no stale arguments"

$(ARM64_DYLIB): $(OBJS)
	@mkdir -p $(dir $@)
	$(CC) $(LDFLAGS) -o $@ $^ $(DOBBY_LIBS) $(FRAMEWORKS) -lc++

$(X86_STUB): steam/hook/stub_x86_64.c
	@mkdir -p $(dir $@)
	$(CC) -arch x86_64 -mmacosx-version-min=$(MIN_VER) \
		-dynamiclib -install_name @rpath/lullaby.dylib \
		-o $@ $<

$(TARGET): $(ARM64_DYLIB) $(X86_STUB)
	lipo -create $^ -output $@
	codesign -fs - $@
	@echo "==> Built: $@"

$(OUT_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

OBJCFLAGS := $(filter-out -std=c17,$(CFLAGS)) -fobjc-arc -fobjc-weak
# Steam Helper's debug command channel (lullaby/steam-windows-debug) is for
# development only: `make LB_DEV=1 ...`. Never in a release (docs/BACKLOG.md 20).
ifeq ($(LB_DEV),1)
OBJCFLAGS += -DNP_STEAMWIN_DEBUG=1
endif

$(OUT_DIR)/%.o: %.m
	@mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS) -c $< -o $@

$(RUN_SCRIPT_H): steam/hook/feats/compat_run.sh steam/hook/embed_script.py
	@mkdir -p $(GENERATED_DIR)
	python3 steam/hook/embed_script.py $< $@ RUN_SCRIPT

$(OUT_DIR)/steam/hook/feats/compat.o: $(RUN_SCRIPT_H)

$(PANEL_JS_H): steam/hook/feats/panel.js steam/hook/embed_js.py
	@mkdir -p $(GENERATED_DIR)
	python3 steam/hook/embed_js.py $< $@ LB_PANEL_JS

$(OUT_DIR)/steam/hook/feats/webpatch.o: $(PANEL_JS_H)

SUPPORT_DIR        := $(HOME)/Library/Application Support/lullaby
OVERLAY_SHIM_SRC   := steam/overlay/overlay_shim.m
OVERLAY_SHIM_ARM   := $(OUT_DIR)/overlay-shim.arm64.dylib
OVERLAY_SHIM_X86   := $(OUT_DIR)/overlay-shim.x86_64.dylib
OVERLAY_SHIM       := $(OUT_DIR)/overlay-shim.dylib
OVERLAY_SHIM_FLAGS := -mmacosx-version-min=$(MIN_VER) -dynamiclib -O2 -Wall -Wextra \
                      -install_name @rpath/overlay-shim.dylib \
                      -framework Metal -framework QuartzCore \
                      -framework CoreGraphics -framework CoreFoundation
OVERLAY_SHIM_TESTS := steam/overlay/tests
OVERLAY_SHIM_TEST_FLAGS := -mmacosx-version-min=$(MIN_VER) -O2 -Wall -Wextra \
                      -framework Metal -framework Foundation -framework QuartzCore

overlay-shim: $(OVERLAY_SHIM)

$(OVERLAY_SHIM): $(OVERLAY_SHIM_SRC)
	@mkdir -p $(OUT_DIR)
	$(CC) -arch arm64 $(OVERLAY_SHIM_FLAGS) -o $(OVERLAY_SHIM_ARM) $<
	$(CC) -arch x86_64 $(OVERLAY_SHIM_FLAGS) -o $(OVERLAY_SHIM_X86) $<
	lipo -create $(OVERLAY_SHIM_ARM) $(OVERLAY_SHIM_X86) -output $@
	codesign -fs - $@
	@lipo -info $@

define install_atomically
	@mkdir -p "$$(dirname "$(2)")"
	cp -f "$(1)" "$(2).new"
	mv -f "$(2).new" "$(2)"
endef

overlay-shim-install: $(OVERLAY_SHIM)
	$(call install_atomically,$(OVERLAY_SHIM),$(SUPPORT_DIR)/overlay-shim.dylib)
	@echo "==> Installed: $(SUPPORT_DIR)/overlay-shim.dylib"

overlay-shim-tests: $(OVERLAY_SHIM)
	@if [ ! -d $(OVERLAY_SHIM_TESTS) ]; then \
		$(call SKIP,overlay-shim-tests,$(OVERLAY_SHIM_TESTS)); exit 0; fi; \
	mkdir -p $(OUT_DIR); \
	fail=0; ran=0; skipped=0; \
	for t in device bridge delivery; do \
		for a in arm64 x86_64; do \
			$(CC) -arch $$a $(OVERLAY_SHIM_TEST_FLAGS) -o $(OUT_DIR)/$$t.$$a \
				$(OVERLAY_SHIM_TESTS)/$$t.m || exit 1; \
			out=$$(LULLABY_OVERLAY_SHIM=$(OVERLAY_SHIM) $(OUT_DIR)/$$t.$$a 2>&1); rc=$$?; \
			case "$$rc" in \
			0) ran=$$((ran+1)); echo "$$out" | sed "s/^/  $$t.$$a /" ;; \
			3|126) skipped=$$((skipped+1)); \
			   echo "  $$t.$$a skipped: $$(echo "$$out" | tail -1)" ;; \
			*) echo "  $$t.$$a exited $$rc:"; echo "$$out" | sed "s/^/    /"; fail=1 ;; \
			esac; \
		done; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi; \
	if [ $$ran -eq 0 ]; then \
		echo "overlay shim tests: all $$skipped skipped, so nothing was checked"; exit 1; fi; \
	echo "==> overlay shim tests: $$ran passed, $$skipped skipped"

# lby-pinkiepie-windowstate (patches/inject/): the state a game's window was left in, put back at the
# next launch. Injected into the Wine loader's process, so arm64 (wineserver, which it ignores) and x86_64.
WINDOWSTATE_DIR  := patches/inject/lby-pinkiepie-windowstate
WINDOWSTATE      := $(OUT_DIR)/lullaby-windowstate.dylib
WINDOWSTATE_FLAGS := -mmacosx-version-min=$(MIN_VER) -dynamiclib -O2 -Wall -Wextra -fobjc-arc \
                      -install_name @rpath/lullaby-windowstate.dylib -framework AppKit

windowstate: $(WINDOWSTATE)

$(WINDOWSTATE): $(WINDOWSTATE_DIR)/windowstate.m $(WINDOWSTATE_DIR)/windowstate_core.h
	@mkdir -p $(OUT_DIR)
	$(CC) -arch arm64 $(WINDOWSTATE_FLAGS) -o $(OUT_DIR)/lullaby-windowstate.arm64.dylib $<
	$(CC) -arch x86_64 $(WINDOWSTATE_FLAGS) -o $(OUT_DIR)/lullaby-windowstate.x86_64.dylib $<
	lipo -create $(OUT_DIR)/lullaby-windowstate.arm64.dylib $(OUT_DIR)/lullaby-windowstate.x86_64.dylib -output $@
	codesign -fs - $@
	@lipo -info $@

# The decisions in plain C, then the library in a process with a WineWindow, on both architectures, with
# freed memory scribbled and zombies on: a static that outlives its autorelease pool fails the run.
windowstate-tests: $(WINDOWSTATE)
	@mkdir -p $(OUT_DIR)
	$(CC) -Wall -Wextra -o $(OUT_DIR)/windowstate-core-test $(WINDOWSTATE_DIR)/tests/core_test.c
	$(OUT_DIR)/windowstate-core-test
	@set -e; for a in arm64 x86_64; do \
		$(CC) -arch $$a -mmacosx-version-min=$(MIN_VER) -fobjc-arc -framework AppKit -o $(OUT_DIR)/wine-windowstate-test.$$a \
			$(WINDOWSTATE_DIR)/tests/windowstate_test.m; \
		f=$$(mktemp -d "$${TMPDIR:-/tmp}/windowstate.XXXXXX")/state.json; \
		MallocScribble=1 MallocPreScribble=1 NSZombieEnabled=YES LULLABY_WINDOWSTATE_DYLIB=$(WINDOWSTATE) $(OUT_DIR)/wine-windowstate-test.$$a save "$$f" 1000 640 2>/dev/null; \
		MallocScribble=1 MallocPreScribble=1 NSZombieEnabled=YES LULLABY_WINDOWSTATE_DYLIB=$(WINDOWSTATE) $(OUT_DIR)/wine-windowstate-test.$$a restore "$$f" 1000 640 2>/dev/null; \
		for bad in '{"state":5,"width":"x","height":[]}' '{"state":"window","width":1e999,"height":-3}' '[1,2]' 'not json'; do \
			printf '%s' "$$bad" > "$$f"; \
			MallocScribble=1 MallocPreScribble=1 NSZombieEnabled=YES LULLABY_WINDOWSTATE_DYLIB=$(WINDOWSTATE) $(OUT_DIR)/wine-windowstate-test.$$a damaged "$$f" 0 0 2>/dev/null; \
		done; \
		for on in 1 0; do \
			rm -f "$$f"; \
			MallocScribble=1 MallocPreScribble=1 NSZombieEnabled=YES LULLABY_WINDOWSTATE_DYLIB=$(WINDOWSTATE) $(OUT_DIR)/wine-windowstate-test.$$a fullscreen "$$f" $$on 0 2>/dev/null; \
		done; \
		rm -rf "$$(dirname "$$f")"; \
	done
	@echo "==> windowstate tests: decisions, saving and putting back a window size, arm64 and x86_64"

overlay-shim-bench:
	@if [ ! -f $(OVERLAY_SHIM_TESTS)/passbench.m ]; then \
		$(call SKIP,overlay-shim-bench,$(OVERLAY_SHIM_TESTS)/passbench.m); exit 0; fi; \
	mkdir -p $(OUT_DIR); \
	for a in arm64 x86_64; do \
		$(CC) -arch $$a $(OVERLAY_SHIM_TEST_FLAGS) -o $(OUT_DIR)/passbench.$$a \
			$(OVERLAY_SHIM_TESTS)/passbench.m || exit 1; \
		printf '  %-8s ' "$$a"; $(OUT_DIR)/passbench.$$a || exit 1; \
	done

ICONMAKER := $(OUT_DIR)/iconmaker

iconmaker: $(ICONMAKER)

$(ICONMAKER): app/helpers/iconmaker.swift steam/hook/util/peicon.c steam/hook/util/peicon.h
	@mkdir -p $(OUT_DIR)
	$(CC) -c -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -O2 \
		-Wall -Wextra -o $(OUT_DIR)/peicon-host.o steam/hook/util/peicon.c
	swiftc -O -target $(ARCH)-apple-macos$(MIN_VER) \
		-framework AppKit -import-objc-header steam/hook/util/peicon.h \
		-o $@ app/helpers/iconmaker.swift $(OUT_DIR)/peicon-host.o
	@echo "==> Built $@"

# The look, the choice of the biggest input, the .icns and the time (app/helpers/tests/iconmaker_test.py).
iconmaker-tests: $(ICONMAKER)
	python3 -I app/helpers/tests/iconmaker_test.py $(ICONMAKER)

APPINFO := $(OUT_DIR)/appinfo

appinfo: $(APPINFO)

$(APPINFO): app/helpers/appinfo.swift
	@mkdir -p $(OUT_DIR)
	swiftc -O -target $(ARCH)-apple-macos$(MIN_VER) -o $@ $<
	@echo "==> Built $@"

# Lullaby's nvapi64.dll (patches/inject/lby-rainbowdash-reflex/): NVIDIA Reflex in front of D3DMetal's. Needs mingw-w64.
NVAPI_SHIM := $(OUT_DIR)/lullaby-nvapi64.dll

nvapi-shim: $(NVAPI_SHIM)

# What Reflex by Lullaby is meant to do, in a simulated game under the installed engine's Wine
# (patches/inject/lby-rainbowdash-reflex/tests/run-sim.sh): shorter latency GPU-bound, nothing changed CPU-bound.
# Skips, exit 0, where no engine is installed.
reflex-sim: $(NVAPI_SHIM)
	patches/inject/lby-rainbowdash-reflex/tests/run-sim.sh $(NVAPI_SHIM)

$(NVAPI_SHIM): patches/inject/lby-rainbowdash-reflex/lullaby_nvapi.c patches/inject/lby-rainbowdash-reflex/nvapi_names.h patches/inject/lby-rainbowdash-reflex/nvapi64.def patches/inject/lby-rainbowdash-reflex/build.sh
	@mkdir -p $(OUT_DIR)
	patches/inject/lby-rainbowdash-reflex/build.sh $@
	@echo "==> Built $@"

helpers-install: $(ICONMAKER) $(APPINFO)
	$(call install_atomically,$(ICONMAKER),$(SUPPORT_DIR)/iconmaker)
	$(call install_atomically,$(APPINFO),$(SUPPORT_DIR)/appinfo)
	@echo "==> Installed: $(SUPPORT_DIR)/{iconmaker,appinfo}"

dobby:
	@mkdir -p $(DOBBY_DIR)
	cd $(DOBBY_DIR) && cmake $(CURDIR)/vendor/dobby \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=$(MIN_VER) \
		-DDOBBY_DEBUG=OFF \
		-DDOBBY_GENERATE_SHARED=OFF \
		-G "Unix Makefiles"
	$(MAKE) -C $(DOBBY_DIR) -j$(shell sysctl -n hw.ncpu)

STEAM_APP    := /Applications/Steam.app
DEPLOY_DST   := $(STEAM_APP)/Contents/MacOS/lullaby.dylib
INSTALL_DST  := $(SUPPORT_DIR)/lullaby.dylib

dylib-install: $(TARGET)
	$(call install_atomically,$(TARGET),$(INSTALL_DST))
	@echo "==> Installed: $(INSTALL_DST)"

sigdb-install:
	@mkdir -p "$(SUPPORT_DIR)/signatures/macos.arm64"
	cp -f steam/signatures/macos.arm64/*.json "$(SUPPORT_DIR)/signatures/macos.arm64/"
	@echo "==> Installed: $(SUPPORT_DIR)/signatures/macos.arm64"

LAUNCHABLE_BUNDLES := $(HOME)/Desktop/Lullaby.app /Applications/Lullaby.app

deploy: $(TARGET) dylib-install sigdb-install helpers-install
	@if [ ! -d "$(STEAM_APP)" ]; then \
		echo "==> deploy: $(STEAM_APP) not found"; exit 1; fi
	$(call install_atomically,$(TARGET),$(DEPLOY_DST))
	@echo "==> Deployed: $(DEPLOY_DST) (restart Steam to load)"
	@for b in $(LAUNCHABLE_BUNDLES); do \
		p=$$(find "$$b" -name lullaby.dylib -type f 2>/dev/null | head -1); \
		[ -n "$$p" ] || continue; \
		cmp -s "$$p" "$(DEPLOY_DST)" && continue; \
		echo "==> warning: $$b carries a different lullaby.dylib"; \
		echo "==> warning: launching it reverts this deploy, so rebuild it with 'make app'"; \
	done

# The Dormison source tree at the engine release's commit, see bridge/setup-wine-tree.sh.
# Dormison's loader is x86_64 only, so there is no arm64 tree.
WINE_BUILD := scratch/dormison-build

# A release bundles the bridges the bridge workflow published (DECISIONS P6-2):
# BRIDGE_FEED_DIR holds <id>/<id>.tar.xz for each entry of bridge/bridge-manifest.json.
# A local build takes scratch/bridge-feed when it is there (DECISIONS P8-17).
# Empty, the bridge comes from the local wine tree and scratch/ntdll-b1.
BRIDGE_FEED_DIR ?= $(wildcard scratch/bridge-feed)

BRIDGE_FILES := \
	$(WINE_BUILD)/programs/steam.exe/x86_64-windows/steam.exe:steam.exe \
	$(WINE_BUILD)/dlls/lsteamclient/x86_64-windows/lsteamclient.dll:x86_64-windows-lsteamclient.dll \
	$(WINE_BUILD)/dlls/lsteamclient/lsteamclient.so:x86_64-unix-lsteamclient.so \
	$(WINE_BUILD)/dlls/lsteamclient/i386-windows/lsteamclient.dll:i386-windows-lsteamclient.dll

bridge:
	bridge/setup-wine-tree.sh
	bridge/lsteamclient/build.sh
	bridge/steam-shim/build.sh
	@echo "==> Built the bridge, now run: $(MAKE) app-payload"

app-payload: $(TARGET) $(OVERLAY_SHIM) $(ICONMAKER) $(APPINFO) $(NVAPI_SHIM) $(WINDOWSTATE)
	@mkdir -p "$(APP_PAYLOAD)/signatures/macos.arm64"
	@mkdir -p "$(APP_PAYLOAD)/bridge"
	cp -f $(TARGET) "$(APP_PAYLOAD)/lullaby.dylib"
	cp -f $(OVERLAY_SHIM) "$(APP_PAYLOAD)/overlay-shim.dylib"
	cp -f $(ICONMAKER) "$(APP_PAYLOAD)/iconmaker"
	cp -f $(APPINFO) "$(APP_PAYLOAD)/appinfo"
	cp -f $(NVAPI_SHIM) "$(APP_PAYLOAD)/lullaby-nvapi64.dll"
	cp -f $(WINDOWSTATE) "$(APP_PAYLOAD)/lullaby-windowstate.dylib"
	swift build --package-path app -c release --product lullaby-settings
	cp -f "$$(swift build --package-path app -c release --show-bin-path)/lullaby-settings" \
		"$(APP_PAYLOAD)/lullaby-settings"
	cp -f steam/hook/feats/compat_run.sh "$(APP_PAYLOAD)/compat_run.sh"
	cp -f steam/signatures/macos.arm64/*.json "$(APP_PAYLOAD)/signatures/macos.arm64/"
ifeq ($(BRIDGE_FEED_DIR),)
	@set -e; for spec in $(BRIDGE_FILES); do \
		src="$${spec%%:*}"; dst="$(APP_PAYLOAD)/bridge/$${spec##*:}"; \
		if [ -f "$$src" ]; then cp -f "$$src" "$$dst"; \
		elif [ -f "$$dst" ]; then echo "==> keeping staged $${spec##*:}"; \
		else echo "$$src is missing and nothing is staged at $$dst, run: $(MAKE) bridge" >&2; exit 1; fi; \
	done
	python3 -I release/feed.py stage-bridge bridge/bridge-manifest.json scratch/ntdll-b1 "$(APP_PAYLOAD)"
else
	python3 -I release/feed.py stage-bridge --from-feed "$(BRIDGE_FEED_DIR)" \
		bridge/bridge-manifest.json - "$(APP_PAYLOAD)"
endif
	python3 -I release/feed.py stage-signatures steam/signatures/manifest.json steam/signatures/macos.arm64 "$(APP_PAYLOAD)"
	@echo "==> Staged app payload in $(APP_PAYLOAD)"

APP_BUNDLE  := $(OUT_DIR)/Lullaby.app
ROSETTA_CHECK := $(APP_BUNDLE)/Contents/Helpers/Lullaby Rosetta Check.app
APP_BUNDLE_PAYLOAD := $(APP_BUNDLE)/Contents/Resources/LullabyApp_LullabyApp.bundle/Contents/Resources/payload
APP_ZIP     := $(OUT_DIR)/Lullaby.zip
APP_VERSION ?= $(shell sed -n 's/^\#define LULLABY_VERSION "\(.*\)"/\1/p' steam/hook/version.h)
# CFBundleVersion, what Sparkle compares. The release workflow passes a number that
# only grows (the commit count); a local build keeps the marketing version.
APP_BUILD   ?= $(APP_VERSION)

APP_SIGN_ID ?= -

# Lullaby's release feed (docs/RELEASING.md). The key is the base64 Ed25519
# public key; empty (the default until Phase 6) leaves the feed off and the app
# uses the bridge and signatures it carries.
# Where Lullaby publishes and how the app downloads come from one file,
# release/feed.json (DECISIONS P6-11); the release workflows read the same file.
feed_config = $(shell python3 -I release/feed.py config $(1))
LB_RELEASE_FEED       ?= $(call feed_config,feed)
LB_RELEASE_ACCESS     ?= $(call feed_config,access)
LB_RELEASE_REPOSITORY ?= $(call feed_config,repository)
LB_RELEASE_MANIFEST_TAG ?= $(call feed_config,manifestTag)
LB_ENGINE_MANIFEST    ?= $(call feed_config,engineManifest)
LB_RELEASE_KEY  ?=

# Sparkle, for Lullaby.app's own updates (Phase 6): the appcast and its EdDSA
# public key. Empty (the default) leaves the updater off. The appcast sits next to
# the signed manifests, in the release tagged `manifest`.
SPARKLE_FEED ?= $(call feed_config,appcastURL)
SPARKLE_KEY  ?=

# release (the release workflow), test (its dry run, TEST keys only) or dev.
# release/check-release.sh holds each kind to its keys before and after the build.
LB_BUILD_KIND ?= dev
export LB_BUILD_KIND LB_DEV LB_RELEASE_KEY LB_RELEASE_FEED SPARKLE_KEY SPARKLE_FEED LB_RELEASE_ACCESS

ICONGEN  := $(OUT_DIR)/icongen
ICON_DOC := $(OUT_DIR)/Lullaby.icon
ICON_DIR := $(OUT_DIR)/icon
ICON_CAR := $(ICON_DIR)/Assets.car
# Named after the app: a folder from before the rename (NotProton.icns) builds again.
ICON_ICNS := $(ICON_DIR)/Lullaby.icns

icon: $(ICON_CAR) $(ICON_ICNS)

$(ICONGEN): app/helpers/icon.swift
	@mkdir -p $(OUT_DIR)
	swiftc -O -o $@ $<
	@echo "==> Built $@"

ICON_ART := app/Icon/lullaby-1024.png

$(ICON_CAR) $(ICON_ICNS): $(ICONGEN) $(ICON_ART)
	rm -rf "$(ICON_DOC)" "$(ICON_DIR)"
	$(ICONGEN) "$(ICON_ART)" "$(ICON_DOC)"
	@mkdir -p "$(ICON_DIR)"
	xcrun actool "$(ICON_DOC)" --compile "$(ICON_DIR)" --platform macosx \
		--minimum-deployment-target 26.0 --app-icon Lullaby \
		--output-partial-info-plist "$(ICON_DIR)/partial.plist" >/dev/null
	@echo "==> Built $@"

app: app-config app-payload $(ICON_CAR) $(ICON_ICNS)
	swift build --package-path app -c release
	rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp app/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c \
		"Set :CFBundleShortVersionString $(APP_VERSION)" -c \
		"Set :CFBundleVersion $(APP_BUILD)" -c \
		"Set :LBReleaseFeedURL $(LB_RELEASE_FEED)" -c \
		"Set :LBReleasePublicKey $(LB_RELEASE_KEY)" -c \
		"Set :LBBuildKind $(LB_BUILD_KIND)" -c \
		"Set :LBReleaseAccess $(LB_RELEASE_ACCESS)" -c \
		"Set :LBReleaseRepository $(LB_RELEASE_REPOSITORY)" -c \
		"Set :LBReleaseManifestTag $(LB_RELEASE_MANIFEST_TAG)" -c \
		"Set :LBEngineManifestURL $(LB_ENGINE_MANIFEST)" -c \
		"Set :SUFeedURL $(if $(SPARKLE_KEY),$(SPARKLE_FEED))" -c \
		"Set :SUPublicEDKey $(SPARKLE_KEY)" -c \
		"Set :SUEnableAutomaticChecks false" \
		"$(APP_BUNDLE)/Contents/Info.plist"
	cp "$$(swift build --package-path app -c release --show-bin-path)/LullabyApp" \
		"$(APP_BUNDLE)/Contents/MacOS/LullabyApp"
	@mkdir -p "$(APP_BUNDLE)/Contents/Frameworks"
	ditto "$$(swift build --package-path app -c release --show-bin-path)/Sparkle.framework" \
		"$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework"
	install_name_tool -add_rpath @executable_path/../Frameworks \
		"$(APP_BUNDLE)/Contents/MacOS/LullabyApp"
	cp -R "$$(swift build --package-path app -c release --show-bin-path)/LullabyApp_LullabyApp.bundle" \
		"$(APP_BUNDLE)/Contents/Resources/"
	cp "$(ICON_DIR)/Assets.car" "$(ICON_DIR)/Lullaby.icns" \
		"$(APP_BUNDLE)/Contents/Resources/"
	@missing=$$(cd "$(APP_PAYLOAD)" && find . -type f ! -name '.DS_Store' | sed 's|^\./||' \
		| while read -r rel; do \
			[ -s "$(CURDIR)/$(APP_BUNDLE_PAYLOAD)/$$rel" ] || echo "$$rel"; \
		done); \
	if [ -n "$$missing" ]; then \
		echo "==> the bundle is missing staged payload, so the app would ship without it:" >&2; \
		echo "$$missing" | sed 's/^/        /' >&2; \
		echo "==> rm -rf app/.build/out and build again" >&2; \
		exit 1; \
	fi
	@echo "==> Payload complete in the bundle"
	@# Install's Rosetta step opens this Intel-only helper so macOS offers Rosetta (Phase 8).
	@mkdir -p "$(ROSETTA_CHECK)/Contents/MacOS"
	cp app/rosetta-check/Info.plist "$(ROSETTA_CHECK)/Contents/Info.plist"
	$(CC) -arch x86_64 -mmacosx-version-min=26.0 -O2 -o "$(ROSETTA_CHECK)/Contents/MacOS/rosetta-check" \
		app/rosetta-check/main.c
	codesign -f -s "$(APP_SIGN_ID)" "$(ROSETTA_CHECK)"
	codesign -f -s "$(APP_SIGN_ID)" "$(APP_BUNDLE)"
	codesign --verify --strict "$(APP_BUNDLE)"
	release/check-release.sh bundle "$(APP_BUNDLE)"
	@echo "==> Built $(APP_BUNDLE) ($(APP_VERSION), build $(APP_BUILD), $(LB_BUILD_KIND))"

# Stops a release or test build whose keys or switches are wrong before anything is built.
app-config:
	@release/check-release.sh config

app-zip: app
	rm -f "$(APP_ZIP)"
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(APP_ZIP)"
	@echo "==> Wrote $(APP_ZIP)"

clean:
	rm -rf $(OUT_DIR)

rebuild: clean all

-include $(DEPS)
