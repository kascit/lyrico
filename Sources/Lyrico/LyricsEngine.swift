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
    public var words: [LyricWord]
    
    public init(startTime: TimeInterval, endTime: TimeInterval, text: String, words: [LyricWord] = []) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        if !words.isEmpty {
            self.words = words
        } else {
            self.words = LyricLine.generateWords(for: text, start: startTime, end: endTime)
        }
    }
    
    public static func generateWords(for lineText: String, start: TimeInterval, end: TimeInterval) -> [LyricWord] {
        let rawWords = lineText.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !rawWords.isEmpty else { return [] }
        
        let totalChars = rawWords.reduce(0) { $0 + max(1, $1.count) }
        let totalDuration = max(0.4, end - start)
        
        // Natural human vocal cadence: ~0.12 - 0.15s per character
        let naturalVocalDuration = max(1.0, min(Double(totalChars) * 0.14, totalDuration))
        let vocalTime = min(totalDuration, naturalVocalDuration)
        
        var cursor = start
        var result: [LyricWord] = []
        
        for word in rawWords {
            let ratio = Double(max(1, word.count)) / Double(totalChars)
            let wordDuration = max(0.18, vocalTime * ratio)
            let wordEnd = min(cursor + wordDuration, end)
            result.append(LyricWord(text: word, startTime: cursor, endTime: wordEnd))
            cursor = wordEnd
        }
        return result
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
    
    private func cacheKey(title: String, artist: String) -> String {
        let raw = "\(artist.lowercased().trimmingCharacters(in: .whitespaces)) - \(title.lowercased().trimmingCharacters(in: .whitespaces))"
        let hash = Insecure.MD5.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
    
    public func fetchLyrics(title: String, artist: String, album: String, duration: TimeInterval, completion: @escaping (ParsedLyrics?) -> Void) {
        let cleanT = sanitizeTitle(title)
        let cleanA = sanitizeArtist(artist)
        let key = cacheKey(title: cleanT, artist: cleanA)
        
        if let cached = memoryCache[key] {
            completion(cached)
            return
        }
        
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        if let data = try? Data(contentsOf: fileURL),
           let cached = try? JSONDecoder().decode(ParsedLyrics.self, from: data) {
            memoryCache[key] = cached
            completion(cached)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Tier 1: LRCLIB exact get
            if let lyrics = self.fetchFromLRCLIB(title: title, artist: artist, album: album, duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            
            // Tier 2: LRCLIB cleaned title + artist
            if cleanT != title || cleanA != artist {
                if let lyrics = self.fetchFromLRCLIB(title: cleanT, artist: cleanA, album: "", duration: duration) {
                    self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                    DispatchQueue.main.async { completion(lyrics) }
                    return
                }
            }
            
            // Tier 3: NetEase CloudSearch Synced API
            if let lyrics = self.fetchFromNetEase(title: cleanT, artist: cleanA, duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            
            // Tier 4: Kugou Synced database
            if let lyrics = self.fetchFromKugou(title: cleanT, artist: cleanA, duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            
            // Tier 5: LRCLIB search query with duration filtering
            if let lyrics = self.searchLRCLIB(query: "\(cleanT) \(cleanA)", duration: duration) {
                self.saveToCache(key: key, fileURL: fileURL, lyrics: lyrics)
                DispatchQueue.main.async { completion(lyrics) }
                return
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
        request.setValue("Lyrico/1.0 (macOS; Native)", forHTTPHeaderField: "User-Agent")
        
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
        request.setValue("Lyrico/1.0", forHTTPHeaderField: "User-Agent")
        
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
                    // Duration match within +/- 4.0 seconds if duration is known
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
        searchReq.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
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
        lyricReq.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
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
    
    // MARK: - Plain Text Provider
    
    private func fetchPlainFromLRCLIB(title: String, artist: String, duration: TimeInterval) -> ParsedLyrics? {
        guard let encoded = "\(title) \(artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lrclib.net/api/search?q=\(encoded)") else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("Lyrico/1.0", forHTTPHeaderField: "User-Agent")
        
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
    
    // MARK: - Enhanced LRC Parser
    
    public func parseLRC(_ lrc: String, duration: TimeInterval) -> [LyricLine] {
        var rawLines: [(time: TimeInterval, text: String, words: [LyricWord])] = []
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
                
                if !content.isEmpty && !content.hasPrefix("//") && !content.hasPrefix("作词") && !content.hasPrefix("作曲") {
                    var parsedWords: [LyricWord] = []
                    let contentNS = content as NSString
                    let wordMatches = wordTagRegex?.matches(in: content, range: NSRange(location: 0, length: contentNS.length)) ?? []
                    
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
                        rawLines.append((time: totalTime, text: cleanText, words: parsedWords))
                    } else {
                        rawLines.append((time: totalTime, text: content, words: []))
                    }
                }
            }
        }
        
        rawLines.sort { $0.time < $1.time }
        guard !rawLines.isEmpty else { return [] }
        
        var result: [LyricLine] = []
        for i in 0..<rawLines.count {
            let start = rawLines[i].time
            let text = rawLines[i].text
            let words = rawLines[i].words
            let end: TimeInterval
            if i + 1 < rawLines.count {
                end = max(start + 0.4, rawLines[i + 1].time)
            } else {
                end = duration > start ? duration : start + 5.0
            }
            result.append(LyricLine(startTime: start, endTime: end, text: text, words: words))
        }
        
        return result
    }
    
    // MARK: - Smart Duration Interpolator
    
    public func interpolatePlainLyrics(_ plain: String, duration: TimeInterval) -> [LyricLine] {
        var rawLines: [String] = []
        for line in plain.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
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
        let patterns = [
            "\\s*[\\(\\[][fF]eat\\.?[^\\)\\]]*[\\)\\]]",
            "\\s*[\\(\\[][fF]t\\.?[^\\)\\]]*[\\)\\]]",
            "\\s*[\\(\\[][wW]ith[^\\)\\]]*[\\)\\]]",
            "\\s*[\\(\\[][rR]emaster[^\\)\\]]*[\\)\\]]",
            "\\s*[\\(\\[][lL]ive[^\\)\\]]*[\\)\\]]",
            "\\s*-\\s*[rR]emastered.*",
            "\\s*-\\s*[lL]ive.*",
            "\\s*-\\s*[rR]adio [eE]dit.*",
            "\\s*-\\s*[sS]ingle [vV]ersion.*",
            "\\s*-\\s*[oO]riginal [mM]ix.*",
            "\\s*-\\s*[aA]coustic.*"
        ]
        
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []) {
                let range = NSRange(location: 0, length: (t as NSString).length)
                t = regex.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: "")
            }
        }
        
        if let idx = t.range(of: " - ") { t = String(t[..<idx.lowerBound]) }
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
