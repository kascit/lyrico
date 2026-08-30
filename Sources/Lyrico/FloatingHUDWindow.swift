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
        let savedPosStr = ConfigManager.shared.config.position
        let pos = HUDPosition(rawValue: savedPosStr) ?? .bottom
        self.currentPosition = pos
        
        let width: CGFloat = 860.0
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
        updatePosition(to: pos, animated: false)
    }
    
    public func updatePosition(to position: HUDPosition, animated: Bool = true) {
        self.currentPosition = position
        ConfigManager.shared.updatePosition(position.rawValue)
        
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 949)
        
        let width: CGFloat = 860.0
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
                ctx.duration = 0.28
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
        didSet {
            ConfigManager.shared.updateStyle(style.rawValue)
            updateLayout()
        }
    }
    
    private var lastLineText: String = ""
    private var lastUpcomingText: String = ""
    private var lastLyricLine: LyricLine?
    private var lastPlaybackPos: TimeInterval = 0.0
    
    public override init(frame frameRect: NSRect) {
        self.visualEffectView = NSVisualEffectView(frame: .zero)
        self.activeLabel = NSTextField(labelWithString: "Lyrico")
        self.upcomingLabel = NSTextField(labelWithString: "")
        
        let savedStyle = ConfigManager.shared.config.style
        self.style = HUDStyle(rawValue: savedStyle) ?? .dual
        
        super.init(frame: frameRect)
        wantsLayer = true
        setupUI()
        
        ThemeManager.shared.onThemeChange = { [weak self] in
            DispatchQueue.main.async {
                self?.applyTheme()
            }
        }
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupUI() {
        // True Crystal-Clear Frosted Glass (behindWindow blur)
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 18.0
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1.0
        visualEffectView.layer?.shadowColor = NSColor.black.cgColor
        visualEffectView.layer?.shadowOpacity = 0.20
        visualEffectView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        visualEffectView.layer?.shadowRadius = 12.0
        addSubview(visualEffectView)
        
        // Active Line (Top Slot)
        activeLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        activeLabel.alignment = .center
        activeLabel.lineBreakMode = .byTruncatingTail
        activeLabel.maximumNumberOfLines = 1
        activeLabel.wantsLayer = true
        visualEffectView.addSubview(activeLabel)
        
        // Upcoming Line (Bottom Slot)
        upcomingLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
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
        let cardWidth = min(b.width - 20, 820.0)
        let cardX = (b.width - cardWidth) / 2
        let cardY = (b.height - cardHeight) / 2
        
        visualEffectView.frame = NSRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        
        if style == .dual {
            // Active Line at top, Upcoming Line at bottom
            activeLabel.frame = NSRect(x: 24, y: cardHeight - 40, width: cardWidth - 48, height: 28)
            upcomingLabel.isHidden = false
            upcomingLabel.frame = NSRect(x: 24, y: 8, width: cardWidth - 48, height: 18)
        } else {
            activeLabel.frame = NSRect(x: 24, y: (cardHeight - 28) / 2, width: cardWidth - 48, height: 28)
            upcomingLabel.isHidden = true
        }
    }
    
    public func applyTheme() {
        let colors = ThemeManager.shared.resolveColors()
        visualEffectView.material = colors.material
        visualEffectView.layer?.backgroundColor = colors.tintColor.cgColor
        visualEffectView.layer?.borderColor = colors.border.cgColor
        upcomingLabel.textColor = colors.upcomingText
        
        if let line = lastLyricLine {
            renderKaraoke(line: line, currentPosition: lastPlaybackPos, upcomingText: lastUpcomingText)
        } else if !lastLineText.isEmpty {
            setStatic(active: lastLineText, upcoming: lastUpcomingText)
        }
    }
    
    public func renderKaraoke(line: LyricLine, currentPosition: TimeInterval, upcomingText: String) {
        lastLyricLine = line
        lastPlaybackPos = currentPosition
        let isNewLine = line.text != lastLineText
        
        if isNewLine && !line.text.isEmpty {
            // Logical upward scroll: previous line slides UP and out, new line slides UP from below
            let pushUpTransition = CATransition()
            pushUpTransition.duration = 0.26
            pushUpTransition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pushUpTransition.type = .push
            pushUpTransition.subtype = .fromBottom // Enters from bottom, exits towards top
            activeLabel.layer?.add(pushUpTransition, forKey: "lyricsScrollUp")
        }
        
        lastLineText = line.text
        
        if upcomingText != lastUpcomingText {
            let fadeTransition = CATransition()
            fadeTransition.duration = 0.22
            fadeTransition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fadeTransition.type = .fade
            upcomingLabel.layer?.add(fadeTransition, forKey: "upcomingFade")
            upcomingLabel.stringValue = upcomingText
            lastUpcomingText = upcomingText
        }
        
        let colors = ThemeManager.shared.resolveColors()
        let attr = NSMutableAttributedString()
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = .center
        
        let subtleGlow = NSShadow()
        subtleGlow.shadowColor = colors.glowColor
        subtleGlow.shadowOffset = .zero
        subtleGlow.shadowBlurRadius = 8.0 // Crisp, professional subtle glow
        
        for (i, word) in line.words.enumerated() {
            let isCurrentWord = (currentPosition >= word.startTime && currentPosition < word.endTime)
            let isSungWord = (currentPosition >= word.endTime)
            
            var attrs: [NSAttributedString.Key: Any] = [
                .paragraphStyle: paraStyle
            ]
            
            if isCurrentWord {
                attrs[.font] = NSFont.systemFont(ofSize: 22, weight: .heavy)
                attrs[.foregroundColor] = colors.activeText
                attrs[.shadow] = subtleGlow
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
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 21, weight: .bold),
            .foregroundColor: colors.activeText,
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
