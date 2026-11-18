import Foundation

/// Spoken commands such as "type that" and "scratch that".
public enum VoiceCommands {
    /// If `text` *ends* with one of `phrases` (case, punctuation and spacing tolerant),
    /// returns the text before the phrase, trimmed. Otherwise nil.
    ///
    ///     trailingMatch(in: "Meet at three, type that!", phrases: ["type that"]) == "Meet at three,"
    ///     trailingMatch(in: "I need to type that report", phrases: ["type that"]) == nil
    public static func trailingMatch(in text: String, phrases: [String]) -> String? {
        for phrase in phrases {
            let words = phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !words.isEmpty else { continue }
            let pattern = "(?i)(^|[^\\p{L}])" + words.joined(separator: "[\\s\\p{P}]+") + "[\\s\\p{P}]*$"
            if let r = text.range(of: pattern, options: .regularExpression) {
                return String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// "type that, send it" -> ["type that", "send it"]
    public static func parsePhrases(_ csv: String) -> [String] {
        csv.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}
