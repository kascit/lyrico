# Lyrico

A high-performance, native macOS floating and fullscreen lyrics engine engineered specifically for **Spotify** and the **AeroSpace** tiling window manager.

![macOS](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/language-Swift%205.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Highlights

- **Multi-Source Lyrics Engine (100% Coverage)**:
  - **Tier 1 (LRCLIB)**: Synced word-by-word and line-by-line LRC timestamps.
  - **Tier 2 (Kugou Cloud)**: Massive secondary synced database.
  - **Tier 3 (Smart Duration Interpolation)**: Character-weighted duration auto-alignment for plain text songs.
- **Word-Level Karaoke Synchronization**:
  - Sweeps across words in real time with high-precision (60Hz) playback interpolation.
  - Word glowing aura matching the live album artwork tint.
- **Modern Squircle Glass HUD**:
  - Soft squircle rounded-rectangle card (`cornerRadius: 18.0`) with ultra-translucent frosted glass (`0.18` background alpha).
  - Background code/browser text is crystal-clear visible.
  - 100% click-through (`ignoresMouseEvents = true`).
- **Immersive Fullscreen Lyrics Canvas**:
  - Expands to take over the entire display with large typography (38pt bold active line, scrolling context).
  - Press `Esc` or `⌥ ⇧ F` to toggle.
- **Dynamic Color Modes**:
  - **System (Default)**: Automatically follows macOS Light / Dark mode.
  - **Dark Mode**: Deep obsidian backdrop with pure white glowing typography.
  - **Light Mode**: Pure crisp white backdrop with deep charcoal typography.
  - **Ambient Mode**: Dynamic gradient tinted with Spotify's live album cover.
- **Zero-Script Multi-Space Floating**:
  - Floats natively across all AeroSpace workspaces (`⌥ Q`, `⌥ W`, `⌥ C`, `⌥ D`, `⌥ G`) via macOS `NSWindow.CollectionBehavior.canJoinAllSpaces`.

---

## Keyboard Shortcuts (AeroSpace)

| Keybinding | Action |
| :--- | :--- |
| `⌥ .` (`Option + Period`) | **Toggle Floating HUD Show / Hide** |
| `⌥ ⇧ .` (`Option + Shift + Period`) | **Toggle Position (Centered Top ⇄ Centered Bottom)** |
| `⌥ ⌃ .` (`Option + Ctrl + Period`) | **Toggle Style (Single-Line ⇄ Dynamic 2-Line HUD)** |
| `⌥ ⇧ F` (`Option + Shift + F`) | **Toggle Immersive Fullscreen Lyrics** |
| `⌥ ⌃ T` (`Option + Ctrl + T`) | **Cycle Theme (Auto / Dark / Light / Ambient)** |
| `⌥ ⇧ /` | **AeroSpace Cheatsheet HUD** |

---

## CLI Usage

```bash
lyrico daemon               # Run background daemon
lyrico toggle-visibility    # Toggle HUD show / hide
lyrico toggle-position      # Switch between Top and Bottom
lyrico toggle-style         # Switch between Single and Dual line
lyrico toggle-fullscreen    # Toggle Fullscreen Lyrics Canvas
lyrico cycle-theme          # Cycle System -> Dark -> Light -> Ambient
lyrico set-theme <mode>     # Set specific theme (system | dark | light | ambient)
lyrico status               # Query playback, lyrics, and display state
lyrico stop                 # Gracefully terminate daemon
```

---

## Installation & Build

```bash
# Clone repository
git clone https://github.com/<your-username>/lyrico.git
cd lyrico

# Build release binary
make release

# Install to ~/.config/aerospace/bin/lyrico
make install
```

---

## License

MIT License.
