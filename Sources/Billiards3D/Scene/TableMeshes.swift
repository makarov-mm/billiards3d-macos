/// The meshes of a table, built from its measurements.
struct TableMeshes {
    /// The cloth, reaching under the cushions; the shader cuts the holes of the pockets.
    var bed = Mesh<SurfaceVertex>()
    /// Cloth over rubber, ending in the jaws of the pockets.
    var cushions = Mesh<SurfaceVertex>()
    /// The wooden rails; the shader cuts the openings of the pockets.
    var rails = Mesh<SurfaceVertex>()
    /// The apron below the rails, and the legs.
    var frame = Mesh<SurfaceVertex>()
    var floorHeight: Float = -0.78
}
