import Foundation

/// Silences audio that is too quiet to be *you* (someone talking in another room, background TV).
/// Adapts to how loudly you speak: the threshold follows a slowly decaying peak of your own level.
public struct VoiceGate {
    public struct Output {
        /// The chunk if the gate is open, otherwise silence of the same length.
        public var samples: [Float]
        /// Set when the gate has just opened: the previous (silenced) chunk, so the soft start of a word is not lost.
        public var restorePrevious: [Float]?
        /// 0...1 meter level (0 while the gate is closed).
        public var level: Float
        public var isOpen: Bool
    }

    public var minLevel: Float
    public var maxThreshold: Float = 0.06
    public var relativeThreshold: Float = 0.25
    public var hangoverChunks = 6

    private var reference: Float = 0
    private var hang = 0
    private var previous: [Float] = []
    public private(set) var isOpen = false
    public private(set) var peak: Float = 0
    public private(set) var gatedChunks = 0
    public private(set) var totalChunks = 0

    public init(minLevel: Float = 0.02) { self.minLevel = minLevel }

    public mutating func reset() {
        reference = 0; hang = 0; previous = []; isOpen = false
        peak = 0; gatedChunks = 0; totalChunks = 0
    }

    public mutating func process(_ chunk: [Float]) -> Output {
        var sum: Float = 0
        for v in chunk { sum += v * v }
        let rms = chunk.isEmpty ? 0 : (sum / Float(chunk.count)).squareRoot()

        reference = max(reference * 0.998, rms)
        let threshold = min(max(minLevel, reference * relativeThreshold), maxThreshold)
        let loud = rms >= threshold

        var restore: [Float]? = nil
        if loud {
            if !isOpen && !previous.isEmpty { restore = previous }
            hang = hangoverChunks
            isOpen = true
        } else if hang > 0 {
            hang -= 1          // short pause between words: stay open
            isOpen = true
        } else {
            isOpen = false
        }
        previous = chunk
        peak = max(peak, rms)
        totalChunks += 1
        if !isOpen { gatedChunks += 1 }

        return Output(
            samples: isOpen ? chunk : [Float](repeating: 0, count: chunk.count),
            restorePrevious: restore,
            level: isOpen ? min(1, rms * 9) : 0,
            isOpen: isOpen
        )
    }
}
