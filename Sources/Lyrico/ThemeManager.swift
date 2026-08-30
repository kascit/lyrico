import Cocoa

public enum AppThemeMode: String, Codable, CaseIterable {
    case dark = "dark"
    case light = "light"
}

public struct ComputedColors {
    public let cardBackground: NSColor
    public let border: NSColor
    public let activeText: NSColor
    public let sungText: NSColor
    public let upcomingText: NSColor
    public let glowColor: NSColor
    public let fullscreenBackground: NSColor
    public let isDark: Bool
}

public final class ThemeManager {
    public static let shared = ThemeManager()
    public static let themeDidChangeNotification = Notification.Name("LyricoThemeDidChangeNotification")
    
    public var currentMode: AppThemeMode = .dark {
        didSet {
            ConfigManager.shared.updateTheme(currentMode.rawValue)
            notifyObservers()
        }
    }
    
    public var albumAccentColor: NSColor = NSColor(red: 0.38, green: 0.82, blue: 1.00, alpha: 1.0) {
        didSet { notifyObservers() }
    }
    
    public init() {
        let saved = ConfigManager.shared.config.theme
        if saved == "light" {
            self.currentMode = .light
        } else if saved == "dark" {
            self.currentMode = .dark
        } else {
            self.currentMode = isSystemDark ? .dark : .light
        }
        
        setupSystemAppearanceObserver()
    }
    
    private func setupSystemAppearanceObserver() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSystemThemeChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }
    
    @objc private func handleSystemThemeChanged() {
        let isDark = self.isSystemDark
        self.currentMode = isDark ? .dark : .light
    }
    
    public var isSystemDark: Bool {
        if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
            return style == "Dark"
        }
        let appearance = NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    
    private func notifyObservers() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: ThemeManager.themeDidChangeNotification, object: nil)
        }
    }
    
    public func resolveColors() -> ComputedColors {
        switch currentMode {
        case .dark:
            return makeDarkColors()
        case .light:
            return makeLightColors()
        }
    }
    
    private func makeDarkColors() -> ComputedColors {
        return ComputedColors(
            cardBackground: NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 0.65), // Translucent black pill
            border: NSColor(white: 1.0, alpha: 0.22),
            activeText: NSColor(white: 1.0, alpha: 1.0), // Crisp solid white text
            sungText: NSColor(white: 1.0, alpha: 0.94),
            upcomingText: NSColor(white: 1.0, alpha: 0.44),
            glowColor: NSColor(white: 1.0, alpha: 0.30),
            fullscreenBackground: NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 0.98),
            isDark: true
        )
    }
    
    private func makeLightColors() -> ComputedColors {
        return ComputedColors(
            cardBackground: NSColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 0.85), // Translucent white pill
            border: NSColor(white: 0.0, alpha: 0.22),
            activeText: NSColor(white: 0.04, alpha: 1.0), // Crisp solid deep black text (#0a0a0c)
            sungText: NSColor(white: 0.12, alpha: 0.94),
            upcomingText: NSColor(white: 0.24, alpha: 0.52),
            glowColor: NSColor(white: 0.0, alpha: 0.15),
            fullscreenBackground: NSColor(white: 0.97, alpha: 0.98),
            isDark: false
        )
    }
    
    @discardableResult
    public func toggleTheme() -> AppThemeMode {
        let next: AppThemeMode = (currentMode == .dark) ? .light : .dark
        currentMode = next
        return next
    }
}
