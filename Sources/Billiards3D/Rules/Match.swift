/// A game in progress: whose turn it is, the groups or the balls each player has taken, a ball in hand, and the
/// winner.
struct Match: Sendable {
    /// Американка: balls to win.
    static let target = 8

    var type = GameType.eightBall
    /// One player, no fouls.
    var practice = false
    var toPlay = 0
    var groups: [BallGroup] = [.open, .open]
    /// Американка: each player's balls.
    var taken: [[Int]] = [[], []]
    var breakShot = true
    var inHand = InHand.kitchen
    var winner = -1

    func score(_ player: Int) -> Int { taken[player].count }

    var isOver: Bool { winner >= 0 }

    /// The balls the cue may strike: the cue ball, or in Американка (after the break) any ball.
    func mayStrike(_ sim: Simulation, _ ball: Int) -> Bool {
        if ball < 0 || ball >= sim.count || !sim.balls[ball].onTable {
            return false
        }
        return type == .americanka && !breakShot ? true : ball == 0
    }

    func ballsLeft(_ sim: Simulation, in group: BallGroup) -> Int {
        (1..<max(sim.count, 1)).count { group.contains($0) && sim.balls[$0].onTable }
    }

    /// Eight-ball: the player has cleared their group and plays the eight.
    func isOnEight(_ sim: Simulation, player: Int) -> Bool {
        let group = groups[player]
        return type == .eightBall && group != .open && ballsLeft(sim, in: group) == 0
    }

    /// The lowest ball on the table, in nine-ball.
    func lowest(_ sim: Simulation) -> Int {
        (1..<max(sim.count, 1)).first { sim.balls[$0].onTable } ?? -1
    }

    /// The balls that may be hit first, by the player to move.
    func targets(_ sim: Simulation, player: Int) -> [Int] {
        switch type {
        case .nineBall:
            let lowest = lowest(sim)
            return lowest > 0 ? [lowest] : []
        case .eightBall:
            let group = groups[player]
            if isOnEight(sim, player: player) {
                return sim.balls[8].onTable ? [8] : []
            }
            return (1..<max(sim.count, 1)).filter { i in
                sim.balls[i].onTable && (group == .open ? i != 8 || breakShot : group.contains(i))
            }
        case .americanka:
            return (0..<sim.count).filter { sim.balls[$0].onTable }
        }
    }
}
