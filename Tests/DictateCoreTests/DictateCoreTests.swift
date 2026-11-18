import XCTest
@testable import DictateCore

final class VoiceCommandTests: XCTestCase {
    func testTrailingPhraseIsStripped() {
        XCTAssertEqual(VoiceCommands.trailingMatch(in: "Please send the report by Friday. Type that.", phrases: ["type that"]),
                       "Please send the report by Friday.")
        XCTAssertEqual(VoiceCommands.trailingMatch(in: "Meet at three, type that!", phrases: ["type that"]), "Meet at three,")
        XCTAssertEqual(VoiceCommands.trailingMatch(in: "Type that", phrases: ["type that"]), "")
        XCTAssertEqual(VoiceCommands.trailingMatch(in: "Scratch, that!", phrases: ["scratch that"]), "")
    }

    func testPhraseInTheMiddleDoesNotTrigger() {
        XCTAssertNil(VoiceCommands.trailingMatch(in: "I need to type that report", phrases: ["type that"]))
        XCTAssertNil(VoiceCommands.trailingMatch(in: "scratch that, I meant Thursday", phrases: ["scratch that"]))
        XCTAssertNil(VoiceCommands.trailingMatch(in: "make it clear", phrases: ["scratch that"]))
    }

    func testStopPhrase() {
        XCTAssertEqual(VoiceCommands.trailingMatch(in: "That is all for now. Close listener.", phrases: ["close listener"]), "That is all for now.")
        XCTAssertEqual(VoiceCommands.trailingMatch(in: "Close listener", phrases: ["close listener"]), "")
        XCTAssertNil(VoiceCommands.trailingMatch(in: "please close listener mode in the settings", phrases: ["close listener"]))
    }

    func testParsePhrases() {
        XCTAssertEqual(VoiceCommands.parsePhrases(" Type That, send it ,, "), ["type that", "send it"])
    }
}

final class VoiceGateTests: XCTestCase {
    private func tone(_ amp: Float, _ n: Int = 1365) -> [Float] { (0..<n).map { amp * sin(Float($0) * 0.3) } }

    func testQuietVoiceIsSilenced() {
        var g = VoiceGate(minLevel: 0.02)
        for _ in 0..<20 {
            let o = g.process(tone(0.01))
            XCTAssertFalse(o.isOpen)
            XCTAssertTrue(o.samples.allSatisfy { $0 == 0 })
        }
    }

    func testNormalVoicePasses() {
        var g = VoiceGate(minLevel: 0.02)
        let o = g.process(tone(0.3))
        XCTAssertTrue(o.isOpen)
        XCTAssertEqual(o.samples.count, 1365)
        XCTAssertGreaterThan(o.level, 0)
    }

    func testSoftOnsetIsRestoredAndHangoverKeepsTail() {
        var g = VoiceGate(minLevel: 0.02)
        _ = g.process(tone(0.005))                 // silence-ish, gated
        let open = g.process(tone(0.3))            // speech starts
        XCTAssertNotNil(open.restorePrevious)      // previous chunk should be recovered
        var passed = 0
        for _ in 0..<10 { if g.process(tone(0.001)).isOpen { passed += 1 } }
        XCTAssertEqual(passed, g.hangoverChunks)   // short pause stays open, then closes
    }

    func testResetClearsState() {
        var g = VoiceGate()
        _ = g.process(tone(0.3))
        g.reset()
        XCTAssertEqual(g.totalChunks, 0)
        XCTAssertFalse(g.isOpen)
    }
}

final class TextRulesTests: XCTestCase {
    func testFillersAndStuttersRemoved() {
        XCTAssertEqual(TextRules.removeFillers("um so the the store was closed"), "So the store was closed")
        XCTAssertEqual(TextRules.removeFillers("Uh, hello there"), "Hello there")
    }

    func testRewriteGuard() {
        XCTAssertTrue(TextRules.isFaithfulRewrite(original: "uh so can you tell me the time", rewritten: "So can you tell me the time?"))
        XCTAssertFalse(TextRules.isFaithfulRewrite(original: "what time is it", rewritten: "It is 3 PM in most time zones, depending on where you are located today."))
        XCTAssertFalse(TextRules.isFaithfulRewrite(original: "hello", rewritten: ""))
    }

    func testLanguageFilter() {
        XCTAssertTrue(TextRules.looksEnglish("I was thinking we could push the meeting to Thursday"))
        XCTAssertTrue(TextRules.looksEnglish("ok"))   // too short to judge
        XCTAssertFalse(TextRules.looksEnglish("Hola, necesito ir al mercado mañana para comprar leche"))
    }
}
