# AeroGlow

A high-performance, native macOS floating lyrics HUD engineered specifically for **Spotify** and the **AeroSpace** tiling window manager.

![macOS](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/language-Swift%205.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Highlights

- **Multi-Source Lyrics Engine**:
  - **Tier 1 (LRCLIB)**: Synced word-by-word and line-by-line LRC timestamps.
  - **Tier 2 (Kugou Cloud)**: Massive global synced database fallback.
  - **Tier 3 (Smart Duration Interpolation)**: Automatically aligns plain-text lyrics across track duration for indie tracks without official LRC timestamps (**100% lyric coverage**).
- **Dynamic Ambient Island UI**:
  - Frosted glass capsule with `NSVisualEffectView` HUD blur.
  - Dynamic album accent color extraction from Spotify artwork.
  - Active lyric line with glowing aura + upcoming line peek.
  - Native click-through (`ignoresMouseEvents = true`) so clicks pass straight through into your code editor or browser.
- **Native Multi-Space Floating**:
  - Uses macOS `NSWindow.CollectionBehavior.canJoinAllSpaces` to float seamlessly over all AeroSpace workspaces with **zero move scripts, zero coordinate drift, and zero CPU bloat**.
- **Instant Hotkey Response**:
  - Sub-millisecond CLI/socket IPC server (`/tmp/aeroglow.sock`).

---

## Keyboard Shortcuts (AeroSpace)

| Keybinding | Action |
| :--- | :--- |
| `⌥ .` (`Option + Period`) | **Toggle Show / Hide** (smooth fade) |
| `⌥ ⇧ .` (`Option + Shift + Period`) | **Toggle Position (Centered Top ⇄ Centered Bottom)** |
| `⌥ ⌃ .` (`Option + Ctrl + Period`) | **Toggle Style Mode (Single-Line ⇄ Dynamic 2-Line Island)** |

---

## Installation & Build

### Requirements
- macOS 13.0 (Ventura) or later
- Swift 5.9+ / Xcode Command Line Tools
- Spotify for macOS

### Building from Source

```bash
# Clone the repository
git clone https://github.com/<your-username>/aeroglow.git
cd aeroglow

# Build release binary
make release

# Install to ~/.config/aerospace/bin/aeroglow
make install
```

---

## CLI Usage

```bash
aeroglow daemon               # Run daemon in foreground
aeroglow toggle-visibility    # Toggle show / hide
aeroglow toggle-position      # Switch between top and bottom
aeroglow toggle-style         # Switch between single-line and dual-line
aeroglow status               # Print current playback & lyrics state
aeroglow stop                 # Gracefully terminate daemon
```

---

## Architecture

- `SpotifyService.swift`: Event-driven `DistributedNotificationCenter` observer and high-precision playback position interpolator.
- `LyricsEngine.swift`: Multi-tier LRC parser, remote API client, and smart timing interpolator with local disk caching.
- `ColorExtractor.swift`: CoreImage dominant color analyzer for dynamic artwork tinting.
- `FloatingCapsuleWindow.swift`: Borderless floating `NSPanel` with native multi-space behaviors and click-through mode.
- `CapsuleContentView.swift`: Frosted glass capsule view with SF Pro typography, dynamic aura glow, and line transitions.
- `IPCServer.swift`: UNIX domain socket server for sub-millisecond CLI and hotkey communication.

---

## License

MIT License.
