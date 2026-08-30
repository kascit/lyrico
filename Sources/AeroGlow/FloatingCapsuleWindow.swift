import Cocoa

public enum CapsulePosition: String, Codable {
    case bottom = "bottom"
    case top = "top"
}

public final class FloatingCapsuleWindow: NSPanel {
    public let capsuleView: CapsuleContentView
    public private(set) var currentPosition: CapsulePosition = .bottom
    
    public init() {
        let width: CGFloat = 920.0
        let height: CGFloat = 110.0
        
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 949)
        
        let x = round((screenFrame.width - width) / 2)
        let bottomY = visibleFrame.origin.y + 40
        let initialRect = NSRect(x: x, y: bottomY, width: width, height: height)
        
        self.capsuleView = CapsuleContentView(frame: NSRect(origin: .zero, size: initialRect.size))
        
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Window Configuration
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        
        self.contentView = capsuleView
        updateWindowFrame(for: .bottom, animated: false)
    }
    
    public func setPosition(_ position: CapsulePosition, animated: Bool = true) {
        self.currentPosition = position
        updateWindowFrame(for: position, animated: animated)
    }
    
    public func togglePosition(animated: Bool = true) {
        let next: CapsulePosition = (currentPosition == .bottom) ? .top : .bottom
        setPosition(next, animated: animated)
    }
    
    private func updateWindowFrame(for position: CapsulePosition, animated: Bool) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 949)
        
        let width: CGFloat = 920.0
        let height: CGFloat = 110.0
        let x = round((screenFrame.width - width) / 2)
        
        let y: CGFloat
        if position == .top {
            // Under menu bar / notch
            y = visibleFrame.origin.y + visibleFrame.height - height - 10
        } else {
            // Above bottom screen edge
            y = visibleFrame.origin.y + 35
        }
        
        let targetRect = NSRect(x: x, y: y, width: width, height: height)
        
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(targetRect, display: true)
            }
        } else {
            self.setFrame(targetRect, display: true)
        }
    }
}
