import Foundation

/// A table: its measurements, its cloth and cushions, the pockets, and the cushion lines the balls bounce off.
/// Distances are in metres, the table is the plane y = 0 with its long side along x, and a ball's position is its
/// middle's (x, z).
final class TableSpec: Sendable {
    let kind: TableKind
    /// Between the noses of the cushions.
    let length: Double
    let width: Double
    let ballRadius: Double
    /// The nose above the cloth.
    let cushionHeight: Double
    /// Of the ball where it meets a cushion's nose.
    let contactRadius: Double
    // For drawing: the cushions from their noses to the rails, the rails, and the frame below.
    let cushionWidth: Double
    let railWidth: Double
    let railHeight: Double

    // The cloth and the balls.
    let slideFriction: Double
    let rollFriction: Double
    /// Of spin about the vertical, rad/s².
    let spinDeceleration: Double
    let ballRestitution: Double
    let ballFriction: Double
    let cushionRestitution: Double
    let cushionFriction: Double

    /// The corners, then the middles: the near side (z > 0) from the left, then the far side.
    let pockets: [Pocket]
    /// The jaws' facings, two for each pocket, then the noses of the six cushions.
    let segments: [CushionSegment]
    let tips: [JawTip]

    var headString: Double { -length / 4 }
    var footSpot: V2 { V2(length / 4, 0) }

    init(_ kind: TableKind) {
        self.kind = kind
        var corner: PocketShape
        var middle: PocketShape
        slideFriction = 0.2
        ballRestitution = 0.95
        ballFriction = 0.06
        if kind == .pool {
            // A nine-foot pool table with balls of 2¼ inches.
            length = 2.54
            width = 1.27
            ballRadius = 0.028575
            cushionWidth = 0.05
            railWidth = 0.13
            railHeight = 0.045
            rollFriction = 0.01
            spinDeceleration = 10
            cushionRestitution = 0.85
            cushionFriction = 0.18
            corner = PocketShape(mouth: 0.1143, deviation: 38 * Double.pi / 180, tipRadius: 0.006, facing: 0.08, shelf: 0.03, hole: 0.0585,
                                 cup: 0.072, depth: 0.115)
            middle = PocketShape(mouth: 0.13, deviation: 76 * Double.pi / 180, tipRadius: 0.006, facing: 0.045, shelf: 0.012, hole: 0.062,
                                 cup: 0.074, depth: 0.115)
        } else {
            // A twelve-foot Russian table: bigger balls, rounded jaws and pockets barely wider than a ball.
            length = 3.569
            width = 1.778
            ballRadius = 0.034
            cushionWidth = 0.055
            railWidth = 0.15
            railHeight = 0.054
            rollFriction = 0.012
            spinDeceleration = 8
            cushionRestitution = 0.8
            cushionFriction = 0.2
            corner = PocketShape(mouth: 0.104, deviation: 44 * Double.pi / 180, tipRadius: 0.012, facing: 0.06, shelf: 0.018, hole: 0.05,
                                 cup: 0.062, depth: 0.13)
            middle = PocketShape(mouth: 0.112, deviation: 80 * Double.pi / 180, tipRadius: 0.012, facing: 0.04, shelf: 0.006, hole: 0.052,
                                 cup: 0.064, depth: 0.13)
        }
        let R = ballRadius
        cushionHeight = 0.635 * 2 * R
        let lift = (cushionHeight - R) / R
        contactRadius = R * (1 - lift * lift).squareRoot()

        let hl = length / 2
        let hw = width / 2
        let a = corner.mouth / 2.0.squareRoot()
        var pockets: [Pocket] = []
        var segments: [CushionSegment] = []
        var tips: [JawTip] = []
        // A jaw: its rounded tip on a cushion's line at `tip`, the cushion running toward the pocket along `along`,
        // the outside of the table in direction `out`.
        func addJaw(_ tip: V2, along: V2, out: V2, _ shape: PocketShape) {
            let c = cos(shape.deviation)
            let s = sin(shape.deviation)
            let center = tip + out * shape.tipRadius
            let facing = along * c + out * s
            let throat = along * s - out * c // the facing's normal, toward the pocket's throat
            let start = center + throat * shape.tipRadius
            tips.append(JawTip(center: center, radius: shape.tipRadius))
            segments.append(CushionSegment(a: start, b: start + facing * shape.facing, normal: throat))
        }
        for sz in [1.0, -1.0] {
            for column in [-1, 0, 1] {
                var pocket = Pocket()
                if column != 0 {
                    let sx = Double(column)
                    let cornerPoint = V2(sx * hl, sz * hw)
                    let onLong = cornerPoint - V2(sx * a, 0)
                    let onShort = cornerPoint - V2(0, sz * a)
                    addJaw(onLong, along: V2(sx, 0), out: V2(0, sz), corner)
                    addJaw(onShort, along: V2(0, sz), out: V2(sx, 0), corner)
                    pocket.corner = true
                    pocket.mouth = (onLong + onShort) * 0.5
                    pocket.axis = V2(sx, sz).normalized
                    pocket.hole = pocket.mouth + pocket.axis * (corner.shelf + corner.hole)
                    pocket.holeRadius = corner.hole
                    pocket.cupRadius = corner.cup
                    pocket.depth = corner.depth
                } else {
                    let left = V2(-middle.mouth / 2, sz * hw)
                    let right = V2(middle.mouth / 2, sz * hw)
                    addJaw(left, along: V2(1, 0), out: V2(0, sz), middle)
                    addJaw(right, along: V2(-1, 0), out: V2(0, sz), middle)
                    pocket.corner = false
                    pocket.mouth = V2(0, sz * hw)
                    pocket.axis = V2(0, sz)
                    pocket.hole = pocket.mouth + pocket.axis * (middle.shelf + middle.hole)
                    pocket.holeRadius = middle.hole
                    pocket.cupRadius = middle.cup
                    pocket.depth = middle.depth
                }
                pockets.append(pocket)
            }
        }
        // The noses of the cushions between the jaws.
        for sz in [1.0, -1.0] {
            let normal = V2(0, -sz)
            segments.append(CushionSegment(a: V2(-hl + a, sz * hw), b: V2(-middle.mouth / 2, sz * hw), normal: normal))
            segments.append(CushionSegment(a: V2(middle.mouth / 2, sz * hw), b: V2(hl - a, sz * hw), normal: normal))
        }
        for sx in [1.0, -1.0] {
            segments.append(CushionSegment(a: V2(sx * hl, -hw + a), b: V2(sx * hl, hw - a), normal: V2(-sx, 0)))
        }
        self.pockets = pockets
        self.segments = segments
        self.tips = tips
    }

    /// Inside the cushions, as far as a ball can go, and clear of the pockets.
    func onCloth(_ p: V2) -> Bool {
        let R = ballRadius
        if abs(p.x) > length / 2 - R || abs(p.z) > width / 2 - R {
            return false
        }
        for pocket in pockets where (p - pocket.hole).length < pocket.holeRadius + R {
            return false
        }
        return true
    }

    /// Where a ball can come to rest: inside the noses of the cushions (closer than `onCloth`, a ball frozen to a
    /// cushion touches it above its middle), or in the jaws of a pocket, but not over a hole.
    func canRest(at p: V2) -> Bool {
        if !p.x.isFinite || !p.z.isFinite {
            return false
        }
        let inside = abs(p.x) <= length / 2 - contactRadius + 1e-6 && abs(p.z) <= width / 2 - contactRadius + 1e-6
        let inJaws = pockets.contains { (p - $0.mouth).length < $0.holeRadius + 2 * ballRadius }
        return (inside || inJaws) && pockets.allSatisfy { (p - $0.hole).length >= $0.holeRadius }
    }

    /// The fastest a cue sends a ball, m/s.
    var maxSpeed: Double { kind == .pool ? 8.5 : 7.5 }
}
