import Foundation

// ── Conversion Engine ─────────────────────────────────────────────────────────
// Thin facade that drives MPCParser + ALSConverter from the GUI.
enum Converter {

    struct Result {
        let success: Bool
        let projectName: String
        let error: String
    }

    static func run(path: String) -> Result {
        do {
            let inURL  = URL(fileURLWithPath: path)
            // Default output: same folder as .xpj, same stem, .als extension
            let stem   = inURL.deletingPathExtension().lastPathComponent
            let outURL = inURL.deletingLastPathComponent()
                              .appendingPathComponent("\(stem).als")

            let project = try MPCParser.parse(url: inURL)
            try ALSConverter.convert(project: project, inputURL: inURL, outputURL: outURL)
            return Result(success: true, projectName: project.name, error: "")
        } catch {
            return Result(success: false, projectName: "", error: error.localizedDescription)
        }
    }
}
