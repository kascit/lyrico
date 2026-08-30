import Cocoa

public enum AppThemeMode: String, Codable, CaseIterable {
    case system = "system"
    case dark = "dark"
    case light = "light"
    case ambient = "ambient"
}

public struct ComputedColors {
    public let background: NSColor
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
        didSet { onThemeChange?() }
    }
    
    public var albumAccentColor: NSColor = NSColor(red: 0.38, green: 0.82, blue: 1.00, alpha: 1.0) {
        didSet { onThemeChange?() }
    }
    
    public var onThemeChange: (() -> Void)?
    
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
            if isSystemDark {
                return makeDarkColors()
            } else {
                return makeLightColors()
            }
            
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
            background: NSColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 0.26),
            border: NSColor(white: 1.0, alpha: 0.14),
            activeText: NSColor.white,
            sungText: NSColor(white: 1.0, alpha: 0.94),
            upcomingText: NSColor(white: 0.90, alpha: 0.40),
            glowColor: albumAccentColor.withAlphaComponent(0.55),
            fullscreenBackground: NSColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 0.98),
            isDark: true
        )
    }
    
    private func makeLightColors() -> ComputedColors {
        return ComputedColors(
            background: NSColor(white: 0.98, alpha: 0.36),
            border: NSColor(white: 0.0, alpha: 0.16),
            activeText: NSColor(white: 0.08, alpha: 1.0),
            sungText: NSColor(white: 0.18, alpha: 0.92),
            upcomingText: NSColor(white: 0.35, alpha: 0.48),
            glowColor: albumAccentColor.withAlphaComponent(0.40),
            fullscreenBackground: NSColor(white: 0.97, alpha: 0.98),
            isDark: false
        )
    }
    
    private func makeAmbientColors() -> ComputedColors {
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        albumAccentColor.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
        let ambientBG = NSColor(hue: hue, saturation: max(0.50, sat), brightness: 0.18, alpha: 0.30)
        let ambientFS = NSColor(hue: hue, saturation: max(0.60, sat), brightness: 0.06, alpha: 0.98)
        
        return ComputedColors(
            background: ambientBG,
            border: albumAccentColor.withAlphaComponent(0.38),
            activeText: NSColor.white,
            sungText: NSColor(white: 1.0, alpha: 0.94),
            upcomingText: NSColor(white: 0.92, alpha: 0.44),
            glowColor: albumAccentColor.withAlphaComponent(0.70),
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
