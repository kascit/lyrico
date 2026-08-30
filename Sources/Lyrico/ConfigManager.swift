import Foundation

public struct LyricoConfig: Codable {
    public var position: String
    public var theme: String
    public var style: String
    public var userOffset: Double
    
    public static let `default` = LyricoConfig(
        position: "bottom",
        theme: "system",
        style: "dual",
        userOffset: 0.0
    )
}

public final class ConfigManager {
    public static let shared = ConfigManager()
    
    private let configURL: URL
    public private(set) var config: LyricoConfig
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/lyrico", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configURL = dir.appendingPathComponent("config.json")
        
        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(LyricoConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
            self.save()
        }
    }
    
    public func save() {
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }
    
    public func updatePosition(_ position: String) {
        config.position = position
        save()
    }
    
    public func updateTheme(_ theme: String) {
        config.theme = theme
        save()
    }
    
    public func updateStyle(_ style: String) {
        config.style = style
        save()
    }
    
    public func updateOffset(_ offset: Double) {
        config.userOffset = offset
        save()
    }
}
