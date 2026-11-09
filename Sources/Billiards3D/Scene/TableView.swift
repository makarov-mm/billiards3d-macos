import Foundation
import simd

/// How the balls are shown: on the cloth where the simulation has them, dropping into the pockets and lying there in
/// a heap, and fading in when they are set back on the table or racked.
struct TableView {
    private struct Visual {
        var pocket = -1
        var slot = -1
        /// Seconds since it dropped.
        var fall: Float = 10
        /// Where it dropped.
        var from = SIMD3<Float>(repeating: 0)
        /// As it dropped.
        var velocity = SIMD3<Float>(repeating: 0)
        /// Fading in, 0 to 1; below 0 waiting to.
        var appear: Float = 1
    }

    /// How the balls lie in a cup: as many round a ring as fit, the next layer in the gaps.
    private struct Ring {
        var count: Int
        var radius: Float
        /// From one layer to the next.
        var rise: Float
    }

    private static let gravity: Float = 9.81
    private static let fallTime: Float = 0.55
    private static let appearTime: Float = 0.35

    private var table: TableSpec?
    private var visuals = [Visual](repeating: Visual(), count: Simulation.maxBalls)

    mutating func setTable(_ table: TableSpec) {
        self.table = table
        visuals = [Visual](repeating: Visual(), count: Simulation.maxBalls)
    }

    /// The balls as they are, without animation: those pocketed lie in their pockets. Racked balls drop in one by one.
    mutating func reset(_ sim: Simulation, rack: Bool) {
        visuals = [Visual](repeating: Visual(), count: Simulation.maxBalls)
        for i in 0..<sim.count {
            let ball = sim.balls[i]
            if !ball.onTable && ball.pocket >= 0 {
                land(i, in: ball.pocket)
            }
            if rack {
                visuals[i].appear = -0.035 * Float(i)
            }
        }
    }

    /// Follows the simulation: balls just pocketed start to drop, balls back on the table fade in.
    mutating func update(_ sim: Simulation, seconds: Float) {
        for i in 0..<sim.count {
            let ball = sim.balls[i]
            if ball.onTable && visuals[i].pocket >= 0 {
                // Back on the table.
                visuals[i].pocket = -1
                visuals[i].slot = -1
                visuals[i].appear = 0
            } else if !ball.onTable && visuals[i].pocket < 0 && ball.pocket >= 0, let table {
                let R = Float(table.ballRadius)
                land(i, in: ball.pocket)
                visuals[i].fall = 0
                visuals[i].from = SIMD3(Float(ball.p.x), R, Float(ball.p.z))
                visuals[i].velocity = SIMD3(Float(ball.v.x), 0, Float(ball.v.z))
            }
            visuals[i].fall += seconds
            visuals[i].appear = min(1, visuals[i].appear + seconds / Self.appearTime)
        }
    }

    var isAnimating: Bool {
        visuals.contains { ($0.pocket >= 0 && $0.fall < Self.fallTime) || $0.appear < 1 }
    }

    /// The middle of a ball as drawn.
    func position(_ sim: Simulation, _ ball: Int) -> SIMD3<Float> {
        guard let table else { return .zero }
        let b = sim.balls[ball]
        let v = visuals[ball]
        let R = Float(table.ballRadius)
        if b.onTable || v.pocket < 0 {
            // Set down from a little above as it fades in.
            let settle = 1 - Easing.smoothStep(0, 1, max(v.appear, 0))
            return SIMD3(Float(b.p.x), R + settle * 1.5 * R, Float(b.p.z))
        }
        let slot = slotPosition(v.pocket, v.slot)
        if v.fall >= Self.fallTime {
            return slot
        }
        // It drops over the hole, carried on a little by its speed, and comes to rest in its place.
        let t = v.fall
        let s = Easing.smoothStep(0, 1, t / (Self.fallTime * 0.75))
        let pocket = table.pockets[v.pocket]
        var carried = v.from + v.velocity * min(t, 0.05)
        let hole = SIMD3<Float>(Float(pocket.hole.x), 0, Float(pocket.hole.z))
        var offset = carried - hole
        offset.y = 0
        let room = Float(pocket.cupRadius) - R
        if length(offset) > room {
            carried = hole + offset * (room / length(offset))
        }
        var p = carried + (slot - carried) * s
        let drop = R - 0.5 * Self.gravity * t * t
        let landing = (2 * max(0, R - slot.y) / Self.gravity).squareRoot()
        if t < landing {
            p.y = max(slot.y, drop)
        } else {
            let after = t - landing
            p.y = slot.y + 0.25 * R * abs(sin(after * 26)) * exp(-after * 14)
        }
        return p
    }

    func isVisible(_ sim: Simulation, _ ball: Int) -> Bool {
        let v = visuals[ball]
        if sim.balls[ball].onTable {
            return v.appear > 0
        }
        return v.pocket >= 0 && (v.slot < capacity(v.pocket) || v.fall < Self.fallTime)
    }

    /// The balls to draw, each with its glow at the rim.
    func balls(_ sim: Simulation, highlight: [Float]) -> [BallDraw] {
        guard let table else { return [] }
        let R = Float(table.ballRadius)
        var draws: [BallDraw] = []
        for i in 0..<sim.count where isVisible(sim, i) {
            let b = sim.balls[i]
            let p = position(sim, i)
            var draw = BallDraw()
            draw.model = Self.ballMatrix(p, b.q, radius: R)
            draw.number = i
            draw.russian = table.kind == .pyramid
            draw.opacity = b.onTable ? Easing.smoothStep(0, 1, max(visuals[i].appear, 0)) : 1
            draw.highlight = highlight[i]
            // What it stands on: the cloth, or the bottom of the pocket or the balls below it.
            draw.ground = b.onTable ? 0 : min(p.y - R, 0)
            if draw.opacity > 0.01 {
                draws.append(draw)
            }
        }
        return draws
    }

    /// A ball's place, turn and size.
    static func ballMatrix(_ position: SIMD3<Float>, _ q: Quat, radius: Float) -> float4x4 {
        let w = Float(q.w)
        let x = Float(q.x)
        let y = Float(q.y)
        let z = Float(q.z)
        return float4x4(columns: (
            SIMD4((1 - 2 * (y * y + z * z)) * radius, 2 * (x * y + w * z) * radius, 2 * (x * z - w * y) * radius, 0),
            SIMD4(2 * (x * y - w * z) * radius, (1 - 2 * (x * x + z * z)) * radius, 2 * (y * z + w * x) * radius, 0),
            SIMD4(2 * (x * z + w * y) * radius, 2 * (y * z - w * x) * radius, (1 - 2 * (x * x + y * y)) * radius, 0),
            SIMD4(position, 1)))
    }

    // MARK: - The pockets

    private static func ring(cup: Float, R: Float) -> Ring {
        let radius = max(0, cup - R - 0.002)
        if radius < R * 1.02 {
            // One at a time, leaning to alternate sides.
            let lean = min(radius, 0.8 * R)
            return Ring(count: 1, radius: lean, rise: max(0, 4 * R * R - 4 * lean * lean).squareRoot())
        }
        let count = min(max(Int(Float.pi / asin(min(1, R / radius))), 1), 5)
        let gap = 2 * radius * sin(Float.pi / Float(2 * count))
        return Ring(count: count, radius: radius, rise: max(0, 4 * R * R - gap * gap).squareRoot())
    }

    private func capacity(_ pocket: Int) -> Int {
        guard let table else { return 0 }
        let p = table.pockets[pocket]
        let R = Float(table.ballRadius)
        let ring = Self.ring(cup: Float(p.cupRadius), R: R)
        // Layers whose balls stay below the cloth.
        let bottom = -Float(p.depth) + R
        var layers = 0
        while bottom + Float(layers) * ring.rise + R < -0.004 && layers < 6 {
            layers += 1
        }
        return max(1, layers) * ring.count
    }

    /// Where the `slot`-th ball lies in a pocket: in layers of a ring at the bottom, the deeper ones first. Past the
    /// pocket's room, out of sight below.
    private func slotPosition(_ pocket: Int, _ slot: Int) -> SIMD3<Float> {
        guard let table else { return .zero }
        let p = table.pockets[pocket]
        let R = Float(table.ballRadius)
        let hole = SIMD3<Float>(Float(p.hole.x), 0, Float(p.hole.z))
        let bottom = -Float(p.depth) + R
        if slot >= capacity(pocket) {
            return hole + SIMD3(0, bottom - 3 * R, 0) // gone deeper, out of sight
        }
        let ring = Self.ring(cup: Float(p.cupRadius), R: R)
        let layer = slot / ring.count
        let index = slot % ring.count
        // The ring turned half a gap on each layer, and toward the table's middle at the start, so the first ball is the
        // one best seen.
        let start = atan2(-Float(p.axis.z), -Float(p.axis.x))
        let angle = start + (Float(index) + 0.5 * Float(layer % 2)) * 2 * Float.pi / Float(ring.count)
            + (ring.count == 1 ? Float.pi * Float(layer % 2) : 0)
        return hole + SIMD3(cos(angle) * ring.radius, bottom + Float(layer) * ring.rise, sin(angle) * ring.radius)
    }

    private func freeSlot(_ pocket: Int) -> Int {
        var slot = 0
        while visuals.contains(where: { $0.pocket == pocket && $0.slot == slot }) {
            slot += 1
        }
        return slot
    }

    private mutating func land(_ ball: Int, in pocket: Int) {
        let slot = freeSlot(pocket)
        visuals[ball].pocket = pocket
        visuals[ball].slot = slot
    }
}
