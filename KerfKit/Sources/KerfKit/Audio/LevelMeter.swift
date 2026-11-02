import Foundation

/// Turns audio into six bar heights that move with the music, low to high, from cheap one-pole
/// filters instead of an FFT. It measures in blocks of about 10 ms whatever size the audio
/// arrives in, so the bars move the same at any buffer size. Not thread-safe: one audio thread.
public struct LevelMeter: Sendable {
    public static let bars = 6

    /// The six heights, 0 to 1, low to high, in the first six lanes; the last two stay 0.
    public typealias Levels = SIMD8<Float>

    /// Band edges in Hz; the last band is everything above the last edge.
    private static let edges: [Double] = [120, 350, 900, 2200, 5000]
    /// Higher bands carry less energy in music: lift them so all six move.
    private static let lift = Levels(0, 3, 6, 9, 12, 15, 0, 0)

    /// Lane i low-passes at edge i, and lane 5 is the signal itself. `previous` runs the same
    /// filters one lane over, so `lows - previous` is every band at once, without moving lanes
    /// for each sample.
    private var lows = Levels()
    private var previous = Levels()
    private let coefficients: Levels
    private let shiftedCoefficients: Levels
    private var energy = Levels()
    private var counted = 0
    private let blockSize: Int
    private var smoothed = Levels()

    public init(sampleRate: Double) {
        let c = Self.edges.map { Float(1 - exp(-2 * Double.pi * $0 / sampleRate)) }
        coefficients = Levels(c[0], c[1], c[2], c[3], c[4], 1, 0, 0)
        shiftedCoefficients = Levels(0, c[0], c[1], c[2], c[3], c[4], 0, 0)
        // 512 samples at 48 kHz: the block the bars were tuned on.
        blockSize = max(1, Int((sampleRate * 512 / 48_000).rounded()))
    }

    /// Feeds mono samples; returns the bars after the last full block.
    public mutating func process(_ samples: UnsafeBufferPointer<Float>) -> Levels {
        for sample in samples { add(sample) }
        return smoothed
    }

    /// Feeds interleaved frames, mixed to mono on the way.
    public mutating func process(interleaved samples: UnsafeBufferPointer<Float>, channels: Int) -> Levels {
        guard channels > 1 else { return process(samples) }
        if channels == 2 {
            var index = 0
            while index + 1 < samples.count {
                add((samples[index] + samples[index + 1]) * 0.5)
                index += 2
            }
            return smoothed
        }
        let scale = 1 / Float(channels)
        var index = 0
        while index + channels <= samples.count {
            var sum: Float = 0
            for channel in 0..<channels { sum += samples[index + channel] }
            add(sum * scale)
            index += channels
        }
        return smoothed
    }

    /// The first six lanes as an array.
    public static func array(_ levels: Levels) -> [Float] {
        (0..<bars).map { levels[$0] }
    }

    @inline(__always)
    private mutating func add(_ sample: Float) {
        let x = Levels(repeating: sample)
        lows += coefficients * (x - lows)
        previous += shiftedCoefficients * (x - previous)
        let band = lows - previous
        energy += band * band
        counted += 1
        if counted == blockSize { finishBlock() }
    }

    private mutating func finishBlock() {
        let count = Float(counted)
        for band in 0..<Self.bars {
            let rms = (energy[band] / count).squareRoot()
            let decibels = 20 * log10(max(rms, 1e-7)) + Self.lift[band]
            let level = min(max((decibels + 48) / 42, 0), 1)
            // Up fast, down slower, like a meter.
            let speed: Float = level > smoothed[band] ? 0.65 : 0.18
            smoothed[band] += (level - smoothed[band]) * speed
        }
        energy = Levels()
        counted = 0
    }
}
