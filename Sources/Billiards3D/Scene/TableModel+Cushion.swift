import Foundation
import simd

/// The cushions and the rails round the cloth.
extension TableModel {
    /// The jaw at an end of a cushion's nose: its rounded tip, and the facing that leads away from it.
    private struct Jaw {
        var tip = JawTip(center: .zero, radius: 0)
        var facing = CushionSegment(a: .zero, b: .zero, normal: .zero)
    }

    /// A cushion between two jaws: its outline seen from above (the jaws' facings, the rounded tips and the nose),
    /// walls round it, a narrow bevel, and a top rising from the nose to the rail.
    static func addCushion(_ mesh: inout Mesh<SurfaceVertex>, table: TableSpec, nose: CushionSegment) {
        let out = -nose.normal
        let cw = table.cushionWidth
        let hn = table.cushionHeight
        let top = table.railHeight - 0.0015
        func depth(_ p: V2) -> Double { min(max((p - nose.a).dot(out), 0), cw) }
        func height(_ p: V2) -> Double { hn + (top - hn) * depth(p) / cw }

        func jaw(at end: V2) -> Jaw {
            var jaw = Jaw()
            for tip in table.tips where (tip.center - (end + out * tip.radius)).length < 1e-6 {
                jaw.tip = tip
            }
            for segment in table.segments.dropLast(6) where abs((segment.a - jaw.tip.center).length - jaw.tip.radius) < 1e-6
                && (segment.a - end).length > 1e-6 {
                jaw.facing = segment
            }
            return jaw
        }
        let start = jaw(at: nose.a)
        let end = jaw(at: nose.b)
        func backOfFacing(_ facing: CushionSegment) -> V2 {
            let direction = (facing.b - facing.a).normalized
            let s = (cw - (facing.a - nose.a).dot(out)) / max(direction.dot(out), 0.05)
            return facing.a + direction * s
        }
        // The angle of pi in single precision, as the original turns its arcs by.
        let pi = Double(Float.pi)
        func arc(_ outline: inout [V2], _ tip: JawTip, from: V2, to: V2) {
            let a0 = atan2(from.z - tip.center.z, from.x - tip.center.x)
            var a1 = atan2(to.z - tip.center.z, to.x - tip.center.x)
            while a1 - a0 > pi {
                a1 -= Double(2 * Float.pi)
            }
            while a1 - a0 < -pi {
                a1 += Double(2 * Float.pi)
            }
            let steps = 8
            for k in 1..<steps {
                let a = a0 + (a1 - a0) * Double(k) / Double(steps)
                outline.append(tip.center + V2(cos(a), sin(a)) * tip.radius)
            }
        }
        var outline: [V2] = []
        outline.append(backOfFacing(start.facing))
        outline.append(start.facing.a)
        arc(&outline, start.tip, from: start.facing.a, to: nose.a)
        outline.append(nose.a)
        outline.append(nose.b)
        arc(&outline, end.tip, from: nose.b, to: end.facing.a)
        outline.append(end.facing.a)
        outline.append(backOfFacing(end.facing))

        // The outward normal of each outline point: the mean of its edges', the back edge left out.
        let n = outline.count
        var middle = V2.zero
        for p in outline {
            middle = middle + p * (1.0 / Double(n))
        }
        func edgeNormal(_ i: Int, _ j: Int) -> V2 {
            var normal = (outline[j] - outline[i]).perpendicular.normalized
            if normal.dot((outline[i] + outline[j]) * 0.5 - middle) < 0 {
                normal = -normal
            }
            return normal
        }
        var normals = [V2](repeating: .zero, count: n)
        for i in 0..<n {
            var sum = V2.zero
            if i > 0 {
                sum = sum + edgeNormal(i - 1, i)
            }
            if i + 1 < n {
                sum = sum + edgeNormal(i, i + 1)
            }
            normals[i] = sum.normalized
        }

        let bevel = 0.004
        let inset = (0..<n).map { outline[$0] - normals[$0] * bevel }
        let up3 = SIMD3<Float>(0, 1, 0)
        for i in 0..<(n - 1) {
            let j = i + 1
            let ni = at(normals[i], 0)
            let nj = at(normals[j], 0)
            // The wall, the bevel above it, and the top.
            mesh.addQuad(SurfaceVertex(at(outline[i], 0), ni, uv(outline[i])), SurfaceVertex(at(outline[j], 0), nj, uv(outline[j])),
                         SurfaceVertex(at(outline[j], height(outline[j]) - bevel), nj, uv(outline[j])),
                         SurfaceVertex(at(outline[i], height(outline[i]) - bevel), ni, uv(outline[i])))
            let bi = Matrix.unit(ni + up3)
            let bj = Matrix.unit(nj + up3)
            mesh.addQuad(SurfaceVertex(at(outline[i], height(outline[i]) - bevel), bi, uv(outline[i])),
                         SurfaceVertex(at(outline[j], height(outline[j]) - bevel), bj, uv(outline[j])),
                         SurfaceVertex(at(inset[j], height(inset[j])), up3, uv(inset[j])),
                         SurfaceVertex(at(inset[i], height(inset[i])), up3, uv(inset[i])))
        }
        let up = Matrix.unit(SIMD3(Float(-out.x * (top - hn) / cw), 1, Float(-out.z * (top - hn) / cw)))
        var center = V2.zero
        for p in inset {
            center = center + p * (1.0 / Double(n))
        }
        for i in 0..<n {
            let j = (i + 1) % n
            mesh.addTriangle(SurfaceVertex(at(center, height(center)), up, uv(center)), SurfaceVertex(at(inset[i], height(inset[i])), up, uv(inset[i])),
                             SurfaceVertex(at(inset[j], height(inset[j])), up, uv(inset[j])))
        }
    }

    /// A straight rail: its top, the rounded outer edge, the outer side down to the apron, and the inner side. It runs
    /// from `from` to `to` at the cushion's back; `out` points outward.
    static func addRail(_ mesh: inout Mesh<SurfaceVertex>, from innerA: V2, to innerB: V2, out: V2, width: Double, top: Double, bottom: Double,
                        caps: Bool) {
        let round = 0.016
        let steps = 6
        struct Ring {
            var d: Double
            var y: Double
            var normal: V2
            var ny: Double
        }
        var profile: [Ring] = []
        profile.append(Ring(d: 0, y: 0, normal: -out, ny: 0))
        profile.append(Ring(d: 0, y: top, normal: -out, ny: 0))
        profile.append(Ring(d: 0, y: top, normal: .zero, ny: 1))
        for k in 0...steps {
            let a = Double(Float.pi / 2) * Double(k) / Double(steps)
            profile.append(Ring(d: width - round + round * sin(a), y: top - round + round * cos(a), normal: out * sin(a), ny: cos(a)))
        }
        profile.append(Ring(d: width, y: bottom, normal: out, ny: 0))
        let along = innerB - innerA
        func vertex(_ r: Ring, _ s: Double) -> SurfaceVertex {
            let position = innerA + along * s + out * r.d
            return SurfaceVertex(at(position, r.y), Matrix.unit(SIMD3(Float(r.normal.x), Float(r.ny), Float(r.normal.z))), uv(position))
        }
        for i in 0..<(profile.count - 1) {
            let p = profile[i]
            let q = profile[i + 1]
            if abs(p.d - q.d) < 1e-9 && abs(p.y - q.y) < 1e-9 {
                continue
            }
            mesh.addQuad(vertex(p, 0), vertex(p, 1), vertex(q, 1), vertex(q, 0))
        }
        guard caps else { return }
        // The ends of a rail that reaches round the corners.
        for s in [0.0, 1.0] {
            let normal = along.normalized * (s == 0 ? -1.0 : 1.0)
            let base = innerA + along * s
            let n3 = at(normal, 0)
            func point(_ r: Ring) -> SurfaceVertex {
                let p = base + out * r.d
                return SurfaceVertex(at(p, r.y), n3, uv(p))
            }
            for i in 0..<(profile.count - 1) {
                mesh.addTriangle(point(Ring(d: width * 0.5, y: bottom, normal: .zero, ny: 0)), point(profile[i]), point(profile[i + 1]))
            }
        }
    }
}
