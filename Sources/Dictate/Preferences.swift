import Foundation

/// All user settings live in UserDefaults. SwiftUI binds to the same keys with @AppStorage.
enum Pref {
    static let triggerMode = "triggerMode"        // "toggle" | "hold"
    static let sounds = "sounds"
    static let cleanup = "cleanup"
    static let englishOnly = "englishOnly"
    static let minLevel = "minLevel"
    static let minConfidence = "minConfidence"
    static let typePhrases = "typePhrases"
    static let clearPhrases = "clearPhrases"
    static let stopPhrases = "stopPhrases"
    static let modelDir = "modelDir"

    static var defaultModelDir: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dictate/models/parakeet-ultra").path
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            triggerMode: "toggle",
            sounds: true,
            cleanup: true,
            englishOnly: true,
            minLevel: 0.02,
            minConfidence: 0.88,
            typePhrases: "type that",
            clearPhrases: "scratch that",
            stopPhrases: "close listener",
            modelDir: defaultModelDir,
        ])
    }

    static var d: UserDefaults { .standard }
    static var holdToTalk: Bool { d.string(forKey: triggerMode) == "hold" }
    static var soundsEnabled: Bool { d.bool(forKey: sounds) }
    static var cleanupEnabled: Bool { d.bool(forKey: cleanup) }
    static var englishOnlyEnabled: Bool { d.bool(forKey: englishOnly) }
    static var minLevelValue: Float { Float(d.double(forKey: minLevel)) }
    static var minConfidenceValue: Float { Float(d.double(forKey: minConfidence)) }
    static var typePhraseList: [String] { phrases(typePhrases, fallback: "type that") }
    static var clearPhraseList: [String] { phrases(clearPhrases, fallback: "scratch that") }
    static var stopPhraseList: [String] { phrases(stopPhrases, fallback: "close listener") }
    static var modelDirectory: String { d.string(forKey: modelDir) ?? defaultModelDir }

    private static func phrases(_ key: String, fallback: String) -> [String] {
        let list = parse(d.string(forKey: key) ?? fallback)
        return list.isEmpty ? [fallback] : list
    }
    private static func parse(_ csv: String) -> [String] {
        csv.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }
}
