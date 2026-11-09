import simd

/// Building the surfaces of the scene out of triangles.
extension Mesh where Vertex == SurfaceVertex {
    /// Adds a triangle, wound counterclockwise as seen from the side its normals face.
    mutating func addTriangle(_ a: SurfaceVertex, _ b: SurfaceVertex, _ c: SurfaceVertex) {
        let base = UInt32(vertices.count)
        vertices += [a, b, c]
        let facing = cross(b.position - a.position, c.position - a.position)
        if dot(facing, a.normal + b.normal + c.normal) >= 0 {
            indices += [base, base + 1, base + 2]
        } else {
            indices += [base, base + 2, base + 1]
        }
    }

    mutating func addQuad(_ a: SurfaceVertex, _ b: SurfaceVertex, _ c: SurfaceVertex, _ d: SurfaceVertex) {
        addTriangle(a, b, c)
        addTriangle(a, c, d)
    }

    /// Another mesh, carried by a transform.
    mutating func append(_ source: Mesh<SurfaceVertex>, transform: float4x4) {
        let base = UInt32(vertices.count)
        for vertex in source.vertices {
            let position = Matrix.transform(vertex.position, by: transform)
            let normal = transform * SIMD4(vertex.normal, 0)
            vertices.append(SurfaceVertex(position, Matrix.unit(SIMD3(normal.x, normal.y, normal.z)), SIMD2(vertex.u, vertex.v)))
        }
        indices += source.indices.map { base + $0 }
    }

    /// Turns each triangle round whose winding does not follow its normals, `minimum` being the least size of the
    /// cross product of its edges that has a winding.
    mutating func windByNormals(minimum: Float, normalsOfFirstOnly: Bool) {
        var k = 0
        while k + 2 < indices.count {
            let a = vertices[Int(indices[k])]
            let b = vertices[Int(indices[k + 1])]
            let c = vertices[Int(indices[k + 2])]
            let facing = cross(b.position - a.position, c.position - a.position)
            let normals = normalsOfFirstOnly ? a.normal : a.normal + b.normal + c.normal
            if length(facing) > minimum && dot(facing, normals) < 0 {
                indices.swapAt(k + 1, k + 2)
            }
            k += 3
        }
    }
}
