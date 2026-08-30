# Lyrico

A lightweight, native macOS lyrics engine designed for **Spotify** and the **AeroSpace** tiling window manager.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Language](https://img.shields.io/badge/language-Swift%205.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

- **Multi-Source Synced Lyrics**: Fetches millisecond-synced lyrics with duration validation from **LRCLIB**, **NetEase CloudSearch**, and **Kugou**, with intelligent fallback timing for plain lyrics.
- **True Translucent HUD**: Layer-backed see-through glass card (0 opaque blur materials) keeping background apps and tabs 100% visible and readable.
- **Hardware Audio Sync**: Driven by Spotify CoreAudio notifications and monotonic time (`CACurrentMediaTime()`) for zero sampling latency and zero jitter.
- **Cinematic Fullscreen Canvas**: 52pt bold active lyrics view with generous spacing. Dismiss with `Esc` or click anywhere.
- **Dark & Light Themes**: Translucent black pill with pure white text in Dark mode, translucent white pill with deep black text in Light mode. Auto-follows macOS system appearance with manual toggle override.
- **Multi-Space Native**: Floats across all AeroSpace workspaces via AppKit `.canJoinAllSpaces`.

---

## Keybindings (AeroSpace)

| Shortcut | Action |
| :--- | :--- |
| `⌥ .` | **Toggle Floating HUD Show / Hide** |
| `⌥ ⇧ .` | **Switch Position (Top ⇄ Bottom)** |
| `⌥ ⌃ .` | **Switch Style (Single ⇄ Dual Line)** |
| `⌥ ⌃ F` | **Toggle Fullscreen Lyrics Canvas** (or `Esc`) |
| `⌥ ⌃ T` | **Toggle Theme (Dark ⇄ Light)** |
| `⌥ [` / `⌥ ]` | **Micro-Calibrate Sync (Earlier / Later by 0.3s)** |
| `⌥ \` | **Reset Sync Calibration (0.0s)** |
| `⌥ ⇧ /` | **Toggle AeroSpace Cheatsheet HUD** |

---

## CLI Commands

```bash
lyrico daemon               # Run daemon
lyrico toggle-visibility    # Toggle HUD show / hide
lyrico toggle-position      # Switch Top / Bottom
lyrico toggle-style         # Switch Single / Dual line
lyrico toggle-fullscreen    # Toggle Fullscreen canvas
lyrico toggle-theme         # Toggle Dark <-> Light
lyrico set-theme <dark|light>
lyrico offset-earlier       # -0.3s calibration
lyrico offset-later         # +0.3s calibration
lyrico offset-reset         # 0.0s reset
lyrico status               # Query current state
lyrico stop                 # Terminate daemon
```

---

## Build & Install

```bash
# Build release binary
make release

# Install to ~/.config/aerospace/bin/lyrico
make install
```

---

## Note

This project was built with AI-assisted pair programming using Antigravity (Google DeepMind).

## License

MIT License. See [LICENSE](LICENSE) for details.
