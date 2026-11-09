/// The four looks of the room and the table.
enum Themes {
    static let all = [classic(), tournament(), club(), night()]

    /// Green cloth, mahogany, pearl sights, a wooden floor.
    private static func classic() -> Theme {
        var t = Theme(englishName: "Classic", russianName: "Классика", cloth: SIMD3(0.016, 0.125, 0.044), rail: SIMD3(0.2, 0.05, 0.022),
                      frame: SIMD3(0.12, 0.03, 0.014), pocket: SIMD3(0.025, 0.018, 0.014), floor: SIMD3(0.12, 0.07, 0.04),
                      sight: SIMD3(0.85, 0.83, 0.78), keyDirection: SIMD3(0.1, 1.0, 0.22), keyRadiance: SIMD3(5.0, 4.75, 4.3),
                      ceiling: SIMD3(0.01, 0.01, 0.01), horizon: SIMD3(0.03, 0.024, 0.018), ground: SIMD3(0.012, 0.01, 0.008),
                      fog: SIMD3(0.012, 0.01, 0.008), accent: SIMD3(0.35, 0.78, 1.0))
        t.railSeed = 0.37
        t.floorRoughness = 0.45
        t.sightRoughness = 0.15
        t.diffuseLight = 0.8
        t.background = 0.4
        t.exposure = 0.95
        t.light(lamp: SIMD3(9.0, 8.4, 7.4), fill: SIMD3(0.12, 0.1, 0.08))
        return t
    }

    /// Blue cloth, black lacquer and chrome, a grey carpet: a tournament hall.
    private static func tournament() -> Theme {
        var t = Theme(englishName: "Tournament", russianName: "Турнир", cloth: SIMD3(0.012, 0.065, 0.23), rail: SIMD3(0.012, 0.012, 0.014),
                      frame: SIMD3(0.01, 0.01, 0.012), pocket: SIMD3(0.012, 0.012, 0.014), floor: SIMD3(0.03, 0.032, 0.036),
                      sight: SIMD3(0.8, 0.82, 0.85), keyDirection: SIMD3(0.08, 1.0, 0.18), keyRadiance: SIMD3(5.2, 5.2, 5.3),
                      ceiling: SIMD3(0.012, 0.013, 0.016), horizon: SIMD3(0.03, 0.032, 0.04), ground: SIMD3(0.01, 0.01, 0.012),
                      fog: SIMD3(0.01, 0.011, 0.014), accent: SIMD3(0.4, 0.8, 1.0))
        t.clothRoughness = 0.85
        t.railRoughness = 0.15
        t.railClearcoat = 1.0
        t.railPattern = 1
        t.frameRoughness = 0.2
        t.framePattern = 1
        t.floorRoughness = 0.95
        t.floorPattern = 1
        t.sightMetallic = 1
        t.sightRoughness = 0.12
        t.keySoftness = 0.2
        t.diffuseLight = 0.9
        t.background = 0.4
        t.exposure = 1.0
        t.light(lamp: SIMD3(9.5, 9.5, 9.7), fill: SIMD3(0.1, 0.11, 0.14))
        return t
    }

    /// Wine-red cloth, walnut, brass dots, a stone floor: a club room.
    private static func club() -> Theme {
        var t = Theme(englishName: "Club", russianName: "Клуб", cloth: SIMD3(0.17, 0.018, 0.026), rail: SIMD3(0.11, 0.055, 0.025),
                      frame: SIMD3(0.075, 0.036, 0.017), pocket: SIMD3(0.06, 0.03, 0.015), floor: SIMD3(0.05, 0.045, 0.04),
                      sight: SIMD3(0.95, 0.7, 0.33), keyDirection: SIMD3(0.12, 1.0, 0.25), keyRadiance: SIMD3(5.0, 4.5, 3.8),
                      ceiling: SIMD3(0.012, 0.009, 0.007), horizon: SIMD3(0.035, 0.025, 0.016), ground: SIMD3(0.012, 0.009, 0.007),
                      fog: SIMD3(0.014, 0.01, 0.007), accent: SIMD3(1.0, 0.72, 0.35))
        t.railSeed = 0.71
        t.frameSeed = 0.2
        t.floorRoughness = 0.3
        t.floorPattern = 2
        t.sightMetallic = 1
        t.sightRoughness = 0.25
        t.sightShape = 1
        t.diffuseLight = 0.8
        t.background = 0.4
        t.exposure = 1.08
        t.light(lamp: SIMD3(9.0, 8.0, 6.6), fill: SIMD3(0.14, 0.1, 0.07))
        return t
    }

    /// Dark teal cloth, glowing sights and a cool, dim room.
    private static func night() -> Theme {
        var t = Theme(englishName: "Night", russianName: "Ночь", cloth: SIMD3(0.006, 0.06, 0.07), rail: SIMD3(0.02, 0.02, 0.025),
                      frame: SIMD3(0.012, 0.012, 0.016), pocket: SIMD3(0.01, 0.01, 0.012), floor: SIMD3(0.012, 0.014, 0.02),
                      sight: SIMD3(0.2, 0.85, 1.0), keyDirection: SIMD3(0.05, 1.0, 0.15), keyRadiance: SIMD3(3.6, 3.9, 4.4),
                      ceiling: SIMD3(0.004, 0.005, 0.01), horizon: SIMD3(0.01, 0.015, 0.03), ground: SIMD3(0.003, 0.004, 0.006),
                      fog: SIMD3(0.004, 0.006, 0.012), accent: SIMD3(0.2, 0.85, 1.0))
        t.clothSheen = 0.5
        t.railRoughness = 0.2
        t.railClearcoat = 1.0
        t.railPattern = 1
        t.framePattern = 1
        t.floorRoughness = 0.9
        t.floorPattern = 1
        t.sightRoughness = 0.3
        t.sightShape = 1
        t.sightGlow = 2.5
        t.keySoftness = 0.12
        t.diffuseLight = 1.0
        t.reflectedLight = 1.1
        t.background = 0.5
        t.exposure = 1.15
        t.bloom = 0.07
        t.vignette = 0.55
        t.light(lamp: SIMD3(6.8, 7.4, 8.4), fill: SIMD3(0.05, 0.08, 0.16))
        t.panels.append(StudioPanel(direction: SIMD3(-0.3, 0.2, 0.93), halfSize: SIMD2(1.0, 0.03), corner: 0.01, softness: 0.02,
                                    radiance: SIMD3(1.0, 3.0, 4.0)))
        return t
    }
}
