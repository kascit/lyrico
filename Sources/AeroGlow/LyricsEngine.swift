import Foundation
import CryptoKit

public struct LyricLine: Equatable, Codable {
    public let startTime: TimeInterval
    public var endTime: TimeInterval
    public let text: String
    
    public init(startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

public struct ParsedLyrics: Equatable, Codable {
    public let lines: [LyricLine]
    public let isSynced: Bool
    public let source: String
    
    public init(lines: [LyricLine], isSynced: Bool, source: String) {
        self.lines = lines
        self.isSynced = isSynced
        self.source = source
    }
    
    public func activeLineIndex(at position: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        
        for (idx, line) in lines.enumerated() {
            if position >= line.startTime && position <= line.endTime {
                return idx
            }
        }
        
        // If between last line start and end
        if let last = lines.last, position >= last.startTime {
            return lines.count - 1
        }
        
        return nil
    }
}

public final class LyricsEngine {
    public static let shared = LyricsEngine()
    
    private let cacheDirectory: URL
    private var memoryCache: [String: ParsedLyrics] = [:]
    private let session: URLSession
    
    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.cacheDirectory = home.appendingPathComponent(".cache/aeroglow/lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 8.0
        self.session = URLSession(configuration: config)
    }
    
    private func cacheKey(title: String, artist: String) -> String {
        let raw = "\(artist.lowercased().trimmingCharacters(in: .whitespaces)) - \(title.lowercased().trimmingCharacters(in: .whitespaces))"
        let hash = Insecure.MD5.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
    
    public func fetchLyrics(title: String, artist: String, album: String, duration: TimeInterval, completion: @escaping (ParsedLyrics?) -> Void) {
        let cleanTitle = sanitizeTitle(title)
        let cleanArtist = sanitizeArtist(artist)
        let key = cacheKey(title: cleanTitle, artist: cleanArtist)
        
        // 1. Check memory cache
        if let cached = memoryCache[key] {
            completion(cached)
            return
        }
        
        // 2. Check disk cache
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        if let data = try? Data(contentsOf: fileURL),
           let cached = try? JSONDecoder().decode(ParsedLyrics.self, from: data) {
            memoryCache[key] = cached
            completion(cached)
            return
        }
        
        // 3. Fetch from remote sources concurrently with priority
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Try LRCLIB first
            if let lyrics = self.fetchFromLRCLIB(title: cleanTitle, artist: cleanArtist, album: album, duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            
            // Try Kugou synced database second
            if let lyrics = self.fetchFromKugou(title: cleanTitle, artist: cleanArtist, duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            
            // Try LRCLIB plain text fallback with smart duration interpolation
            if let lyrics = self.fetchPlainFromLRCLIB(title: cleanTitle, artist: cleanArtist, duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            
            DispatchQueue.main.async { completion(nil) }
        }
    }
    
    private func saveToCache(key: String, fileURL: URL, lyrics: ParsedLyrics) {
        memoryCache[key] = lyrics
        if let data = try? JSONEncoder().encode(lyrics) {
            try? data.write(to: fileURL)
        }
    }
    
    // MARK: - LRCLIB Provider
    
    private func fetchFromLRCLIB(title: String, artist: String, album: String, duration: TimeInterval) -> ParsedLyrics? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")
        var queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if !album.isEmpty { queryItems.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { queryItems.append(URLQueryItem(name: "duration", value: String(Int(round(duration))))) }
        comps?.queryItems = queryItems
        
        guard let url = comps?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("AeroGlow/1.0 (macOS; Native)", forHTTPHeaderField: "User-Agent")
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: ParsedLyrics?
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            defer { semaphore.signal() }
            guard let data = data, error == nil else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
                let lines = self?.parseLRC(synced, duration: duration) ?? []
                if !lines.isEmpty {
                    result = ParsedLyrics(lines: lines, isSynced: true, source: "LRCLIB")
                }
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3.5)
        
        if result == nil {
            // Try LRCLIB search endpoint as backup
            result = searchLRCLIB(query: "\(title) \(artist)", duration: duration)
        }
        
        return result
    }
    
    private func searchLRCLIB(query: String, duration: TimeInterval) -> ParsedLyrics? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lrclib.net/api/search?q=\(encoded)") else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("AeroGlow/1.0", forHTTPHeaderField: "User-Agent")
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: ParsedLyrics?
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            defer { semaphore.signal() }
            guard let data = data, error == nil else { return }
            
            if let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in list {
                    if let synced = item["syncedLyrics"] as? String, !synced.isEmpty {
                        let lines = self?.parseLRC(synced, duration: duration) ?? []
                        if !lines.isEmpty {
                            result = ParsedLyrics(lines: lines, isSynced: true, source: "LRCLIB Search")
                            return
                        }
                    }
                }
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3.5)
        return result
    }
    
    private func fetchPlainFromLRCLIB(title: String, artist: String, duration: TimeInterval) -> ParsedLyrics? {
        guard let encoded = "\(title) \(artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lrclib.net/api/search?q=\(encoded)") else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("AeroGlow/1.0", forHTTPHeaderField: "User-Agent")
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: ParsedLyrics?
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            defer { semaphore.signal() }
            guard let data = data, error == nil else { return }
            
            if let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in list {
                    if let plain = item["plainLyrics"] as? String, !plain.isEmpty {
                        let lines = self?.interpolatePlainLyrics(plain, duration: duration) ?? []
                        if !lines.isEmpty {
                            result = ParsedLyrics(lines: lines, isSynced: false, source: "LRCLIB Plain (Smart Timing)")
                            return
                        }
                    }
                }
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3.5)
        return result
    }
    
    // MARK: - Kugou Provider
    
    private func fetchFromKugou(title: String, artist: String, duration: TimeInterval) -> ParsedLyrics? {
        let query = "\(title) - \(artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "http://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword=\(encoded)&duration=") else { return nil }
        
        var request = URLRequest(url: searchURL)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let semaphore = DispatchSemaphore(value: 0)
        var candidateID: String?
        var accessKey: String?
        
        let searchTask = session.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let id = first["id"] as? String ?? (first["id"] as? NSNumber)?.stringValue,
                  let key = first["accesskey"] as? String else { return }
            candidateID = id
            accessKey = key
        }
        searchTask.resume()
        _ = semaphore.wait(timeout: .now() + 3.0)
        
        guard let id = candidateID, let key = accessKey,
              let downloadURL = URL(string: "http://lyrics.kugou.com/download?ver=1&client=pc&id=\(id)&accesskey=\(key)&fmt=lrc&charset=utf8") else {
            return nil
        }
        
        let dlSem = DispatchSemaphore(value: 0)
        var parsed: ParsedLyrics?
        
        let dlTask = session.dataTask(with: downloadURL) { [weak self] data, _, _ in
            defer { dlSem.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let base64 = json["content"] as? String,
                  let lrcData = Data(base64Encoded: base64),
                  let lrcText = String(data: lrcData, encoding: .utf8) else { return }
            
            let lines = self?.parseLRC(lrcText, duration: duration) ?? []
            if !lines.isEmpty {
                parsed = ParsedLyrics(lines: lines, isSynced: true, source: "Kugou")
            }
        }
        dlTask.resume()
        _ = dlSem.wait(timeout: .now() + 3.0)
        
        return parsed
    }
    
    // MARK: - LRC Parser
    
    public func parseLRC(_ lrc: String, duration: TimeInterval) -> [LyricLine] {
        var rawLines: [(time: TimeInterval, text: String)] = []
        let regex = try? NSRegularExpression(pattern: "\\[(\\d{2}):(\\d{2})\\.(\\d{2,3})\\](.*)")
        
        for line in lrc.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            let nsString = trimmed as NSString
            let matches = regex?.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length)) ?? []
            
            for match in matches {
                guard match.numberOfRanges >= 5 else { continue }
                let minStr = nsString.substring(with: match.range(at: 1))
                let secStr = nsString.substring(with: match.range(at: 2))
                let msStr = nsString.substring(with: match.range(at: 3))
                let text = nsString.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
                
                guard let minutes = Double(minStr),
                      let seconds = Double(secStr),
                      let fractions = Double(msStr) else { continue }
                
                let msDivider = msStr.count == 2 ? 100.0 : 1000.0
                let totalTime = (minutes * 60.0) + seconds + (fractions / msDivider)
                
                // Skip empty instrumental tags
                if !text.isEmpty && !text.hasPrefix("//") {
                    rawLines.append((time: totalTime, text: text))
                }
            }
        }
        
        rawLines.sort { $0.time < $1.time }
        guard !rawLines.isEmpty else { return [] }
        
        var result: [LyricLine] = []
        for i in 0..<rawLines.count {
            let start = rawLines[i].time
            let text = rawLines[i].text
            let end: TimeInterval
            if i + 1 < rawLines.count {
                end = max(start + 0.5, rawLines[i + 1].time)
            } else {
                end = duration > start ? duration : start + 6.0
            }
            result.append(LyricLine(startTime: start, endTime: end, text: text))
        }
        
        return result
    }
    
    // MARK: - Smart Duration Interpolator for Plain Lyrics
    
    public func interpolatePlainLyrics(_ plain: String, duration: TimeInterval) -> [LyricLine] {
        var rawLines: [String] = []
        for line in plain.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Filter section markers like [Chorus], (Scene 2), Verse 1:
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { continue }
            if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") && trimmed.count < 15 { continue }
            if trimmed.lowercased().hasPrefix("verse") || trimmed.lowercased().hasPrefix("chorus") { continue }
            rawLines.append(trimmed)
        }
        
        guard !rawLines.isEmpty else { return [] }
        
        let totalDuration = duration > 10 ? duration : Double(rawLines.count * 4)
        let introPadding: TimeInterval = min(8.0, totalDuration * 0.05)
        let outroPadding: TimeInterval = min(8.0, totalDuration * 0.05)
        let activeDuration = max(totalDuration - introPadding - outroPadding, 10.0)
        
        let timePerLine = activeDuration / Double(rawLines.count)
        var result: [LyricLine] = []
        
        for (idx, text) in rawLines.enumerated() {
            let start = introPadding + (Double(idx) * timePerLine)
            let end = start + timePerLine
            result.append(LyricLine(startTime: start, endTime: end, text: text))
        }
        
        return result
    }
    
    private func sanitizeTitle(_ title: String) -> String {
        var t = title
        if let idx = t.range(of: " - ") { t = String(t[..<idx.lowerBound]) }
        if let idx = t.range(of: " (feat.") { t = String(t[..<idx.lowerBound]) }
        if let idx = t.range(of: " (with ") { t = String(t[..<idx.lowerBound]) }
        if let idx = t.range(of: " [feat.") { t = String(t[..<idx.lowerBound]) }
        return t.trimmingCharacters(in: .whitespaces)
    }
    
    private func sanitizeArtist(_ artist: String) -> String {
        var a = artist
        if let idx = a.range(of: ", ") { a = String(a[..<idx.lowerBound]) }
        if let idx = a.range(of: " feat. ") { a = String(a[..<idx.lowerBound]) }
        return a.trimmingCharacters(in: .whitespaces)
    }
}
