import Cocoa
import UniformTypeIdentifiers

// MARK: - HeroView

private class HeroView: NSView {
    var isDark: Bool = true { didSet { needsDisplay = true } }
    var accentColor: NSColor = K2LColors.accent { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).addClip()

        if isDark {
            NSGradient(colors: [K2LColors.heroBg, K2LColors.heroBg2])!
                .draw(in: bounds, angle: 315)

            // Accent radial glow
            NSGradient(colors: [accentColor.withAlphaComponent(0.2), NSColor.clear])!
                .draw(fromCenter: NSPoint(x: w * 0.2, y: h * 0.4), radius: 0,
                      toCenter: NSPoint(x: w * 0.2, y: h * 0.4), radius: w * 0.55, options: [])

            // Purple glow
            NSGradient(colors: [NSColor(red:0.16, green:0.1, blue:0.32, alpha:1), NSColor.clear])!
                .draw(fromCenter: NSPoint(x: w * 0.9, y: h * 0.6), radius: 0,
                      toCenter: NSPoint(x: w * 0.9, y: h * 0.6), radius: w * 0.55, options: [])

            // Grid
            NSColor(white: 1, alpha: 0.04).setStroke()
            let grid = NSBezierPath(); grid.lineWidth = 0.5
            var gx: CGFloat = 0; while gx <= w { grid.move(to: NSPoint(x:gx,y:0)); grid.line(to: NSPoint(x:gx,y:h)); gx += 24 }
            var gy: CGFloat = 0; while gy <= h { grid.move(to: NSPoint(x:0,y:gy)); grid.line(to: NSPoint(x:w,y:gy)); gy += 24 }
            grid.stroke()

            // Horizon line
            let hy = h - 36
            accentColor.withAlphaComponent(0.4).setStroke()
            let hl = NSBezierPath(); hl.move(to: NSPoint(x:0,y:hy)); hl.line(to: NSPoint(x:w,y:hy)); hl.lineWidth = 1; hl.stroke()

            // Neon arcs (centers 30px below bottom in flipped = h+30)
            let arcCX = w / 2, arcCY = h + 30
            for (r, op) in [(CGFloat(100), 0.55), (70, 0.38), (40, 0.25)] as [(CGFloat,Double)] {
                accentColor.withAlphaComponent(CGFloat(op)).setStroke()
                let a = NSBezierPath(ovalIn: NSRect(x:arcCX-r, y:arcCY-r, width:r*2, height:r*2))
                a.lineWidth = 1.2; a.stroke()
            }

        } else {
            NSGradient(colors: [NSColor(white:0.97,alpha:1), NSColor(white:0.95,alpha:1)])!
                .draw(in: bounds, angle: 270)
            NSColor(white:0,alpha:0.06).setStroke()
            let bl = NSBezierPath(); bl.move(to: NSPoint(x:0,y:h)); bl.line(to: NSPoint(x:w,y:h)); bl.lineWidth = 1; bl.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Wordmark (centered)
        let titleFont = NSFont.boldSystemFont(ofSize: 22)
        let iconColor: NSColor = isDark ? .white : NSColor(white:0.1,alpha:1)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont, .foregroundColor: iconColor, .kern: -0.5 as Any
        ]
        let titleNS = NSAttributedString(string: "MPC2Live", attributes: titleAttrs)
        let titleSz = titleNS.size()
        let rowX = (w - titleSz.width) / 2
        let rowY = h / 2 - 20

        titleNS.draw(at: NSPoint(x: rowX, y: rowY))

        // Subtitle
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: accentColor, .kern: 2.5 as Any
        ]
        let subNS = NSAttributedString(string: "AKAI MPC SAMPLE  →  ABLETON LIVE", attributes: subAttrs)
        subNS.draw(at: NSPoint(x: (w - subNS.size().width) / 2, y: rowY + titleSz.height + 8))
    }
}

// MARK: - FooterView

private class FooterView: NSView {
    var isDark: Bool = true { didSet { applyTheme() } }
    var onAction: ((String) -> Void)?

    private let versionLabel = NSTextField(labelWithString: "")
    private let donateBtn    = NSButton(title: "Donate", target: nil, action: nil)
    private var linkBtns: [NSButton] = []
    private var topBorder: CALayer?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        versionLabel.isBezeled = false; versionLabel.isEditable = false; versionLabel.drawsBackground = false
        versionLabel.font = .systemFont(ofSize: 11)
        addSubview(versionLabel)

        donateBtn.isBordered = false; donateBtn.wantsLayer = true; donateBtn.layer?.cornerRadius = 6
        donateBtn.identifier = NSUserInterfaceItemIdentifier("donate")
        donateBtn.target = self; donateBtn.action = #selector(footerAction(_:))
        addSubview(donateBtn)

        for (id, lbl) in [("about","About"),("updates","Updates"),("changelog","Change Log"),("feedback","Feedback")] {
            let b = NSButton(title: lbl, target: self, action: #selector(footerAction(_:)))
            b.isBordered = false; b.wantsLayer = true
            b.identifier = NSUserInterfaceItemIdentifier(id)
            addSubview(b); linkBtns.append(b)
        }

        applyTheme()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func applyTheme() {
        let dark = isDark
        layer?.backgroundColor = (dark ? NSColor(white:0,alpha:0.2) : NSColor(white:0,alpha:0.03)).cgColor

        topBorder?.removeFromSuperlayer()
        let tb = CALayer()
        tb.frame = NSRect(x:0, y:0, width:10000, height:1)
        tb.backgroundColor = (dark ? NSColor(white:1,alpha:0.05) : NSColor(white:0,alpha:0.06)).cgColor
        layer?.addSublayer(tb); topBorder = tb

        let fg: NSColor = dark ? NSColor(white:1,alpha:0.5) : NSColor(white:0,alpha:0.55)
        versionLabel.textColor = dark ? NSColor(white:1,alpha:0.35) : NSColor(white:0,alpha:0.4)
        versionLabel.stringValue = "v\(Util.appVersion()) beta"

        for b in linkBtns {
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: fg])
        }

        let acc = K2LColors.accent(dark: dark)
        donateBtn.layer?.backgroundColor = acc.withAlphaComponent(0.10).cgColor
        donateBtn.layer?.borderColor = acc.withAlphaComponent(0.27).cgColor
        donateBtn.layer?.borderWidth = 1
        donateBtn.attributedTitle = NSAttributedString(string: "Donate", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: acc])
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        var x: CGFloat = 16
        let cy = (h - 18) / 2
        versionLabel.sizeToFit()
        versionLabel.frame = NSRect(x: x, y: cy, width: versionLabel.frame.width + 4, height: 18); x = versionLabel.frame.maxX + 10
        for b in linkBtns {
            b.sizeToFit()
            let bw = max(b.frame.width + 8, 50)
            b.frame = NSRect(x: x, y: cy, width: bw, height: 18); x += bw + 6
        }
        donateBtn.frame = NSRect(x: bounds.width - 74 - 16, y: (h-24)/2, width: 74, height: 24)
    }

    @objc private func footerAction(_ sender: NSButton) {
        onAction?(sender.identifier?.rawValue ?? "")
    }
}

// MARK: - InfoPanelView

private class InfoPanelView: NSView {
    var isDark: Bool = true        { didSet { rebuildTheme() } }
    var accentColor: NSColor = K2LColors.accent { didSet { rebuildTheme() } }
    override var isFlipped: Bool { true }

    private let whatHeader = NSTextField(labelWithString: "WHAT IT DOES")
    private let whatBody   = NSTextField(wrappingLabelWithString: "")
    private let howHeader  = NSTextField(labelWithString: "HOW TO USE")

    private struct StepRow { let dot: NSView; let num: NSTextField; let lbl: NSTextField }
    private let stepData: [(Int, String, String)] = [
        (1, "Export from MPC Sample",   "Save your project on the MPC Sample — the .xpj file will be in your project folder."),
        (2, "Drop it in",        "Drag the .xpj file above — or click browse."),
        (3, "Open in Ableton",   "The .als appears alongside your project — open it to find your tracks and clips."),
    ]
    private var stepRows: [StepRow] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 10; layer?.borderWidth = 1

        for h in [whatHeader, howHeader] {
            h.isBezeled = false; h.isEditable = false; h.drawsBackground = false
            h.font = .systemFont(ofSize: 9.5, weight: .bold)
        }
        whatBody.isBezeled = false; whatBody.isEditable = false; whatBody.isSelectable = false; whatBody.drawsBackground = false
        whatBody.cell?.wraps = true; whatBody.cell?.isScrollable = false

        for (n, _, _) in stepData {
            let dot = NSView(); dot.wantsLayer = true
            let num = NSTextField(labelWithString: "\(n)")
            num.isBezeled = false; num.isEditable = false; num.drawsBackground = false
            num.alignment = .center; num.font = NSFont.boldSystemFont(ofSize: 10)
            dot.addSubview(num)
            let lbl = NSTextField(wrappingLabelWithString: "")
            lbl.isBezeled = false; lbl.isEditable = false; lbl.isSelectable = false; lbl.drawsBackground = false
            lbl.cell?.wraps = true; lbl.cell?.isScrollable = false
            stepRows.append(StepRow(dot: dot, num: num, lbl: lbl))
            addSubview(dot); addSubview(lbl)
        }
        [whatHeader, whatBody, howHeader].forEach { addSubview($0) }
        rebuildTheme()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rebuildTheme() {
        let dark = isDark; let acc = accentColor
        layer?.backgroundColor = (dark ? NSColor(white:1,alpha:0.02) : NSColor.white).cgColor
        layer?.borderColor     = (dark ? NSColor(white:1,alpha:0.06) : NSColor(white:0,alpha:0.08)).cgColor
        let hdrC = dark ? NSColor(white:1,alpha:0.40) : NSColor(white:0,alpha:0.45)
        let txtC = dark ? NSColor(white:1,alpha:0.78) : NSColor(white:0,alpha:0.78)
        let mutC = dark ? NSColor(white:1,alpha:0.52) : NSColor(white:0,alpha:0.55)
        let dotC = dark ? NSColor(white:1,alpha:0.06) : NSColor(white:0,alpha:0.04)
        whatHeader.textColor = hdrC; howHeader.textColor = hdrC

        let bA: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: txtC]
        let mA: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: acc]
        let body = NSMutableAttributedString(string: "Converts a ", attributes: bA)
        body.append(NSAttributedString(string: ".xpj", attributes: mA))
        body.append(NSAttributedString(string: " project into an Ableton Live Set. Drum tracks are mapped to a rack, sequences become clips, and samples are linked so you can keep arranging.", attributes: bA))
        whatBody.attributedStringValue = body

        for (i, (_, title, desc)) in stepData.enumerated() {
            let r = stepRows[i]
            r.dot.layer?.backgroundColor = dotC.cgColor; r.num.textColor = acc
            let s = NSMutableAttributedString(string: title + ". ", attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium), .foregroundColor: txtC])
            s.append(NSAttributedString(string: desc, attributes: [
                .font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: mutC]))
            r.lbl.attributedStringValue = s
        }
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let pad: CGFloat = 14, ipad: CGFloat = 16, colGap: CGFloat = 18
        let colW = (w - ipad * 2 - colGap) / 2
        let lx = ipad, rx = ipad + colW + colGap

        whatHeader.frame = NSRect(x: lx, y: pad,      width: colW, height: 14)
        whatBody.frame   = NSRect(x: lx, y: pad + 22, width: colW, height: bounds.height - pad - 22 - pad)

        howHeader.frame  = NSRect(x: rx, y: pad, width: colW, height: 14)
        let dotS: CGFloat = 16, stepGap: CGFloat = 6
        var sy = pad + 22
        
        // Calculate proper heights for each step based on text content
        let textW = colW - dotS - 8
        for r in stepRows {
            r.dot.frame = NSRect(x: rx, y: sy, width: dotS, height: dotS)
            r.dot.layer?.cornerRadius = dotS / 2
            r.num.frame = NSRect(x: 0, y: (dotS - 14) / 2, width: dotS, height: 14)
            
            // Calculate the actual height needed for the text
            let textHeight = r.lbl.attributedStringValue.boundingRect(
                with: NSSize(width: textW, height: 1000),
                options: [.usesLineFragmentOrigin]
            ).height
            let stepH = max(dotS, ceil(textHeight) + 4)
            
            r.lbl.frame = NSRect(x: rx + dotS + 8, y: sy, width: textW, height: stepH)
            sy += stepH + stepGap
        }
    }
}

// MARK: - DropViewController

class DropViewController: NSViewController {

    // MARK: State
    var isDark: Bool = true { didSet { applyTheme() } }

    // MARK: Subviews
    private let heroView  = HeroView()
    private let dropView  = DropZoneView()
    private let infoPanel = InfoPanelView()
    private let footerView = FooterView()

    // MARK: Conversion
    private var progressTimer: Timer?
    private var autoDismissTimer: Timer?
    private var fakeProgress: CGFloat = 0
    private var convResult: Converter.Result?
    private var convDone = false
    private var currentPath = ""

    private static let logSteps: [(CGFloat, String)] = [
        (0,  "Opening project…"),
        (8,  "Parsing XPJ data"),
        (22, "Analysing drum tracks"),
        (38, "Building drum rack"),
        (54, "Writing MIDI clips"),
        (68, "Generating arrangements"),
        (82, "Embedding samples"),
        (94, "Finalising .als…"),
    ]

    // MARK: loadView

    override func loadView() {
        let v = FlippedView(frame: NSRect(x:0, y:0, width:640, height:680))
        view = v; v.wantsLayer = true

        heroView.isDark = isDark
        v.addSubview(heroView)

        dropView.controller = self; dropView.isDark = isDark
        v.addSubview(dropView)

        infoPanel.isDark = isDark
        v.addSubview(infoPanel)

        footerView.isDark = isDark
        footerView.onAction = { [weak self] id in self?.handleFooterAction(id) }
        v.addSubview(footerView)

        applyTheme()
    }

    override func viewWillLayout() {
        super.viewWillLayout()
        let w = view.bounds.width, h = view.bounds.height
        let side: CGFloat = 20
        let iw = w - side * 2
        let heroH: CGFloat = 120, topPad: CGFloat = 14
        let footH: CGFloat = 40
        let heroGap: CGFloat = 16, dropGap: CGFloat = 12
        let infoPanelH: CGFloat = 190, infoPanelGap: CGFloat = 12

        heroView.frame   = NSRect(x: side, y: topPad,                                           width: iw, height: heroH)
        footerView.frame = NSRect(x: 0,    y: h - footH,                                        width: w,  height: footH)
        infoPanel.frame  = NSRect(x: side, y: h - footH - infoPanelGap - infoPanelH,            width: iw, height: infoPanelH)

        let dropTop    = heroView.frame.maxY + heroGap
        let dropBottom = infoPanel.frame.minY - dropGap
        dropView.frame = NSRect(x: side, y: dropTop, width: iw, height: max(160, dropBottom - dropTop))
    }

    // MARK: Theme

    private func applyTheme() {
        let dark = isDark
        // Light mode: #d9d9d6 classic MPC grey
        let lightBg = NSColor(red: 0.851, green: 0.851, blue: 0.839, alpha: 1)
        view.layer?.backgroundColor = (dark ? K2LColors.darkBg : lightBg).cgColor
        heroView.isDark = dark
        heroView.accentColor = K2LColors.accent(dark: dark)
        dropView.isDark = dark
        infoPanel.isDark = dark
        infoPanel.accentColor = K2LColors.accent(dark: dark)
        footerView.isDark = dark

        if let mainWindow = view.window as? MainWindow {
            mainWindow.setTitleBarAppearance(dark: dark)
        }
    }

    // MARK: Actions

    private func handleFooterAction(_ id: String) {
        guard let del = NSApp.delegate as? AppDelegate else { return }
        switch id {
        case "about":     del.showAboutPanel()
        case "updates":   del.checkUpdates()
        case "changelog": del.showChangelog()
        case "feedback":  del.showFeedback()
        case "donate":    del.openDonation()
        default: break
        }
    }

    // MARK: Public

    func processFile(_ path: String) {
        guard path.hasSuffix(".xpj"), FileManager.default.fileExists(atPath: path) else {
            dropView.showError("Expected a .xpj file from an Akai MPC Sample.")
            return
        }
        currentPath = path
        let fname = URL(fileURLWithPath: path).lastPathComponent
        startConvertingUI(filename: fname)

        DispatchQueue.global(qos: .userInitiated).async {
            let r = Converter.run(path: path)
            DispatchQueue.main.async { self.handleResult(r) }
        }
    }

    func browseForFile() {
        let panel = NSOpenPanel()
        panel.title = "Select MPC Sample Project"
        if #available(macOS 11.0, *) {
            if let t = UTType(filenameExtension: "xpj") { panel.allowedContentTypes = [t] }
        } else { panel.allowedFileTypes = ["xpj"] }
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { processFile(url.path) }
    }

    func resetToIdle() {
        progressTimer?.invalidate(); progressTimer = nil
        autoDismissTimer?.invalidate(); autoDismissTimer = nil
        fakeProgress = 0; convDone = false; convResult = nil
        dropView.resetState()
    }

    // MARK: Converting

    private func startConvertingUI(filename: String) {
        dropView.startConverting(filename: filename)
        fakeProgress = 0; convDone = false; convResult = nil
        var logged = Set<Int>()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.055, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            
            // Stop at 95% and wait for actual conversion to complete
            if self.fakeProgress < 95 {
                self.fakeProgress = min(self.fakeProgress + 1.6, 95)
            }
            
            self.dropView.setProgress(self.fakeProgress)
            for (i, step) in Self.logSteps.enumerated() {
                if self.fakeProgress >= step.0 && !logged.contains(i) {
                    logged.insert(i); self.dropView.appendLogLine(step.1)
                }
            }
            
            // When conversion is done, jump to 100%
            if self.convDone {
                self.fakeProgress = 100
                self.dropView.setProgress(100)
                t.invalidate(); self.progressTimer = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.applyResultIfReady() }
            }
        }
    }

    private func handleResult(_ r: Converter.Result) {
        convResult = r; convDone = true
        // Timer will detect convDone and jump to 100%
    }

    private func applyResultIfReady() {
        guard let r = convResult else { return }
        if r.success {
            let inURL  = URL(fileURLWithPath: currentPath)
            let stem   = inURL.deletingPathExtension().lastPathComponent
            let outALS = inURL.deletingLastPathComponent().appendingPathComponent("\(stem).als")
            let revealURL = FileManager.default.fileExists(atPath: outALS.path) ? outALS : inURL.deletingLastPathComponent()
            dropView.appendLogLine("Done! ✓")
            dropView.showDone(filename: URL(fileURLWithPath: currentPath).lastPathComponent,
                              outputURL: revealURL)
            
            // Auto-dismiss after 3 seconds
            autoDismissTimer?.invalidate()
            autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.resetToIdle()
            }
        } else {
            let e = r.error.count > 140 ? String(r.error.prefix(140)) + "…" : r.error
            dropView.showError(e)
        }
    }
}

// MARK: - FlippedView

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
