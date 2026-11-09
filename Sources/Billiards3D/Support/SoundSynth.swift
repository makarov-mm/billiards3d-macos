import Foundation

/// The sounds, made up at start from damped resonances and noise: a struck body for the cue, the balls, the cushions
/// and the pockets, swishing noise for a net, and bells for a foul and a win.
enum SoundSynth {
    static let rate = 44_100.0

    static func samples(_ effect: SoundEffect) -> [Float] {
        switch effect {
        case .cue:
            // The leather tip on the ball: a short, woody knock.
            return normalized(strike(length: 0.14, modes: [(1250, 0.6, 0.006), (2350, 0.38, 0.003), (430, 0.45, 0.014), (760, 0.2, 0.01)],
                                     click: 0.9, clickDecay: 0.0012, brightness: 0.6, seed: 3), peak: 0.55)
        case .ball:
            return normalized(ballClick(seed: 5, pitch: 1.0), peak: 0.75)
        case .cushion:
            // Rubber under cloth: a dull thump.
            return normalized(strike(length: 0.22, modes: [(160, 0.8, 0.026), (95, 0.6, 0.042), (430, 0.28, 0.008)], click: 0.5, clickDecay: 0.01,
                                     brightness: 0.1, seed: 7), peak: 0.6)
        case .pocket:
            // A drop pocket: a thud as the ball lands, then knocks as it settles against the others.
            var pocket = strike(length: 0.3, modes: [(110, 0.9, 0.045), (230, 0.5, 0.025), (620, 0.2, 0.01)], click: 0.4, clickDecay: 0.008,
                                brightness: 0.2, seed: 11)
            for (at, gain, pitch) in [(0.06, 0.55, 1.0), (0.115, 0.35, 1.08), (0.16, 0.2, 0.96)] {
                add(strike(length: 0.06, modes: [(700 * pitch, 0.7, 0.012), (1520 * pitch, 0.4, 0.005)], click: 0.6, clickDecay: 0.001,
                           brightness: 0.7, seed: UInt32(at * 1000)), to: &pocket, at: at, gain: Float(gain))
            }
            return normalized(pocket, peak: 0.6)
        case .net:
            // A net: a soft thump and the swish of the cords.
            var net = strike(length: 0.3, modes: [(90, 0.8, 0.06), (180, 0.3, 0.03)], click: 0.3, clickDecay: 0.01, brightness: 0.1, seed: 13)
            add(swish(length: 0.35, center: 2400, seed: 17), to: &net, at: 0, gain: 1.6)
            return normalized(net, peak: 0.5)
        case .rack:
            // Racking: balls set down and knocking together.
            var rack = silence(0.5)
            var random = MinimalRandom(seed: 23)
            for i in 0..<12 {
                let pitch = 0.85 + 0.3 * random.unit()
                let at = 0.03 * Double(i) + 0.02 * random.unit()
                let gain = Float(0.25 + 0.5 * random.unit())
                add(ballClick(seed: UInt32(30 + i), pitch: pitch), to: &rack, at: at, gain: gain)
            }
            return normalized(rack, peak: 0.45)
        case .click:
            let click = (0..<Int(0.03 * rate)).map { i -> Float in
                let t = Double(i) / rate
                return Float(sin(2 * Double.pi * 2600 * t) * exp(-t / 0.004))
            }
            return normalized(click, peak: 0.18)
        case .foul:
            var foul = silence(0.9)
            add(bell(frequency: 392.0, length: 0.6), to: &foul, at: 0, gain: 1)
            add(bell(frequency: 311.1, length: 0.7), to: &foul, at: 0.16, gain: 1)
            return normalized(foul, peak: 0.22)
        case .win:
            var chord = silence(1.8)
            for (index, note) in [523.25, 659.25, 783.99, 1046.5].enumerated() {
                add(bell(frequency: note, length: 1.5), to: &chord, at: Double(index) * 0.11, gain: 0.8)
            }
            return normalized(chord, peak: 0.35)
        }
    }

    // MARK: - Making sounds

    /// A minimal standard generator, as the noise of the original was made with.
    private struct MinimalRandom {
        private var state: UInt64

        init(seed: UInt32) {
            let s = UInt64(seed) % 2_147_483_647
            state = s == 0 ? 1 : s
        }

        /// In [0, 1).
        mutating func unit() -> Double {
            state = state * 48_271 % 2_147_483_647
            return Double(state - 1) / 2_147_483_646
        }
    }

    private static func silence(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * rate)) }

    private static func add(_ source: [Float], to target: inout [Float], at seconds: Double, gain: Float) {
        let offset = Int(seconds * rate)
        if target.count < offset + source.count {
            target += [Float](repeating: 0, count: offset + source.count - target.count)
        }
        for (i, sample) in source.enumerated() {
            target[offset + i] += sample * gain
        }
    }

    /// Scaled so that the loudest sample is `peak`.
    private static func normalized(_ samples: [Float], peak: Float) -> [Float] {
        let loudest = samples.reduce(Float(1e-6)) { max($0, abs($1)) }
        return samples.map { $0 * peak / loudest }
    }

    /// A struck body: a burst of noise, the higher part of it for a hard click, and damped resonances, each a frequency
    /// (Hz), an amplitude and the seconds it takes to fall to 1/e.
    private static func strike(length: Double, modes: [(frequency: Double, gain: Double, decay: Double)], click: Double, clickDecay: Double,
                               brightness: Double, seed: UInt32) -> [Float] {
        var random = MinimalRandom(seed: seed)
        var low: Float = 0
        return (0..<Int(length * rate)).map { i -> Float in
            let t = Double(i) / rate
            let white = Float(random.unit() * 2 - 1)
            low += (white - low) * 0.08
            let bright = white - low
            var value = click * (brightness * Double(bright) + (1 - brightness) * 3 * Double(low)) * exp(-t / clickDecay)
            for mode in modes {
                value += mode.gain * sin(2 * Double.pi * mode.frequency * t) * exp(-t / mode.decay)
            }
            return Float(value * min(1, t / 0.0003))
        }
    }

    private static func ballClick(seed: UInt32, pitch: Double) -> [Float] {
        strike(length: 0.09, modes: [(3350 * pitch, 0.9, 0.0045), (5650 * pitch, 0.5, 0.0024), (1900 * pitch, 0.32, 0.007), (7900 * pitch, 0.22, 0.0012)],
               click: 1.4, clickDecay: 0.0006, brightness: 0.9, seed: seed)
    }

    /// A small bell: inharmonic partials dying away at their own rates.
    private static func bell(frequency: Double, length: Double) -> [Float] {
        let partials: [(ratio: Double, gain: Double, decay: Double)] = [(1.0, 1.0, 1.0), (2.0, 0.45, 0.6), (2.76, 0.3, 0.4), (5.4, 0.12, 0.25)]
        return (0..<Int(length * rate)).map { i -> Float in
            let t = Double(i) / rate
            var value = 0.0
            for partial in partials {
                value += partial.gain * sin(2 * Double.pi * frequency * partial.ratio * t) * exp(-t / (length * 0.35 * partial.decay))
            }
            return Float(value * min(1, t / 0.004))
        }
    }

    /// Noise through a band round `center`, swelling and dying away: a net taking a ball.
    private static func swish(length: Double, center: Double, seed: UInt32) -> [Float] {
        var random = MinimalRandom(seed: seed)
        // A resonant filter.
        let r = 0.97
        let theta = 2 * Double.pi * center / rate
        let a1 = 2 * r * cos(theta)
        let a2 = -r * r
        var y1 = 0.0
        var y2 = 0.0
        return (0..<Int(length * rate)).map { i -> Float in
            let t = Double(i) / rate
            let y = (random.unit() * 2 - 1) * (1 - r) + a1 * y1 + a2 * y2
            y2 = y1
            y1 = y
            let envelope = min(1, t / 0.02) * exp(-t / (length * 0.3))
            return Float(y * envelope)
        }
    }
}
