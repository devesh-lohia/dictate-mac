import DictateCore
import Foundation

/// Decides whether a transcript is really *you* speaking English clearly.
/// Rejects other languages, low-confidence guesses (distant or mumbled voices) and gibberish.
enum SpeechFilter {
    enum Verdict { case accept(String), reject(reason: String) }

    static func evaluate(_ t: Transcript) -> Verdict {
        guard !t.text.isEmpty else { return .accept("") }
        guard Pref.englishOnlyEnabled else { return .accept(t.text) }
        if TextRules.wordCount(t.text) >= 3, t.confidence < Pref.minConfidenceValue {
            return .reject(reason: String(format: "low confidence %.2f", t.confidence))
        }
        if !TextRules.looksEnglish(t.text) { return .reject(reason: "not English") }
        return .accept(t.text)
    }
}
