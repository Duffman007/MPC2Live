import Cocoa

// Manual entry point - bypasses @main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
