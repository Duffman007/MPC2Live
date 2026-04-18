import Cocoa

// ── App Delegate ──────────────────────────────────────────────────────────────
// Note: @main removed - using main.swift instead
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: MainWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        window = MainWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Check for updates on launch (silently, only shows alert if update found)
        UpdateChecker.checkOnLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        return true
    }

    // Fix for secure restorable state warning
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func setupMenuBar() {
        let mainMenu = NSMenu()

        // ── App menu ──────────────────────────────────────────────────────────
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        appMenu.addItem(menuItem("About MPC2Live",     action: #selector(showAboutPanel), key: ""))
        appMenu.addItem(menuItem("Check for Updates…", action: #selector(checkUpdates),   key: ""))
        appMenu.addItem(menuItem("View Change Log",    action: #selector(showChangelog),   key: ""))
        appMenu.addItem(menuItem("Known Bugs",         action: #selector(showKnownBugs),   key: ""))
        appMenu.addItem(menuItem("Send Feedback",      action: #selector(showFeedback),    key: ""))
        appMenu.addItem(menuItem("Donate",             action: #selector(openDonation),    key: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit MPC2Live",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))

        // ── File menu ─────────────────────────────────────────────────────────
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(menuItem("Open…", action: #selector(openFile), key: "o"))

        // ── Help menu ─────────────────────────────────────────────────────────
        let helpItem = NSMenuItem()
        mainMenu.addItem(helpItem)
        let helpMenu = NSMenu(title: "Help")
        helpItem.submenu = helpMenu
        helpMenu.addItem(menuItem("MPC2Live Help", action: #selector(showHelp), key: "?"))

        NSApp.mainMenu = mainMenu
    }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc func openFile() {
        (window.contentViewController as? DropViewController)?.browseForFile()
    }

    @objc func showAboutPanel() {
        let version = Util.appVersion()
        let alert = NSAlert()
        alert.messageText     = "MPC2Live"
        alert.informativeText = "Version \(version) beta\n\nConvert Akai MPC projects to Ableton Live Sets.\n\nCreated by Duffman"
        alert.alertStyle      = .informational
        if let icon = NSApp.applicationIconImage { alert.icon = icon }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func showHelp()      { Panels.showScrollingText(title: "MPC2Live Help", resource: "help") }
    @objc func showChangelog() { Panels.showScrollingText(title: "Change Log",    resource: "changelog") }
    @objc func showKnownBugs() { Panels.showScrollingText(title: "Known Bugs",    resource: "known_bugs") }
    @objc func showFeedback()  { Panels.showFeedback() }
    @objc func openDonation()  { Panels.openDonation() }
    @objc func checkUpdates()  { UpdateChecker.checkForUpdates(showNoUpdateAlert: true) }
}
