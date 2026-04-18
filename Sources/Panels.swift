import Cocoa
import ObjectiveC  // For objc_setAssociatedObject

// ── Auxiliary Panels ──────────────────────────────────────────────────────────
// Changelog, Known Bugs, Feedback, Donation
enum Panels {

    // MARK: - Scrolling text panel (Changelog / Known Bugs / Help)

    static func showScrollingText(title: String, resource: String) {
        let text = Util.readResource("\(resource).txt")

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask:   [.titled, .closable, .resizable],
            backing:     .buffered,
            defer:       false)
        panel.title = title
        panel.center()

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask    = [.width, .height]

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 580, height: 480))
        textView.string             = text.isEmpty ? "(Nothing here yet)" : text
        textView.isEditable         = false
        textView.isSelectable       = true
        textView.font               = .systemFont(ofSize: 12, weight: .regular)
        textView.textColor          = .labelColor
        textView.backgroundColor    = .textBackgroundColor
        textView.autoresizingMask   = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        panel.contentView       = scrollView
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Feedback window

    static func showFeedback() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 390),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false)
        panel.title = "Send Feedback"
        panel.center()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 390))

        let emailLabel   = label("Your Email:", frame: NSRect(x: 20, y: 330, width: 80, height: 20))
        let emailField   = NSTextField(frame: NSRect(x: 100, y: 328, width: 360, height: 24))
        emailField.placeholderString = "Optional - only if you want a response"

        let subjectLabel = label("Subject:", frame: NSRect(x: 20, y: 290, width: 80, height: 20))
        let subjectField = NSTextField(frame: NSRect(x: 100, y: 288, width: 360, height: 24))
        subjectField.placeholderString = "e.g. Bug report / Feature request"

        let bodyLabel  = label("Message:", frame: NSRect(x: 20, y: 260, width: 80, height: 20))
        let scrollView = NSScrollView(frame: NSRect(x: 100, y: 60, width: 360, height: 200))
        scrollView.hasVerticalScroller = true
        scrollView.borderType          = .bezelBorder
        let bodyView = NSTextView(frame: scrollView.bounds)
        bodyView.isEditable = true; bodyView.isRichText = false
        bodyView.font = .systemFont(ofSize: 13)
        bodyView.textContainerInset = NSSize(width: 6, height: 6)
        scrollView.documentView = bodyView

        let sendButton = NSButton(frame: NSRect(x: 380, y: 14, width: 80, height: 32))
        sendButton.title = "Send"; sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"

        let helper = FeedbackHelper(email: emailField, subject: subjectField,
                                    body: bodyView, panel: panel)
        sendButton.target = helper; sendButton.action = #selector(FeedbackHelper.send)
        objc_setAssociatedObject(panel, "feedbackHelper", helper, .OBJC_ASSOCIATION_RETAIN)

        [emailLabel, emailField, subjectLabel, subjectField, bodyLabel, scrollView, sendButton]
            .forEach { container.addSubview($0) }
        panel.contentView = container
        panel.makeKeyAndOrderFront(nil)
        panel.initialFirstResponder = emailField
    }

    // MARK: - Donation link

    static func openDonation() {
        if let url = URL(string: "https://ko-fi.com/duffman007") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helper

    private static func label(_ text: String, frame: NSRect) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.frame = frame; f.font = .systemFont(ofSize: 12); f.textColor = .secondaryLabelColor
        return f
    }
}

// ── Feedback send helper ──────────────────────────────────────────────────────
private class FeedbackHelper: NSObject {
    let emailField: NSTextField
    let subjectField: NSTextField
    let bodyView: NSTextView
    weak var panel: NSPanel?

    init(email: NSTextField, subject: NSTextField, body: NSTextView, panel: NSPanel) {
        self.emailField   = email
        self.subjectField = subject
        self.bodyView     = body
        self.panel        = panel
    }

    @objc func send() {
        let userEmail = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject   = subjectField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let message   = bodyView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !subject.isEmpty else {
            showAlert(title: "Subject Required", message: "Please enter a subject.")
            return
        }
        guard !message.isEmpty else {
            showAlert(title: "Message Required", message: "Please enter a message.")
            return
        }
        sendEmailViaEmailJS(from: userEmail, subject: subject, message: message)
    }

    private func sendEmailViaEmailJS(from email: String, subject: String, message: String) {
        let serviceID  = "service_z5c4357"
        let templateID = "template_iuezwgx"
        let publicKey  = "hrwLg7mIRzW6PGSVK"
        let privateKey = "adw6c7lrwdqZAdV8SEapd"

        let url = URL(string: "https://api.emailjs.com/api/v1.0/email/send")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let templateParams: [String: String] = [
            "from_email": email.isEmpty ? "No reply email provided" : email,
            "name":       email.isEmpty ? "Anonymous User" : email,
            "email":      email.isEmpty ? "noreply@mpc2live.app" : email,
            "subject":    subject,
            "message":    message,
            "reply_to":   email.isEmpty ? "noreply@mpc2live.app" : email
        ]
        let body: [String: Any] = [
            "service_id":    serviceID,
            "template_id":   templateID,
            "user_id":       publicKey,
            "accessToken":   privateKey,
            "template_params": templateParams
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            showAlert(title: "Error", message: "Failed to prepare feedback.")
            return
        }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showAlert(title: "Send Failed",
                                   message: "Could not send feedback: \(error.localizedDescription)")
                    return
                }
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        self?.showAlert(title: "Feedback Sent!", message: "Thank you!")
                        self?.panel?.close()
                    } else {
                        var msg = "Server error \(http.statusCode)."
                        if let d = data, let t = String(data: d, encoding: .utf8) { msg += "\n\n\(t)" }
                        self?.showAlert(title: "Send Failed", message: msg)
                    }
                }
            }
        }.resume()
    }

    private func showAlert(title: String, message: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = message
        a.alertStyle = .informational; a.addButton(withTitle: "OK"); a.runModal()
    }
}
