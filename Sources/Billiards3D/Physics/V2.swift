import Foundation

/// A point or a direction on the table, in metres: x along its length, z across it.
struct V2: Equatable, Sendable {
    var x: Double
    var z: Double

    init(_ x: Double, _ z: Double) {
        self.x = x
        self.z = z
    }

    static let zero = V2(0, 0)

    static func + (a: V2, b: V2) -> V2 { V2(a.x + b.x, a.z + b.z) }
    static func - (a: V2, b: V2) -> V2 { V2(a.x - b.x, a.z - b.z) }
    static prefix func - (a: V2) -> V2 { V2(-a.x, -a.z) }
    static func * (a: V2, s: Double) -> V2 { V2(a.x * s, a.z * s) }
    static func * (s: Double, a: V2) -> V2 { a * s }

    func dot(_ b: V2) -> Double { x * b.x + z * b.z }
    func cross(_ b: V2) -> Double { x * b.z - z * b.x }
    var length: Double { dot(self).squareRoot() }

    /// Of length one; along x where it has no length.
    var normalized: V2 {
        let length = self.length
        return length > 1e-12 ? self * (1 / length) : V2(1, 0)
    }

    /// Turned a quarter to the left, as seen from above with x to the right and z toward the viewer.
    var perpendicular: V2 { V2(z, -x) }

    /// Turned by `angle` radians.
    func rotated(_ angle: Double) -> V2 {
        let c = cos(angle)
        let s = sin(angle)
        return V2(x * c - z * s, x * s + z * c)
    }

    var angle: Double { atan2(z, x) }
}
