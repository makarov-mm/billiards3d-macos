import Foundation

/// A small deterministic source of random numbers (SplitMix64), with uniform and normal deviates and shuffles. The
/// same seed gives the same racks and the same strokes of the computer on every machine.
struct RandomSource: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Seeded from the system's generator.
    init() {
        self.init(seed: UInt64.random(in: .min ... .max))
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// In [0, 1).
    mutating func uniform() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// In [low, high).
    mutating func uniform(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * uniform()
    }

    /// Below `bound`, which is above zero.
    mutating func below(_ bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }

    /// From the normal distribution (Box-Muller).
    mutating func normal(mean: Double = 0, deviation: Double = 1) -> Double {
        let u = 1 - uniform()
        let v = uniform()
        let z = (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
        return z * deviation + mean
    }

    /// Fisher-Yates.
    mutating func shuffle<Element>(_ items: inout [Element]) {
        var i = items.count - 1
        while i > 0 {
            items.swapAt(i, below(i + 1))
            i -= 1
        }
    }
}
