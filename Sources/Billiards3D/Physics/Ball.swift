/// A ball: where it is, how it moves and spins, and how it is turned.
struct Ball: Sendable {
    enum State: Int, Sendable {
        case onTable, pocketed
    }

    var p = V2.zero
    var v = V2.zero
    /// The angular velocity.
    var w = V3.zero
    var q = Quat()
    var state = State.onTable
    var pocket = -1

    var onTable: Bool { state == .onTable }
}
