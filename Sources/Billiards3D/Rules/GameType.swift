/// The games: eight-ball and nine-ball on a pool table, and «Американка» (free pyramid) on a Russian one.
enum GameType: Int, CaseIterable, Sendable {
    case eightBall, nineBall, americanka

    var table: TableKind { self == .americanka ? .pyramid : .pool }
}
