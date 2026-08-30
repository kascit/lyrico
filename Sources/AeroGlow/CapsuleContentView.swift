import Cocoa
import QuartzCore

public enum DisplayStyle: String, Codable {
    case dualLine = "dual"
    case singleLine = "single"
}

public final class CapsuleContentView: NSView {
    private let visualEffectView: NSVisualEffectView
    private let activeLabel: NSTextField
    private let upcomingLabel: NSTextField
    
    public var currentStyle: DisplayStyle = .dualLine {
        didSet { updateLayout() }
    }
    
    public var currentTheme: ArtworkColorTheme = .default {
        didSet { updateTheme() }
    }
    
    private var lastLineText: String = ""
    private var lastUpcomingText: String = ""
    private var cachedActiveAttributedString: NSAttributedString?
    
    public override init(frame frameRect: NSRect) {
        self.visualEffectView = NSVisualEffectView(frame: .zero)
        self.activeLabel = NSTextField(labelWithString: "AeroGlow")
        self.upcomingLabel = NSTextField(labelWithString: "")
        
        super.init(frame: frameRect)
        wantsLayer = true
        setupUI()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupUI() {
        // Ultra-translucent airy frosted glass
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 28.0
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.backgroundColor = NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 0.28).cgColor
        visualEffectView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        visualEffectView.layer?.borderWidth = 1.0
        visualEffectView.layer?.shadowColor = NSColor.black.cgColor
        visualEffectView.layer?.shadowOpacity = 0.25
        visualEffectView.layer?.shadowOffset = CGSize(width: 0, height: -6)
        visualEffectView.layer?.shadowRadius = 18.0
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
        upcomingLabel.textColor = NSColor(white: 0.90, alpha: 0.40)
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
            upcomingLabel.isHidden = false
            upcomingLabel.frame = NSRect(x: 28, y: 10, width: pillWidth - 56, height: 18)
        } else {
            activeLabel.frame = NSRect(x: 28, y: (pillHeight - 30) / 2, width: pillWidth - 56, height: 30)
            upcomingLabel.isHidden = true
        }
    }
    
    public func updateTheme() {
        visualEffectView.layer?.borderColor = currentTheme.border.cgColor
    }
    
    // MARK: - Word-by-Word Karaoke Rendering
    
    public func renderKaraoke(line: LyricLine, currentPosition: TimeInterval, upcomingText: String) {
        let isNewLine = line.text != lastLineText
        
        if isNewLine && !line.text.isEmpty {
            let transition = CATransition()
            transition.duration = 0.26
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
        
        // Build AttributedString with Word-Level Glowing Highlight
        let attr = NSMutableAttributedString()
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = .center
        
        let glowShadow = NSShadow()
        glowShadow.shadowColor = currentTheme.glow
        glowShadow.shadowOffset = .zero
        glowShadow.shadowBlurRadius = 16.0
        
        for (i, word) in line.words.enumerated() {
            let isCurrentWord = (currentPosition >= word.startTime && currentPosition < word.endTime)
            let isSungWord = (currentPosition >= word.endTime)
            
            var attrs: [NSAttributedString.Key: Any] = [
                .paragraphStyle: paraStyle
            ]
            
            if isCurrentWord {
                // Currently being sung (Active glowing word)
                attrs[.font] = NSFont.systemFont(ofSize: 22, weight: .heavy)
                attrs[.foregroundColor] = NSColor.white
                attrs[.shadow] = glowShadow
            } else if isSungWord {
                // Already sung
                attrs[.font] = NSFont.systemFont(ofSize: 21, weight: .bold)
                attrs[.foregroundColor] = NSColor(white: 1.0, alpha: 0.95)
            } else {
                // Upcoming word in the sentence
                attrs[.font] = NSFont.systemFont(ofSize: 21, weight: .medium)
                attrs[.foregroundColor] = NSColor(white: 1.0, alpha: 0.38)
            }
            
            let wordStr = (i == 0 ? "" : " ") + word.text
            attr.append(NSAttributedString(string: wordStr, attributes: attrs))
        }
        
        activeLabel.attributedStringValue = attr
    }
    
    public func setStaticText(active: String, upcoming: String = "") {
        if active == lastLineText && upcoming == lastUpcomingText { return }
        
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = .center
        
        let glowShadow = NSShadow()
        glowShadow.shadowColor = currentTheme.glow
        glowShadow.shadowOffset = .zero
        glowShadow.shadowBlurRadius = 12.0
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 21, weight: .bold),
            .foregroundColor: NSColor.white,
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
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().alphaValue = targetAlpha
            }
        } else {
            self.alphaValue = targetAlpha
        }
    }
}
