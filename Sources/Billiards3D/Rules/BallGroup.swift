/// In eight-ball: no group yet, the solids (1 to 7) or the stripes (9 to 15).
enum BallGroup: Int, Sendable {
    case open, solids, stripes

    func contains(_ ball: Int) -> Bool {
        switch self {
        case .solids: (1...7).contains(ball)
        case .stripes: (9...15).contains(ball)
        case .open: false
        }
    }
}
