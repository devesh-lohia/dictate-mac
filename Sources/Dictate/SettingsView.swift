import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var tab: SettingsTab = .general
}

enum SettingsTab: Hashable { case general, voice, filters, permissions }

struct SettingsView: View {
    @ObservedObject private var nav = SettingsNavigation.shared

    var body: some View {
        TabView(selection: $nav.tab) {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            VoiceTab().tabItem { Label("Voice", systemImage: "text.bubble") }.tag(SettingsTab.voice)
            FiltersTab().tabItem { Label("Filters", systemImage: "waveform.badge.magnifyingglass") }.tag(SettingsTab.filters)
            PermissionsTab().tabItem { Label("Permissions", systemImage: "lock.shield") }.tag(SettingsTab.permissions)
        }
        .frame(width: 520, height: 480)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @AppStorage(Pref.triggerMode) private var triggerMode = "toggle"
    @AppStorage(Pref.sounds) private var sounds = true
    @AppStorage(Pref.modelDir) private var modelDir = Pref.defaultModelDir
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Fn key") {
                Picker("Behavior", selection: $triggerMode) {
                    Text("Press to start, press again to stop").tag("toggle")
                    Text("Hold to talk, release to stop").tag("hold")
                }
                .pickerStyle(.radioGroup)
                Toggle("Play a sound when dictation starts and stops", isOn: $sounds)
            }
            Section("Startup") {
                Toggle("Open Dictate at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            loginError = nil
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            loginError = "Could not change login item: \(error.localizedDescription)"
                        }
                    }))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Speech model") {
                LabeledContent("Parakeet Ultra") {
                    Text((modelDir as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Button("Choose Folder…") { chooseModelFolder() }
                    Button("Reset") { modelDir = Pref.defaultModelDir }
                    Spacer()
                    Text("Takes effect after relaunch").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseModelFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url { modelDir = url.path }
    }
}

// MARK: - Voice commands & cleanup

private struct VoiceTab: View {
    @AppStorage(Pref.cleanup) private var cleanup = true
    @AppStorage(Pref.typePhrases) private var typePhrases = "type that"
    @AppStorage(Pref.clearPhrases) private var clearPhrases = "scratch that"
    @AppStorage(Pref.stopPhrases) private var stopPhrases = "close listener"

    var body: some View {
        Form {
            Section("Cleanup") {
                Toggle("Fix grammar and remove “um”, “uh” and repeated words", isOn: $cleanup)
                Text("Uses Apple’s on-device language model. Nothing leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Voice commands") {
                TextField("Type what I said so far, keep listening", text: $typePhrases)
                TextField("Throw away what I said so far", text: $clearPhrases)
                TextField("Stop listening, type nothing", text: $stopPhrases)
                Text("Say the phrase at the end and pause for a second. Separate alternatives with commas, for example “type that, insert that”.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Filters

private struct FiltersTab: View {
    @AppStorage(Pref.englishOnly) private var englishOnly = true
    @AppStorage(Pref.minLevel) private var minLevel = 0.02
    @AppStorage(Pref.minConfidence) private var minConfidence = 0.88

    var body: some View {
        Form {
            Section("Only listen to me") {
                Toggle("English only, ignore other languages and unclear speech", isOn: $englishOnly)
                VStack(alignment: .leading) {
                    HStack { Text("Ignore voices quieter than"); Spacer(); Text(String(format: "%.3f", minLevel)).monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: $minLevel, in: 0.005...0.06)
                    Text("Raise it if people in other rooms still get picked up. Lower it if Dictate misses you when you speak softly.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    HStack { Text("Minimum speech confidence"); Spacer(); Text(String(format: "%.2f", minConfidence)).monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: $minConfidence, in: 0.5...0.97)
                        .disabled(!englishOnly)
                    Text("Lower it if your own speech gets dropped in a noisy room.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Restore Defaults") { minLevel = 0.02; minConfidence = 0.88; englishOnly = true }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions

private struct PermissionsTab: View {
    @State private var mic = Permissions.microphone
    @State private var ax = Permissions.accessibility
    @State private var input = Permissions.inputMonitoring
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                row("Microphone", "Hear what you say.", mic,
                    request: Permissions.requestMicrophone, open: { Permissions.openSettings(.microphone) })
                row("Input Monitoring", "Detect the Fn key.", input,
                    request: Permissions.requestInputMonitoring, open: { Permissions.openSettings(.inputMonitoring) })
                row("Accessibility", "Paste text at your cursor.", ax,
                    request: Permissions.requestAccessibility, open: { Permissions.openSettings(.accessibility) })
            } footer: {
                Text("After granting Input Monitoring or Accessibility, quit and reopen Dictate once.")
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            mic = Permissions.microphone; ax = Permissions.accessibility; input = Permissions.inputMonitoring
        }
    }

    private func row(_ title: String, _ detail: String, _ granted: Bool,
                     request: @escaping () -> Void, open: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Allow") { request(); open() }
            }
        }
    }
}
