import Foundation
import Cocoa

// ── Update Checker ────────────────────────────────────────────────────────────
// Polls a remote version file and notifies if update available
enum UpdateChecker {

    // GitHub URLs — update these when the repo is public
    private static let versionURL  = "https://raw.githubusercontent.com/Duffman007/MPC2Live/refs/heads/main/version.txt"
    private static let downloadURL = "https://github.com/Duffman007/MPC2Live/releases/latest"

    /// Check for updates and show alert if newer version available
    static func checkForUpdates(showNoUpdateAlert: Bool = false) {
        guard let url = URL(string: versionURL) else { return }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  error == nil,
                  let remoteVersion = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) else {
                if showNoUpdateAlert {
                    DispatchQueue.main.async {
                        showAlert(title: "Update Check Failed",
                                  message: "Could not reach update server.")
                    }
                }
                return
            }

            let currentVersion = Util.appVersion()

            DispatchQueue.main.async {
                if isNewerVersion(remote: remoteVersion, current: currentVersion) {
                    showUpdateAvailable(newVersion: remoteVersion)
                } else if showNoUpdateAlert {
                    showAlert(title: "No Updates Available",
                              message: "You're running the latest version \(currentVersion).")
                }
            }
        }
        task.resume()
    }

    /// Check for updates silently on launch (only shows alert if update found)
    static func checkOnLaunch() {
        checkForUpdates(showNoUpdateAlert: false)
    }

    // MARK: - Helpers

    private static func isNewerVersion(remote: String, current: String) -> Bool {
        let clean: (String) -> String = {
            $0.replacingOccurrences(of: "Beta ", with: "", options: .caseInsensitive)
              .replacingOccurrences(of: "beta ", with: "", options: .caseInsensitive)
              .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let r = clean(remote), c = clean(current)
        if r == c { return false }
        return r.compare(c, options: .numeric) == .orderedDescending
    }

    private static func showUpdateAvailable(newVersion: String) {
        let alert = NSAlert()
        alert.messageText     = "Update Available"
        alert.informativeText = "Version \(newVersion) is now available.\n\nWould you like to download it?"
        alert.alertStyle      = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: downloadURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText     = title
        alert.informativeText = message
        alert.alertStyle      = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
