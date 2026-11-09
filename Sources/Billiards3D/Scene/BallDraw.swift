import simd

/// A ball to draw.
struct BallDraw {
    /// With the radius as its scale.
    var model = Matrix.identity
    var number = 0
    var russian = false
    /// Below 1, seen through: where the struck ball will meet another.
    var opacity: Float = 1
    /// A glow at the rim.
    var highlight: Float = 0
    /// The height of the cloth or the pocket under it.
    var ground: Float = 0
}
