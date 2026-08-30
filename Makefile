PREFIX ?= /Users/dhanurr/.config/aerospace
BINDIR = $(PREFIX)/bin

.PHONY: all build release install clean uninstall run

all: release

build:
	swift build

release:
	swift build -c release

install: release
	mkdir -p $(BINDIR)
	cp .build/release/aeroglow $(BINDIR)/aeroglow
	chmod +x $(BINDIR)/aeroglow
	@echo "✅ Installed aeroglow to $(BINDIR)/aeroglow"

uninstall:
	rm -f $(BINDIR)/aeroglow

run: release
	./.build/release/aeroglow daemon

clean:
	swift package clean
	rm -rf .build
