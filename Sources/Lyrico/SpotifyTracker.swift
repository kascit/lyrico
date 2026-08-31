import Foundation
import Cocoa
import QuartzCore

public struct TrackMetadata: Equatable {
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

public enum TrackPlaybackState: String {
    case playing = "Playing"
    case paused = "Paused"
    case stopped = "Stopped"
    case unknown = "Unknown"
}

public protocol SpotifyTrackerDelegate: AnyObject {
    func spotifyTracker(_ tracker: SpotifyTracker, didChangeTrack track: TrackMetadata?)
    func spotifyTracker(_ tracker: SpotifyTracker, didChangeState state: TrackPlaybackState)
    func spotifyTracker(_ tracker: SpotifyTracker, didTickPlayback position: TimeInterval)
}

public final class SpotifyTracker {
    public weak var delegate: SpotifyTrackerDelegate?
    
    public private(set) var currentTrack: TrackMetadata?
    public private(set) var currentState: TrackPlaybackState = .unknown
    public private(set) var currentPosition: TimeInterval = 0.0
    
    public var userOffset: TimeInterval = 0.0
    public var visualLeadOffset: TimeInterval = 0.28 // 280ms lead matching Apple Music / Spotify native visual onset
    
    private var anchorPosition: TimeInterval = 0.0
    private var anchorHostTime: CFTimeInterval = 0.0
    
    private var displayTimer: Timer?
    private var periodicSyncTimer: Timer?
    private var compiledAppleScript: NSAppleScript?
    private let syncQueue = DispatchQueue(label: "com.lyrico.spotify.sync", qos: .userInitiated)
    
    public init() {
        setupPrecompiledScript()
        setupNotifications()
        startTimers()
        pollState()
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        displayTimer?.invalidate()
        periodicSyncTimer?.invalidate()
    }
    
    private func setupPrecompiledScript() {
        let scriptSource = """
        tell application "Spotify"
            if running then
                return {player state as string, player position as string, id of current track, name of current track, artist of current track, album of current track, duration of current track, artwork url of current track}
            else
                return "not_running"
            end if
        end tell
        """
        compiledAppleScript = NSAppleScript(source: scriptSource)
        compiledAppleScript?.compileAndReturnError(nil)
    }
    
    private func setupNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handlePlaybackNotification(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
    }
    
    @objc private func handlePlaybackNotification(_ notification: Notification) {
        guard let info = notification.userInfo else { return }
        let now = CACurrentMediaTime()
        
        let rawState = (info["Player State"] as? String) ?? "Unknown"
        let state: TrackPlaybackState
        switch rawState.lowercased() {
        case "playing": state = .playing
        case "paused": state = .paused
        default: state = .stopped
        }
        
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
            self.anchorPosition = position
            self.anchorHostTime = now
            self.currentPosition = position
            
            let isNewTrack = self.currentTrack == nil || self.currentTrack?.id != trackID || self.currentTrack?.title != name
            if isNewTrack && !trackID.isEmpty {
                self.userOffset = 0.0
                let track = TrackMetadata(id: trackID, title: name, artist: artist, album: album, duration: duration)
                self.currentTrack = track
                self.delegate?.spotifyTracker(self, didChangeTrack: track)
                self.fetchArtwork(for: trackID)
            }
            
            self.delegate?.spotifyTracker(self, didChangeState: state)
            let effectivePos = max(0.0, position + self.userOffset + self.visualLeadOffset)
            self.delegate?.spotifyTracker(self, didTickPlayback: effectivePos)
            self.manageDisplayTimer(for: state)
        }
    }
    
    private func startTimers() {
        periodicSyncTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.pollState()
        }
    }
    
    private func manageDisplayTimer(for state: TrackPlaybackState) {
        displayTimer?.invalidate()
        displayTimer = nil
        
        guard state == .playing else { return }
        
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self, self.currentState == .playing else { return }
            let now = CACurrentMediaTime()
            let elapsed = max(0.0, now - self.anchorHostTime)
            self.currentPosition = self.anchorPosition + elapsed
            let effectivePos = max(0.0, self.currentPosition + self.userOffset + self.visualLeadOffset)
            self.delegate?.spotifyTracker(self, didTickPlayback: effectivePos)
        }
    }
    
    public func pollState() {
        syncQueue.async { [weak self] in
            guard let self = self, let script = self.compiledAppleScript else { return }
            
            let sampleStart = CACurrentMediaTime()
            var errorInfo: NSDictionary?
            let result = script.executeAndReturnError(&errorInfo)
            let sampleEnd = CACurrentMediaTime()
            guard errorInfo == nil else { return }
            
            // Estimated time when Spotify actually sampled its position (midpoint of IPC call)
            let estimatedSampleHostTime = sampleStart + ((sampleEnd - sampleStart) / 2.0)
            
            if result.stringValue == "not_running" {
                DispatchQueue.main.async {
                    if self.currentState != .stopped {
                        self.currentState = .stopped
                        self.currentTrack = nil
                        self.delegate?.spotifyTracker(self, didChangeState: .stopped)
                        self.delegate?.spotifyTracker(self, didChangeTrack: nil)
                    }
                }
                return
            }
            
            guard let list = result.coerce(toDescriptorType: typeAEList), list.numberOfItems >= 7 else { return }
            
            let stateStr = list.atIndex(1)?.stringValue ?? "stopped"
            let posStr = list.atIndex(2)?.stringValue ?? "0"
            let trackID = list.atIndex(3)?.stringValue ?? ""
            let name = list.atIndex(4)?.stringValue ?? ""
            let artist = list.atIndex(5)?.stringValue ?? ""
            let album = list.atIndex(6)?.stringValue ?? ""
            let durStr = list.atIndex(7)?.stringValue ?? "0"
            let artURL = list.numberOfItems >= 8 ? list.atIndex(8)?.stringValue : nil
            
            let state: TrackPlaybackState
            switch stateStr.lowercased() {
            case "playing": state = .playing
            case "paused": state = .paused
            default: state = .stopped
            }
            
            let rawPos = Double(posStr) ?? 0.0
            var dur = Double(durStr) ?? 0.0
            if dur > 1000 { dur = dur / 1000.0 }
            
            DispatchQueue.main.async {
                let stateChanged = self.currentState != state
                self.currentState = state
                
                let isNew = self.currentTrack == nil || self.currentTrack?.id != trackID || self.currentTrack?.title != name
                if isNew && !trackID.isEmpty {
                    self.userOffset = 0.0
                    let track = TrackMetadata(id: trackID, title: name, artist: artist, album: album, duration: dur, artworkURL: artURL)
                    self.currentTrack = track
                    self.delegate?.spotifyTracker(self, didChangeTrack: track)
                }
                
                let predictedPos = self.anchorPosition + (estimatedSampleHostTime - self.anchorHostTime)
                
                // Only re-anchor if there is a real seek (>1.2s) or track change or state change
                if abs(predictedPos - rawPos) > 1.2 || stateChanged || isNew {
                    self.anchorPosition = rawPos
                    self.anchorHostTime = estimatedSampleHostTime
                    self.currentPosition = rawPos + max(0.0, CACurrentMediaTime() - estimatedSampleHostTime)
                }
                
                if stateChanged {
                    self.delegate?.spotifyTracker(self, didChangeState: state)
                    self.manageDisplayTimer(for: state)
                }
            }
        }
    }
    
    private func fetchArtwork(for trackID: String) {
        syncQueue.async { [weak self] in
            let script = "tell application \"Spotify\" to if running then return artwork url of current track"
            guard let appleScript = NSAppleScript(source: script) else { return }
            var err: NSDictionary?
            let res = appleScript.executeAndReturnError(&err)
            if err == nil, let url = res.stringValue, !url.isEmpty {
                DispatchQueue.main.async {
                    guard let self = self, let current = self.currentTrack, current.id == trackID else { return }
                    let updated = TrackMetadata(id: current.id, title: current.title, artist: current.artist, album: current.album, duration: current.duration, artworkURL: url)
                    self.currentTrack = updated
                    self.delegate?.spotifyTracker(self, didChangeTrack: updated)
                }
            }
        }
    }
}
