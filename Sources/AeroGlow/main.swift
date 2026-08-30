import Cocoa

final class AeroGlowApp: NSObject, NSApplicationDelegate, SpotifyServiceDelegate, IPCServerDelegate {
    private var window: FloatingCapsuleWindow!
    private var spotifyService: SpotifyService!
    private var ipcServer: IPCServer!
    
    private var currentLyrics: ParsedLyrics?
    private var isUserHidden: Bool = false
    private var pauseAutoHideTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // 1. Initialize UI Window
        window = FloatingCapsuleWindow()
        window.makeKeyAndOrderFront(nil)
        
        // 2. Start IPC Server for CLI hotkey commands
        ipcServer = IPCServer()
        ipcServer.delegate = self
        if !ipcServer.start() {
            print("Warning: Could not start IPC socket server on \(IPCServer.socketPath)")
        }
        
        // 3. Start Spotify Playback Observer
        spotifyService = SpotifyService()
        spotifyService.delegate = self
        
        // Show initial greeting / waiting indicator
        window.capsuleView.setStaticText(active: "AeroGlow", upcoming: "Waiting for Spotify playback...")
    }
    
    // MARK: - SpotifyServiceDelegate
    
    func spotifyService(_ service: SpotifyService, didChangeTrack track: TrackInfo?) {
        guard let track = track else {
            currentLyrics = nil
            window.capsuleView.setStaticText(active: "", upcoming: "")
            return
        }
        
        // Reset and fetch lyrics
        window.capsuleView.setStaticText(active: track.title, upcoming: track.artist)
        
        LyricsEngine.shared.fetchLyrics(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration
        ) { [weak self] lyrics in
            guard let self = self, self.spotifyService.currentTrack?.id == track.id else { return }
            self.currentLyrics = lyrics
            if let lyrics = lyrics {
                print("✅ Lyrics loaded: \(lyrics.lines.count) lines [\(lyrics.source)]")
            } else {
                print("ℹ️ No lyrics available for: \(track.title) - \(track.artist)")
                self.window.capsuleView.setStaticText(active: track.title, upcoming: track.artist)
            }
        }
        
        // Extract album accent colors
        ColorExtractor.shared.extractTheme(from: track.artworkURL) { [weak self] theme in
            guard let self = self, self.spotifyService.currentTrack?.id == track.id else { return }
            self.window.capsuleView.currentTheme = theme
        }
    }
    
    func spotifyService(_ service: SpotifyService, didChangeState state: PlayerState) {
        pauseAutoHideTimer?.invalidate()
        pauseAutoHideTimer = nil
        
        switch state {
        case .playing:
            if !isUserHidden {
                window.capsuleView.setVisibility(visible: true, animated: true)
            }
        case .paused:
            // Graceful 3.5s pause fade
            pauseAutoHideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
                guard let self = self, self.spotifyService.currentState == .paused else { return }
                self.window.capsuleView.setVisibility(visible: false, animated: true)
            }
        case .stopped, .unknown:
            window.capsuleView.setVisibility(visible: false, animated: true)
        }
    }
    
    func spotifyService(_ service: SpotifyService, didTickPlayback position: TimeInterval) {
        guard let lyrics = currentLyrics, !lyrics.lines.isEmpty else { return }
        
        if let activeIdx = lyrics.activeLineIndex(at: position) {
            let activeLine = lyrics.lines[activeIdx]
            let upcomingText = (activeIdx + 1 < lyrics.lines.count) ? lyrics.lines[activeIdx + 1].text : ""
            window.capsuleView.renderKaraoke(line: activeLine, currentPosition: position, upcomingText: upcomingText)
        }
    }
    
    // MARK: - IPCServerDelegate (CLI / AeroSpace Integration)
    
    func ipcServer(_ server: IPCServer, didReceiveCommand command: String) -> String {
        switch command {
        case "toggle-visibility", "toggle-show":
            isUserHidden.toggle()
            window.capsuleView.setVisibility(visible: !isUserHidden, animated: true)
            return isUserHidden ? "hidden" : "visible"
            
        case "show":
            isUserHidden = false
            window.capsuleView.setVisibility(visible: true, animated: true)
            return "visible"
            
        case "hide":
            isUserHidden = true
            window.capsuleView.setVisibility(visible: false, animated: true)
            return "hidden"
            
        case "toggle-position", "toggle-pos":
            window.togglePosition(animated: true)
            return window.currentPosition.rawValue
            
        case "position-top", "set-top":
            window.setPosition(.top, animated: true)
            return "top"
            
        case "position-bottom", "set-bottom":
            window.setPosition(.bottom, animated: true)
            return "bottom"
            
        case "toggle-style", "toggle-mode":
            let next: DisplayStyle = (window.capsuleView.currentStyle == .dualLine) ? .singleLine : .dualLine
            window.capsuleView.currentStyle = next
            return next.rawValue
            
        case "status":
            let state = spotifyService.currentState.rawValue
            let track = spotifyService.currentTrack?.title ?? "None"
            let artist = spotifyService.currentTrack?.artist ?? ""
            let pos = window.currentPosition.rawValue
            let style = window.capsuleView.currentStyle.rawValue
            return "State: \(state) | Track: \(track) - \(artist) | Pos: \(pos) | Style: \(style)"
            
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

let arguments = CommandLine.arguments
var strongDelegate: AeroGlowApp?

if arguments.count > 1 {
    let command = arguments[1]
    
    if command == "daemon" {
        // Run in foreground as daemon
        let app = NSApplication.shared
        strongDelegate = AeroGlowApp()
        app.delegate = strongDelegate
        app.run()
    } else {
        // Send command to running instance
        if let response = IPCServer.sendCommand(command) {
            print(response)
            exit(0)
        } else {
            // Not running -> if command was toggle or start, launch daemon in background
            if command == "toggle-visibility" || command == "toggle-show" || command == "start" || command == "toggle-position" {
                let binaryPath = arguments[0]
                let task = Process()
                task.launchPath = "/bin/bash"
                task.arguments = ["-c", "\(binaryPath) daemon >/dev/null 2>&1 &"]
                try? task.run()
                print("AeroGlow daemon started")
                exit(0)
            } else {
                print("AeroGlow is not running. Start it with: aeroglow daemon")
                exit(1)
            }
        }
    }
} else {
    // No arguments -> run daemon
    let app = NSApplication.shared
    strongDelegate = AeroGlowApp()
    app.delegate = strongDelegate
    app.run()
}
