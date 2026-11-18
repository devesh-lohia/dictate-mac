import AVFoundation
import DictateCore

/// Records the microphone as 16 kHz mono Float32 and passes it through the VoiceGate.
final class AudioCapture {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var gate = VoiceGate()
    private var _level: Float = 0

    var level: Float { lock.lock(); defer { lock.unlock() }; return _level }

    var statsDescription: String {
        lock.lock(); defer { lock.unlock() }
        return String(format: "peak=%.3f gated=%d/%d", gate.peak, gate.gatedChunks, gate.totalChunks)
    }

    func start(minLevel: Float) throws {
        lock.lock(); samples = []; gate = VoiceGate(minLevel: minLevel); _level = 0; lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw CaptureError.noInputDevice }
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: inputFormat, to: target) else { throw CaptureError.noConverter }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / inputFormat.sampleRate) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            converter.convert(to: out, error: nil) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            guard let channel = out.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))

            self.lock.lock()
            let wasOpen = self.gate.isOpen
            let result = self.gate.process(chunk)
            if let previous = result.restorePrevious, !wasOpen, self.samples.count >= previous.count {
                self.samples.replaceSubrange((self.samples.count - previous.count)..<self.samples.count, with: previous)
            }
            self.samples.append(contentsOf: result.samples)
            self._level = result.level
            self.lock.unlock()
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }

    func snapshot() -> [Float] { lock.lock(); defer { lock.unlock() }; return samples }

    /// Forget everything recorded so far (used by "scratch that" / "type that").
    func discard() {
        lock.lock(); samples = []; _level = 0; gate.reset(); lock.unlock()
    }

    enum CaptureError: Error { case noInputDevice, noConverter }
}
