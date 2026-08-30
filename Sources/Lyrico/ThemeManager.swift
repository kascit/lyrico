import Cocoa

public enum AppThemeMode: String, Codable, CaseIterable {
    case dark = "dark"
    case light = "light"
    case ambient = "ambient"
    case system = "system"
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
    
    public var currentMode: AppThemeMode = .dark {
        didSet {
            ConfigManager.shared.updateTheme(currentMode.rawValue)
            onThemeChange?()
        }
    }
    
    public var albumAccentColor: NSColor = NSColor(red: 0.38, green: 0.82, blue: 1.00, alpha: 1.0) {
        didSet { onThemeChange?() }
    }
    
    public var onThemeChange: (() -> Void)?
    
    public init() {
        let saved = ConfigManager.shared.config.theme
        self.currentMode = AppThemeMode(rawValue: saved) ?? .dark
    }
    
    public var isSystemDark: Bool {
        if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
            return style == "Dark"
        }
        let appearance = NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    
    public var isDarkEffective: Bool {
        switch currentMode {
        case .dark, .ambient: return true
        case .light: return false
        case .system: return isSystemDark
        }
    }
    
    public func resolveColors() -> ComputedColors {
        switch currentMode {
        case .dark:
            return makeDarkColors()
        case .light:
            return makeLightColors()
        case .ambient:
            return makeAmbientColors()
        case .system:
            return isSystemDark ? makeDarkColors() : makeLightColors()
        }
    }
    
    private func makeDarkColors() -> ComputedColors {
        return ComputedColors(
            cardBackground: NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.28), // 72% transparent black tint
            border: NSColor(white: 1.0, alpha: 0.22),
            activeText: NSColor(white: 1.0, alpha: 1.0), // Crisp solid white
            sungText: NSColor(white: 1.0, alpha: 0.94),
            upcomingText: NSColor(white: 1.0, alpha: 0.44),
            glowColor: NSColor(white: 1.0, alpha: 0.30),
            fullscreenBackground: NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 0.98),
            isDark: true
        )
    }
    
    private func makeLightColors() -> ComputedColors {
        return ComputedColors(
            cardBackground: NSColor(white: 1.0, alpha: 0.32), // 68% transparent white tint
            border: NSColor(white: 0.0, alpha: 0.18),
            activeText: NSColor(white: 0.06, alpha: 1.0), // Crisp solid black/charcoal
            sungText: NSColor(white: 0.14, alpha: 0.94),
            upcomingText: NSColor(white: 0.25, alpha: 0.48),
            glowColor: NSColor(white: 0.0, alpha: 0.15),
            fullscreenBackground: NSColor(white: 0.97, alpha: 0.98),
            isDark: false
        )
    }
    
    private func makeAmbientColors() -> ComputedColors {
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        albumAccentColor.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
        
        let ambientTint = NSColor(hue: hue, saturation: max(0.40, sat * 0.8), brightness: 0.16, alpha: 0.26)
        let ambientFS = NSColor(hue: hue, saturation: max(0.50, sat), brightness: 0.06, alpha: 0.98)
        let subtleGlow = albumAccentColor.withAlphaComponent(0.45)
        
        return ComputedColors(
            cardBackground: ambientTint,
            border: albumAccentColor.withAlphaComponent(0.38),
            activeText: NSColor.white,
            sungText: NSColor(white: 1.0, alpha: 0.94),
            upcomingText: NSColor(white: 0.90, alpha: 0.44),
            glowColor: subtleGlow,
            fullscreenBackground: ambientFS,
            isDark: true
        )
    }
    
    public func cycleMode() -> AppThemeMode {
        let all = AppThemeMode.allCases
        guard let idx = all.firstIndex(of: currentMode) else { return .dark }
        let next = all[(idx + 1) % all.count]
        currentMode = next
        return next
    }
}
