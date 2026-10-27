APP_NAME := Home Widgets
APP := build/$(APP_NAME).app

.PHONY: build app run install update uninstall clean

# Compile only (fast check that everything builds).
build:
	swift build -c release

# Build the double-clickable app into ./build
app:
	./scripts/build-app.sh

# Build and launch from ./build
run: app
	-pkill -x HomeWidgets && sleep 1
	open "$(APP)"

# Build, copy to /Applications, and launch.
install: app
	-pkill -x HomeWidgets && sleep 1
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/
	# Only keep the installed copy, so Spotlight shows one Home Widgets.
	rm -rf "$(APP)"
	open "/Applications/$(APP_NAME).app"

# Download the latest code and reinstall.
update:
	git pull --ff-only
	$(MAKE) install

uninstall:
	-pkill -x HomeWidgets
	rm -rf "/Applications/$(APP_NAME).app"

clean:
	rm -rf .build build
