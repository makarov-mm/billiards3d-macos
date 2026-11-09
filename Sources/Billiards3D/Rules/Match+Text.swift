/// The match and the balls as a line of text, for the settings.
extension Match {
    func text(with sim: Simulation) -> String {
        var fields = ["B1", "\(type.rawValue)", practice ? "1" : "0", "\(toPlay)", "\(groups[0].rawValue)", "\(groups[1].rawValue)",
                      breakShot ? "1" : "0", "\(inHand.rawValue)", "\(winner)"]
        for balls in taken {
            fields.append("\(balls.count)")
            fields += balls.map { "\($0)" }
        }
        fields.append("\(sim.count)")
        for i in 0..<sim.count {
            let b = sim.balls[i]
            fields += ["\(b.state.rawValue)", "\(b.pocket)", "\(b.p.x)", "\(b.p.z)", "\(b.q.w)", "\(b.q.x)", "\(b.q.y)", "\(b.q.z)"]
        }
        return fields.joined(separator: " ")
    }

    /// A match read back, with its balls on `table`; nil when the text is not one, or is for another table.
    static func read(_ text: String, table: TableSpec) -> (match: Match, sim: Simulation)? {
        var tokens = text.split(whereSeparator: \.isWhitespace).makeIterator()
        func int() -> Int? { tokens.next().flatMap { Int($0) } }
        func double() -> Double? { tokens.next().flatMap { Double($0) }.flatMap { $0.isFinite ? $0 : nil } }

        guard tokens.next() == "B1",
              let type = int().flatMap(GameType.init(rawValue:)),
              let practice = int(),
              let toPlay = int(), (0...1).contains(toPlay),
              let group0 = int().flatMap(BallGroup.init(rawValue:)),
              let group1 = int().flatMap(BallGroup.init(rawValue:)),
              let breakShot = int(),
              let inHand = int().flatMap(InHand.init(rawValue:)),
              let winner = int(), (-1...1).contains(winner)
        else {
            return nil
        }
        var m = Match()
        m.type = type
        m.practice = practice != 0
        m.toPlay = toPlay
        m.groups = [group0, group1]
        m.breakShot = breakShot != 0
        m.inHand = inHand
        m.winner = winner
        for player in 0..<2 {
            guard let size = int(), (0...16).contains(size) else {
                return nil
            }
            for _ in 0..<size {
                guard let ball = int(), (0..<Simulation.maxBalls).contains(ball) else {
                    return nil
                }
                m.taken[player].append(ball)
            }
        }
        guard let count = int(), (2...Simulation.maxBalls).contains(count), table.kind == type.table else {
            return nil
        }
        var s = Simulation(table: table)
        s.count = count
        for i in 0..<count {
            guard let state = int().flatMap(Ball.State.init(rawValue:)),
                  let pocket = int(), (-1...5).contains(pocket),
                  let x = double(), let z = double(),
                  let qw = double(), let qx = double(), let qy = double(), let qz = double()
            else {
                return nil
            }
            var b = Ball()
            b.state = state
            b.pocket = pocket
            b.p = V2(x, z)
            // A turn of any other length is set right; none at all is no turn.
            let n = (qw * qw + qx * qx + qy * qy + qz * qz).squareRoot()
            if n > 1e-9 {
                b.q = abs(n - 1) > 1e-9 ? Quat(w: qw / n, x: qx / n, y: qy / n, z: qz / n) : Quat(w: qw, x: qx, y: qy, z: qz)
            }
            if b.onTable && !table.canRest(at: b.p) {
                return nil
            }
            s.balls[i] = b
        }
        return (m, s)
    }
}
