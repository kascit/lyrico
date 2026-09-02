PREFIX ?= $(HOME)/.config/aerospace
BINDIR = $(PREFIX)/bin

.PHONY: all build release install clean uninstall run

all: release

build:
	swift build

release:
	swift build -c release

install: release
	mkdir -p $(BINDIR)
	cp .build/release/lyrico $(BINDIR)/lyrico
	chmod +x $(BINDIR)/lyrico
	@echo "✅ Installed lyrico to $(BINDIR)/lyrico"

uninstall:
	rm -f $(BINDIR)/lyrico

run: release
	./.build/release/lyrico daemon

clean:
	swift package clean
