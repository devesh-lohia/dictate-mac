import FluidAudio
import Foundation

struct Transcript {
    let text: String
    let confidence: Float
    static let empty = Transcript(text: "", confidence: 1)
}

/// Parakeet Ultra (CoreML, runs on the Neural Engine) via FluidAudio. The model stays loaded in memory.
final class Transcriber {
    private var manager: AsrManager?
    var isReady: Bool { manager != nil }

    func load(directory: String) async throws {
        let models: AsrModels
        if FileManager.default.fileExists(atPath: directory) {
            models = try AsrModels.loadLocal(from: URL(fileURLWithPath: directory), version: .ultra)
        } else {
            // First run: download Parakeet Ultra (about 600 MB) into FluidAudio's cache, then load it.
            Log.write("model folder not found, downloading Parakeet Ultra")
            models = try await AsrModels.downloadAndLoad(version: .ultra)
        }
        let m = AsrManager(config: .default, models: models)
        manager = m
        // Warm up so the first real dictation is not slow.
        _ = await transcribe([Float](repeating: 0, count: 16_000))
    }

    func transcribe(_ samples: [Float]) async -> Transcript? {
        guard let m = manager else { return nil }
        guard samples.count > 8_000 else { return .empty }       // < 0.5 s: nothing to say yet
        var state = TdtDecoderState.make(decoderLayers: await m.decoderLayerCount)
        guard let result = try? await m.transcribe(samples, decoderState: &state) else { return nil }
        return Transcript(text: result.text.trimmingCharacters(in: .whitespacesAndNewlines), confidence: result.confidence)
    }
}
