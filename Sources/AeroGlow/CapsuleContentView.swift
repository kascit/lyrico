import Cocoa
import QuartzCore

public enum DisplayStyle: String, Codable {
    case dualLine = "dual"
    case singleLine = "single"
}

public final class CapsuleContentView: NSView {
    private let visualEffectView: NSVisualEffectView
    private let pillLayer: CALayer
    private let activeLabel: NSTextField
    private let upcomingLabel: NSTextField
    private let progressIndicator: CALayer
    
    public var currentStyle: DisplayStyle = .dualLine {
        didSet { updateLayout() }
    }
    
    public var currentTheme: ArtworkColorTheme = .default {
        didSet { updateTheme() }
    }
    
    private var lastActiveText: String = ""
    private var lastUpcomingText: String = ""
    
    public override init(frame frameRect: NSRect) {
        self.visualEffectView = NSVisualEffectView(frame: .zero)
        self.pillLayer = CALayer()
        self.activeLabel = NSTextField(labelWithString: "AeroGlow")
        self.upcomingLabel = NSTextField(labelWithString: "")
        self.progressIndicator = CALayer()
        
        super.init(frame: frameRect)
        wantsLayer = true
        setupUI()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupUI() {
        // Visual Effect (Frosted Glass)
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 28.0
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.backgroundColor = NSColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 0.78).cgColor
        visualEffectView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        visualEffectView.layer?.borderWidth = 1.0
        visualEffectView.layer?.shadowColor = NSColor.black.cgColor
        visualEffectView.layer?.shadowOpacity = 0.45
        visualEffectView.layer?.shadowOffset = CGSize(width: 0, height: -8)
        visualEffectView.layer?.shadowRadius = 24.0
        addSubview(visualEffectView)
        
        // Active Lyric Label
        activeLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        activeLabel.textColor = .white
        activeLabel.alignment = .center
        activeLabel.lineBreakMode = .byTruncatingTail
        activeLabel.maximumNumberOfLines = 1
        activeLabel.wantsLayer = true
        visualEffectView.addSubview(activeLabel)
        
        // Upcoming Lyric Label
        upcomingLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        upcomingLabel.textColor = NSColor(white: 0.85, alpha: 0.45)
        upcomingLabel.alignment = .center
        upcomingLabel.lineBreakMode = .byTruncatingTail
        upcomingLabel.maximumNumberOfLines = 1
        upcomingLabel.wantsLayer = true
        visualEffectView.addSubview(upcomingLabel)
        
        updateLayout()
        updateTheme()
    }
    
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        updateLayout()
    }
    
    private func updateLayout() {
        let b = bounds
        guard b.width > 0 && b.height > 0 else { return }
        
        let pillHeight: CGFloat = currentStyle == .dualLine ? 72.0 : 52.0
        let pillWidth = min(b.width - 24, 880.0)
        let pillX = (b.width - pillWidth) / 2
        let pillY = (b.height - pillHeight) / 2
        
        visualEffectView.frame = NSRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)
        visualEffectView.layer?.cornerRadius = pillHeight / 2
        
        if currentStyle == .dualLine {
            activeLabel.frame = NSRect(x: 28, y: pillHeight - 44, width: pillWidth - 56, height: 30)
            activeLabel.font = NSFont.systemFont(ofSize: 21, weight: .bold)
            upcomingLabel.isHidden = false
            upcomingLabel.frame = NSRect(x: 28, y: 10, width: pillWidth - 56, height: 18)
        } else {
            activeLabel.frame = NSRect(x: 28, y: (pillHeight - 30) / 2, width: pillWidth - 56, height: 30)
            activeLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
            upcomingLabel.isHidden = true
        }
    }
    
    public func updateTheme() {
        visualEffectView.layer?.borderColor = currentTheme.border.cgColor
        applyGlowEffect(to: activeLabel, color: currentTheme.glow)
    }
    
    private func applyGlowEffect(to label: NSTextField, color: NSColor) {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowOffset = NSSize(width: 0, height: 0)
        shadow.shadowBlurRadius = 14.0
        
        label.shadow = shadow
    }
    
    public func setLyrics(active: String, upcoming: String = "", animated: Bool = true) {
        if active == lastActiveText && upcoming == lastUpcomingText { return }
        
        if animated && !active.isEmpty && active != lastActiveText {
            // Smooth vertical fade transition
            let transition = CATransition()
            transition.duration = 0.28
            transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            transition.type = .push
            transition.subtype = .fromTop
            activeLabel.layer?.add(transition, forKey: "lyricLineChange")
        }
        
        activeLabel.stringValue = active.isEmpty ? "♫" : active
        upcomingLabel.stringValue = upcoming
        
        lastActiveText = active
        lastUpcomingText = upcoming
    }
    
    public func setVisibility(visible: Bool, animated: Bool = true) {
        let targetAlpha: CGFloat = visible ? 1.0 : 0.0
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().alphaValue = targetAlpha
            }
        } else {
            self.alphaValue = targetAlpha
        }
    }
}
