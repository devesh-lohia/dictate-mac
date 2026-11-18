import Foundation
import NaturalLanguage

public enum TextRules {
    public static func wordCount(_ t: String) -> Int {
        t.split(whereSeparator: { !$0.isLetter }).count
    }

    /// Fast, model-free cleanup: drops "um/uh", collapses stutters ("the the" -> "the"), capitalizes.
    public static func removeFillers(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: #"(?i)\b(u+h+m*|u+m+|e+r+m*|a+h+m+|hmm+)\b[,.]?\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\b(\w+)(\s+\1\b)+"#, with: "$1", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = s.first, f.isLowercase { s = f.uppercased() + s.dropFirst() }
        return s
    }

    /// Is a model rewrite close enough to what was said? Guards against the model answering instead of editing.
    public static func isFaithfulRewrite(original: String, rewritten: String, range: ClosedRange<Double> = 0.6...1.4) -> Bool {
        guard !rewritten.isEmpty else { return false }
        let ratio = Double(rewritten.count) / Double(max(original.count, 1))
        return range.contains(ratio)
    }

    /// False when the text is clearly another language (for example someone speaking Hindi or Spanish nearby).
    /// Short texts (< 3 words) always pass: language detection is unreliable on them.
    public static func looksEnglish(_ text: String) -> Bool {
        guard wordCount(text) >= 3 else { return true }
        let r = NLLanguageRecognizer()
        r.processString(text)
        guard let lang = r.dominantLanguage else { return true }
        if lang == .english { return true }
        let h = r.languageHypotheses(withMaximum: 5)
        return !((h[lang] ?? 0) >= 0.6 && (h[.english] ?? 0) < 0.25)
    }
}
