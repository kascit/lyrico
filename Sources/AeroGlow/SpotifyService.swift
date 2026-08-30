import Foundation
import Cocoa
import QuartzCore

public struct TrackInfo: Equatable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let artworkURL: String?
    
    public init(id: String, title: String, artist: String, album: String, duration: TimeInterval, artworkURL: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
    }
}

public enum PlayerState: String {
    case playing = "Playing"
    case paused = "Paused"
    case stopped = "Stopped"
    case unknown = "Unknown"
}

public protocol SpotifyServiceDelegate: AnyObject {
    func spotifyService(_ service: SpotifyService, didChangeTrack track: TrackInfo?)
    func spotifyService(_ service: SpotifyService, didChangeState state: PlayerState)
    func spotifyService(_ service: SpotifyService, didTickPlayback position: TimeInterval)
}

public final class SpotifyService {
    public weak var delegate: SpotifyServiceDelegate?
    
    public private(set) var currentTrack: TrackInfo?
    public private(set) var currentState: PlayerState = .unknown
    public private(set) var currentPosition: TimeInterval = 0.0
    
    private var lastKnownPosition: TimeInterval = 0.0
    private var lastAnchorTime: CFTimeInterval = 0.0
    private var playbackTimer: Timer?
    private var periodicSyncTimer: Timer?
    
    public init() {
        setupDistributedNotification()
        startPeriodicSync()
        fetchInitialState()
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        playbackTimer?.invalidate()
        periodicSyncTimer?.invalidate()
    }
    
    private func setupDistributedNotification() {
        let notificationName = NSNotification.Name("com.spotify.client.PlaybackStateChanged")
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handlePlaybackStateChange(_:)),
            name: notificationName,
            object: nil
        )
    }
    
    @objc private func handlePlaybackStateChange(_ notification: Notification) {
        guard let info = notification.userInfo else { return }
        
        let rawState = (info["Player State"] as? String) ?? "Unknown"
        let state = PlayerState(rawValue: rawState) ?? .unknown
        let trackID = (info["Track ID"] as? String) ?? ""
        let name = (info["Name"] as? String) ?? ""
        let artist = (info["Artist"] as? String) ?? ""
        let album = (info["Album"] as? String) ?? ""
        
        var duration: TimeInterval = 0.0
        if let durNum = info["Duration"] as? NSNumber {
            let val = durNum.doubleValue
            duration = val > 1000 ? val / 1000.0 : val
        }
        
        var position: TimeInterval = 0.0
        if let posNum = info["Playback Position"] as? NSNumber {
            position = posNum.doubleValue
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.currentState = state
            self.lastKnownPosition = position
            self.currentPosition = position
            self.lastAnchorTime = CACurrentMediaTime()
            
            if !trackID.isEmpty && (self.currentTrack?.id != trackID || self.currentTrack?.title != name) {
                let track = TrackInfo(id: trackID, title: name, artist: artist, album: album, duration: duration)
                self.currentTrack = track
                self.delegate?.spotifyService(self, didChangeTrack: track)
                self.fetchArtworkURL(for: trackID)
            }
            
            self.delegate?.spotifyService(self, didChangeState: state)
            self.delegate?.spotifyService(self, didTickPlayback: position)
            self.updatePlaybackTimer(for: state)
        }
    }
    
    private func updatePlaybackTimer(for state: PlayerState) {
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        guard state == .playing else { return }
        
        // 30Hz high-frequency interpolation for silky smooth lyrics sync
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            guard let self = self, self.currentState == .playing else { return }
            let elapsed = CACurrentMediaTime() - self.lastAnchorTime
            self.currentPosition = self.lastKnownPosition + elapsed
            self.delegate?.spotifyService(self, didTickPlayback: self.currentPosition)
        }
    }
    
    private func startPeriodicSync() {
        periodicSyncTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollSpotifyState()
        }
    }
    
    public func pollSpotifyState() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let script = """
            tell application "Spotify"
                if running then
                    return {player state as string, player position as string, id of current track, name of current track, artist of current track, album of current track, duration of current track, artwork url of current track}
                else
                    return "not_running"
                end if
            end tell
            """
            
            guard let appleScript = NSAppleScript(source: script) else { return }
            var errorInfo: NSDictionary?
            let result = appleScript.executeAndReturnError(&errorInfo)
            
            guard errorInfo == nil else { return }
            
            if result.stringValue == "not_running" {
                DispatchQueue.main.async {
                    if self?.currentState != .stopped {
                        self?.currentState = .stopped
                        self?.currentTrack = nil
                        self?.delegate?.spotifyService(self!, didChangeState: .stopped)
                        self?.delegate?.spotifyService(self!, didChangeTrack: nil)
                    }
                }
                return
            }
            
            guard let list = result.coerce(toDescriptorType: typeAEList) else { return }
            let count = list.numberOfItems
            guard count >= 7 else { return }
            
            let stateStr = list.atIndex(1)?.stringValue ?? "stopped"
            let posStr = list.atIndex(2)?.stringValue ?? "0"
            let trackID = list.atIndex(3)?.stringValue ?? ""
            let name = list.atIndex(4)?.stringValue ?? ""
            let artist = list.atIndex(5)?.stringValue ?? ""
            let album = list.atIndex(6)?.stringValue ?? ""
            let durStr = list.atIndex(7)?.stringValue ?? "0"
            let artURL = count >= 8 ? list.atIndex(8)?.stringValue : nil
            
            let state: PlayerState
            switch stateStr.lowercased() {
            case "playing": state = .playing
            case "paused": state = .paused
            default: state = .stopped
            }
            
            let pos = Double(posStr) ?? 0.0
            var dur = Double(durStr) ?? 0.0
            if dur > 1000 { dur = dur / 1000.0 }
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                let stateChanged = self.currentState != state
                self.currentState = state
                self.lastKnownPosition = pos
                self.lastAnchorTime = CACurrentMediaTime()
                self.currentPosition = pos
                
                let isNewTrack = self.currentTrack == nil || self.currentTrack?.id != trackID || self.currentTrack?.title != name
                if isNewTrack && !trackID.isEmpty {
                    let track = TrackInfo(id: trackID, title: name, artist: artist, album: album, duration: dur, artworkURL: artURL)
                    self.currentTrack = track
                    self.delegate?.spotifyService(self, didChangeTrack: track)
                }
                
                if stateChanged {
                    self.delegate?.spotifyService(self, didChangeState: state)
                    self.updatePlaybackTimer(for: state)
                }
            }
        }
    }
    
    private func fetchInitialState() {
        pollSpotifyState()
    }
    
    private func fetchArtworkURL(for trackID: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let script = "tell application \"Spotify\" to if running then return artwork url of current track"
            guard let appleScript = NSAppleScript(source: script) else { return }
            var err: NSDictionary?
            let res = appleScript.executeAndReturnError(&err)
            if err == nil, let url = res.stringValue, !url.isEmpty {
                DispatchQueue.main.async {
                    guard let self = self, let current = self.currentTrack, current.id == trackID else { return }
                    let updated = TrackInfo(id: current.id, title: current.title, artist: current.artist, album: current.album, duration: current.duration, artworkURL: url)
                    self.currentTrack = updated
                    self.delegate?.spotifyService(self, didChangeTrack: updated)
                }
            }
        }
    }
}
