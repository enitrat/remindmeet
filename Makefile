APP := build/RemindMeet.app

.PHONY: app run clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/RemindMeet $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	codesign --force --sign - $(APP)

# Dev loop. The installed copy comes from the Nix config and runs as a launchd agent:
# quit it from its menu first, or both show the panel.
run: app
	open $(APP)

clean:
	rm -rf .build build
