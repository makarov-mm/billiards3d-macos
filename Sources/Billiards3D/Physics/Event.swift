/// Something that happened to the balls: a collision, a cushion struck, or a ball dropping into a pocket.
struct Event: Sendable {
    enum Kind: Sendable {
        case ballBall, cushion, pocket
    }

    var kind: Kind
    /// The balls; for a cushion, `b` is -1; for a pocket, `b` is the pocket.
    var a: Int
    var b: Int
    /// Of the impact.
    var speed: Double
    var time: Double
}
