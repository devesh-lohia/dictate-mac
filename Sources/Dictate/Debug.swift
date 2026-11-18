import AppKit
import AVFoundation
import DictateCore
import Foundation

/// Command-line helpers for testing without a microphone:
///   Dictate --test file.wav     transcribe a file through the same filters and cleanup the app uses
///   Dictate --demo              show the overlay with sample text for a few seconds
/// Environment: DICTATE_GAIN=0.05 simulates a distant/quiet voice; DICTATE_GATE=1 applies the voice gate.
@MainActor
enum Debug {
    static func runTest(path: String) -> Never {
        Pref.registerDefaults()
        let env = ProcessInfo.processInfo.environment
        guard var samples = try? load16kMono(path: path) else { print("could not read \(path)"); exit(1) }
        let gain = Float(env["DICTATE_GAIN"] ?? "1") ?? 1
        samples = samples.map { $0 * gain }
        if env["DICTATE_GATE"] != nil {
            var gate = VoiceGate(minLevel: Pref.minLevelValue)
            var out: [Float] = []
            var i = 0
            while i < samples.count {
                let chunk = Array(samples[i..<min(i + 1365, samples.count)])
                let r = gate.process(chunk)
                if let p = r.restorePrevious, out.count >= p.count { out.replaceSubrange((out.count - p.count)..<out.count, with: p) }
                out += r.samples
                i += 1365
            }
            print("gate: peak=\(gate.peak) gated=\(gate.gatedChunks)/\(gate.totalChunks)")
            samples = out
        }
        Task {
            let transcriber = Transcriber()
            let t0 = Date()
            do { try await transcriber.load(directory: Pref.modelDirectory) } catch { print("load failed: \(error)"); exit(1) }
            print(String(format: "load %.2fs", Date().timeIntervalSince(t0)))
            let t1 = Date()
            guard let transcript = await transcriber.transcribe(samples) else { print("transcription failed"); exit(1) }
            print(String(format: "raw (%.2fs, confidence %.2f): %@", Date().timeIntervalSince(t1), transcript.confidence, transcript.text))
            switch SpeechFilter.evaluate(transcript) {
            case .reject(let reason): print("filter: REJECTED (\(reason))")
            case .accept(let text):
                print("filter: accepted")
                let t2 = Date()
                let cleaned = await Cleaner().clean(text)
                print(String(format: "clean (%.2fs): %@", Date().timeIntervalSince(t2), cleaned))
            }
            exit(0)
        }
        RunLoop.main.run()
        exit(0)
    }

    static func runDemo(controller: DictationController) {
        controller.overlay.show()
        var tick: Float = 0
        Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { _ in
            Task { @MainActor in tick += 0.2; controller.overlay.model.level = 0.5 + 0.4 * Float(sin(Double(tick))) }
        }
        let words = "So basically I was thinking that we could push the meeting to Thursday because the team is not ready yet and they need more time to finish the work. After that we should review the budget with finance, update the roadmap, and send a short summary to everyone who attended. Then I want to book a room for Friday, invite the design team, and prepare a few slides covering what changed this week and what is still blocked. The very last words of this long dictation should always be visible at the bottom.".split(separator: " ")
        var count = 0
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { t in
            Task { @MainActor in
                count += 1
                controller.overlay.setText(words.prefix(count).joined(separator: " "))
                if count >= words.count { t.invalidate() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 14) { controller.overlay.setWorking("Cleaning up") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { exit(0) }
    }

    private static func load16kMono(path: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: input)
        let converter = AVAudioConverter(from: file.processingFormat, to: target)!
        let capacity = AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 100
        let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)!
        var supplied = false
        converter.convert(to: output, error: nil) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true; status.pointee = .haveData; return input
        }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}
