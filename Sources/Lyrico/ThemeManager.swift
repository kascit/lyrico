import Cocoa

public enum AppThemeMode: String, Codable, CaseIterable {
    case system = "system"
    case dark = "dark"
    case light = "light"
    case ambient = "ambient"
}

public struct ComputedColors {
    public let material: NSVisualEffectView.Material
    public let tintColor: NSColor
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
    
    public var currentMode: AppThemeMode = .system {
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
        self.currentMode = AppThemeMode(rawValue: saved) ?? .system
    }
    
    public var isSystemDark: Bool {
        let appearance = NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    
    public var isDarkEffective: Bool {
        switch currentMode {
        case .system: return isSystemDark
        case .dark, .ambient: return true
        case .light: return false
        }
    }
    
    public func resolveColors() -> ComputedColors {
        switch currentMode {
        case .system:
            return isSystemDark ? makeDarkColors() : makeLightColors()
        case .dark:
            return makeDarkColors()
        case .light:
            return makeLightColors()
        case .ambient:
            return makeAmbientColors()
        }
    }
    
    private func makeDarkColors() -> ComputedColors {
        return ComputedColors(
            material: .hudWindow,
            tintColor: NSColor.clear, // 100% natural transparent glass blur
            border: NSColor(white: 1.0, alpha: 0.14),
            activeText: NSColor.white,
            sungText: NSColor(white: 1.0, alpha: 0.94),
            upcomingText: NSColor(white: 1.0, alpha: 0.42),
            glowColor: NSColor(white: 1.0, alpha: 0.30), // Sleek, clean white glow
            fullscreenBackground: NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 0.98),
            isDark: true
        )
    }
    
    private func makeLightColors() -> ComputedColors {
        return ComputedColors(
            material: .sheet, // Pure frosty milk-glass blur
            tintColor: NSColor(white: 1.0, alpha: 0.12),
            border: NSColor(white: 0.0, alpha: 0.12),
            activeText: NSColor(white: 0.08, alpha: 1.0), // Deep solid charcoal
            sungText: NSColor(white: 0.18, alpha: 0.92),
            upcomingText: NSColor(white: 0.35, alpha: 0.48),
            glowColor: NSColor(white: 0.0, alpha: 0.15),
            fullscreenBackground: NSColor(white: 0.97, alpha: 0.98),
            isDark: false
        )
    }
    
    private func makeAmbientColors() -> ComputedColors {
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        albumAccentColor.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
        
        let ambientTint = NSColor(hue: hue, saturation: max(0.40, sat * 0.8), brightness: 0.20, alpha: 0.16)
        let ambientFS = NSColor(hue: hue, saturation: max(0.50, sat), brightness: 0.06, alpha: 0.98)
        let subtleGlow = albumAccentColor.withAlphaComponent(0.45)
        
        return ComputedColors(
            material: .hudWindow,
            tintColor: ambientTint,
            border: albumAccentColor.withAlphaComponent(0.30),
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
        guard let idx = all.firstIndex(of: currentMode) else { return .system }
        let next = all[(idx + 1) % all.count]
        currentMode = next
        return next
    }
}
