import Foundation
import CryptoKit

public struct LyricWord: Equatable, Codable {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    
    public init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

public struct LyricLine: Equatable, Codable {
    public let startTime: TimeInterval
    public var endTime: TimeInterval
    public let text: String
    public let hasWordSync: Bool
    public var words: [LyricWord]
    
    public init(startTime: TimeInterval, endTime: TimeInterval, text: String, hasWordSync: Bool = false, words: [LyricWord] = []) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.hasWordSync = hasWordSync
        self.words = words
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
    
    public func activeLineIndex(at position: TimeInterval) -> Int {
        guard !lines.isEmpty else { return -1 }
        
        if position < lines[0].startTime {
            return -1
        }
        
        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            if position >= lines[i].startTime {
                return i
            }
        }
        
        return 0
    }
}

public final class LyricsEngine {
    public static let shared = LyricsEngine()
    
    private let cacheDirectory: URL
    private var memoryCache: [String: ParsedLyrics] = [:]
    private let cacheLock = NSLock()
    private let session: URLSession
    
    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.cacheDirectory = home.appendingPathComponent(".cache/lyrico/lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 8.0
        self.session = URLSession(configuration: config)
    }
    
    private func cacheKey(title: String, artist: String, duration: TimeInterval) -> String {
        let durBucket = Int(round(duration))
        let raw = "\(artist.lowercased().trimmingCharacters(in: .whitespaces)) - \(title.lowercased().trimmingCharacters(in: .whitespaces)) - \(durBucket)"
        let hash = Insecure.MD5.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
    
    public func fetchLyrics(title: String, artist: String, album: String, duration: TimeInterval, completion: @escaping (ParsedLyrics?) -> Void) {
        let key = cacheKey(title: title, artist: artist, duration: duration)
        
        cacheLock.lock()
        if let cached = memoryCache[key] {
            cacheLock.unlock()
            completion(cached)
            return
        }
        cacheLock.unlock()
        
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        if let data = try? Data(contentsOf: fileURL),
           let cached = try? JSONDecoder().decode(ParsedLyrics.self, from: data) {
            cacheLock.lock()
            memoryCache[key] = cached
            cacheLock.unlock()
            completion(cached)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Tier 1: LRCLIB exact get (exact title + exact artist + exact duration)
            if let lyrics = self.fetchFromLRCLIB(title: title, artist: artist, album: album, duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            
            let cleanT = self.sanitizeTitle(title)
            let cleanA = self.sanitizeArtist(artist)
            
            // Tier 2: LRCLIB cleaned title + primary artist (with duration match)
            if cleanT != title || cleanA != artist {
                if let lyrics = self.fetchFromLRCLIB(title: cleanT, artist: cleanA, album: "", duration: duration) {
                    self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                    DispatchQueue.main.async { completion(lyrics) }
                    return
                }
            }
            
            // Tier 3: NetEase CloudSearch Synced API
            if let lyrics = self.fetchFromNetEase(title: title, artist: artist, duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            if cleanT != title {
                if let lyrics = self.fetchFromNetEase(title: cleanT, artist: cleanA, duration: duration) {
                    self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                    DispatchQueue.main.async { completion(lyrics) }
                    return
                }
            }
            
            // Tier 4: Kugou Synced database
            if let lyrics = self.fetchFromKugou(title: title, artist: artist, duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            if cleanT != title {
                if let lyrics = self.fetchFromKugou(title: cleanT, artist: cleanA, duration: duration) {
                    self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                    DispatchQueue.main.async { completion(lyrics) }
                    return
                }
            }
            
            // Tier 5: LRCLIB search query with duration filtering
            if let lyrics = self.searchLRCLIB(query: "\(title) \(artist)", duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            if cleanT != title {
                if let lyrics = self.searchLRCLIB(query: "\(cleanT) \(cleanA)", duration: duration) {
                    self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                    DispatchQueue.main.async { completion(lyrics) }
                    return
                }
            }
            
            // Tier 6: LRCLIB title-only search
            if let lyrics = self.searchLRCLIB(query: cleanT, duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            
            // Tier 7: LRCLIB plain text fallback
            if let lyrics = self.fetchPlainFromLRCLIB(title: cleanT, artist: cleanA, duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            
            DispatchQueue.main.async { completion(nil) }
        }
    }
    
    private func saveToCache(key: String, fileURL: URL, lyrics: ParsedLyrics) {
        cacheLock.lock()
        memoryCache[key] = lyrics
        cacheLock.unlock()
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
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        
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
        _ = semaphore.wait(timeout: .now() + 3.0)
        
        return result
    }
    
    private func searchLRCLIB(query: String, duration: TimeInterval) -> ParsedLyrics? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lrclib.net/api/search?q=\(encoded)") else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: ParsedLyrics?
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            defer { semaphore.signal() }
            guard let data = data, error == nil else { return }
            
            if let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let syncedItems = list.filter { ($0["syncedLyrics"] as? String)?.isEmpty == false }
                let sortedByDuration = syncedItems.sorted { item1, item2 in
                    let d1 = (item1["duration"] as? Double) ?? 0
                    let d2 = (item2["duration"] as? Double) ?? 0
                    return abs(d1 - duration) < abs(d2 - duration)
                }
                
                if let best = sortedByDuration.first, let synced = best["syncedLyrics"] as? String {
                    let bestDur = (best["duration"] as? Double) ?? 0
                    if duration == 0 || abs(bestDur - duration) <= 4.0 {
                        let lines = self?.parseLRC(synced, duration: duration) ?? []
                        if !lines.isEmpty {
                            result = ParsedLyrics(lines: lines, isSynced: true, source: "LRCLIB Search")
                        }
                    }
                }
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3.0)
        return result
    }
    
    // MARK: - NetEase Provider
    
    private func fetchFromNetEase(title: String, artist: String, duration: TimeInterval) -> ParsedLyrics? {
        let query = "\(title) \(artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://music.163.com/api/cloudsearch/pc?s=\(encoded)&type=1&offset=0&limit=5") else { return nil }
        
        var searchReq = URLRequest(url: searchURL)
        searchReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        searchReq.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        
        let semaphore = DispatchSemaphore(value: 0)
        var songID: Int?
        
        let searchTask = session.dataTask(with: searchReq) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any],
                  let songs = result["songs"] as? [[String: Any]],
                  let first = songs.first,
                  let id = first["id"] as? Int else { return }
            songID = id
        }
        searchTask.resume()
        _ = semaphore.wait(timeout: .now() + 3.0)
        
        guard let id = songID,
              let lyricURL = URL(string: "https://music.163.com/api/song/lyric?os=pc&id=\(id)&lv=-1&kv=-1&tv=-1") else {
            return nil
        }
        
        var lyricReq = URLRequest(url: lyricURL)
        lyricReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        
        let dlSem = DispatchSemaphore(value: 0)
        var parsed: ParsedLyrics?
        
        let lyricTask = session.dataTask(with: lyricReq) { [weak self] data, _, _ in
            defer { dlSem.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lrcObj = json["lrc"] as? [String: Any],
                  let lrcText = lrcObj["lyric"] as? String, !lrcText.isEmpty else { return }
            
            let lines = self?.parseLRC(lrcText, duration: duration) ?? []
            if !lines.isEmpty {
                parsed = ParsedLyrics(lines: lines, isSynced: true, source: "NetEase")
            }
        }
        lyricTask.resume()
        _ = dlSem.wait(timeout: .now() + 3.0)
        
        return parsed
    }
    
    // MARK: - Kugou Provider
    
    private func fetchFromKugou(title: String, artist: String, duration: TimeInterval) -> ParsedLyrics? {
        let query = "\(title) - \(artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "http://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword=\(encoded)&duration=") else { return nil }
        
        var request = URLRequest(url: searchURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        
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
    
    // MARK: - Plain Text Provider
    
    private func fetchPlainFromLRCLIB(title: String, artist: String, duration: TimeInterval) -> ParsedLyrics? {
        guard let encoded = "\(title) \(artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lrclib.net/api/search?q=\(encoded)") else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        
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
        _ = semaphore.wait(timeout: .now() + 3.0)
        return result
    }
    
    public func cleanLyricLineText(_ rawText: String) -> String? {
        var t = rawText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        
        // 1. Standalone section markers or credits that should be completely dropped
        let standalonePatterns = [
            "^\\s*\\[?(verse\\s*\\d*|chorus\\s*\\d*|pre-chorus\\s*\\d*|post-chorus\\s*\\d*|hook\\s*\\d*|bridge\\s*\\d*|intro\\s*\\d*|outro\\s*\\d*|break\\s*\\d*|drop\\s*\\d*|solo|instrumental|interlude|refrain)\\]?:?\\s*$",
            "^(作词|作曲|编曲|制作人|混音|母带|吉他|贝斯|鼓|键盘|录音|和声|企划|统筹|监制|发行|op|sp|lyrics by|composed by|produced by|written by|arranged by|mixed by|mastered by):?.*$"
        ]
        for p in standalonePatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: (t as NSString).length)
                if regex.firstMatch(in: t, options: [], range: range) != nil {
                    return nil
                }
            }
        }
        
        // 2. Section prefixes on real lyric lines, e.g. "Verse 1: I just wanna go" -> "I just wanna go"
        let prefixPatterns = [
            "^\\s*\\[?(verse\\s*\\d*|chorus\\s*\\d*|pre-chorus\\s*\\d*|post-chorus\\s*\\d*|hook\\s*\\d*|bridge\\s*\\d*|intro\\s*\\d*|outro\\s*\\d*)\\]?\\s*:\\s*",
            "^\\s*\\[(verse\\s*\\d*|chorus\\s*\\d*|pre-chorus\\s*\\d*|post-chorus\\s*\\d*|hook\\s*\\d*|bridge\\s*\\d*|intro\\s*\\d*|outro\\s*\\d*)\\]\\s*"
        ]
        for p in prefixPatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: (t as NSString).length)
                t = regex.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespaces)
            }
        }
        
        return t.isEmpty ? nil : t
    }
    
    // MARK: - Enhanced LRC Parser
    
    public func parseLRC(_ lrc: String, duration: TimeInterval) -> [LyricLine] {
        var rawLines: [(time: TimeInterval, text: String, hasWordSync: Bool, words: [LyricWord])] = []
        let lineRegex = try? NSRegularExpression(pattern: "\\[(\\d{2}):(\\d{2})\\.(\\d{2,3})\\](.*)")
        let wordTagRegex = try? NSRegularExpression(pattern: "<(\\d{2}):(\\d{2})\\.(\\d{2,3})>([^<]+)")
        let offsetRegex = try? NSRegularExpression(pattern: "\\[offset:([+-]?\\d+)\\]", options: .caseInsensitive)
        
        var offsetSeconds: TimeInterval = 0.0
        
        for line in lrc.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            let nsString = trimmed as NSString
            
            if let offMatch = offsetRegex?.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsString.length)) {
                let offStr = nsString.substring(with: offMatch.range(at: 1))
                if let offMs = Double(offStr) {
                    offsetSeconds = offMs / 1000.0
                }
                continue
            }
            
            let matches = lineRegex?.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length)) ?? []
            
            for match in matches {
                guard match.numberOfRanges >= 5 else { continue }
                let minStr = nsString.substring(with: match.range(at: 1))
                let secStr = nsString.substring(with: match.range(at: 2))
                let msStr = nsString.substring(with: match.range(at: 3))
                let content = nsString.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
                
                guard let minutes = Double(minStr),
                      let seconds = Double(secStr),
                      let fractions = Double(msStr) else { continue }
                
                let msDivider = msStr.count == 2 ? 100.0 : 1000.0
                let totalTime = (minutes * 60.0) + seconds + (fractions / msDivider) + offsetSeconds
                
                guard let cleanContent = cleanLyricLineText(content) else {
                    continue
                }
                
                var parsedWords: [LyricWord] = []
                let contentNS = cleanContent as NSString
                let wordMatches = wordTagRegex?.matches(in: cleanContent, range: NSRange(location: 0, length: contentNS.length)) ?? []
                
                if !wordMatches.isEmpty {
                    var prevWordTime: TimeInterval = totalTime
                    var cleanText = ""
                    for wMatch in wordMatches {
                        let wMin = Double(contentNS.substring(with: wMatch.range(at: 1))) ?? 0
                        let wSec = Double(contentNS.substring(with: wMatch.range(at: 2))) ?? 0
                        let wMs = Double(contentNS.substring(with: wMatch.range(at: 3))) ?? 0
                        let wText = contentNS.substring(with: wMatch.range(at: 4)).trimmingCharacters(in: .whitespaces)
                        let wTime = (wMin * 60.0) + wSec + (wMs / 100.0) + offsetSeconds
                        
                        cleanText += (cleanText.isEmpty ? "" : " ") + wText
                        parsedWords.append(LyricWord(text: wText, startTime: prevWordTime, endTime: max(prevWordTime + 0.20, wTime)))
                        prevWordTime = wTime
                    }
                    rawLines.append((time: totalTime, text: cleanText, hasWordSync: true, words: parsedWords))
                } else {
                    rawLines.append((time: totalTime, text: cleanContent, hasWordSync: false, words: []))
                }
            }
        }
        
        rawLines.sort { $0.time < $1.time }
        guard !rawLines.isEmpty else { return [] }
        
        var result: [LyricLine] = []
        for i in 0..<rawLines.count {
            let start = rawLines[i].time
            let text = rawLines[i].text
            let hasWordSync = rawLines[i].hasWordSync
            let words = rawLines[i].words
            let end: TimeInterval
            if i + 1 < rawLines.count {
                end = max(start + 0.4, rawLines[i + 1].time)
            } else {
                end = duration > start ? duration : start + 5.0
            }
            result.append(LyricLine(startTime: start, endTime: end, text: text, hasWordSync: hasWordSync, words: words))
        }
        
        return result
    }
    
    // MARK: - Smart Duration Interpolator
    
    public func interpolatePlainLyrics(_ plain: String, duration: TimeInterval) -> [LyricLine] {
        var rawLines: [String] = []
        for line in plain.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let clean = cleanLyricLineText(trimmed) else { continue }
            rawLines.append(clean)
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
            result.append(LyricLine(startTime: start, endTime: end, text: text, hasWordSync: false, words: []))
        }
        
        return result
    }
    
    private func sanitizeTitle(_ title: String) -> String {
        var t = title
        let patterns = [
            "\\s*[\\(\\[][fF]eat\\.?[^\\)\\]]*[\\)\\]]",
            "\\s*[\\(\\[][fF]t\\.?[^\\)\\]]*[\\)\\]]",
            "\\s*[\\(\\[][wW]ith[^\\)\\]]*[\\)\\]]",
            "\\s*[\\(\\[][rR]emaster[^\\)\\]]*[\\)\\]]",
            "\\s*-\\s*[rR]emastered.*",
            "\\s*-\\s*[sS]ingle [vV]ersion.*",
            "\\s*-\\s*[oO]fficial [aA]udio.*"
        ]
        
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []) {
                let range = NSRange(location: 0, length: (t as NSString).length)
                t = regex.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: "")
            }
        }
        
        return t.trimmingCharacters(in: .whitespaces)
    }
    
    private func sanitizeArtist(_ artist: String) -> String {
        var a = artist
        if let idx = a.range(of: ", ") { a = String(a[..<idx.lowerBound]) }
        if let idx = a.range(of: " feat. ") { a = String(a[..<idx.lowerBound]) }
        if let idx = a.range(of: " ft. ") { a = String(a[..<idx.lowerBound]) }
        if let idx = a.range(of: " & ") { a = String(a[..<idx.lowerBound]) }
        return a.trimmingCharacters(in: .whitespaces)
    }
}
