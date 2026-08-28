.PHONY: build test app run clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

run: app
	open "dist/Sub2API Monitor.app"

clean:
	swift package clean
	rm -rf "dist/Sub2API Monitor.app"
