/// Curves for animation and blending.
enum Easing {
    static func saturate(_ x: Float) -> Float { min(max(x, 0), 1) }

    static func smoothStep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = saturate((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }
}
