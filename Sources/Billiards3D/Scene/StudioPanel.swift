/// A light of the room round the table, the lamp over it among them, seen as a rounded rectangle in the environment.
struct StudioPanel: Sendable {
    /// Toward the panel.
    var direction: SIMD3<Float>
    var roll: Float = 0
    /// As tangents of the angles.
    var halfSize: SIMD2<Float>
    var corner: Float = 0.05
    var softness: Float = 0.05
    var radiance: SIMD3<Float>
    var falloff: Float = 0.3
}
