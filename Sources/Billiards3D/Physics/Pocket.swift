/// A pocket: its mouth between the jaws, and the hole the balls drop into.
struct Pocket: Sendable {
    /// The middle of the mouth, between the jaws.
    var mouth = V2.zero
    /// Outward, into the pocket.
    var axis = V2.zero
    /// Where the balls drop: they fall once their middles are over it.
    var hole = V2.zero
    var holeRadius: Double = 0
    /// Of the opening in the rails, for drawing.
    var cupRadius: Double = 0
    /// Of the pocket below the cloth, for drawing.
    var depth: Double = 0
    var corner = true
}
