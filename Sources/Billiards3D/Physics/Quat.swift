import Foundation

/// A rotation, kept for drawing the balls turning.
struct Quat: Equatable, Sendable {
    var w: Double = 1
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0

    /// This rotation, then a turn by `angle` about the unit `axis` of the table's space.
    func turned(about axis: V3, by angle: Double) -> Quat {
        let s = sin(angle / 2)
        let c = cos(angle / 2)
        let d = Quat(w: c, x: axis.x * s, y: axis.y * s, z: axis.z * s)
        var r = Quat(w: d.w * w - d.x * x - d.y * y - d.z * z, x: d.w * x + d.x * w + d.y * z - d.z * y,
                     y: d.w * y - d.x * z + d.y * w + d.z * x, z: d.w * z + d.x * y - d.y * x + d.z * w)
        let n = (r.w * r.w + r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        r.w /= n
        r.x /= n
        r.y /= n
        r.z /= n
        return r
    }
}
