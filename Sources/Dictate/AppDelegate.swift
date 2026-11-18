import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = DictationController()
    private let fnKey = FnKeyMonitor()
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private var signalSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        buildMenuBar()

        controller.onListeningChanged = { [weak self] listening in self?.updateIcon(listening: listening) }

        fnKey.onPress = { [weak self] in
            guard let self else { return }
            Pref.holdToTalk ? self.controller.start() : self.controller.toggle()
        }
        fnKey.onRelease = { [weak self] in
            if Pref.holdToTalk { self?.controller.stop() }
        }
        let tapOK = fnKey.start()
        Log.write("launch: microphone=\(Permissions.microphone) accessibility=\(Permissions.accessibility) inputMonitoring=\(Permissions.inputMonitoring) tap=\(tapOK)")

        if !Permissions.allGranted {
            if !Permissions.microphone { Permissions.requestMicrophone() }
            if !Permissions.inputMonitoring { Permissions.requestInputMonitoring() }
            if !Permissions.accessibility { Permissions.requestAccessibility() }
            showSettings(tab: .permissions)
        }

        updateIcon(listening: false, loading: true)
        Task {
            do {
                try await controller.loadModels()
                updateIcon(listening: false)
                Log.write("models ready")
            } catch {
                Log.write("model load failed: \(error)")
                let alert = NSAlert()
                alert.messageText = "Speech model could not be loaded or downloaded"
                alert.informativeText = "\(error)\n\nDictate looks for a Parakeet Ultra CoreML folder at:\n\((Pref.modelDirectory as NSString).abbreviatingWithTildeInPath)\nand downloads the model (about 600 MB) if it is missing, so check your internet connection."
                alert.runModal()
            }
        }

        // Debug aid: `kill -USR1 <pid>` toggles dictation without the Fn key.
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            Log.write("SIGUSR1 toggle")
            Task { @MainActor in self?.controller.toggle() }
        }
        source.resume()
        signalSource = source
    }

    // MARK: - Menu bar

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "Dictate", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        toggleItem = NSMenuItem(title: "Start Dictation", action: #selector(toggleDictation), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Dictate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func updateIcon(listening: Bool, loading: Bool = false) {
        guard let button = statusItem.button else { return }
        let name = loading ? "hourglass" : (listening ? "waveform" : "mic.fill")
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Dictate")
        if listening {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            button.image = image?.withSymbolConfiguration(config)
            button.image?.isTemplate = false
        } else {
            image?.isTemplate = true
            button.image = image
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        toggleItem.title = controller.isListening ? "Stop Dictation" : "Start Dictation"
    }

    @objc private func toggleDictation() { controller.toggle() }
    @objc private func openSettings() { showSettings(tab: .general) }

    // MARK: - Settings window

    func showSettings(tab: SettingsTab) {
        SettingsNavigation.shared.tab = tab
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Dictate Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Debug

    var debugController: DictationController { controller }
}
