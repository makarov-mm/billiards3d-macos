import Foundation
import simd

/// The meshes of the scene: the table (its cloth, cushions, rails, frame, legs and pockets), the floor, the ball and
/// the cue. The cloth is the plane y = 0, and the table's measurements come from its TableSpec.
enum TableModel {
    static let cueLength: Float = 1.45

    static func table(_ table: TableSpec) -> TableMeshes {
        var meshes = TableMeshes()
        let hl = table.length / 2
        let hw = table.width / 2
        let cw = table.cushionWidth
        let rw = table.railWidth
        let rh = table.railHeight
        let pool = table.kind == .pool

        // The cloth, as one rectangle; the holes of the pockets are cut in the shader.
        let corners = [V2(-hl - cw, -hw - cw), V2(hl + cw, -hw - cw), V2(hl + cw, hw + cw), V2(-hl - cw, hw + cw)]
        let bed = corners.map { SurfaceVertex(at($0, 0), SIMD3(0, 1, 0), uv($0)) }
        meshes.bed.addQuad(bed[0], bed[1], bed[2], bed[3])

        // The cushions: the last six segments are their noses.
        for nose in table.segments.suffix(6) {
            addCushion(&meshes.cushions, table: table, nose: nose)
        }

        // The rails: the long ones reach round the corners, the short ones fit between them.
        let railBottom = rh - 0.065
        for sz in [1.0, -1.0] {
            addRail(&meshes.rails, from: V2(-hl - cw - rw, sz * (hw + cw)), to: V2(hl + cw + rw, sz * (hw + cw)), out: V2(0, sz), width: rw, top: rh,
                    bottom: railBottom, caps: true)
        }
        for sx in [1.0, -1.0] {
            addRail(&meshes.rails, from: V2(sx * (hl + cw), -hw - cw), to: V2(sx * (hl + cw), hw + cw), out: V2(sx, 0), width: rw, top: rh,
                    bottom: railBottom, caps: false)
        }

        // The apron under the rails, and the legs down to the floor.
        let outerX = Float(hl + cw + rw)
        let outerZ = Float(hw + cw + rw)
        let apron: Float = pool ? 0.17 : 0.21
        meshes.floorHeight = pool ? -0.78 : -0.8
        addBox(&meshes.frame, low: SIMD3(-outerX + 0.012, -apron, -outerZ + 0.012), high: SIMD3(outerX - 0.012, Float(railBottom), outerZ - 0.012),
               top: false)
        addBox(&meshes.frame, low: SIMD3(-outerX + 0.05, -apron - 0.03, -outerZ + 0.05), high: SIMD3(outerX - 0.05, -apron, outerZ - 0.05), top: true)
        let leg = self.leg(height: -meshes.floorHeight - apron - 0.03, radius: pool ? 0.065 : 0.075)
        var legs: [V2] = []
        for sx in [-1.0, 1.0] {
            for sz in [-1.0, 1.0] {
                legs.append(V2(sx * (Double(outerX) - 0.17), sz * (Double(outerZ) - 0.15)))
            }
        }
        if !pool {
            legs.append(V2(0, Double(outerZ) - 0.15))
            legs.append(V2(0, -(Double(outerZ) - 0.15)))
        }
        for p in legs {
            meshes.frame.append(leg, transform: Matrix.translation(at(p, Double(-apron - 0.03))))
        }
        return meshes
    }

    /// A pocket's cup or net round the y axis: its rim at `top`, its bottom `depth` below the cloth.
    static func pocket(radius r: Float, top: Float, depth: Float) -> Mesh<SurfaceVertex> {
        // A cup with a rounded bottom, seen from within.
        var profile: [(r: Float, y: Float)] = [(r, top), (r, -depth * 0.45)]
        for k in 1...8 {
            let a = (Float.pi / 2) * Float(k) / 8
            profile.append((r * cos(a), -depth * 0.45 - depth * 0.55 * sin(a)))
        }
        profile[profile.count - 1].r = 0
        return lathe(profile, segments: 48, inside: true)
    }

    static func floor(size: Float, height: Float) -> Mesh<SurfaceVertex> {
        var mesh = Mesh<SurfaceVertex>()
        func v(_ x: Float, _ z: Float) -> SurfaceVertex { SurfaceVertex(SIMD3(x, height, z), SIMD3(0, 1, 0), SIMD2(x, z)) }
        mesh.addQuad(v(-size, -size), v(size, -size), v(size, size), v(-size, size))
        return mesh
    }

    /// A sphere of radius 1; its positions are its normals.
    static func ball(rings: Int, segments: Int) -> Mesh<SurfaceVertex> {
        var mesh = Mesh<SurfaceVertex>()
        for i in 0...rings {
            let theta = Float.pi * Float(i) / Float(rings)
            for j in 0...segments {
                let phi = 2 * Float.pi * Float(j) / Float(segments)
                let n = SIMD3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
                mesh.vertices.append(SurfaceVertex(n, n, SIMD2(Float(j) / Float(segments), Float(i) / Float(rings))))
            }
        }
        for i in 0..<rings {
            for j in 0..<segments {
                let a = UInt32(i * (segments + 1) + j)
                let b = a + 1
                let c = a + UInt32(segments) + 2
                let d = a + UInt32(segments) + 1
                // Counterclockwise seen from outside.
                mesh.indices += [a, c, b, a, d, c]
            }
        }
        mesh.windByNormals(minimum: 1e-9, normalsOfFirstOnly: true)
        return mesh
    }

    /// The cue from its tip at the origin along +z; v is the distance from the tip.
    static func cue() -> Mesh<SurfaceVertex> {
        // The radius along the cue: the tip, the ferrule, the shaft tapering out, the joint, the forearm, the wrap and the butt.
        let outline: [(r: Float, y: Float)] = [
            (0.0, 0.0), (0.0045, 0.0), (0.0062, 0.0015), (0.0064, 0.009), (0.0066, 0.009), (0.0066, 0.03), (0.0068, 0.03), (0.0082, 0.3),
            (0.0102, 0.735), (0.0108, 0.74), (0.0108, 0.765), (0.0112, 0.77), (0.0128, 1.03), (0.0132, 1.04), (0.0138, 1.32), (0.0144, 1.33),
            (0.0148, 1.44), (0.0138, cueLength), (0.0, cueLength),
        ]
        // The lathe runs down y; turned onto +z below.
        var mesh = lathe(outline.map { (r: $0.r, y: -$0.y) }, segments: 28, inside: false)
        // Turned a quarter about x, so that it runs along +z: a rotation, which keeps the winding.
        mesh.vertices = mesh.vertices.map { v in
            SurfaceVertex(SIMD3(v.px, v.pz, -v.py), SIMD3(v.nx, v.nz, -v.ny), SIMD2(v.u, v.v))
        }
        return mesh
    }

    // MARK: - Parts

    static func at(_ p: V2, _ y: Double) -> SIMD3<Float> { SIMD3(Float(p.x), Float(y), Float(p.z)) }

    static func uv(_ p: V2) -> SIMD2<Float> { SIMD2(Float(p.x), Float(p.z)) }

    /// An outline turned round the y axis; `inside` for a cup seen from within. uv: the turn, and the distance along
    /// the outline.
    static func lathe(_ profile: [(r: Float, y: Float)], segments: Int, inside: Bool) -> Mesh<SurfaceVertex> {
        var mesh = Mesh<SurfaceVertex>()
        let count = profile.count
        var along = [Float](repeating: 0, count: count)
        for i in stride(from: 1, to: count, by: 1) {
            along[i] = along[i - 1] + hypot(profile[i].r - profile[i - 1].r, profile[i].y - profile[i - 1].y)
        }
        for i in 0..<count {
            let before = profile[max(i - 1, 0)]
            let after = profile[min(i + 1, count - 1)]
            var nr = after.y - before.y
            var ny = -(after.r - before.r)
            let size = max(hypot(nr, ny), 1e-6)
            nr /= size
            ny /= size
            if inside {
                nr = -nr
                ny = -ny
            }
            let point = profile[i]
            for j in 0...segments {
                let t = Float(j) / Float(segments)
                let c = cos(2 * Float.pi * t)
                let s = sin(2 * Float.pi * t)
                mesh.vertices.append(SurfaceVertex(SIMD3(point.r * c, point.y, point.r * s), Matrix.unit(SIMD3(nr * c, ny, nr * s)), SIMD2(t, along[i])))
            }
        }
        func index(_ i: Int, _ j: Int) -> UInt32 { UInt32(i * (segments + 1) + j) }
        for i in stride(from: 0, to: count - 1, by: 1) {
            for j in 0..<segments {
                let a = index(i, j)
                let b = index(i, j + 1)
                let c = index(i + 1, j + 1)
                let d = index(i + 1, j)
                // Outward the outline runs downward on its right; flipped when seen from inside.
                mesh.indices += inside ? [a, b, c, a, c, d] : [a, c, b, a, d, c]
            }
        }
        // The winding follows the normals, whichever way the outline was given.
        mesh.windByNormals(minimum: 1e-12, normalsOfFirstOnly: false)
        return mesh
    }

    /// A turned leg: a collar under the frame, a swelling, a waist, and a foot.
    private static func leg(height h: Float, radius r: Float) -> Mesh<SurfaceVertex> {
        let profile: [(r: Float, y: Float)] = [
            (0, 0), (r * 0.9, 0), (r * 0.95, -0.03 * h), (r * 0.75, -0.06 * h), (r * 0.8, -0.1 * h), (r * 1.05, -0.3 * h), (r * 1.1, -0.42 * h),
            (r * 0.95, -0.55 * h), (r * 0.62, -0.72 * h), (r * 0.7, -0.86 * h), (r * 0.95, -0.92 * h), (r * 1.0, -0.97 * h), (r * 0.9, -h), (0, -h),
        ]
        return lathe(profile, segments: 40, inside: false)
    }

    /// A box; without its top where the pockets hang inside it.
    private static func addBox(_ mesh: inout Mesh<SurfaceVertex>, low: SIMD3<Float>, high: SIMD3<Float>, top: Bool) {
        let c: [SIMD3<Float>] = [
            SIMD3(low.x, low.y, low.z), SIMD3(high.x, low.y, low.z), SIMD3(high.x, high.y, low.z), SIMD3(low.x, high.y, low.z),
            SIMD3(low.x, low.y, high.z), SIMD3(high.x, low.y, high.z), SIMD3(high.x, high.y, high.z), SIMD3(low.x, high.y, high.z),
        ]
        func face(_ a: Int, _ b: Int, _ d: Int, _ e: Int, _ normal: SIMD3<Float>) {
            func v(_ i: Int) -> SurfaceVertex { SurfaceVertex(c[i], normal, SIMD2(c[i].x + c[i].y, c[i].z + c[i].y)) }
            mesh.addQuad(v(a), v(b), v(d), v(e))
        }
        face(0, 1, 2, 3, SIMD3(0, 0, -1))
        face(4, 5, 6, 7, SIMD3(0, 0, 1))
        face(0, 4, 7, 3, SIMD3(-1, 0, 0))
        face(1, 5, 6, 2, SIMD3(1, 0, 0))
        face(0, 1, 5, 4, SIMD3(0, -1, 0))
        if top {
            face(3, 2, 6, 7, SIMD3(0, 1, 0))
        }
    }
}
