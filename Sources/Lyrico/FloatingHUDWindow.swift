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
        
        let width: CGFloat = 820.0
        let height: CGFloat = 90.0
        
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
        
        let width: CGFloat = 820.0
        let height: CGFloat = 90.0
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
    private let cardView: NSView
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
        self.cardView = NSView(frame: .zero)
        self.activeLabel = NSTextField(labelWithString: "Lyrico")
        self.upcomingLabel = NSTextField(labelWithString: "")
        
        let savedStyle = ConfigManager.shared.config.style
        self.style = HUDStyle(rawValue: savedStyle) ?? .dual
        
        super.init(frame: frameRect)
        wantsLayer = true
        setupUI()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeDidChange),
            name: ThemeManager.themeDidChangeNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupUI() {
        // True Translucent Glass Card
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 18.0
        cardView.layer?.masksToBounds = true
        cardView.layer?.borderWidth = 1.0
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.layer?.shadowOpacity = 0.25
        cardView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        cardView.layer?.shadowRadius = 14.0
        addSubview(cardView)
        
        // Active Line
        activeLabel.font = NSFont.systemFont(ofSize: 21.5, weight: .bold)
        activeLabel.alignment = .center
        activeLabel.lineBreakMode = .byTruncatingTail
        activeLabel.maximumNumberOfLines = 1
        activeLabel.isBezeled = false
        activeLabel.isEditable = false
        activeLabel.drawsBackground = false
        activeLabel.wantsLayer = true
        cardView.addSubview(activeLabel)
        
        // Upcoming Line (Bottom Slot)
        upcomingLabel.font = NSFont.systemFont(ofSize: 13.0, weight: .medium)
        upcomingLabel.alignment = .center
        upcomingLabel.lineBreakMode = .byTruncatingTail
        upcomingLabel.maximumNumberOfLines = 1
        upcomingLabel.isBezeled = false
        upcomingLabel.isEditable = false
        upcomingLabel.drawsBackground = false
        upcomingLabel.wantsLayer = true
        cardView.addSubview(upcomingLabel)
        
        updateLayout()
        applyTheme()
    }
    
    public override func layout() {
        super.layout()
        updateLayout()
    }
    
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        updateLayout()
    }
    
    private func updateLayout() {
        let b = bounds
        guard b.width > 0 && b.height > 0 else { return }
        
        let cardHeight: CGFloat = (style == .dual) ? 66.0 : 46.0
        let cardWidth = min(b.width - 20, 780.0)
        let cardX = (b.width - cardWidth) / 2
        let cardY = (b.height - cardHeight) / 2
        
        cardView.frame = NSRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        
        let labelPad: CGFloat = 20.0
        let labelWidth = cardWidth - (labelPad * 2)
        
        if style == .dual {
            activeLabel.frame = NSRect(x: labelPad, y: cardHeight - 37, width: labelWidth, height: 27)
            upcomingLabel.isHidden = false
            upcomingLabel.frame = NSRect(x: labelPad, y: 8, width: labelWidth, height: 17)
        } else {
            activeLabel.frame = NSRect(x: labelPad, y: (cardHeight - 27) / 2, width: labelWidth, height: 27)
            upcomingLabel.isHidden = true
        }
    }
    
    @objc private func handleThemeDidChange() {
        applyTheme()
    }
    
    public func applyTheme() {
        let colors = ThemeManager.shared.resolveColors()
        cardView.layer?.backgroundColor = colors.cardBackground.cgColor
        cardView.layer?.borderColor = colors.border.cgColor
        upcomingLabel.textColor = colors.upcomingText
        
        if let line = lastLyricLine {
            renderKaraoke(line: line, currentPosition: lastPlaybackPos, upcomingText: lastUpcomingText)
        } else if !lastLineText.isEmpty {
            setStatic(active: lastLineText, upcoming: lastUpcomingText)
        }
    }
    
    private func fontForText(_ text: String, availableWidth: CGFloat, weight: NSFont.Weight = .bold) -> NSFont {
        let baseFont = NSFont.systemFont(ofSize: 21.5, weight: weight)
        let str = text as NSString
        let size = str.size(withAttributes: [.font: baseFont])
        
        if size.width <= availableWidth {
            return baseFont
        } else if size.width <= availableWidth * 1.15 {
            return NSFont.systemFont(ofSize: 19.0, weight: weight)
        } else {
            return NSFont.systemFont(ofSize: 16.5, weight: weight)
        }
    }
    
    public func renderKaraoke(line: LyricLine, currentPosition: TimeInterval, upcomingText: String) {
        lastLyricLine = line
        lastPlaybackPos = currentPosition
        let isNewLine = line.text != lastLineText
        
        if isNewLine && !line.text.isEmpty {
            let pushUpTransition = CATransition()
            pushUpTransition.duration = 0.20
            pushUpTransition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pushUpTransition.type = .push
            pushUpTransition.subtype = .fromBottom
            activeLabel.layer?.add(pushUpTransition, forKey: "lyricsScrollUp")
        }
        
        lastLineText = line.text
        
        if upcomingText != lastUpcomingText {
            let fadeTransition = CATransition()
            fadeTransition.duration = 0.20
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
        paraStyle.lineBreakMode = .byTruncatingTail
        
        let labelWidth = max(200.0, activeLabel.bounds.width > 0 ? activeLabel.bounds.width : 740.0)
        let activeFont = fontForText(line.text, availableWidth: labelWidth, weight: .heavy)
        let sungFont = fontForText(line.text, availableWidth: labelWidth, weight: .bold)
        let upcomingFont = fontForText(line.text, availableWidth: labelWidth, weight: .medium)
        
        let subtleGlow = NSShadow()
        subtleGlow.shadowColor = colors.glowColor
        subtleGlow.shadowOffset = .zero
        subtleGlow.shadowBlurRadius = 8.0
        
        for (i, word) in line.words.enumerated() {
            let isCurrentWord = (currentPosition >= word.startTime && currentPosition < word.endTime)
            let isSungWord = (currentPosition >= word.endTime)
            
            var attrs: [NSAttributedString.Key: Any] = [
                .paragraphStyle: paraStyle
            ]
            
            if isCurrentWord {
                attrs[.font] = activeFont
                attrs[.foregroundColor] = colors.activeText
                attrs[.shadow] = subtleGlow
            } else if isSungWord {
                attrs[.font] = sungFont
                attrs[.foregroundColor] = colors.sungText
            } else {
                attrs[.font] = upcomingFont
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
        paraStyle.lineBreakMode = .byTruncatingTail
        
        let labelWidth = max(200.0, activeLabel.bounds.width > 0 ? activeLabel.bounds.width : 740.0)
        let font = fontForText(active, availableWidth: labelWidth, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
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
