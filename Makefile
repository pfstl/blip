.PHONY: build install dev demo uninstall clean

BIN_PATH = $(shell swift build -c release --show-bin-path)

## Release build of the CLI and the app
build:
	swift build -c release

## Build + install the app locally (for development; normally the plugin extension does this)
install: build
	"$(BIN_PATH)/blip" install --build-dir "$(BIN_PATH)" --source "$(CURDIR)"

## Run the app straight from the debug build (for development, Ctrl+C quits)
dev:
	swift build
	"$$(swift build --show-bin-path)/BlipApp"

## Show off the animations with fake sessions
demo:
	"$$(swift build --show-bin-path)/blip" demo

uninstall:
	"$(BIN_PATH)/blip" uninstall

clean:
	rm -rf .build
