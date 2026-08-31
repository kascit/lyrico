import Cocoa

final class LyricoApp: NSObject, NSApplicationDelegate, SpotifyTrackerDelegate, IPCServerDelegate {
    private var hudWindow: FloatingHUDWindow!
    private var fullscreenWindow: FullscreenLyricsWindow!
    private var spotifyTracker: SpotifyTracker!
    private var ipcServer: IPCServer!
    
    private var currentLyrics: ParsedLyrics?
    private var isUserHidden: Bool = false
    private var pauseAutoHideTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // 1. Initialize Floating HUD Window (loads saved position & style from ConfigManager)
        hudWindow = FloatingHUDWindow()
        hudWindow.makeKeyAndOrderFront(nil)
        
        // 2. Initialize Fullscreen Lyrics Window
        fullscreenWindow = FullscreenLyricsWindow()
        
        // 3. Start IPC Socket Server
        ipcServer = IPCServer()
        ipcServer.delegate = self
        _ = ipcServer.start()
        
        // 4. Start Spotify Tracker
        spotifyTracker = SpotifyTracker()
        spotifyTracker.userOffset = 0.0
        spotifyTracker.delegate = self
        
        hudWindow.hudView.setStatic(active: "Lyrico", upcoming: "Waiting for Spotify playback...")
    }
    
    // MARK: - SpotifyTrackerDelegate
    
    func spotifyTracker(_ tracker: SpotifyTracker, didChangeTrack track: TrackMetadata?) {
        guard let track = track else {
            currentLyrics = nil
            hudWindow.hudView.setStatic(active: "", upcoming: "")
            fullscreenWindow.fullscreenView.updateTrackInfo(title: "", artist: "")
            fullscreenWindow.fullscreenView.updateLyrics(lyrics: nil)
            return
        }
        
        hudWindow.hudView.setStatic(active: track.title, upcoming: track.artist)
        fullscreenWindow.fullscreenView.updateTrackInfo(title: track.title, artist: track.artist)
        
        LyricsEngine.shared.fetchLyrics(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration
        ) { [weak self] lyrics in
            guard let self = self, self.spotifyTracker.currentTrack?.id == track.id else { return }
            self.currentLyrics = lyrics
            self.fullscreenWindow.fullscreenView.updateLyrics(lyrics: lyrics)
            
            if let l = lyrics {
                if l.isSynced {
                    self.fullscreenWindow.fullscreenView.tickPlayback(position: self.spotifyTracker.currentPosition + self.spotifyTracker.userOffset)
                } else {
                    self.hudWindow.hudView.setStatic(active: track.title, upcoming: "Plain lyrics (Unsynced) • ⌥⌃F for full text")
                }
            } else {
                self.hudWindow.hudView.setStatic(active: track.title, upcoming: track.artist)
            }
        }
        
        // Extract album accent color
        ColorExtractor.shared.extractColor(from: track.artworkURL) { color in
            ThemeManager.shared.albumAccentColor = color
        }
    }
    
    func spotifyTracker(_ tracker: SpotifyTracker, didChangeState state: TrackPlaybackState) {
        pauseAutoHideTimer?.invalidate()
        pauseAutoHideTimer = nil
        
        switch state {
        case .playing:
            if !isUserHidden {
                hudWindow.hudView.setVisibility(visible: true, animated: true)
            }
        case .paused:
            pauseAutoHideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
                guard let self = self, self.spotifyTracker.currentState == .paused else { return }
                self.hudWindow.hudView.setVisibility(visible: false, animated: true)
            }
        case .stopped, .unknown:
            hudWindow.hudView.setVisibility(visible: false, animated: true)
        }
    }
    
    func spotifyTracker(_ tracker: SpotifyTracker, didTickPlayback position: TimeInterval) {
        guard let lyrics = currentLyrics, !lyrics.lines.isEmpty else { return }
        
        if !lyrics.isSynced {
            // For unsynced plain lyrics, don't jump lines on a fake linear timer
            let trackName = spotifyTracker.currentTrack?.title ?? "♫"
            hudWindow.hudView.setStatic(active: trackName, upcoming: "Plain lyrics (Unsynced) • ⌥⌃F for full text")
            if fullscreenWindow.isShowingFullscreen {
                fullscreenWindow.fullscreenView.tickPlayback(position: position)
            }
            return
        }
        
        let activeIdx = lyrics.activeLineIndex(at: position)
        
        if activeIdx == -1 {
            // Instrumental Intro before first line
            let firstLineText = lyrics.lines.first?.text ?? ""
            hudWindow.hudView.setStatic(active: "♫", upcoming: firstLineText)
        } else {
            let activeLine = lyrics.lines[activeIdx]
            let upcomingText = (activeIdx + 1 < lyrics.lines.count) ? lyrics.lines[activeIdx + 1].text : ""
            hudWindow.hudView.renderKaraoke(line: activeLine, currentPosition: position, upcomingText: upcomingText)
        }
        
        if fullscreenWindow.isShowingFullscreen {
            fullscreenWindow.fullscreenView.tickPlayback(position: position)
        }
    }
    
    // MARK: - IPCServerDelegate
    
    func ipcServer(_ server: IPCServer, didReceiveCommand command: String) -> String {
        let parts = command.components(separatedBy: " ")
        let action = parts.first ?? command
        
        switch action {
        case "toggle-visibility", "toggle-show":
            isUserHidden.toggle()
            hudWindow.hudView.setVisibility(visible: !isUserHidden, animated: true)
            return isUserHidden ? "hidden" : "visible"
            
        case "show":
            isUserHidden = false
            hudWindow.hudView.setVisibility(visible: true, animated: true)
            return "visible"
            
        case "hide":
            isUserHidden = true
            hudWindow.hudView.setVisibility(visible: false, animated: true)
            return "hidden"
            
        case "toggle-position", "toggle-pos":
            hudWindow.togglePosition(animated: true)
            return hudWindow.currentPosition.rawValue
            
        case "set-top":
            hudWindow.updatePosition(to: .top, animated: true)
            return "top"
            
        case "set-bottom":
            hudWindow.updatePosition(to: .bottom, animated: true)
            return "bottom"
            
        case "toggle-style", "toggle-mode":
            let next: HUDStyle = (hudWindow.hudView.style == .dual) ? .single : .dual
            hudWindow.hudView.style = next
            return next.rawValue
            
        case "toggle-fullscreen", "fullscreen":
            if !fullscreenWindow.isShowingFullscreen {
                if let track = spotifyTracker.currentTrack {
                    fullscreenWindow.fullscreenView.updateTrackInfo(title: track.title, artist: track.artist)
                }
                fullscreenWindow.fullscreenView.updateLyrics(lyrics: currentLyrics)
                fullscreenWindow.fullscreenView.tickPlayback(position: spotifyTracker.currentPosition + spotifyTracker.userOffset)
            }
            fullscreenWindow.toggleFullscreen(animated: true)
            return fullscreenWindow.isShowingFullscreen ? "fullscreen" : "floating"
            
        case "offset-earlier":
            spotifyTracker.userOffset -= 0.3
            return "offset: \(String(format: "%.1f", spotifyTracker.userOffset))s"
            
        case "offset-later":
            spotifyTracker.userOffset += 0.3
            return "offset: \(String(format: "%.1f", spotifyTracker.userOffset))s"
            
        case "offset-reset":
            spotifyTracker.userOffset = 0.0
            return "offset: 0.0s"
            
        case "cycle-theme", "toggle-theme":
            let next = ThemeManager.shared.toggleTheme()
            return "theme: \(next.rawValue)"
            
        case "set-theme":
            let modeStr = parts.count > 1 ? parts[1] : "dark"
            let mode = AppThemeMode(rawValue: modeStr) ?? .dark
            ThemeManager.shared.currentMode = mode
            return "theme: \(mode.rawValue)"
            
        case "status":
            let state = spotifyTracker.currentState.rawValue
            let track = spotifyTracker.currentTrack?.title ?? "None"
            let artist = spotifyTracker.currentTrack?.artist ?? ""
            let pos = hudWindow.currentPosition.rawValue
            let style = hudWindow.hudView.style.rawValue
            let theme = ThemeManager.shared.currentMode.rawValue
            let isFull = fullscreenWindow.isShowingFullscreen ? "true" : "false"
            let offset = String(format: "%.1f", spotifyTracker.userOffset)
            let isSynced = currentLyrics?.isSynced == true ? "synced" : "unsynced"
            return "State: \(state) | Track: \(track) - \(artist) | Lyrics: \(isSynced) | Pos: \(pos) | Style: \(style) | Theme: \(theme) | Offset: \(offset)s | Fullscreen: \(isFull)"
            
        case "stop", "quit", "exit":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.terminate(nil)
            }
            return "stopping"
            
        default:
            return "unknown_command"
        }
    }
}

// MARK: - App Entrypoint

let arguments = CommandLine.arguments
var strongAppInstance: LyricoApp?

if arguments.count > 1 {
    let command = arguments[1]
    
    if command == "daemon" {
        let app = NSApplication.shared
        strongAppInstance = LyricoApp()
        app.delegate = strongAppInstance
        app.run()
    } else {
        let fullCmd = arguments.dropFirst().joined(separator: " ")
        if let response = IPCServer.sendCommand(fullCmd) {
            print(response)
            exit(0)
        } else {
            if command == "toggle-visibility" || command == "toggle-show" || command == "start" || command == "toggle-position" || command == "toggle-fullscreen" {
                let binaryPath = arguments[0]
                let task = Process()
                task.launchPath = "/bin/bash"
                task.arguments = ["-c", "\(binaryPath) daemon >/dev/null 2>&1 &"]
                try? task.run()
                print("Lyrico daemon started")
                exit(0)
            } else {
                print("Lyrico is not running. Start it with: lyrico daemon")
                exit(1)
            }
        }
    }
} else {
    let app = NSApplication.shared
    strongAppInstance = LyricoApp()
    app.delegate = strongAppInstance
    app.run()
}
