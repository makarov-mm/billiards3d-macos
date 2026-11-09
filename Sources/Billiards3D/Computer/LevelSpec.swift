/// How well the computer plays at one of its five levels.
struct LevelSpec: Sendable {
    /// Pots looked at closely.
    let candidates: Int
    /// Variants of each.
    let speeds: Int
    let spins: Int
    /// The spread of the aim, degrees.
    let aim: Double
    /// Of the speed, as a fraction.
    let speed: Double
    /// Of the point struck, as a fraction of the radius.
    let spin: Double
    let finalists: Int
    let samples: Int

    static let levels = [
        LevelSpec(candidates: 4, speeds: 1, spins: 1, aim: 1.5, speed: 0.12, spin: 0.14, finalists: 1, samples: 3),
        LevelSpec(candidates: 8, speeds: 1, spins: 1, aim: 0.85, speed: 0.08, spin: 0.1, finalists: 2, samples: 4),
        LevelSpec(candidates: 14, speeds: 2, spins: 3, aim: 0.42, speed: 0.05, spin: 0.06, finalists: 3, samples: 5),
        LevelSpec(candidates: 26, speeds: 3, spins: 3, aim: 0.18, speed: 0.03, spin: 0.035, finalists: 5, samples: 8),
        LevelSpec(candidates: 40, speeds: 3, spins: 3, aim: 0.07, speed: 0.015, spin: 0.015, finalists: 6, samples: 12),
    ]

    /// Of a level from 1 to 5.
    static func level(_ level: Int) -> LevelSpec {
        levels[min(max(level, 1), 5) - 1]
    }
}
