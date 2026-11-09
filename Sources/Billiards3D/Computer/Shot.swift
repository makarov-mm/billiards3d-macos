/// A stroke: which ball the cue strikes, where to, how hard, and where on the ball; first putting the ball down
/// when it is in hand, and calling a pocket for the eight.
struct Shot: Sendable {
    var struck = 0
    var direction = V2(1, 0)
    /// Of the struck ball, m/s.
    var speed = 1.0
    /// Right of the middle, as a fraction of the radius.
    var side = 0.0
    /// Above the middle.
    var vertical = 0.0
    var calledPocket = -1
    var place = false
    var spot = V2.zero
}
