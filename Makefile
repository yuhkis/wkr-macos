APP := $(CURDIR)/build/WKRMacOS.app
EXECUTABLE := $(APP)/Contents/MacOS/WKRMacOS
INSTALLED_APP ?= /Applications/WKRMacOS.app
INSTALLED_EXECUTABLE := $(INSTALLED_APP)/Contents/MacOS/WKRMacOS
MODE ?= deferred
# Per-key press counts. Off unless asked for; see docs/design.md section 9.
KEY_FREQUENCY ?= off

# A Mac may have Command Line Tools selected globally even though the
# full Xcode app is installed. Keep the system-wide xcode-select untouched and
# use full Xcode only for this project's make targets.
ifeq ($(origin DEVELOPER_DIR), undefined)
ifneq ($(wildcard /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
endif

.PHONY: test build app input-source input-source-installed start start-installed stop install-login-agent uninstall-login-agent key-frequency-report key-frequency-report-installed key-frequency-reset

test:
	swift test

build:
	swift build

app:
	./Scripts/build-app.sh

input-source:
	@test -x "$(EXECUTABLE)" || (echo 'App is not built; run make app first.' >&2; exit 2)
	$(EXECUTABLE) --print-input-source

input-source-installed:
	@test -x "$(INSTALLED_EXECUTABLE)" || (echo 'Installed app was not found at $(INSTALLED_APP).' >&2; exit 2)
	$(INSTALLED_EXECUTABLE) --print-input-source

start:
	@test -x "$(EXECUTABLE)" || (echo 'App is not built; run make app first.' >&2; exit 2)
	@test -n "$(INPUT_SOURCE_ID)" || (echo 'INPUT_SOURCE_ID is required; run make input-source after selecting Apple Japanese input.' >&2; exit 2)
	@test -n "$(INPUT_MODE_ID)" || (echo 'INPUT_MODE_ID is required; run make input-source while Apple Japanese Hiragana is active.' >&2; exit 2)
	@if [ "$(MODE)" = "optimistic" ] && [ "$(ALLOW_OPTIMISTIC)" != "1" ]; then echo 'optimistic mode requires ALLOW_OPTIMISTIC=1 and a disposable untitled document.' >&2; exit 2; fi
	@$(MAKE) stop
	./Scripts/start-app.sh "$(APP)" --input-source-id "$(INPUT_SOURCE_ID)" --input-mode-id "$(INPUT_MODE_ID)" --mode "$(MODE)" --key-frequency "$(KEY_FREQUENCY)" --request-permissions $(if $(filter optimistic,$(MODE)),--allow-unverified-optimistic,) $(if $(SYMBOL_LAYER),--symbol-layer $(SYMBOL_LAYER),)

start-installed:
	@test -x "$(INSTALLED_EXECUTABLE)" || (echo 'Installed app was not found at $(INSTALLED_APP).' >&2; exit 2)
	@test -n "$(INPUT_SOURCE_ID)" || (echo 'INPUT_SOURCE_ID is required; run make input-source-installed after selecting Apple Japanese input.' >&2; exit 2)
	@test -n "$(INPUT_MODE_ID)" || (echo 'INPUT_MODE_ID is required; run make input-source-installed while Apple Japanese Hiragana is active.' >&2; exit 2)
	@if [ "$(MODE)" = "optimistic" ] && [ "$(ALLOW_OPTIMISTIC)" != "1" ]; then echo 'optimistic mode requires ALLOW_OPTIMISTIC=1 and a disposable untitled document.' >&2; exit 2; fi
	@$(MAKE) stop
	./Scripts/start-app.sh "$(INSTALLED_APP)" --input-source-id "$(INPUT_SOURCE_ID)" --input-mode-id "$(INPUT_MODE_ID)" --mode "$(MODE)" --key-frequency "$(KEY_FREQUENCY)" --request-permissions $(if $(filter optimistic,$(MODE)),--allow-unverified-optimistic,) $(if $(SYMBOL_LAYER),--symbol-layer $(SYMBOL_LAYER),)

stop:
	@pkill -TERM -x WKRMacOS 2>/dev/null || true

install-login-agent:
	@$(MAKE) stop
	./Scripts/install-login-agent.sh

uninstall-login-agent:
	./Scripts/uninstall-login-agent.sh

# Render the heatmap. Reading counts the app already wrote needs no permission,
# so this works from the build directory even when the bundle is not installed.
# VIL points at a Vial .vil export so the Cornix picture carries the keymap that
# is actually flashed to the keyboard; without it the built-in layout is drawn.
key-frequency-report:
	@test -x "$(EXECUTABLE)" || (echo 'App is not built; run make app first.' >&2; exit 2)
	$(EXECUTABLE) --key-frequency-report --open $(if $(VIL),--vil "$(VIL)",) $(if $(OUTPUT),--output "$(OUTPUT)",)

key-frequency-report-installed:
	@test -x "$(INSTALLED_EXECUTABLE)" || (echo 'Installed app was not found at $(INSTALLED_APP).' >&2; exit 2)
	$(INSTALLED_EXECUTABLE) --key-frequency-report --open $(if $(VIL),--vil "$(VIL)",) $(if $(OUTPUT),--output "$(OUTPUT)",)

key-frequency-reset:
	@test -x "$(EXECUTABLE)" || (echo 'App is not built; run make app first.' >&2; exit 2)
	$(EXECUTABLE) --key-frequency-reset
