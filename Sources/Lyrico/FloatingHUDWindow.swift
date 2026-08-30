import Cocoa
import QuartzCore

public enum HUDPosition: String, Codable {
    case bottom = "bottom"
    case top = "top"
}

public enum HUDStyle: String, Codable {
    case dual = "dual"
    case single = "single"
}

public final class FloatingHUDWindow: NSPanel {
    public let hudView: FloatingHUDView
    public private(set) var currentPosition: HUDPosition = .bottom
    
    public init() {
        let width: CGFloat = 880.0
        let height: CGFloat = 100.0
        
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 949)
        
        let x = round((screenFrame.width - width) / 2)
        let bottomY = visibleFrame.origin.y + 36
        let rect = NSRect(x: x, y: bottomY, width: width, height: height)
        
        self.hudView = FloatingHUDView(frame: NSRect(origin: .zero, size: rect.size))
        
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        
        self.contentView = hudView
        updatePosition(to: .bottom, animated: false)
    }
    
    public func updatePosition(to position: HUDPosition, animated: Bool = true) {
        self.currentPosition = position
        
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 949)
        
        let width: CGFloat = 880.0
        let height: CGFloat = 100.0
        let x = round((screenFrame.width - width) / 2)
        
        let y: CGFloat
        if position == .top {
            y = visibleFrame.origin.y + visibleFrame.height - height - 12
        } else {
            y = visibleFrame.origin.y + 36
        }
        
        let targetRect = NSRect(x: x, y: y, width: width, height: height)
        
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.30
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(targetRect, display: true)
            }
        } else {
            self.setFrame(targetRect, display: true)
        }
    }
    
    public func togglePosition(animated: Bool = true) {
        let next: HUDPosition = (currentPosition == .bottom) ? .top : .bottom
        updatePosition(to: next, animated: animated)
    }
}

public final class FloatingHUDView: NSView {
    private let visualEffectView: NSVisualEffectView
    private let activeLabel: NSTextField
    private let upcomingLabel: NSTextField
    
    public var style: HUDStyle = .dual {
        didSet { updateLayout() }
    }
    
    private var lastLineText: String = ""
    private var lastUpcomingText: String = ""
    
    public override init(frame frameRect: NSRect) {
        self.visualEffectView = NSVisualEffectView(frame: .zero)
        self.activeLabel = NSTextField(labelWithString: "Lyrico")
        self.upcomingLabel = NSTextField(labelWithString: "")
        
        super.init(frame: frameRect)
        wantsLayer = true
        setupUI()
        
        ThemeManager.shared.onThemeChange = { [weak self] in
            self?.applyTheme()
        }
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupUI() {
        // Modern Squircle Glass Card (not a pill, clean rounded rectangle)
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 18.0
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 0.8
        visualEffectView.layer?.shadowColor = NSColor.black.cgColor
        visualEffectView.layer?.shadowOpacity = 0.22
        visualEffectView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        visualEffectView.layer?.shadowRadius = 14.0
        addSubview(visualEffectView)
        
        // Active Line
        activeLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        activeLabel.textColor = .white
        activeLabel.alignment = .center
        activeLabel.lineBreakMode = .byTruncatingTail
        activeLabel.maximumNumberOfLines = 1
        activeLabel.wantsLayer = true
        visualEffectView.addSubview(activeLabel)
        
        // Upcoming Line
        upcomingLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        upcomingLabel.textColor = NSColor(white: 0.88, alpha: 0.45)
        upcomingLabel.alignment = .center
        upcomingLabel.lineBreakMode = .byTruncatingTail
        upcomingLabel.maximumNumberOfLines = 1
        upcomingLabel.wantsLayer = true
        visualEffectView.addSubview(upcomingLabel)
        
        updateLayout()
        applyTheme()
    }
    
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        updateLayout()
    }
    
    private func updateLayout() {
        let b = bounds
        guard b.width > 0 && b.height > 0 else { return }
        
        let cardHeight: CGFloat = style == .dual ? 68.0 : 48.0
        let cardWidth = min(b.width - 24, 840.0)
        let cardX = (b.width - cardWidth) / 2
        let cardY = (b.height - cardHeight) / 2
        
        visualEffectView.frame = NSRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        
        if style == .dual {
            activeLabel.frame = NSRect(x: 24, y: cardHeight - 42, width: cardWidth - 48, height: 30)
            upcomingLabel.isHidden = false
            upcomingLabel.frame = NSRect(x: 24, y: 8, width: cardWidth - 48, height: 18)
        } else {
            activeLabel.frame = NSRect(x: 24, y: (cardHeight - 30) / 2, width: cardWidth - 48, height: 30)
            upcomingLabel.isHidden = true
        }
    }
    
    public func applyTheme() {
        let colors = ThemeManager.shared.resolveColors()
        visualEffectView.layer?.backgroundColor = colors.background.cgColor
        visualEffectView.layer?.borderColor = colors.border.cgColor
        upcomingLabel.textColor = colors.upcomingText
    }
    
    public func renderKaraoke(line: LyricLine, currentPosition: TimeInterval, upcomingText: String) {
        let isNewLine = line.text != lastLineText
        
        if isNewLine && !line.text.isEmpty {
            let transition = CATransition()
            transition.duration = 0.24
            transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            transition.type = .push
            transition.subtype = .fromTop
            activeLabel.layer?.add(transition, forKey: "karaokeLinePush")
        }
        
        lastLineText = line.text
        
        if upcomingText != lastUpcomingText {
            upcomingLabel.stringValue = upcomingText
            lastUpcomingText = upcomingText
        }
        
        let colors = ThemeManager.shared.resolveColors()
        let attr = NSMutableAttributedString()
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = .center
        
        let glowShadow = NSShadow()
        glowShadow.shadowColor = colors.glowColor
        glowShadow.shadowOffset = .zero
        glowShadow.shadowBlurRadius = 14.0
        
        for (i, word) in line.words.enumerated() {
            let isCurrentWord = (currentPosition >= word.startTime && currentPosition < word.endTime)
            let isSungWord = (currentPosition >= word.endTime)
            
            var attrs: [NSAttributedString.Key: Any] = [
                .paragraphStyle: paraStyle
            ]
            
            if isCurrentWord {
                attrs[.font] = NSFont.systemFont(ofSize: 22, weight: .heavy)
                attrs[.foregroundColor] = colors.activeText
                attrs[.shadow] = glowShadow
            } else if isSungWord {
                attrs[.font] = NSFont.systemFont(ofSize: 21, weight: .bold)
                attrs[.foregroundColor] = colors.sungText
            } else {
                attrs[.font] = NSFont.systemFont(ofSize: 21, weight: .medium)
                attrs[.foregroundColor] = colors.upcomingText
            }
            
            let wordStr = (i == 0 ? "" : " ") + word.text
            attr.append(NSAttributedString(string: wordStr, attributes: attrs))
        }
        
        activeLabel.attributedStringValue = attr
    }
    
    public func setStatic(active: String, upcoming: String = "") {
        if active == lastLineText && upcoming == lastUpcomingText { return }
        
        let colors = ThemeManager.shared.resolveColors()
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = .center
        
        let glowShadow = NSShadow()
        glowShadow.shadowColor = colors.glowColor
        glowShadow.shadowOffset = .zero
        glowShadow.shadowBlurRadius = 12.0
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 21, weight: .bold),
            .foregroundColor: colors.activeText,
            .shadow: glowShadow,
            .paragraphStyle: paraStyle
        ]
        
        activeLabel.attributedStringValue = NSAttributedString(string: active.isEmpty ? "♫" : active, attributes: attrs)
        upcomingLabel.stringValue = upcoming
        
        lastLineText = active
        lastUpcomingText = upcoming
    }
    
    public func setVisibility(visible: Bool, animated: Bool = true) {
        let targetAlpha: CGFloat = visible ? 1.0 : 0.0
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().alphaValue = targetAlpha
            }
        } else {
            self.alphaValue = targetAlpha
        }
    }
}
