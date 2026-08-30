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
        let dark = isDarkEffective
        
        switch currentMode {
        case .system, .dark:
            if dark {
                return ComputedColors(
                    background: NSColor(white: 0.0, alpha: 0.06), // Ultra-translucent airy glass
                    border: NSColor(white: 1.0, alpha: 0.12),
                    activeText: NSColor.white,
                    sungText: NSColor(white: 1.0, alpha: 0.94),
                    upcomingText: NSColor(white: 0.90, alpha: 0.42),
                    glowColor: albumAccentColor.withAlphaComponent(0.50),
                    fullscreenBackground: NSColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 0.95)
                )
            } else {
                return ComputedColors(
                    background: NSColor(white: 1.0, alpha: 0.08),
                    border: NSColor(white: 0.0, alpha: 0.10),
                    activeText: NSColor(white: 0.08, alpha: 1.0),
                    sungText: NSColor(white: 0.15, alpha: 0.92),
                    upcomingText: NSColor(white: 0.30, alpha: 0.45),
                    glowColor: albumAccentColor.withAlphaComponent(0.35),
                    fullscreenBackground: NSColor(white: 0.96, alpha: 0.96)
                )
            }
            
        case .light:
            return ComputedColors(
                background: NSColor(white: 1.0, alpha: 0.08),
                border: NSColor(white: 0.0, alpha: 0.10),
                activeText: NSColor(white: 0.08, alpha: 1.0),
                sungText: NSColor(white: 0.15, alpha: 0.92),
                upcomingText: NSColor(white: 0.30, alpha: 0.45),
                glowColor: albumAccentColor.withAlphaComponent(0.35),
                fullscreenBackground: NSColor(white: 0.96, alpha: 0.96)
            )
            
        case .ambient:
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
            albumAccentColor.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
            let ambientBG = NSColor(hue: hue, saturation: max(0.4, sat), brightness: 0.15, alpha: 0.10)
            
            return ComputedColors(
                background: ambientBG,
                border: albumAccentColor.withAlphaComponent(0.25),
                activeText: NSColor.white,
                sungText: NSColor(white: 1.0, alpha: 0.94),
                upcomingText: NSColor(white: 0.92, alpha: 0.42),
                glowColor: albumAccentColor.withAlphaComponent(0.65),
                fullscreenBackground: NSColor(hue: hue, saturation: max(0.5, sat), brightness: 0.08, alpha: 0.96)
            )
        }
    }
    
    public func cycleMode() -> AppThemeMode {
        let all = AppThemeMode.allCases
        guard let idx = all.firstIndex(of: currentMode) else { return .system }
        let next = all[(idx + 1) % all.count]
        currentMode = next
        return next
    }
}
