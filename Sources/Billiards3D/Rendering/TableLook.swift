import simd

/// The uniforms of the table shader, as TableUniforms in Common.metal lays them out: the looks of a theme and the
/// marks of a frame, then the arrays, each filled up to its length.
struct TableLook {
    static let sightRoom = 24
    static let guideRoom = 16
    static let ballRoom = 16

    var cloth = SIMD4<Float>(repeating: 0)
    var clothStyle = SIMD4<Float>(repeating: 0)
    var railColor = SIMD4<Float>(repeating: 0)
    var railStyle = SIMD4<Float>(repeating: 0)
    var frameColor = SIMD4<Float>(repeating: 0)
    var frameStyle = SIMD4<Float>(repeating: 0)
    var pocketColor = SIMD4<Float>(repeating: 0)
    var pocketStyle = SIMD4<Float>(repeating: 0)
    var floorColor = SIMD4<Float>(repeating: 0)
    var floorStyle = SIMD4<Float>(repeating: 0)
    var sightColor = SIMD4<Float>(repeating: 0)
    var sightStyle = SIMD4<Float>(repeating: 0)
    var table = SIMD4<Float>(repeating: 0)
    var marks = SIMD4<Float>(repeating: 0)
    var guideColor = SIMD4<Float>(repeating: 0)
    var pocketMark = SIMD4<Float>(repeating: 0)
    var holes: [SIMD4<Float>] = []
    var cups: [SIMD4<Float>] = []
    var sights: [SIMD4<Float>] = []
    var guides: [SIMD4<Float>] = []
    var balls: [SIMD4<Float>] = []

    /// The values in the shader's order, the counts after the scalars.
    var packed: [SIMD4<Float>] {
        func filled(_ values: [SIMD4<Float>], _ room: Int) -> [SIMD4<Float>] {
            Array(values.prefix(room)) + Array(repeating: SIMD4<Float>(repeating: 0), count: max(0, room - values.count))
        }
        let counts = SIMD4<Float>(Float(min(sights.count, Self.sightRoom)), Float(min(guides.count, Self.guideRoom)),
                                  Float(min(balls.count, Self.ballRoom)), 0)
        return [cloth, clothStyle, railColor, railStyle, frameColor, frameStyle, pocketColor, pocketStyle, floorColor, floorStyle, sightColor,
                sightStyle, table, marks, guideColor, pocketMark, counts]
            + filled(holes, 6) + filled(cups, 6) + filled(sights, Self.sightRoom) + filled(guides, Self.guideRoom) + filled(balls, Self.ballRoom)
    }
}
