import Cocoa
import QuartzCore

public final class FullscreenLyricsWindow: NSPanel {
    public let fullscreenView: FullscreenLyricsView
    public private(set) var isShowingFullscreen: Bool = false
    
    public init() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let rect = screen?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        
        self.fullscreenView = FullscreenLyricsView(frame: NSRect(origin: .zero, size: rect.size))
        
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.hasShadow = false
        self.contentView = fullscreenView
        self.alphaValue = 0.0
        self.ignoresMouseEvents = false
    }
    
    public func showFullscreen(animated: Bool = true) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let rect = screen?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        self.setFrame(rect, display: true)
        
        isShowingFullscreen = true
        self.makeKeyAndOrderFront(nil)
        
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 1.0
            }
        } else {
            self.alphaValue = 1.0
        }
    }
    
    public func hideFullscreen(animated: Bool = true) {
        isShowingFullscreen = false
        
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                self?.orderOut(nil)
            })
        } else {
            self.alphaValue = 0.0
            self.orderOut(nil)
        }
    }
    
    public func toggleFullscreen(animated: Bool = true) {
        if isShowingFullscreen {
            hideFullscreen(animated: animated)
        } else {
            showFullscreen(animated: animated)
        }
    }
    
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            hideFullscreen(animated: true)
        } else {
            super.keyDown(with: event)
        }
    }
}

public final class FullscreenLyricsView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let closeHintLabel = NSTextField(labelWithString: "Press Esc or ⌥⇧F to exit fullscreen")
    
    // Lyrics Display Lines (Past, Active, Next 1, Next 2)
    private let prevLineLabel = NSTextField(labelWithString: "")
    private let activeLineLabel = NSTextField(labelWithString: "")
    private let nextLine1Label = NSTextField(labelWithString: "")
    private let nextLine2Label = NSTextField(labelWithString: "")
    
    private var currentLyrics: ParsedLyrics?
    private var lastActiveIndex: Int = -1
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupUI()
        
        ThemeManager.shared.onThemeChange = { [weak self] in
            self?.applyTheme()
        }
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupUI() {
        // Header
        titleLabel.font = NSFont.systemFont(ofSize: 26, weight: .heavy)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        
        artistLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        artistLabel.alignment = .center
        artistLabel.lineBreakMode = .byTruncatingTail
        addSubview(artistLabel)
        
        closeHintLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        closeHintLabel.alignment = .center
        addSubview(closeHintLabel)
        
        // Lines
        prevLineLabel.font = NSFont.systemFont(ofSize: 22, weight: .medium)
        prevLineLabel.alignment = .center
        prevLineLabel.lineBreakMode = .byTruncatingTail
        addSubview(prevLineLabel)
        
        activeLineLabel.font = NSFont.systemFont(ofSize: 36, weight: .heavy)
        activeLineLabel.alignment = .center
        activeLineLabel.lineBreakMode = .byTruncatingTail
        addSubview(activeLineLabel)
        
        nextLine1Label.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        nextLine1Label.alignment = .center
        nextLine1Label.lineBreakMode = .byTruncatingTail
        addSubview(nextLine1Label)
        
        nextLine2Label.font = NSFont.systemFont(ofSize: 20, weight: .medium)
        nextLine2Label.alignment = .center
        nextLine2Label.lineBreakMode = .byTruncatingTail
        addSubview(nextLine2Label)
        
        applyTheme()
    }
    
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutSubviews()
    }
    
    private func layoutSubviews() {
        let b = bounds
        guard b.width > 0 && b.height > 0 else { return }
        
        let centerX = b.width / 2
        let centerY = b.height / 2
        let maxW = min(b.width - 80, 1100.0)
        let leftX = (b.width - maxW) / 2
        
        // Header at top
        titleLabel.frame = NSRect(x: leftX, y: b.height - 90, width: maxW, height: 34)
        artistLabel.frame = NSRect(x: leftX, y: b.height - 124, width: maxW, height: 24)
        closeHintLabel.frame = NSRect(x: leftX, y: 30, width: maxW, height: 20)
        
        // Center lyrics column
        activeLineLabel.frame = NSRect(x: leftX, y: centerY - 25, width: maxW, height: 50)
        prevLineLabel.frame = NSRect(x: leftX, y: centerY + 45, width: maxW, height: 35)
        nextLine1Label.frame = NSRect(x: leftX, y: centerY - 80, width: maxW, height: 40)
        nextLine2Label.frame = NSRect(x: leftX, y: centerY - 130, width: maxW, height: 35)
    }
    
    public func applyTheme() {
        let colors = ThemeManager.shared.resolveColors()
        layer?.backgroundColor = colors.fullscreenBackground.cgColor
        
        titleLabel.textColor = colors.activeText
        artistLabel.textColor = colors.upcomingText
        closeHintLabel.textColor = colors.upcomingText.withAlphaComponent(0.5)
        
        prevLineLabel.textColor = colors.sungText.withAlphaComponent(0.35)
        nextLine1Label.textColor = colors.upcomingText
        nextLine2Label.textColor = colors.upcomingText.withAlphaComponent(0.35)
    }
    
    public func updateTrackInfo(title: String, artist: String) {
        titleLabel.stringValue = title
        artistLabel.stringValue = artist
    }
    
    public func updateLyrics(lyrics: ParsedLyrics?) {
        self.currentLyrics = lyrics
        self.lastActiveIndex = -1
    }
    
    public func tickPlayback(position: TimeInterval) {
        guard let lyrics = currentLyrics, !lyrics.lines.isEmpty else {
            activeLineLabel.stringValue = "♫"
            prevLineLabel.stringValue = ""
            nextLine1Label.stringValue = ""
            nextLine2Label.stringValue = ""
            return
        }
        
        guard let activeIdx = lyrics.activeLineIndex(at: position) else { return }
        
        if activeIdx != lastActiveIndex {
            lastActiveIndex = activeIdx
            
            // Previous Line
            prevLineLabel.stringValue = (activeIdx > 0) ? lyrics.lines[activeIdx - 1].text : ""
            
            // Next Lines
            nextLine1Label.stringValue = (activeIdx + 1 < lyrics.lines.count) ? lyrics.lines[activeIdx + 1].text : ""
            nextLine2Label.stringValue = (activeIdx + 2 < lyrics.lines.count) ? lyrics.lines[activeIdx + 2].text : ""
        }
        
        // Active Line with Word Karaoke Highlighting
        let activeLine = lyrics.lines[activeIdx]
        let colors = ThemeManager.shared.resolveColors()
        let attr = NSMutableAttributedString()
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = .center
        
        let glowShadow = NSShadow()
        glowShadow.shadowColor = colors.glowColor
        glowShadow.shadowOffset = .zero
        glowShadow.shadowBlurRadius = 22.0
        
        for (i, word) in activeLine.words.enumerated() {
            let isCurrent = (position >= word.startTime && position < word.endTime)
            let isSung = (position >= word.endTime)
            
            var attrs: [NSAttributedString.Key: Any] = [
                .paragraphStyle: paraStyle
            ]
            
            if isCurrent {
                attrs[.font] = NSFont.systemFont(ofSize: 38, weight: .black)
                attrs[.foregroundColor] = colors.activeText
                attrs[.shadow] = glowShadow
            } else if isSung {
                attrs[.font] = NSFont.systemFont(ofSize: 36, weight: .heavy)
                attrs[.foregroundColor] = colors.sungText
            } else {
                attrs[.font] = NSFont.systemFont(ofSize: 36, weight: .semibold)
                attrs[.foregroundColor] = colors.upcomingText
            }
            
            let wordStr = (i == 0 ? "" : " ") + word.text
            attr.append(NSAttributedString(string: wordStr, attributes: attrs))
        }
        
        activeLineLabel.attributedStringValue = attr
    }
}
