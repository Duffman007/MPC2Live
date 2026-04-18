import Cocoa

// MARK: - Utilities

enum Util {
    static func resourcePath(_ name: String) -> String {
        Bundle.main.path(forResource: (name as NSString).deletingPathExtension,
                         ofType: (name as NSString).pathExtension) ?? ""
    }
    static func readResource(_ name: String) -> String {
        let path = resourcePath(name)
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
    static func appVersion() -> String {
        let v = readResource("version.txt").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? "0.10" : v
    }
}

// MARK: - Title Bar Theme Toggle

private class TitleBarThemeToggle: NSView {
    var isDark: Bool = true {
        didSet {
            guard oldValue != isDark else { return }
            onThemeChanged?(isDark)
            startAnimation(target: isDark ? 1 : 0)
        }
    }
    var onThemeChanged: ((Bool) -> Void)?

    private var thumbPosition: CGFloat = 1.0
    private var animFrom: CGFloat = 1.0
    private var animTarget: CGFloat = 1.0
    private var animStart: CFTimeInterval = 0
    private var animTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 52, height: 24))
        wantsLayer = true
        toolTip = "Toggle theme"
    }
    required init?(coder: NSCoder) { fatalError() }

    private func startAnimation(target: CGFloat) {
        animTimer?.invalidate()
        animFrom = thumbPosition
        animTarget = target
        animStart = CACurrentMediaTime()
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            let duration: CFTimeInterval = 0.25
            let t = min(1, CGFloat((CACurrentMediaTime() - s.animStart) / duration))
            let eased = t < 0.5 ? 2*t*t : -1+(4-2*t)*t
            s.thumbPosition = s.animFrom + (s.animTarget - s.animFrom) * eased
            s.needsDisplay = true
            if t >= 1 { s.animTimer?.invalidate(); s.animTimer = nil }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let w: CGFloat = 52, h: CGFloat = 24, r = h / 2
        let rect = NSRect(x: 0, y: 0, width: w, height: h)

        let trackPath = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()

        let isDarkMode = thumbPosition > 0.5
        if isDarkMode {
            let c1 = NSColor(red: 0.16, green: 0.10, blue: 0.32, alpha: 1)
            let c2 = NSColor(red: 0.10, green: 0.06, blue: 0.20, alpha: 1)
            NSGradient(colors: [c1, c2])!.draw(in: rect, angle: 270)
        } else {
            let c1 = NSColor(white: 0.92, alpha: 1)
            let c2 = NSColor(white: 0.88, alpha: 1)
            NSGradient(colors: [c1, c2])!.draw(in: rect, angle: 270)
        }
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(isDarkMode ? 0.3 : 0.15).setStroke()
        let innerTrack = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                      xRadius: r - 0.5, yRadius: r - 0.5)
        innerTrack.lineWidth = 1
        innerTrack.stroke()

        let thumbSize: CGFloat = h - 6
        let thumbTravel = w - h + 2
        let thumbX = 3 + thumbPosition * thumbTravel
        let thumbRect = NSRect(x: thumbX, y: 3, width: thumbSize, height: thumbSize)
        let thumbPath = NSBezierPath(ovalIn: thumbRect)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 3
        shadow.set()
        NSColor.white.setFill()
        thumbPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let iconSize: CGFloat = 12
        let iconRect = NSRect(x: thumbRect.midX - iconSize/2, y: thumbRect.midY - iconSize/2,
                              width: iconSize, height: iconSize)
        let iconAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: iconSize, weight: .medium),
            .foregroundColor: isDarkMode ? NSColor(white: 0.3, alpha: 1) : NSColor(white: 0.4, alpha: 1)
        ]
        let icon = isDarkMode ? "☾" : "☀"
        NSAttributedString(string: icon, attributes: iconAttrs)
            .draw(at: NSPoint(x: iconRect.minX - 1, y: iconRect.minY - 1))
    }

    override func mouseDown(with event: NSEvent) { isDark = !isDark }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

// MARK: - Main Window

class MainWindow: NSWindow {
    private var themeToggle: TitleBarThemeToggle?
    
    // UserDefaults key for theme preference
    private static let themePreferenceKey = "MPC2Live.AppearanceIsDark"

    init() {
        let w: CGFloat = 640, h: CGFloat = 680
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let rect = NSRect(x: (screen.width - w) / 2, y: (screen.height - h) / 2, width: w, height: h)
        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        title = "MPC2Live"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 540, height: 580)

        // Load saved theme preference (defaults to dark if not set)
        let savedIsDark = UserDefaults.standard.object(forKey: Self.themePreferenceKey) as? Bool ?? true
        appearance = NSAppearance(named: savedIsDark ? .darkAqua : .aqua)
        contentViewController = DropViewController()
        setupTitleBarToggle(initialDark: savedIsDark)
    }

    private func setupTitleBarToggle(initialDark: Bool) {
        guard let titlebarView = standardWindowButton(.closeButton)?.superview else { return }

        standardWindowButton(.documentIconButton)?.isHidden = true
        standardWindowButton(.documentIconButton)?.alphaValue = 0
        standardWindowButton(.documentIconButton)?.frame = .zero

        for subview in titlebarView.subviews {
            if let button = subview as? NSButton, button.image != nil {
                if button != standardWindowButton(.closeButton) &&
                   button != standardWindowButton(.miniaturizeButton) &&
                   button != standardWindowButton(.zoomButton) {
                    button.isHidden = true
                }
            }
        }

        let toggle = TitleBarThemeToggle()
        toggle.isDark = initialDark
        toggle.onThemeChanged = { [weak self] dark in
            // Save preference
            UserDefaults.standard.set(dark, forKey: Self.themePreferenceKey)
            
            self?.setTitleBarAppearance(dark: dark)
            if let vc = self?.contentViewController as? DropViewController {
                vc.isDark = dark
            }
        }

        titlebarView.addSubview(toggle)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toggle.trailingAnchor.constraint(equalTo: titlebarView.trailingAnchor, constant: -16),
            toggle.centerYAnchor.constraint(equalTo: titlebarView.centerYAnchor),
            toggle.widthAnchor.constraint(equalToConstant: 52),
            toggle.heightAnchor.constraint(equalToConstant: 24)
        ])
        themeToggle = toggle
        
        // Apply initial theme to view controller
        if let vc = contentViewController as? DropViewController {
            vc.isDark = initialDark
        }
    }

    func setTitleBarAppearance(dark: Bool) {
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}
