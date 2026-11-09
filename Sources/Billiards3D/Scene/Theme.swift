/// The looks of the room and the table: the cloth, the wood, the pockets, the floor, and the lamp over the table.
struct Theme: Sendable {
    var englishName: String
    var russianName: String

    var cloth: SIMD3<Float>
    var clothRoughness: Float = 0.9
    var clothNap: Float = 1
    var clothSheen: Float = 0.3
    var clothWear: Float = 1
    var rail: SIMD3<Float>
    var railRoughness: Float = 0.3
    var railClearcoat: Float = 0.8
    /// 0 wood, 1 lacquer.
    var railPattern: Float = 0
    var railSeed: Float = 0.3
    var frame: SIMD3<Float>
    var frameRoughness: Float = 0.35
    var frameClearcoat: Float = 0.6
    var framePattern: Float = 0
    var frameSeed: Float = 0.6
    var pocket: SIMD3<Float>
    var pocketRoughness: Float = 0.6
    var floor: SIMD3<Float>
    var floorRoughness: Float = 0.5
    /// 0 boards, 1 carpet, 2 stone.
    var floorPattern: Float = 0
    var sight: SIMD3<Float>
    var sightMetallic: Float = 0
    var sightRoughness: Float = 0.2
    /// 0 diamonds, 1 dots.
    var sightShape: Float = 0
    var sightGlow: Float = 0
    var ballRoughness: Float = 0.06
    var ballCoatRoughness: Float = 0.02

    // The light.
    var keyDirection: SIMD3<Float>
    var keyRadiance: SIMD3<Float>
    /// Tangent of the light's angular radius.
    var keySoftness: Float = 0.15
    var ceiling: SIMD3<Float>
    var horizon: SIMD3<Float>
    var ground: SIMD3<Float>
    var panels: [StudioPanel] = []
    var diffuseLight: Float = 1
    var reflectedLight: Float = 1
    var background: Float = 0.5
    var fog: SIMD3<Float>
    var exposure: Float = 1
    var bloom: Float = 0.04
    var vignette: Float = 0.45

    /// Highlights, the aim and the interface.
    var accent: SIMD3<Float>

    func name(_ language: Language) -> String { language == .russian ? russianName : englishName }

    /// The lamp over the table, and a dim room round it.
    mutating func light(lamp radiance: SIMD3<Float>, fill: SIMD3<Float>) {
        panels = [
            StudioPanel(direction: SIMD3(0, 1, 0), halfSize: SIMD2(0.75, 0.32), corner: 0.05, softness: 0.08, radiance: radiance),
            StudioPanel(direction: SIMD3(0, 1, 0), halfSize: SIMD2(1.4, 0.8), corner: 0.3, softness: 0.6, radiance: radiance * 0.08),
            StudioPanel(direction: SIMD3(0.9, 0.25, 0.35), halfSize: SIMD2(0.8, 0.3), corner: 0.1, softness: 0.3, radiance: fill),
            StudioPanel(direction: SIMD3(-0.9, 0.25, -0.35), halfSize: SIMD2(0.8, 0.3), corner: 0.1, softness: 0.3, radiance: fill * 0.7),
            StudioPanel(direction: SIMD3(0.1, 0.3, 0.95), halfSize: SIMD2(1.2, 0.25), corner: 0.1, softness: 0.4, radiance: fill * 0.5),
        ]
    }
}
