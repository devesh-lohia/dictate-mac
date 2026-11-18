import AppKit

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    if args.count > 2, args[1] == "--test" { Debug.runTest(path: args[2]) }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate

    if args.count > 1, args[1] == "--demo" {
        Pref.registerDefaults()
        Debug.runDemo(controller: delegate.debugController)
    }
    if args.count > 1, args[1].hasPrefix("--settings") {
        let tabs: [String: SettingsTab] = ["general": .general, "voice": .voice, "filters": .filters, "permissions": .permissions]
        let tab = tabs[args[1].replacingOccurrences(of: "--settings=", with: "")] ?? .general
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { delegate.showSettings(tab: tab) }
    }
    app.run()
}
