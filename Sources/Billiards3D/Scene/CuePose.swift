import Foundation
import simd

/// Where the cue lies: its tip `pull` behind the point it strikes, and raised to clear the cushion and the rail behind
/// the ball.
enum CuePose {
    /// How far the cue is drawn back for a stroke of the given power.
    static func pull(for power: Float) -> Float { 0.02 + 0.2 * power }

    static func matrix(table: TableSpec, center: SIMD3<Float>, aim: V2, side: Float, vertical: Float, pull: Float) -> float4x4 {
        let R = Float(table.ballRadius)
        let n = aim.normalized
        let d = SIMD3<Float>(Float(n.x), 0, Float(n.z))
        let up = SIMD3<Float>(0, 1, 0)
        let right = SIMD3<Float>(-d.z, 0, d.x)
        let depth = max(0, 1 - side * side - vertical * vertical).squareRoot() * R
        let contact = center - d * depth + right * (side * R) + up * (vertical * R)

        // How far behind the ball the cushion's nose is.
        let hl = Float(table.length / 2)
        let hw = Float(table.width / 2)
        var behind: Float = 10
        if d.x < -1e-5 {
            behind = min(behind, (hl - center.x) / -d.x)
        } else if d.x > 1e-5 {
            behind = min(behind, (center.x + hl) / d.x)
        }
        if d.z < -1e-5 {
            behind = min(behind, (hw - center.z) / -d.z)
        } else if d.z > 1e-5 {
            behind = min(behind, (center.z + hw) / d.z)
        }
        behind = max(behind - depth, 0.01)
        let gap = 0.006 + pull
        func radius(_ h: Float) -> Float { 0.0065 + 0.006 * max(h - gap, 0) }
        let overCushion = (Float(table.cushionHeight) + 0.004 + radius(behind) - contact.y) / behind
        let railAt = behind + Float(table.cushionWidth)
        let overRail = (Float(table.railHeight) + 0.004 + radius(railAt) - contact.y) / railAt
        let elevation = min(max(atan(max(overCushion, overRail)), 0.07), 0.8)

        let axis = Matrix.unit(d * -cos(elevation) + up * sin(elevation))
        let x = Matrix.unit(cross(up, axis))
        let y = cross(axis, x)
        let tip = contact + axis * gap
        return float4x4(columns: (SIMD4(x, 0), SIMD4(y, 0), SIMD4(axis, 0), SIMD4(tip, 1)))
    }
}
