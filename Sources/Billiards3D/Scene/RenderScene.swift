import simd

/// Everything the renderer draws in a frame, but the interface.
struct RenderScene {
    var view = Matrix.identity
    var projection = Matrix.identity
    var eye = SIMD3<Float>(repeating: 0)
    var time: Float = 0
    var balls: [BallDraw] = []
    var cue: float4x4?
    /// Segments on the cloth: from xz, to xz.
    var guides: [SIMD4<Float>] = []
    var guideStrength: Float = 0
    var showKitchen = false
    /// A ring round a pocket: xz, radius, strength.
    var pocketMark = SIMD4<Float>(repeating: 0)
    var panels: [FrostedPanel] = []
}
