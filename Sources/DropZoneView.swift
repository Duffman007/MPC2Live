import Cocoa

// MARK: - DropZoneState

enum DropZoneState { case idle, dragging, converting, done, error }

// MARK: - HardwareToggleControl

class HardwareToggleControl: NSView {
    var isOn: Bool = false {
        didSet { guard oldValue != isOn else { return }; onChanged?(isOn); startAnim(isOn ? 1 : 0) }
    }
    var accentColor: NSColor = K2LColors.accent
    var onChanged: ((Bool) -> Void)?

    private var thumb: CGFloat = 0
    private var animFrom: CGFloat = 0
    private var animTarget: CGFloat = 0
    private var animStart: CFTimeInterval = 0
    private var animTimer: Timer?

    override var intrinsicContentSize: NSSize { NSSize(width: 46, height: 26) }

    private func startAnim(_ target: CGFloat) {
        animTimer?.invalidate()
        animFrom = thumb; animTarget = target; animStart = CACurrentMediaTime()
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            let d: CFTimeInterval = 0.22
            let t = min(1, CGFloat((CACurrentMediaTime() - s.animStart) / d))
            let e = t < 0.5 ? 2*t*t : -1+(4-2*t)*t
            s.thumb = s.animFrom + (s.animTarget - s.animFrom) * e
            s.needsDisplay = true
            if t >= 1 { s.animTimer?.invalidate(); s.animTimer = nil }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let w: CGFloat = 46, h: CGFloat = 26, r = h / 2
        let rect = NSRect(x: 0, y: 0, width: w, height: h)
        let track = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)

        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        if isOn {
            let end = accentColor.blended(withFraction: 0.18, of: .black) ?? accentColor
            NSGradient(colors: [accentColor, end])!.draw(in: rect, angle: 270)
        } else {
            NSGradient(colors: [NSColor(calibratedWhite: 0.10, alpha: 1),
                                 NSColor(calibratedWhite: 0.16, alpha: 1)])!.draw(in: rect, angle: 270)
        }
        NSColor.black.withAlphaComponent(isOn ? 0.3 : 0.55).setStroke()
        let inner = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: r - 0.5, yRadius: r - 0.5)
        inner.lineWidth = 1; inner.stroke()
        NSGraphicsContext.restoreGraphicsState()

        if isOn {
            accentColor.withAlphaComponent(0.3).setStroke()
            let glow = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
            glow.lineWidth = 2; glow.stroke()
        }

        let travel = w - h
        let tx = 2 + thumb * travel
        let th = h - 4
        let thumbRect = NSRect(x: tx, y: 2, width: th, height: th)
        let thumbPath = NSBezierPath(ovalIn: thumbRect)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 4; shadow.set()
        NSGradient(colors: [NSColor(calibratedWhite: 0.96, alpha: 1),
                             NSColor(calibratedWhite: 0.78, alpha: 1)])!.draw(in: thumbPath, angle: 270)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        thumbPath.addClip()
        NSGradient(colors: [NSColor(white: 1, alpha: 0.85), NSColor.clear])!
            .draw(from: NSPoint(x: thumbRect.midX, y: thumbRect.maxY),
                  to: NSPoint(x: thumbRect.midX, y: thumbRect.midY), options: [])
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseUp(with event: NSEvent) { isOn = !isOn }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

// MARK: - Color / Style helpers

enum K2LColors {
    // MPC Red — #c8262a
    static let accentDark  = NSColor(red: 0.784, green: 0.149, blue: 0.165, alpha: 1)
    static let accentLight = NSColor(red: 0.784, green: 0.149, blue: 0.165, alpha: 1)

    static func accent(dark: Bool) -> NSColor { accentDark }
    static var accent: NSColor { accentDark }

    // #14161a
    static let darkBg       = NSColor(red: 0.078, green: 0.086, blue: 0.102, alpha: 1)
    // #0f0a1f → #1a1030 (deep indigo hero gradient)
    static let heroBg       = NSColor(red: 0.059, green: 0.039, blue: 0.122, alpha: 1)
    static let heroBg2      = NSColor(red: 0.102, green: 0.063, blue: 0.188, alpha: 1)
    // #22c55e
    static let successGreen = NSColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1)
    // #ef4444
    static let errorRed     = NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1)
}

// MARK: - MPC 4×4 Pad Grid

private class MPCPadGridView: NSView {

    var accentColor: NSColor = K2LColors.accent { didSet { needsDisplay = true } }

    // Pads 5 and 10 are lit (row-major, 0-based) matching the design
    private let litPads: Set<Int> = [5, 10]

    // Deterministic pseudo-random (mirrors design's Math.sin approach)
    private func rand(_ i: Int, salt: Double = 1.0) -> CGFloat {
        let x = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
        return CGFloat(x - floor(x))
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let bezelR: CGFloat = 12

        // ── Bezel: classic MPC light grey in light mode, dark metallic in dark mode
        NSGraphicsContext.saveGraphicsState()
        let bezelPath = NSBezierPath(roundedRect: b, xRadius: bezelR, yRadius: bezelR)
        bezelPath.addClip()
        
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            // Dark mode: metallic dark grey gradient (145deg) — #3a3a38 → #1e1e1d
            NSGradient(colors: [NSColor(red: 0.227, green: 0.227, blue: 0.220, alpha: 1),
                                 NSColor(red: 0.118, green: 0.118, blue: 0.114, alpha: 1)])!
                .draw(in: b, angle: 145)
        } else {
            // Light mode: classic MPC light grey — #d9d9d6 → #bdbdba (slightly darker for gradient)
            NSGradient(colors: [NSColor(red: 0.851, green: 0.851, blue: 0.839, alpha: 1),
                                 NSColor(red: 0.741, green: 0.741, blue: 0.729, alpha: 1)])!
                .draw(in: b, angle: 145)
        }
        NSGraphicsContext.restoreGraphicsState()

        // ── Inset top highlight (inner bevel)
        NSGraphicsContext.saveGraphicsState()
        bezelPath.addClip()
        NSColor(white: 1, alpha: 0.08).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: b.maxY - 3, width: b.width, height: 3)).fill()
        NSGraphicsContext.restoreGraphicsState()

        // ── Outer border (dark)
        NSColor(white: 0, alpha: 0.7).setStroke()
        let outerBorder = NSBezierPath(roundedRect: b.insetBy(dx: 1, dy: 1),
                                        xRadius: bezelR - 1, yRadius: bezelR - 1)
        outerBorder.lineWidth = 2; outerBorder.stroke()

        // ── Bezel scuff overlays (subtle)
        NSGraphicsContext.saveGraphicsState()
        bezelPath.addClip()
        
        // Top-left scuff
        let scuff1X = b.width * 0.18, scuff1Y = b.maxY - b.height * 0.22
        NSGradient(colors: [NSColor(white: 1, alpha: 0.04), NSColor.clear])!
            .draw(fromCenter: NSPoint(x: scuff1X, y: scuff1Y), radius: 0,
                  toCenter: NSPoint(x: scuff1X, y: scuff1Y), radius: b.width * 0.18, options: [])
        
        // Bottom-right scuff
        let scuff2X = b.width * 0.82, scuff2Y = b.height * 0.22
        NSGradient(colors: [NSColor(white: 1, alpha: 0.03), NSColor.clear])!
            .draw(fromCenter: NSPoint(x: scuff2X, y: scuff2Y), radius: 0,
                  toCenter: NSPoint(x: scuff2X, y: scuff2Y), radius: b.width * 0.22, options: [])
        
        // Top-right dark scuff
        let scuff3X = b.width * 0.70, scuff3Y = b.maxY - b.height * 0.15
        NSGradient(colors: [NSColor(white: 0, alpha: 0.35), NSColor.clear])!
            .draw(fromCenter: NSPoint(x: scuff3X, y: scuff3Y), radius: 0,
                  toCenter: NSPoint(x: scuff3X, y: scuff3Y), radius: b.width * 0.08, options: [])
        
        NSGraphicsContext.restoreGraphicsState()

        // ── Pads grid  (proportional to view size — reference design: 16px gap / 95px pad)
        let padding: CGFloat = 9, gap: CGFloat = 5
        let padW = (b.width  - padding * 2 - gap * 3) / 4
        let padH = (b.height - padding * 2 - gap * 3) / 4
        let padR      = max(2.5, padW * 0.13)   // ~6% corner radius like design
        let ledMargin = max(2,   padW * 0.11)   // ~10.5% of padW like design

        for i in 0..<16 {
            let col        = i % 4
            let rowFromTop = i / 4
            let rowFromBot = 3 - rowFromTop   // NSView y=0 is bottom

            let padX    = padding + CGFloat(col)        * (padW + gap)
            let padY    = padding + CGFloat(rowFromBot) * (padH + gap)
            let padRect = NSRect(x: padX, y: padY, width: padW, height: padH)
            let padPath = NSBezierPath(roundedRect: padRect, xRadius: padR, yRadius: padR)
            let isLit   = litPads.contains(i)

            // ── Drop shadow beneath pad
            NSGraphicsContext.saveGraphicsState()
            let dropShadow = NSShadow()
            dropShadow.shadowColor      = NSColor(white: 0, alpha: 0.4)
            dropShadow.shadowBlurRadius = 2
            dropShadow.shadowOffset     = NSSize(width: 0, height: -2)
            dropShadow.set()
            NSColor(white: 0, alpha: 0).setFill()
            padPath.fill()
            NSGraphicsContext.restoreGraphicsState()

            // ── Pad body gradient (145deg)
            NSGraphicsContext.saveGraphicsState()
            padPath.addClip()
            if isLit {
                // Lit: #ff6b6f → #c8262a
                NSGradient(colors: [NSColor(red: 1.0, green: 0.420, blue: 0.435, alpha: 1),
                                     NSColor(red: 0.784, green: 0.149, blue: 0.165, alpha: 1)])!
                    .draw(in: padRect, angle: 145)
            } else {
                // Unlit: #bebebb → #888884
                NSGradient(colors: [NSColor(red: 0.745, green: 0.745, blue: 0.733, alpha: 1),
                                     NSColor(red: 0.533, green: 0.533, blue: 0.518, alpha: 1)])!
                    .draw(in: padRect, angle: 145)
            }

            // ── Grain highlight (top-left radial)
            let grainX = padRect.minX + padW * 0.30
            let grainY = padRect.minY + padH * 0.70  // 30% from top in flipped coords
            let grainR = min(padW, padH) * 0.55
            NSGradient(colors: [NSColor(white: 1, alpha: isLit ? 0.40 : 0.30), NSColor.clear])!
                .draw(fromCenter: NSPoint(x: grainX, y: grainY), radius: 0,
                      toCenter: NSPoint(x: grainX, y: grainY), radius: grainR, options: [])

            // ── Speckle texture (multiple tiny radial gradients)
            let speckles: [(CGFloat, CGFloat, CGFloat)] = [
                (0.20, 0.40, 0.15), (0.70, 0.30, 0.12), (0.40, 0.75, 0.15),
                (0.85, 0.85, 0.13), (0.60, 0.50, 0.10)
            ]
            for (sx, sy, op) in speckles {
                let spX = padRect.minX + padW * sx
                let spY = padRect.minY + padH * (1.0 - sy)  // flip Y
                NSGradient(colors: [NSColor(white: 0, alpha: isLit ? op * 0.15 : op * 0.35), NSColor.clear])!
                    .draw(fromCenter: NSPoint(x: spX, y: spY), radius: 0,
                          toCenter: NSPoint(x: spX, y: spY), radius: max(1.5, padW * 0.055), options: [])
            }

            // ── Scuffs (2-3 per pad)
            let numScuffs = 2 + Int(rand(i, salt: 1) * 2)
            for s in 0..<numScuffs {
                let scuffW: CGFloat = s == 0 ? padW * 0.16 : padW * 0.09  // proportional to pad size
                let scuffH: CGFloat = s == 0 ? max(1, padH * 0.04) : 1
                let scuffX = padRect.minX + padW * (0.10 + rand(i, salt: Double(s + 2)) * 0.70)
                let scuffY = padRect.minY + padH * (0.10 + rand(i, salt: Double(s + 5)) * 0.70)
                let scuffAngle = rand(i, salt: Double(s + 8)) * 180
                let scuffOp = 0.3 + rand(i, salt: Double(s + 11)) * 0.5
                
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: scuffX, yBy: scuffY)
                transform.rotate(byDegrees: scuffAngle)
                transform.concat()
                
                let scuffColor = isLit ? NSColor(white: 1, alpha: 0.18 * scuffOp)
                                       : NSColor(white: 0, alpha: 0.20 * scuffOp)
                scuffColor.setFill()
                NSBezierPath(rect: NSRect(x: -scuffW/2, y: -scuffH/2, width: scuffW, height: scuffH)).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            NSGraphicsContext.restoreGraphicsState()

            // ── Inset top highlight
            NSGraphicsContext.saveGraphicsState()
            padPath.addClip()
            NSColor(white: 1, alpha: isLit ? 0.50 : 0.35).setFill()
            NSBezierPath(rect: NSRect(x: padRect.minX, y: padRect.maxY - 2,
                                       width: padW, height: 2)).fill()
            NSGraphicsContext.restoreGraphicsState()

            // ── Inset bottom shadow
            NSGraphicsContext.saveGraphicsState()
            padPath.addClip()
            NSColor(white: 0, alpha: isLit ? 0.45 : 0.35).setFill()
            NSBezierPath(rect: NSRect(x: padRect.minX, y: padRect.minY,
                                       width: padW, height: 4)).fill()
            NSGraphicsContext.restoreGraphicsState()

            // ── LED indicator — bottom-right (proportional ~5% of pad width)
            let ledS    = max(2.5, padW * 0.095)
            let ledRect = NSRect(x: padRect.maxX - ledMargin - ledS,
                                  y: padRect.minY + ledMargin,
                                  width: ledS, height: ledS)
            NSGraphicsContext.saveGraphicsState()
            if isLit {
                let ledGlow = NSShadow()
                ledGlow.shadowColor      = NSColor.white
                ledGlow.shadowBlurRadius = 8
                ledGlow.shadowOffset     = .zero
                ledGlow.set()
                NSColor.white.setFill()
                NSBezierPath(ovalIn: ledRect).fill()
                
                // Additional pink glow
                let pinkGlow = NSShadow()
                pinkGlow.shadowColor      = NSColor(red: 1, green: 0.66, blue: 0.66, alpha: 1)
                pinkGlow.shadowBlurRadius = 14
                pinkGlow.shadowOffset     = .zero
                pinkGlow.set()
                NSBezierPath(ovalIn: ledRect).fill()
            } else {
                // Unlit LED — dark with inset look
                NSColor(white: 0, alpha: 0.35).setFill()
                NSBezierPath(ovalIn: ledRect).fill()
                
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(ovalIn: ledRect).addClip()
                NSColor(white: 0, alpha: 0.5).setFill()
                NSBezierPath(rect: NSRect(x: ledRect.minX, y: ledRect.minY,
                                           width: ledS, height: 1)).fill()
                NSColor(white: 1, alpha: 0.2).setFill()
                NSBezierPath(rect: NSRect(x: ledRect.minX, y: ledRect.maxY - 1,
                                           width: ledS, height: 1)).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            NSGraphicsContext.restoreGraphicsState()

            // ── Outer glow for lit pads
            if isLit {
                NSGraphicsContext.saveGraphicsState()
                let halo = NSShadow()
                halo.shadowColor      = accentColor.withAlphaComponent(0.80)
                halo.shadowBlurRadius = 12
                halo.shadowOffset     = .zero
                halo.set()
                NSColor.clear.setStroke()
                let haloPath = NSBezierPath(roundedRect: padRect.insetBy(dx: 2, dy: 2),
                                             xRadius: padR - 2, yRadius: padR - 2)
                haloPath.lineWidth = 0.5
                haloPath.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}

// MARK: - FlippedGroupView

private class FlippedGroupView: NSView { override var isFlipped: Bool { true } }

// MARK: - DropZoneView

class DropZoneView: NSView {

    // MARK: Public
    var isDark: Bool = true { didSet { styleForTheme(); applyGroupVisibility(); setBorderForState() } }
    weak var controller: DropViewController?

    // MARK: Private state
    private var dropState: DropZoneState = .idle

    // MARK: Border
    private let borderLayer = CAShapeLayer()

    // MARK: Idle group
    private let idleGroup = FlippedGroupView()
    private let padGrid   = MPCPadGridView()
    private let idleTitle = NSTextField(labelWithString: "")
    private let idleSub   = NSTextField(labelWithString: "")
    private let browsBtn  = NSButton(title: "", target: nil, action: nil)

    // MARK: Converting group
    private let convGroup    = FlippedGroupView()
    private let convCaption  = NSTextField(labelWithString: "")
    private let convFnLabel  = NSTextField(labelWithString: "")
    private let progPctLabel = NSTextField(labelWithString: "")
    private let progressBg   = NSView()
    private let progressFill = NSView()
    private let logScroll    = NSScrollView()
    private let logText      = NSTextView(frame: .zero)

    // MARK: Done group
    private let doneGroup  = FlippedGroupView()
    private let doneIcon   = NSView()
    private let doneTitle  = NSTextField(labelWithString: "")
    private let doneSub    = NSTextField(labelWithString: "")
    private let revealBtn  = NSButton(title: "", target: nil, action: nil)
    private let anotherBtn = NSButton(title: "", target: nil, action: nil)
    private var savedOutputURL: URL?

    // MARK: Error group
    private let errGroup  = FlippedGroupView()
    private let errIcon   = NSView()
    private let errTitle  = NSTextField(labelWithString: "")
    private let errDesc   = NSTextField(labelWithString: "")
    private let retryBtn  = NSButton(title: "", target: nil, action: nil)

    // MARK: Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineWidth = 1.5
        borderLayer.lineDashPattern = [7, 4]
        layer?.addSublayer(borderLayer)

        buildIdleGroup()
        buildConvertingGroup()
        buildDoneGroup()
        buildErrorGroup()

        [idleGroup, convGroup, doneGroup, errGroup].forEach { addSubview($0) }
        registerForDraggedTypes([.fileURL])
        styleForTheme()
        applyGroupVisibility()
        setBorderForState()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: Public entry points

    func startConverting(filename: String) {
        convFnLabel.stringValue = filename
        logText.string = ""
        setProgress(0)
        setState(.converting)
    }

    func setProgress(_ p: CGFloat) {
        let clamped = max(0, min(100, p))
        progPctLabel.stringValue = "\(Int(clamped))%"
        if progressBg.bounds.width > 0 {
            let fillW = progressBg.bounds.width * clamped / 100
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12; ctx.allowsImplicitAnimation = false
                progressFill.frame = NSRect(x: 0, y: 0, width: fillW, height: 6)
            }
        }
    }

    func appendLogLine(_ line: String) {
        guard !line.isEmpty else { return }
        let color = isDark ? NSColor(white: 1, alpha: 0.6) : NSColor(white: 0, alpha: 0.55)
        let attr = NSAttributedString(string: "› \(line)\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: color
        ])
        logText.textStorage?.append(attr)
        logText.scrollToEndOfDocument(nil)
    }

    func showDone(filename: String, outputURL: URL?) {
        doneSub.stringValue = filename.replacingOccurrences(of: ".xpj", with: ".als",
                                                            options: .caseInsensitive)
        savedOutputURL = outputURL
        setState(.done)
    }

    func showError(_ message: String) {
        errDesc.stringValue = message.isEmpty
            ? "Expected a .xpj file from an Akai MPC Sample." : message
        setState(.error)
    }

    func resetState() {
        logText.string = ""
        setProgress(0)
        setState(.idle)
    }

    // MARK: Build subgroups

    private func buildIdleGroup() {
        idleGroup.wantsLayer = true

        padGrid.wantsLayer = false   // draws entirely in draw(_:)

        for lbl in [idleTitle, idleSub] {
            lbl.isBezeled = false; lbl.isEditable = false; lbl.drawsBackground = false
            lbl.alignment = .center
        }
        idleTitle.font = .boldSystemFont(ofSize: 16)
        idleTitle.stringValue = "Drag your MPC Sample project here"
        idleSub.font = .systemFont(ofSize: 12)
        idleSub.stringValue = ".xpj  ·"
        idleSub.alignment = .right

        browsBtn.isBordered = false
        browsBtn.target = self; browsBtn.action = #selector(doBrowse)

        [padGrid, idleTitle, idleSub, browsBtn].forEach { idleGroup.addSubview($0) }
    }

    private func buildConvertingGroup() {
        convGroup.wantsLayer = true
        for lbl in [convCaption, convFnLabel, progPctLabel] {
            lbl.isBezeled = false; lbl.isEditable = false; lbl.drawsBackground = false
        }
        convCaption.font = .monospacedSystemFont(ofSize: 9.5, weight: .semibold)
        convCaption.stringValue = "CONVERTING"
        convFnLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        progPctLabel.font = .monospacedSystemFont(ofSize: 28, weight: .semibold)
        progPctLabel.alignment = .right
        progPctLabel.stringValue = "0%"

        progressBg.wantsLayer = true; progressBg.layer?.cornerRadius = 3
        progressFill.wantsLayer = true; progressFill.layer?.cornerRadius = 3
        progressBg.addSubview(progressFill)

        logScroll.hasVerticalScroller = true
        logScroll.borderType = .noBorder
        logScroll.wantsLayer = true
        logScroll.layer?.cornerRadius = 8
        logScroll.layer?.masksToBounds = true
        logScroll.scrollerStyle = .overlay
        logText.isEditable = false; logText.isSelectable = false
        logText.backgroundColor = .clear
        logText.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logText.textContainerInset = NSSize(width: 10, height: 8)
        logScroll.documentView = logText

        [convCaption, convFnLabel, progPctLabel, progressBg, logScroll].forEach { convGroup.addSubview($0) }
    }

    private func buildDoneGroup() {
        doneIcon.wantsLayer = true
        doneGroup.addSubview(doneIcon)

        for lbl in [doneTitle, doneSub] {
            lbl.isBezeled = false; lbl.isEditable = false; lbl.drawsBackground = false; lbl.alignment = .center
        }
        doneTitle.font = .boldSystemFont(ofSize: 15)
        doneTitle.stringValue = "Conversion complete"
        doneSub.font = .systemFont(ofSize: 12)

        revealBtn.isBordered = false; revealBtn.wantsLayer = true; revealBtn.layer?.cornerRadius = 8
        anotherBtn.isBordered = false; anotherBtn.wantsLayer = true; anotherBtn.layer?.cornerRadius = 8
        revealBtn.target = self;  revealBtn.action  = #selector(doReveal)
        anotherBtn.target = self; anotherBtn.action = #selector(doAnother)

        [doneTitle, doneSub, revealBtn, anotherBtn].forEach { doneGroup.addSubview($0) }
    }

    private func buildErrorGroup() {
        errIcon.wantsLayer = true
        errGroup.addSubview(errIcon)

        for lbl in [errTitle, errDesc] {
            lbl.isBezeled = false; lbl.isEditable = false; lbl.drawsBackground = false; lbl.alignment = .center
        }
        errTitle.font = .boldSystemFont(ofSize: 15)
        errTitle.stringValue = "Conversion failed"
        errDesc.font = .systemFont(ofSize: 12)
        errDesc.cell?.wraps = true; errDesc.cell?.isScrollable = false

        retryBtn.isBordered = false; retryBtn.wantsLayer = true; retryBtn.layer?.cornerRadius = 8
        retryBtn.target = self; retryBtn.action = #selector(doAnother)

        [errTitle, errDesc, retryBtn].forEach { errGroup.addSubview($0) }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let b = bounds
        borderLayer.path  = NSBezierPath(roundedRect: b.insetBy(dx: 0.75, dy: 0.75),
                                          xRadius: 13.25, yRadius: 13.25).cgPath
        borderLayer.frame = b
        for g in [idleGroup, convGroup, doneGroup, errGroup] { g.frame = b }
        layoutIdleGroup()
        layoutConvertingGroup()
        layoutDoneGroup()
        layoutErrorGroup()
    }

    private func layoutIdleGroup() {
        let w = idleGroup.bounds.width, h = idleGroup.bounds.height
        let gridS: CGFloat = 148
        let contentH: CGFloat = gridS + 14 + 22 + 8 + 18   // grid + gap + title + gap + sub-row
        let startY = max(16, (h - contentH) / 2)             // top of content block (flipped: y from top)

        padGrid.frame   = NSRect(x: (w - gridS) / 2, y: startY, width: gridS, height: gridS)
        idleTitle.frame = NSRect(x: 20, y: padGrid.frame.maxY + 14, width: w - 40, height: 22)
        let subY = idleTitle.frame.maxY + 8
        let subW: CGFloat = 65, btnW: CGFloat = 80
        let rowX = (w - subW - btnW) / 2
        idleSub.frame  = NSRect(x: rowX,          y: subY, width: subW, height: 18)
        browsBtn.frame = NSRect(x: rowX + subW,   y: subY, width: btnW, height: 18)
    }

    private func layoutConvertingGroup() {
        let w = convGroup.bounds.width
        let px: CGFloat = 24, iw = w - px * 2, topY: CGFloat = 28
        convCaption.frame  = NSRect(x: px, y: topY,      width: iw * 0.65, height: 14)
        convFnLabel.frame  = NSRect(x: px, y: topY + 16, width: iw * 0.65, height: 20)
        progPctLabel.frame = NSRect(x: px + iw * 0.6 - 10, y: topY, width: iw * 0.4 + 10, height: 40)
        let barY = topY + 48
        progressBg.frame   = NSRect(x: px, y: barY, width: iw, height: 6)
        progressFill.frame = NSRect(x: 0, y: 0, width: 0, height: 6)
        let logY = barY + 18
        let logH = max(80, convGroup.bounds.height - logY - 20)
        logScroll.frame = NSRect(x: px, y: logY, width: iw, height: logH)
        logText.frame   = NSRect(x: 0, y: 0, width: iw, height: max(logH, 200))
    }

    private func layoutDoneGroup() {
        let w = doneGroup.bounds.width, h = doneGroup.bounds.height
        let midY = h / 2 - 52
        let iconS: CGFloat = 44
        doneIcon.frame  = NSRect(x: (w - iconS)/2, y: midY, width: iconS, height: iconS)
        doneIcon.layer?.cornerRadius = iconS / 2
        doneTitle.frame = NSRect(x: 20, y: doneIcon.frame.maxY + 14, width: w-40, height: 22)
        doneSub.frame   = NSRect(x: 20, y: doneTitle.frame.maxY + 6,  width: w-40, height: 18)
        let btnW: CGFloat = 150, btnH: CGFloat = 32, gap: CGFloat = 10
        let bx = (w - btnW * 2 - gap) / 2
        let by = doneSub.frame.maxY + 16
        revealBtn.frame  = NSRect(x: bx,           y: by, width: btnW, height: btnH)
        anotherBtn.frame = NSRect(x: bx + btnW + gap, y: by, width: btnW, height: btnH)
    }

    private func layoutErrorGroup() {
        let w = errGroup.bounds.width, h = errGroup.bounds.height
        let midY = h / 2 - 52
        let iconS: CGFloat = 44
        errIcon.frame  = NSRect(x: (w - iconS)/2, y: midY, width: iconS, height: iconS)
        errIcon.layer?.cornerRadius = iconS / 2
        errTitle.frame = NSRect(x: 20, y: errIcon.frame.maxY + 14, width: w-40, height: 22)
        errDesc.frame  = NSRect(x: 20, y: errTitle.frame.maxY + 8,  width: w-40, height: 40)
        retryBtn.frame = NSRect(x: (w-130)/2, y: errDesc.frame.maxY + 16, width: 130, height: 32)
    }

    // MARK: Theme

    private func styleForTheme() {
        let dark = isDark
        let acc  = K2LColors.accent(dark: dark)
        let textC = dark ? NSColor.white            : NSColor(white: 0.08, alpha: 1)
        let subC  = dark ? NSColor(white:1,alpha:0.55) : NSColor(white:0,alpha:0.5)
        let captC = dark ? NSColor(white:1,alpha:0.35) : NSColor(white:0,alpha:0.4)
        let monoC = dark ? NSColor(white:1,alpha:0.85) : NSColor(white:0.1,alpha:1)

        padGrid.accentColor = acc
        idleTitle.textColor = textC

        // ".xpj" in accent mono color
        let monoFont  = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let monoAttrs: [NSAttributedString.Key: Any] = [.font: monoFont, .foregroundColor: acc]
        let subAttrs:  [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12),
                                                          .foregroundColor: subC]
        let subStr = NSMutableAttributedString(string: ".xpj  ", attributes: monoAttrs)
        subStr.append(NSAttributedString(string: "·", attributes: subAttrs))
        idleSub.attributedStringValue = subStr

        browsBtn.attributedTitle = NSAttributedString(string: "browse files", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: acc,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])

        convCaption.textColor  = captC
        convFnLabel.textColor  = monoC
        progPctLabel.textColor = acc
        progressBg.layer?.backgroundColor = (dark ? NSColor(white:1,alpha:0.06) : NSColor(white:0,alpha:0.07)).cgColor
        progressFill.layer?.backgroundColor = acc.cgColor
        logScroll.layer?.backgroundColor = (dark ? NSColor(white:0,alpha:0.3) : NSColor(white:1,alpha:0.8)).cgColor
        logText.textColor = subC

        doneIcon.layer?.backgroundColor = K2LColors.successGreen.withAlphaComponent(0.15).cgColor
        doneIcon.layer?.borderColor = K2LColors.successGreen.withAlphaComponent(0.4).cgColor
        doneIcon.layer?.borderWidth = 1
        doneTitle.textColor = textC; doneSub.textColor = subC
        stylePrimaryBtn(revealBtn, "Reveal in Finder")
        styleSecondaryBtn(anotherBtn, "Convert another")

        errIcon.layer?.backgroundColor = K2LColors.errorRed.withAlphaComponent(0.15).cgColor
        errIcon.layer?.borderColor = K2LColors.errorRed.withAlphaComponent(0.4).cgColor
        errIcon.layer?.borderWidth = 1
        errTitle.textColor = textC; errDesc.textColor = subC
        styleSecondaryBtn(retryBtn, "Try again")
    }

    private func stylePrimaryBtn(_ b: NSButton, _ title: String) {
        let acc = K2LColors.accent(dark: isDark)
        b.layer?.backgroundColor = acc.cgColor; b.layer?.borderWidth = 0
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white])
    }

    private func styleSecondaryBtn(_ b: NSButton, _ title: String) {
        b.layer?.backgroundColor = (isDark ? NSColor(white:1,alpha:0.06) : NSColor(white:0,alpha:0.04)).cgColor
        b.layer?.borderColor     = (isDark ? NSColor(white:1,alpha:0.10) : NSColor(white:0,alpha:0.10)).cgColor
        b.layer?.borderWidth = 1
        let fg: NSColor = isDark ? NSColor(white:1,alpha:0.85) : NSColor(white:0,alpha:0.82)
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: fg])
    }

    // MARK: State management

    private func setState(_ s: DropZoneState) {
        dropState = s
        applyGroupVisibility()
        setBorderForState()
        if s == .idle { idleTitle.stringValue = "Drag your MPC Sample project here" }
    }

    private func applyGroupVisibility() {
        idleGroup.isHidden = !(dropState == .idle || dropState == .dragging)
        convGroup.isHidden = dropState != .converting
        doneGroup.isHidden = dropState != .done
        errGroup.isHidden  = dropState != .error
        if dropState == .dragging { idleTitle.stringValue = "Drop to convert" }
    }

    private func setBorderForState() {
        let dark = isDark
        let acc = K2LColors.accent(dark: dark)
        switch dropState {
        case .idle:
            borderLayer.strokeColor = (dark ? NSColor(white:1,alpha:0.12) : NSColor(white:0,alpha:0.14)).cgColor
            layer?.backgroundColor  = (dark ? NSColor(white:1,alpha:0.02) : NSColor(white:0.98,alpha:1)).cgColor
        case .dragging:
            borderLayer.strokeColor = acc.cgColor
            layer?.backgroundColor  = acc.withAlphaComponent(0.07).cgColor
        case .converting:
            borderLayer.strokeColor = (dark ? NSColor(white:1,alpha:0.08) : NSColor(white:0,alpha:0.10)).cgColor
            layer?.backgroundColor  = (dark ? NSColor(white:1,alpha:0.02) : NSColor(white:0.99,alpha:1)).cgColor
        case .done:
            borderLayer.strokeColor = K2LColors.successGreen.withAlphaComponent(0.5).cgColor
            layer?.backgroundColor  = K2LColors.successGreen.withAlphaComponent(0.05).cgColor
        case .error:
            borderLayer.strokeColor = K2LColors.errorRed.withAlphaComponent(0.5).cgColor
            layer?.backgroundColor  = K2LColors.errorRed.withAlphaComponent(0.05).cgColor
        }
    }

    // MARK: Drag & Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropState = .dragging; applyGroupVisibility(); setBorderForState(); return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        if dropState == .dragging { setState(.idle) }
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url  = urls.first else { return false }
        setState(.idle)
        controller?.processFile(url.path)
        return true
    }

    // MARK: Mouse

    override func mouseUp(with event: NSEvent) {
        if dropState == .idle { controller?.browseForFile() }
    }
    override func mouseEntered(with event: NSEvent) {
        if dropState == .idle {
            borderLayer.strokeColor = (isDark
                ? NSColor(white:1,alpha:0.35) : NSColor(white:0,alpha:0.25)).cgColor
        }
    }
    override func mouseExited(with event: NSEvent) {
        if dropState == .idle { setBorderForState() }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    // MARK: Button actions

    @objc private func doBrowse() { controller?.browseForFile() }
    @objc private func doReveal() {
        if let url = savedOutputURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    @objc private func doAnother() { controller?.resetToIdle() }
}

// MARK: - NSBezierPath → CGPath

extension NSBezierPath {
    var cgPath: CGPath {
        let p = CGMutablePath()
        var pts = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &pts) {
            case .moveTo:    p.move(to: pts[0])
            case .lineTo:    p.addLine(to: pts[0])
            case .curveTo:   p.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .closePath: p.closeSubpath()
            default:         break
            }
        }
        return p
    }
}
