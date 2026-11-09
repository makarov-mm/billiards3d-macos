/// What the rules made of a stroke.
struct Verdict: Sendable {
    var foul = Foul.none
    var keepsTurn = false
    /// The game is over.
    var winner = -1
    /// Balls taken out of the pockets and set on the foot spot.
    var respot: [Int] = []
    /// Eight-ball: the group the shooter now has.
    var assigned = BallGroup.open
    /// Американка: the balls the shooter scored.
    var scored = 0
    /// Американка: a ball given back for a foul.
    var forfeited = -1
}
